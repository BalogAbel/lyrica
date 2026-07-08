-- SEC-3: pin a non-mutable search_path on the capability helpers.
-- has_capability lost its search_path when redefined in
-- 202605250002_organization_read_only_role_constraints.sql; get_my_capabilities
-- (202605280001) never carried one. current_organization_ids already sets it.
-- Matches the ALTER FUNCTION hardening style of
-- 202605160007_auth_boundary_hardening.sql.
alter function public.has_capability(uuid, text, uuid)
  set search_path = public;

alter function public.get_my_capabilities(uuid, uuid)
  set search_path = public;
