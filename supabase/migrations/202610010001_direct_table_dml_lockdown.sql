-- Direct table DML lockdown.
-- Spec: docs/specs/2026-10-01-direct-table-dml-lockdown.md; ADR-039.
--
-- Writes to the application tables go only through security definer RPCs,
-- which run as the table owner. This migration removes every other write path:
--   1. anon and authenticated lose every privilege on every table and
--      sequence in public, including any a drifted database holds beyond the
--      ten known tables; authenticated then gets SELECT back on exactly those
--      ten (the ADR-026 read boundary). TRUNCATE ignores RLS, so it must go
--      even though no policy allows it.
--   2. The six permissive `for all` write policies are dropped. Each one is
--      already covered by its table's select policy: has_capability is true
--      only for an organization the caller is an active member of, and the
--      canEditSongs roles are a subset of the canViewSongs roles. No visible
--      row changes.
--   3. Objects postgres creates in public from now on start with no grant to
--      anon, authenticated or service_role (functions keep PUBLIC EXECUTE, see
--      below); each migration grants what it needs explicitly.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

grant select on table
  public.organizations,
  public.groups,
  public.memberships,
  public.songs,
  public.plans,
  public.sessions,
  public.session_items,
  public.attachments,
  public.invitations,
  public.invitation_redemption_attempts
to authenticated;

drop policy "memberships are manageable by capability" on public.memberships;
drop policy "songs are editable with song edit capability" on public.songs;
drop policy "plans are editable with plan capability" on public.plans;
drop policy "sessions are editable with session capability" on public.sessions;
drop policy "session items inherit session edit capability" on public.session_items;
drop policy "attachments are editable to song editors" on public.attachments;

-- `revoke all`, not the four table privileges the Supabase guide lists: those
-- leave TRUNCATE, REFERENCES, TRIGGER and MAINTAIN granted on every new table.
-- PUBLIC keeps the PostgreSQL-global EXECUTE default on functions, which a
-- per-schema revoke cannot remove, so every function migration still revokes
-- from public, anon and authenticated explicitly.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on functions from anon, authenticated, service_role;
