-- Live updates for workspace events: new members joining, team agents being
-- created, agents added to channels. Without these in the publication, clients
-- only see them after manual refresh / app restart.

alter publication supabase_realtime add table public.memberships;
alter publication supabase_realtime add table public.agents;
alter publication supabase_realtime add table public.channel_agents;
