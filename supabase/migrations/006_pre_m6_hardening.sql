-- Pre-M6 hardening pass. Tightens invitations RLS, gives create_workspace
-- a friendly slug-taken error, folds the workspace row into the redeem
-- response to avoid a post-RPC race, and adds the FK indexes we'll lean on
-- once shared channels land.

-- ─── P1 #11 — invitations: restrict who can read rows ────────────────────────
-- Previous policy let any workspace member read every invitation (including
-- the invited email, which is PII of a person who hasn't even joined yet).
-- Tighten to: workspace owner, invite creator, or the invitee by email.

drop policy if exists "invitations_select_members" on public.invitations;

create policy "invitations_select_scoped"
    on public.invitations for select
    using (
        -- Workspace owner sees all invitations for their workspace.
        exists (
            select 1 from public.workspaces w
            where w.id = invitations.workspace_id
              and w.owner_id = auth.uid()
        )
        -- Or the caller created the invite.
        or invitations.invited_by = auth.uid()
        -- Or the invite is email-gated and targets the caller's own email.
        or (
            invitations.email is not null
            and exists (
                select 1 from public.users u
                where u.id = auth.uid()
                  and lower(u.email) = lower(invitations.email)
            )
        )
    );

-- ─── P1 #6 — create_workspace: friendly error on slug collision ─────────────
-- Client-side slug generation can collide across users ("Acme" → "acme").
-- Raise a named exception that the Swift layer can map to a helpful UI
-- message instead of surfacing Postgres's unique-violation SQLSTATE.

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

    if exists (select 1 from public.workspaces where slug = workspace_slug) then
        raise exception 'workspace_slug_exists' using errcode = 'P0001';
    end if;

    insert into public.workspaces (name, slug, owner_id)
    values (workspace_name, workspace_slug, uid)
    returning * into ws;

    insert into public.memberships (workspace_id, user_id, role)
    values (ws.id, uid, 'owner');

    return ws;
end;
$$;

-- ─── P1 #7 — redeem_invitation: return the full workspace row ───────────────
-- Old flow: RPC returned workspace_id, client did a follow-up SELECT that
-- can race the membership-insert's commit visibility. Return the workspace
-- inline so the join commit and the data needed for UI arrive atomically.

create or replace function public.redeem_invitation(invite_code text)
returns json language plpgsql security definer set search_path = public as $$
declare
    inv          public.invitations%rowtype;
    ws           public.workspaces%rowtype;
    uid          uuid := auth.uid();
    caller_email text;
    already      bool := false;
begin
    if uid is null then raise exception 'Not authenticated'; end if;

    select * into inv from public.invitations
    where code = invite_code
    for update;

    if not found then
        raise exception 'Invalid invite code';
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
        already := true;
    else
        if inv.redeemed_by is not null then
            raise exception 'Invite already redeemed';
        end if;
        insert into public.memberships (workspace_id, user_id, role)
        values (inv.workspace_id, uid, inv.role);
        update public.invitations
        set redeemed_by = uid, redeemed_at = now()
        where id = inv.id;
    end if;

    select * into ws from public.workspaces where id = inv.workspace_id;

    return json_build_object(
        'workspace_id',   ws.id::text,
        'already_member', already,
        'workspace',      row_to_json(ws)
    );
end;
$$;

-- ─── P1 #12 — FK indexes ─────────────────────────────────────────────────────
-- memberships_user_workspace already has a unique(workspace_id, user_id) index.
-- Add a user_id-leading lookup for "what workspaces is this user in?" which is
-- the most frequent query (workspaces RLS + bootstrap refresh both hit it).

create index if not exists idx_memberships_user_id
    on public.memberships (user_id);

create index if not exists idx_invitations_workspace_id
    on public.invitations (workspace_id);

create index if not exists idx_invitations_invited_by
    on public.invitations (invited_by);

create index if not exists idx_invitations_code
    on public.invitations (code);
