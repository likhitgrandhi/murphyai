-- The Swift client INSERTed directly into agents but didn't supply created_by,
-- so the RLS check `created_by = auth.uid()` failed every time. Same pattern
-- as create_channel/create_dm: a SECURITY DEFINER RPC fills in the caller and
-- validates workspace membership atomically.

create or replace function public.create_team_agent(
    p_workspace_id  uuid,
    p_slug          text,
    p_display_name  text,
    p_system_prompt text,
    p_model         text default 'claude-opus-4-7',
    p_avatar_tint   text default null
) returns public.agents
language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    a   public.agents%rowtype;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    if not exists (
        select 1 from public.memberships
        where workspace_id = p_workspace_id and user_id = uid
    ) then
        raise exception 'Not a member of this workspace';
    end if;

    if p_display_name is null or btrim(p_display_name) = '' then
        raise exception 'Display name required';
    end if;
    if p_slug is null or btrim(p_slug) = '' then
        raise exception 'Slug required';
    end if;

    insert into public.agents (
        workspace_id, slug, display_name, system_prompt,
        model, avatar_tint, created_by
    ) values (
        p_workspace_id, lower(btrim(p_slug)), btrim(p_display_name), p_system_prompt,
        p_model, p_avatar_tint, uid
    ) returning * into a;

    return a;
end;
$$;
