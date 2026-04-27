-- M7a: Team agents — server-stored agent configs, channel membership, first-claim execution leases.

-- ─── Tables ─────────────────────────────────────────────────────────────────

create table public.agents (
    id           uuid primary key default gen_random_uuid(),
    workspace_id uuid not null references workspaces on delete cascade,
    slug         text not null,
    display_name text not null,
    system_prompt text not null,
    model        text not null default 'claude-opus-4-7',
    avatar_tint  text,
    created_by   uuid not null references users,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now(),
    archived_at  timestamptz,
    unique (workspace_id, slug)
);

create table public.channel_agents (
    channel_id uuid references channels on delete cascade,
    agent_id   uuid references agents  on delete cascade,
    added_by   uuid references users,
    added_at   timestamptz not null default now(),
    primary key (channel_id, agent_id)
);

create table public.agent_runs (
    message_id     uuid references messages on delete cascade,
    agent_id       uuid references agents   on delete cascade,
    runner_user_id uuid not null references users,
    claimed_at     timestamptz not null default now(),
    completed_at   timestamptz,
    status         text not null default 'running'
        check (status in ('running', 'done', 'failed')),
    primary key (message_id, agent_id)
);

create index idx_agent_runs_status on agent_runs(status, claimed_at);

-- ─── RLS ────────────────────────────────────────────────────────────────────

alter table public.agents enable row level security;

create policy "agents_select_ws_member" on public.agents
    for select using (
        workspace_id in (
            select workspace_id from memberships where user_id = auth.uid()
        )
    );

create policy "agents_insert_ws_member" on public.agents
    for insert with check (
        workspace_id in (
            select workspace_id from memberships where user_id = auth.uid()
        )
        and created_by = auth.uid()
    );

create policy "agents_update_steward_or_owner" on public.agents
    for update using (
        created_by = auth.uid()
        or exists (
            select 1 from memberships
            where workspace_id = agents.workspace_id
              and user_id = auth.uid()
              and role = 'owner'
        )
    );

alter table public.channel_agents enable row level security;

create policy "channel_agents_select" on public.channel_agents
    for select using (
        channel_id in (
            select channel_id from channel_members where user_id = auth.uid()
        )
    );

create policy "channel_agents_insert" on public.channel_agents
    for insert with check (
        channel_id in (
            select channel_id from channel_members where user_id = auth.uid()
        )
    );

create policy "channel_agents_delete" on public.channel_agents
    for delete using (
        channel_id in (
            select channel_id from channel_members where user_id = auth.uid()
        )
    );

alter table public.agent_runs enable row level security;

create policy "agent_runs_select_channel_member" on public.agent_runs
    for select using (
        message_id in (
            select id from messages
            where channel_id in (
                select channel_id from channel_members where user_id = auth.uid()
            )
        )
    );

-- Direct INSERT on agent_runs is forbidden — only via claim_agent_run.

-- ─── RPCs ────────────────────────────────────────────────────────────────────

-- First-claim lease: INSERT ON CONFLICT DO NOTHING; returns true if this caller won.
create or replace function public.claim_agent_run(
    p_message_id uuid,
    p_agent_id   uuid
) returns json
language plpgsql security definer
set search_path = public
as $$
declare
    v_channel_id uuid;
    v_won        boolean;
begin
    select channel_id into v_channel_id from messages where id = p_message_id;

    if not exists (
        select 1 from channel_members
        where channel_id = v_channel_id and user_id = auth.uid()
    ) then
        return json_build_object('won', false);
    end if;

    insert into agent_runs (message_id, agent_id, runner_user_id)
    values (p_message_id, p_agent_id, auth.uid())
    on conflict (message_id, agent_id) do nothing;

    v_won := found;
    return json_build_object('won', v_won);
end;
$$;

-- Release lease — set final status. Only the winning runner can release.
create or replace function public.release_agent_run(
    p_message_id uuid,
    p_agent_id   uuid,
    p_status     text
) returns void
language plpgsql security definer
set search_path = public
as $$
begin
    update agent_runs
       set status = p_status, completed_at = now()
     where message_id = p_message_id
       and agent_id   = p_agent_id
       and runner_user_id = auth.uid();
end;
$$;

-- Post an agent message. Bypasses the user-only INSERT RLS on messages by running
-- as the definer. Validates that caller holds a winning agent_runs row.
create or replace function public.post_agent_message(
    p_channel_id        uuid,
    p_message_id        uuid,
    p_agent_id          uuid,
    p_agent_slug        text,
    p_agent_display_name text,
    p_content           text,
    p_thinking          text    default null,
    p_tool_cards        jsonb   default null
) returns void
language plpgsql security definer
set search_path = public
as $$
begin
    if not exists (
        select 1 from agent_runs
        where message_id = p_message_id
          and agent_id   = p_agent_id
          and runner_user_id = auth.uid()
          and status = 'running'
    ) then
        raise exception 'no winning claim for this run';
    end if;

    if not exists (
        select 1 from channel_members
        where channel_id = p_channel_id and user_id = auth.uid()
    ) then
        raise exception 'not a channel member';
    end if;

    insert into messages (
        channel_id, sender_kind, sender_user_id,
        agent_id, agent_slug, agent_display_name, run_by_user_id,
        content, thinking, tool_cards
    ) values (
        p_channel_id, 'agent', null,
        p_agent_id, p_agent_slug, p_agent_display_name, auth.uid(),
        p_content, p_thinking, p_tool_cards
    );
end;
$$;

-- List all active team agents in a workspace (for roster + @-autocomplete).
create or replace function public.list_workspace_agents(
    p_workspace_id uuid
) returns setof agents
language sql security definer
set search_path = public
as $$
    select a.*
      from agents a
     where a.workspace_id = p_workspace_id
       and a.archived_at is null
       and exists (
           select 1 from memberships
           where workspace_id = p_workspace_id and user_id = auth.uid()
       )
     order by a.display_name;
$$;

-- List agents currently in a specific channel.
create or replace function public.list_channel_agents(
    p_channel_id uuid
) returns setof agents
language sql security definer
set search_path = public
as $$
    select a.*
      from agents a
      join channel_agents ca on ca.agent_id = a.id
     where ca.channel_id = p_channel_id
       and a.archived_at is null
       and exists (
           select 1 from channel_members
           where channel_id = p_channel_id and user_id = auth.uid()
       )
     order by a.display_name;
$$;
