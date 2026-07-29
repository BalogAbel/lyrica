-- Restore the security definer property on has_capability.
--
-- 20260323220000_fix_membership_helper_rls_recursion.sql introduced it to break
-- an RLS recursion: the "memberships are manageable by capability" ALL policy
-- calls can_manage_membership, which calls has_capability, which reads
-- public.memberships. Without security definer that read re-enters the same
-- policy and recurses until "stack depth limit exceeded".
--
-- 202605250002_organization_read_only_role_constraints.sql re-created the
-- function with create or replace to add the organization_read_only role and
-- dropped both security definer and search_path. 202607080001 (SEC-3) restored
-- search_path only, so authenticated reads of memberships — and the
-- get_my_capabilities RPC, which reads memberships as invoker — have been
-- failing since.
--
-- Uses ALTER FUNCTION rather than a redefinition so the current body stays the
-- single source of truth and cannot drift again in the same way.
alter function public.has_capability(uuid, text, uuid)
  security definer;
