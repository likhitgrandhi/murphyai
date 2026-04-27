-- M6 — Human-to-human messaging.
-- Channels, channel members, messages. RLS scopes everything to channel
-- membership. Agent-flavored columns (agent_id, agent_slug, etc.) are present
-- but unused until M7a; messages with sender_kind='agent' are blocked by RLS
-- here so the schema is forward-compatible without opening a hole.

-- ─── Tables ──────────────────────────────────────────────────────────────────

create table public.channels (
    id           uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references public.workspaces(id) on delete cascade,
    name         text,
    topic        text,
    is_dm        bool not null default false,
    created_by   uuid not null references public.users(id),
    created_at   timestamptz not null default now(),
    archived_at  timestamptz
);

create table public.channel_members (
    channel_id uuid not null references public.channels(id) on delete cascade,
    user_id    uuid not null references public.users(id) on delete cascade,
    joined_at  timestamptz not null default now(),
    primary key (channel_id, user_id)
);

create table public.messages (
    id                  uuid primary key default gen_random_uuid(),
    channel_id          uuid not null references public.channels(id) on delete cascade,
    seq                 bigserial,
    sender_kind         text not null check (sender_kind in ('user','agent','system')),
    sender_user_id      uuid references public.users(id),
    agent_id            uuid,                    -- populated in M7a
    agent_slug          text,
    agent_display_name  text,
    run_by_user_id      uuid references public.users(id),
    content             text,
    thinking            text,                    -- redacted summary or null (M7a)
    tool_cards          jsonb,                   -- redacted [{name, summary, ok}] (M7a)
    created_at          timestamptz not null default now()
);

-- Per-channel ordering. seq is global-bigserial; sort by (created_at, seq).
create index idx_messages_channel_seq on public.messages (channel_id, seq);
create index idx_channel_members_user on public.channel_members (user_id);
create index idx_channels_workspace   on public.channels (workspace_id);

-- ─── Enable RLS ──────────────────────────────────────────────────────────────

alter table public.channels        enable row level security;
alter table public.channel_members enable row level security;
alter table public.messages        enable row level security;

-- ─── channels: SELECT iff caller is in channel_members ───────────────────────

create policy "channels_select_members"
    on public.channels for select
    using (
        exists (
            select 1 from public.channel_members cm
            where cm.channel_id = channels.id
              and cm.user_id    = auth.uid()
        )
    );

-- INSERT only via create_channel / create_dm RPCs (SECURITY DEFINER), which
-- atomically insert the channel + first members. We block direct inserts to
-- avoid a window where a channel exists with no members and the creator can't
-- read it back.
revoke insert on public.channels from authenticated;

-- ─── channel_members: SELECT iff caller is in same channel ───────────────────

create policy "channel_members_select_same_channel"
    on public.channel_members for select
    using (
        exists (
            select 1 from public.channel_members me
            where me.channel_id = channel_members.channel_id
              and me.user_id    = auth.uid()
        )
    );

-- INSERT/DELETE only via add_to_channel / leave_channel RPCs.
revoke insert, delete on public.channel_members from authenticated;

-- ─── messages: SELECT iff caller is in the channel ───────────────────────────

create policy "messages_select_members"
    on public.messages for select
    using (
        exists (
            select 1 from public.channel_members cm
            where cm.channel_id = messages.channel_id
              and cm.user_id    = auth.uid()
        )
    );

-- INSERT: user messages only at M6. sender_kind='agent' is blocked here and
-- re-opened in M7a via SECURITY DEFINER post_agent_message. sender_kind='system'
-- is blocked from clients entirely; only RPCs (e.g. resource upload helper in
-- M7b) can write system messages.
create policy "messages_insert_self_user"
    on public.messages for insert
    with check (
        sender_kind = 'user'
        and sender_user_id = auth.uid()
        and exists (
            select 1 from public.channel_members cm
            where cm.channel_id = messages.channel_id
              and cm.user_id    = auth.uid()
        )
    );

-- No UPDATE / DELETE on messages in M6.

-- ─── Realtime publication ────────────────────────────────────────────────────
-- Subscribe via Postgres Changes from the Swift client. Adding to the existing
-- `supabase_realtime` publication so logical replication fans out INSERTs.

alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.channels;
alter publication supabase_realtime add table public.channel_members;

-- ─── RPC: create_channel ─────────────────────────────────────────────────────
-- Atomically creates a non-DM channel and adds the caller as the first member.

create or replace function public.create_channel(
    p_workspace_id uuid,
    p_name         text,
    p_topic        text default null
)
returns public.channels
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ch  public.channels%rowtype;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    if not exists (
        select 1 from public.memberships m
        where m.workspace_id = p_workspace_id and m.user_id = uid
    ) then
        raise exception 'Not a member of this workspace';
    end if;

    if p_name is null or btrim(p_name) = '' then
        raise exception 'Channel name required';
    end if;

    insert into public.channels (workspace_id, name, topic, is_dm, created_by)
    values (p_workspace_id, btrim(p_name), nullif(btrim(p_topic), ''), false, uid)
    returning * into ch;

    insert into public.channel_members (channel_id, user_id)
    values (ch.id, uid);

    return ch;
end;
$$;

-- ─── RPC: create_dm ──────────────────────────────────────────────────────────
-- Get-or-create a 1:1 DM between caller and another workspace member. Idempotent:
-- returns the existing DM if one already exists for this pair.

create or replace function public.create_dm(
    p_workspace_id uuid,
    p_other_user_id uuid
)
returns public.channels
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ch  public.channels%rowtype;
    existing_id uuid;
begin
    if uid is null then raise exception 'Not authenticated'; end if;
    if uid = p_other_user_id then raise exception 'Cannot DM yourself'; end if;

    -- Both must be workspace members.
    if not exists (
        select 1 from public.memberships m
        where m.workspace_id = p_workspace_id
          and m.user_id in (uid, p_other_user_id)
        group by m.workspace_id having count(*) = 2
    ) then
        raise exception 'Both users must be members of this workspace';
    end if;

    -- Existing DM? Two members, exactly these two.
    select c.id into existing_id
    from public.channels c
    where c.workspace_id = p_workspace_id
      and c.is_dm = true
      and exists (select 1 from public.channel_members where channel_id = c.id and user_id = uid)
      and exists (select 1 from public.channel_members where channel_id = c.id and user_id = p_other_user_id)
      and (select count(*) from public.channel_members where channel_id = c.id) = 2
    limit 1;

    if existing_id is not null then
        select * into ch from public.channels where id = existing_id;
        return ch;
    end if;

    insert into public.channels (workspace_id, name, is_dm, created_by)
    values (p_workspace_id, null, true, uid)
    returning * into ch;

    insert into public.channel_members (channel_id, user_id)
    values (ch.id, uid), (ch.id, p_other_user_id);

    return ch;
end;
$$;

-- ─── RPC: add_to_channel ─────────────────────────────────────────────────────
-- Add a workspace member to a non-DM channel. Caller must be in the channel.

create or replace function public.add_to_channel(
    p_channel_id uuid,
    p_user_id    uuid
)
returns void
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ch  public.channels%rowtype;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    select * into ch from public.channels where id = p_channel_id;
    if not found then raise exception 'Channel not found'; end if;
    if ch.is_dm then raise exception 'Cannot add members to a DM'; end if;

    if not exists (
        select 1 from public.channel_members
        where channel_id = p_channel_id and user_id = uid
    ) then
        raise exception 'Not a member of this channel';
    end if;

    if not exists (
        select 1 from public.memberships m
        where m.workspace_id = ch.workspace_id and m.user_id = p_user_id
    ) then
        raise exception 'User is not a member of this workspace';
    end if;

    insert into public.channel_members (channel_id, user_id)
    values (p_channel_id, p_user_id)
    on conflict do nothing;
end;
$$;

-- ─── RPC: leave_channel ──────────────────────────────────────────────────────
-- Remove caller from a channel. DMs cannot be left (use archive in M8).

create or replace function public.leave_channel(p_channel_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    ch  public.channels%rowtype;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    select * into ch from public.channels where id = p_channel_id;
    if not found then raise exception 'Channel not found'; end if;
    if ch.is_dm then raise exception 'Cannot leave a DM'; end if;

    delete from public.channel_members
    where channel_id = p_channel_id and user_id = uid;
end;
$$;

-- ─── RPC: list_channels (workspace-scoped, your-channels-only) ──────────────
-- Convenience for the sidebar: all channels in the workspace where caller is
-- a member, plus DM partner names so we can render "Direct messages — Sarah".

create or replace function public.list_my_channels(p_workspace_id uuid)
returns table(
    id           uuid,
    workspace_id uuid,
    name         text,
    topic        text,
    is_dm        bool,
    created_by   uuid,
    created_at   timestamptz,
    archived_at  timestamptz,
    dm_other_user_id uuid,
    dm_other_display_name text,
    dm_other_email text
)
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    if not exists (
        select 1 from public.memberships m
        where m.workspace_id = p_workspace_id and m.user_id = uid
    ) then
        raise exception 'Not a member of this workspace';
    end if;

    return query
    with my_channels as (
        select c.*
        from public.channels c
        join public.channel_members cm on cm.channel_id = c.id
        where c.workspace_id = p_workspace_id
          and cm.user_id    = uid
          and c.archived_at is null
    )
    select
        c.id, c.workspace_id, c.name, c.topic, c.is_dm,
        c.created_by, c.created_at, c.archived_at,
        other.user_id          as dm_other_user_id,
        u.display_name         as dm_other_display_name,
        u.email                as dm_other_email
    from my_channels c
    left join lateral (
        select cm2.user_id from public.channel_members cm2
        where cm2.channel_id = c.id and cm2.user_id <> uid
        limit 1
    ) other on c.is_dm
    left join public.users u on u.id = other.user_id
    order by c.is_dm desc, c.created_at desc;
end;
$$;
