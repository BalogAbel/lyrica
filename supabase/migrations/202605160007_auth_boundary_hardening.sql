alter function public.set_updated_at()
  set search_path = public;

alter function public.can_manage_membership(uuid, public.scope_type, uuid)
  set search_path = public;

alter function public.session_group_id(uuid, uuid)
  set search_path = public;

alter function public.slugify(text)
  set search_path = public;

revoke all on table
  public.organizations,
  public.groups,
  public.memberships,
  public.songs,
  public.plans,
  public.sessions,
  public.session_items,
  public.attachments,
  public.invitations
from anon;

revoke all on function public.current_organization_ids()
from public, anon, authenticated;
revoke all on function public.has_capability(uuid, text, uuid)
from public, anon, authenticated;
revoke all on function public.can_manage_membership(uuid, public.scope_type, uuid)
from public, anon, authenticated;
revoke all on function public.session_group_id(uuid, uuid)
from public, anon, authenticated;

grant execute on function public.current_organization_ids()
to authenticated;
grant execute on function public.has_capability(uuid, text, uuid)
to authenticated;
grant execute on function public.can_manage_membership(uuid, public.scope_type, uuid)
to authenticated;
grant execute on function public.session_group_id(uuid, uuid)
to authenticated;

revoke all on function public.create_invitation(uuid, public.role_code, text)
from public, anon, authenticated;
revoke all on function public.redeem_invitation(text)
from public, anon, authenticated;
revoke all on function public.delete_account()
from public, anon, authenticated;

grant execute on function public.create_invitation(uuid, public.role_code, text)
to authenticated, service_role;
grant execute on function public.redeem_invitation(text)
to authenticated;
grant execute on function public.delete_account()
to authenticated;

revoke all on function public.create_song(uuid, text, text, text, integer, text[], text, jsonb, text, uuid)
from public, anon, authenticated;
revoke all on function public.update_song(uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb)
from public, anon, authenticated;
revoke all on function public.overwrite_song_update(uuid, uuid, bigint, text, text, text, text, integer, text[], text, jsonb)
from public, anon, authenticated;
revoke all on function public.delete_song(uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.overwrite_song_delete(uuid, uuid, bigint)
from public, anon, authenticated;

grant execute on function public.create_song(uuid, text, text, text, integer, text[], text, jsonb, text, uuid)
to authenticated;
grant execute on function public.update_song(uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb)
to authenticated;
grant execute on function public.overwrite_song_update(uuid, uuid, bigint, text, text, text, text, integer, text[], text, jsonb)
to authenticated;
grant execute on function public.delete_song(uuid, uuid, bigint)
to authenticated;
grant execute on function public.overwrite_song_delete(uuid, uuid, bigint)
to authenticated;

revoke all on function public.create_plan(uuid, uuid, text, text, text, timestamptz)
from public, anon, authenticated;
revoke all on function public.update_plan_fields(uuid, uuid, bigint, text, text, timestamptz)
from public, anon, authenticated;
revoke all on function public.create_session(uuid, uuid, uuid, text, text)
from public, anon, authenticated;
revoke all on function public.rename_session(uuid, uuid, bigint, text)
from public, anon, authenticated;
revoke all on function public.delete_empty_session(uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[])
from public, anon, authenticated;
revoke all on function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer)
from public, anon, authenticated;
revoke all on function public.delete_session_item(uuid, uuid, uuid, bigint)
from public, anon, authenticated;
revoke all on function public.reorder_session_items(uuid, uuid, bigint, uuid[])
from public, anon, authenticated;

grant execute on function public.create_plan(uuid, uuid, text, text, text, timestamptz)
to authenticated;
grant execute on function public.update_plan_fields(uuid, uuid, bigint, text, text, timestamptz)
to authenticated;
grant execute on function public.create_session(uuid, uuid, uuid, text, text)
to authenticated;
grant execute on function public.rename_session(uuid, uuid, bigint, text)
to authenticated;
grant execute on function public.delete_empty_session(uuid, uuid, bigint)
to authenticated;
grant execute on function public.reorder_plan_sessions(uuid, uuid, bigint, uuid[])
to authenticated;
grant execute on function public.create_song_session_item(uuid, uuid, uuid, uuid, bigint, integer)
to authenticated;
grant execute on function public.delete_session_item(uuid, uuid, uuid, bigint)
to authenticated;
grant execute on function public.reorder_session_items(uuid, uuid, bigint, uuid[])
to authenticated;

revoke all on function public.require_song_write_access(uuid)
from public, anon, authenticated;
revoke all on function public.song_next_slug(uuid, text)
from public, anon, authenticated;
revoke all on function public.song_write_update_common(uuid, uuid, bigint, text, text, text, integer, text[], text, jsonb, boolean)
from public, anon, authenticated;
revoke all on function public.song_write_delete_common(uuid, uuid, bigint, boolean)
from public, anon, authenticated;
revoke all on function public.require_plan_write_access(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.require_session_write_access(uuid, uuid)
from public, anon, authenticated;
revoke all on function public.plan_next_slug(uuid, text)
from public, anon, authenticated;
revoke all on function public.session_next_slug(uuid, text)
from public, anon, authenticated;
revoke all on function public.slugify(text)
from public, anon, authenticated;
