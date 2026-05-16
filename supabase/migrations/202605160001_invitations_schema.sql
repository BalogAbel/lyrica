create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  email text,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  role_code public.role_code not null
    check (role_code in ('organization_admin', 'organization_member')),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id) on delete set null,
  issued_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default timezone('utc', now())
);
create index invitations_active_token_idx
  on public.invitations(token)
  where redeemed_at is null;
