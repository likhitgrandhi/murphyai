-- ─── Extensions ──────────────────────────────────────────────────────────────
create extension if not exists "pgcrypto";

-- ─── Types ────────────────────────────────────────────────────────────────────
create type public.member_role as enum ('owner', 'member');

-- ─── Tables (all created before any cross-table RLS policies) ─────────────────

create table public.users (
    id           uuid primary key references auth.users(id) on delete cascade,
    email        text not null,
    display_name text,
    avatar_url   text,
    created_at   timestamptz default now() not null
);

create table public.workspaces (
    id         uuid primary key default gen_random_uuid(),
    name       text not null,
    slug       text not null unique,
    owner_id   uuid not null references public.users(id) on delete restrict,
    created_at timestamptz default now() not null
);

create table public.memberships (
    id           uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    user_id      uuid not null references public.users(id) on delete cascade,
    role         public.member_role not null default 'member',
    joined_at    timestamptz default now() not null,
    unique (workspace_id, user_id)
);

create table public.invitations (
    id           uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    email        text,
    code         text not null unique default encode(gen_random_bytes(7), 'base64url'),
    invited_by   uuid not null references public.users(id) on delete cascade,
    role         public.member_role not null default 'member',
    expires_at   timestamptz not null default now() + interval '7 days',
    redeemed_by  uuid references public.users(id),
    redeemed_at  timestamptz
);

-- ─── Enable RLS ───────────────────────────────────────────────────────────────
alter table public.users       enable row level security;
alter table public.workspaces  enable row level security;
alter table public.memberships enable row level security;
alter table public.invitations enable row level security;

-- ─── RLS Policies ─────────────────────────────────────────────────────────────

-- users
create policy "users_select_own"
    on public.users for select using (auth.uid() = id);

create policy "users_update_own"
    on public.users for update using (auth.uid() = id);

-- workspaces (references memberships — safe now since both tables exist)
create policy "workspaces_select_members"
    on public.workspaces for select
    using (
        exists (
            select 1 from public.memberships
            where memberships.workspace_id = workspaces.id
              and memberships.user_id = auth.uid()
        )
    );

create policy "workspaces_update_owner"
    on public.workspaces for update
    using (owner_id = auth.uid());

-- memberships
create policy "memberships_select"
    on public.memberships for select
    using (
        user_id = auth.uid()
        or exists (
            select 1 from public.memberships m2
            where m2.workspace_id = memberships.workspace_id
              and m2.user_id = auth.uid()
        )
    );

-- invitations
create policy "invitations_insert_members"
    on public.invitations for insert
    with check (
        exists (
            select 1 from public.memberships
            where memberships.workspace_id = invitations.workspace_id
              and memberships.user_id = auth.uid()
        )
    );

create policy "invitations_select_authenticated"
    on public.invitations for select
    using (auth.role() = 'authenticated');

-- ─── Trigger: auto-create user row on sign-up ─────────────────────────────────
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
    insert into public.users (id, email)
    values (new.id, new.email)
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ─── RPC: create_workspace ────────────────────────────────────────────────────
create or replace function public.create_workspace(
    workspace_name text,
    workspace_slug text
)
returns public.workspaces language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ws  public.workspaces%rowtype;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    insert into public.workspaces (name, slug, owner_id)
    values (workspace_name, workspace_slug, uid)
    returning * into ws;

    insert into public.memberships (workspace_id, user_id, role)
    values (ws.id, uid, 'owner');

    return ws;
end;
$$;

-- ─── RPC: redeem_invitation ───────────────────────────────────────────────────
create or replace function public.redeem_invitation(invite_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
    inv          public.invitations%rowtype;
    uid          uuid := auth.uid();
    caller_email text;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    select * into inv from public.invitations
    where code = invite_code
    for update;

    if not found then
        raise exception 'Invalid invite code';
    end if;

    if inv.redeemed_by is not null then
        raise exception 'Invite already redeemed';
    end if;

    if inv.expires_at < now() then
        raise exception 'Invite has expired';
    end if;

    if inv.email is not null then
        select email into caller_email from public.users where id = uid;
        if lower(caller_email) != lower(inv.email) then
            raise exception 'This invite is for a different email address';
        end if;
    end if;

    if exists (
        select 1 from public.memberships
        where workspace_id = inv.workspace_id and user_id = uid
    ) then
        return json_build_object(
            'workspace_id', inv.workspace_id::text,
            'already_member', true
        );
    end if;

    insert into public.memberships (workspace_id, user_id, role)
    values (inv.workspace_id, uid, inv.role);

    update public.invitations
    set redeemed_by = uid, redeemed_at = now()
    where id = inv.id;

    return json_build_object(
        'workspace_id', inv.workspace_id::text,
        'already_member', false
    );
end;
$$;
