-- ─── RPC: create_invitation ──────────────────────────────────────────────────
-- Any workspace member can generate an invite. Optional email gates redemption.

create or replace function public.create_invitation(
    p_workspace_id uuid,
    p_email        text default null,
    p_role         public.member_role default 'member'
)
returns public.invitations language plpgsql security definer set search_path = public as $$
declare
    uid uuid := auth.uid();
    inv public.invitations%rowtype;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    if not exists (
        select 1 from public.memberships
        where workspace_id = p_workspace_id and user_id = uid
    ) then
        raise exception 'Not a member of this workspace';
    end if;

    insert into public.invitations (workspace_id, email, invited_by, role)
    values (p_workspace_id, lower(trim(p_email)), uid, p_role)
    returning * into inv;

    return inv;
end;
$$;

-- ─── RPC: preview_invitation ─────────────────────────────────────────────────
-- Returns workspace details for a given invite code WITHOUT joining.
-- Used to show the join-preview card before the user commits.
-- SECURITY DEFINER so non-members can read workspace name + member count.

create or replace function public.preview_invitation(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
    inv           public.invitations%rowtype;
    ws            public.workspaces%rowtype;
    inviter       public.users%rowtype;
    member_count  int;
    caller_id     uuid := auth.uid();
    already_member bool;
begin
    select * into inv from public.invitations where code = trim(p_code);

    if not found then
        raise exception 'Invalid invite code';
    end if;

    if inv.expires_at < now() then
        raise exception 'This invite link has expired';
    end if;

    if inv.redeemed_by is not null then
        -- Check if the caller is the one who redeemed — treat as success
        if inv.redeemed_by = caller_id then
            -- fall through, they can still preview their own workspace
            null;
        else
            raise exception 'This invite has already been used';
        end if;
    end if;

    select * into ws      from public.workspaces where id = inv.workspace_id;
    select * into inviter from public.users      where id = inv.invited_by;
    select count(*) into member_count
        from public.memberships where workspace_id = inv.workspace_id;

    select exists (
        select 1 from public.memberships
        where workspace_id = inv.workspace_id and user_id = caller_id
    ) into already_member;

    return json_build_object(
        'workspace_id',    ws.id::text,
        'workspace_name',  ws.name,
        'workspace_slug',  ws.slug,
        'invited_by_name', coalesce(inviter.display_name, inviter.email),
        'member_count',    member_count,
        'expires_at',      inv.expires_at,
        'email_gated',     inv.email is not null,
        'already_member',  already_member
    );
end;
$$;
