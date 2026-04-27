-- Two RLS bugs surfaced once a second user joined the workspace:
--
--   1. `channel_members_select_same_channel` self-references public.channel_members
--      inside its USING clause, which Postgres rejects with
--      "infinite recursion detected in policy for relation channel_members".
--      Every read that touches channel_members (channels, messages, agent_runs,
--      channel_agents) failed for the recipient of a DM or shared channel.
--
--   2. `memberships_select` only let a caller see their own row, so realtime
--      INSERTs on memberships were never delivered to existing workspace
--      members — new joins required quit+reopen to appear.
--
-- The fix is the standard Postgres pattern: SECURITY DEFINER helper functions
-- that bypass RLS for the membership check, then call those helpers from the
-- policy bodies. The functions are STABLE so the planner can hoist them.

-- ─── Helpers ─────────────────────────────────────────────────────────────────

create or replace function public.is_workspace_member(p_workspace_id uuid, p_user_id uuid)
returns boolean
language sql security definer set search_path = public stable as $$
    select exists (
        select 1 from public.memberships
        where workspace_id = p_workspace_id and user_id = p_user_id
    );
$$;

create or replace function public.is_channel_member(p_channel_id uuid, p_user_id uuid)
returns boolean
language sql security definer set search_path = public stable as $$
    select exists (
        select 1 from public.channel_members
        where channel_id = p_channel_id and user_id = p_user_id
    );
$$;

-- ─── Fix 1: channel_members recursion ───────────────────────────────────────

drop policy if exists "channel_members_select_same_channel" on public.channel_members;

create policy "channel_members_select_same_channel"
    on public.channel_members for select
    using (public.is_channel_member(channel_id, auth.uid()));

-- ─── Fix 2: memberships visibility for workspace peers ───────────────────────

drop policy if exists "memberships_select" on public.memberships;

create policy "memberships_select"
    on public.memberships for select
    using (public.is_workspace_member(workspace_id, auth.uid()));
