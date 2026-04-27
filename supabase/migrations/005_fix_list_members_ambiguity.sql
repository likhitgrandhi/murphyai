-- Fix: column reference "user_id" was ambiguous because the function's
-- RETURNS TABLE declares a user_id output column and the membership check
-- referenced `user_id` without a table qualifier. Rewrite with explicit
-- qualifications throughout.

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
        select 1 from public.memberships m
        where m.workspace_id = p_workspace_id and m.user_id = uid
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
