-- Session item key: the shared plan layer of the song key (S3 PR 1).
-- Spec: docs/specs/2026-10-13-personal-song-settings.md (PS10-PS13);
-- ADR-042; ADR-038 amendment of 2026-10-13.
--
-- A song item's transpose and capo are what everyone who opens the song from
-- this plan sees; null falls through to the song's ChordPro base. Only
-- set_session_item_key writes them. It versions a key edit on
-- session_items.version (no other RPC bumps it), bumps the plan's
-- content_version like every child write, and leaves sessions.version alone:
-- a key is not session structure.

alter table public.session_items
  add column transpose smallint,
  add column capo smallint;

alter table public.session_items
  add constraint session_items_transpose_range_check
    check (transpose between -11 and 11),
  add constraint session_items_capo_range_check
    check (capo between 0 and 11);

create function public.set_session_item_key(
  p_organization_id uuid,
  p_session_id uuid,
  p_session_item_id uuid,
  p_base_version bigint,
  p_transpose_mode text,
  p_transpose integer,
  p_capo_mode text,
  p_capo integer
)
returns table (
  id uuid,
  plan_id uuid,
  session_id uuid,
  organization_id uuid,
  version bigint,
  transpose integer,
  capo integer,
  plan_content_version bigint
)
language plpgsql
security definer
set search_path = public
as $$
#variable_conflict use_column
declare
  existing_session public.sessions%rowtype;
  existing_item public.session_items%rowtype;
  v_new_transpose smallint;
  v_new_capo smallint;
  v_plan_content_version bigint;
begin
  -- PS12 step 1: validate the payload before reading or locking anything.
  if p_transpose_mode is null
    or p_capo_mode is null
    or p_transpose_mode not in ('keep', 'set', 'clear')
    or p_capo_mode not in ('keep', 'set', 'clear')
    or (
      p_transpose_mode = 'set'
      and (p_transpose is null or p_transpose not between -11 and 11)
    )
    or (p_transpose_mode <> 'set' and p_transpose is not null)
    or (
      p_capo_mode = 'set'
      and (p_capo is null or p_capo not between 0 and 11)
    )
    or (p_capo_mode <> 'set' and p_capo is not null)
  then
    raise exception using
      errcode = '22023',
      message = 'invalid_session_item_key',
      detail = 'Each mode is keep, set or clear; set needs a value in range, keep and clear need null';
  end if;

  -- Step 2: a key edit always names the version it was made against.
  if p_base_version is null then
    raise exception using
      errcode = 'P0001',
      message = 'session_item_version_conflict',
      detail = 'base_version is required for a session-item key edit';
  end if;

  -- Step 3: the same authorization as every session-item write.
  select *
  into existing_session
  from public.sessions as session
  where session.organization_id = p_organization_id
    and session.id = p_session_id
    and public.has_capability(
      session.organization_id,
      'canEditSessions',
      session.group_id
    );

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_not_found',
      detail = 'The target session does not exist in the requested organization';
  end if;

  -- Step 4: lock the owning plan row first (ADR-038 lock order), without
  -- bumping it yet, so a no-op can still return without writing.
  perform 1
  from public.plans as plan
  where plan.organization_id = p_organization_id
    and plan.id = existing_session.plan_id
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'plan_not_found',
      detail = 'The owning plan does not exist in the requested organization';
  end if;

  -- Step 5: re-read the song item after the lock.
  select *
  into existing_item
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.session_id = p_session_id
    and item.id = p_session_item_id
    and item.item_type = 'song'
  for update;

  if not found then
    raise exception using
      errcode = 'P0002',
      message = 'session_item_not_found',
      detail = 'The target song item does not exist in the requested session';
  end if;

  v_new_transpose := case p_transpose_mode
    when 'set' then p_transpose::smallint
    when 'clear' then null
    else existing_item.transpose
  end;
  v_new_capo := case p_capo_mode
    when 'set' then p_capo::smallint
    when 'clear' then null
    else existing_item.capo
  end;

  -- Step 6: every affected field already holds the requested value. Return
  -- the current row and write nothing, whatever the base (LF-T5b).
  if v_new_transpose is not distinct from existing_item.transpose
    and v_new_capo is not distinct from existing_item.capo
  then
    select plan.content_version
    into v_plan_content_version
    from public.plans as plan
    where plan.organization_id = p_organization_id
      and plan.id = existing_session.plan_id;

    return query
    select
      existing_item.id,
      existing_session.plan_id,
      existing_item.session_id,
      existing_item.organization_id,
      existing_item.version,
      existing_item.transpose::integer,
      existing_item.capo::integer,
      v_plan_content_version;
    return;
  end if;

  -- Step 7: optimistic concurrency on the item's own version.
  if existing_item.version <> p_base_version then
    raise exception using
      errcode = 'P0001',
      message = 'session_item_version_conflict',
      detail = format(
        'expected base_version %s but found current version %s',
        p_base_version::text,
        existing_item.version::text
      );
  end if;

  -- Step 8: write. The session's version is deliberately left alone.
  v_plan_content_version := public.bump_plan_content_version(
    p_organization_id,
    existing_session.plan_id
  );

  update public.session_items as item
  set
    transpose = v_new_transpose,
    capo = v_new_capo,
    version = item.version + 1,
    base_version = item.version,
    sync_status = 'synced',
    last_modified_by = auth.uid()
  where item.organization_id = p_organization_id
    and item.id = p_session_item_id;

  return query
  select
    item.id,
    existing_session.plan_id,
    item.session_id,
    item.organization_id,
    item.version,
    item.transpose::integer,
    item.capo::integer,
    v_plan_content_version
  from public.session_items as item
  where item.organization_id = p_organization_id
    and item.id = p_session_item_id;
end;
$$;

revoke all on function public.set_session_item_key(
  uuid, uuid, uuid, bigint, text, integer, text, integer
) from public, anon, authenticated;

grant execute on function public.set_session_item_key(
  uuid, uuid, uuid, bigint, text, integer, text, integer
) to authenticated;
