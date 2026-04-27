-- ─── Fix: invitation code default ────────────────────────────────────────────
-- Original migration used `base64url` which isn't available on older Postgres
-- versions. Switch to hex — always URL-safe, 16 chars, ~64 bits entropy.

alter table public.invitations
    alter column code set default encode(gen_random_bytes(8), 'hex');

-- ─── RPC: list_workspace_members ─────────────────────────────────────────────
-- SECURITY DEFINER bypasses memberships_select RLS (which is own-row only)
-- so we can show the full roster to any member of the workspace.

create or replace function public.list_workspace_members(p_workspace_id uuid)
returns table(
    user_id      uuid,
    email        text,
    display_name text,
    avatar_url   text,
    role         public.member_role,
    joined_at    timestamptz
)
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then
        raise exception 'Not authenticated';
    end if;

    if not exists (
        select 1 from public.memberships
        where workspace_id = p_workspace_id and user_id = uid
    ) then
        raise exception 'Not a member of this workspace';
    end if;

    return query
    select m.user_id, u.email, u.display_name, u.avatar_url, m.role, m.joined_at
    from public.memberships m
    join public.users u on u.id = m.user_id
    where m.workspace_id = p_workspace_id
    order by m.joined_at asc;
end;
$$;

-- ─── Fix: invitations select policy ──────────────────────────────────────────
-- Old policy let any authenticated user see all invitations. Tighten to
-- "must be a member of the workspace" so the People page can safely list
-- pending invites for a workspace without leaking cross-workspace data.

drop policy if exists "invitations_select_authenticated" on public.invitations;

create policy "invitations_select_members"
    on public.invitations for select
    using (
        exists (
            select 1 from public.memberships
            where memberships.workspace_id = invitations.workspace_id
              and memberships.user_id = auth.uid()
        )
    );
