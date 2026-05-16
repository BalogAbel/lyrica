alter table public.invitations enable row level security;

create policy invitations_select_admin_or_issuer
  on public.invitations
  for select
  to authenticated
  using (
    issued_by = auth.uid()
    or exists (
      select 1
      from public.memberships m
      where m.user_id = auth.uid()
        and m.organization_id = invitations.organization_id
        and m.scope_type = 'organization'
        and m.role_code = 'organization_admin'
        and m.status = 'active'
    )
  );

-- Writes happen only through security-definer functions; deny authenticated direct DML.
create policy invitations_no_direct_insert
  on public.invitations for insert
  to authenticated
  with check (false);

create policy invitations_no_direct_update
  on public.invitations for update
  to authenticated
  using (false);

create policy invitations_no_direct_delete
  on public.invitations for delete
  to authenticated
  using (false);
