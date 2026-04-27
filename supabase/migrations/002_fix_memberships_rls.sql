-- The original memberships_select policy was self-referential:
--     user_id = auth.uid() OR exists (select 1 from memberships m2 where ...)
-- which caused Postgres "infinite recursion detected in policy" errors
-- whenever workspaces_select_members evaluated its `exists` subquery.
-- Result: clients silently got zero rows back from `select * from workspaces`.
--
-- Fix: drop the recursive branch. Users can see their own memberships only.
-- When we need "list all members in a workspace I'm part of", we'll add that
-- via a SECURITY DEFINER RPC rather than RLS.

drop policy if exists "memberships_select" on public.memberships;

create policy "memberships_select"
    on public.memberships for select
    using (user_id = auth.uid());
