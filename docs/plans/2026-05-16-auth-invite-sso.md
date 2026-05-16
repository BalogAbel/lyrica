# Auth Invite-Only SSO Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver invite-only onboarding with Google + Apple + magic link sign-in, hard account deletion, and orphan cleanup, per `docs/specs/2026-05-16-auth-invite-sso.md`.

**Architecture:** Separate identity (Supabase Auth) from authorization (membership). Provider sign-in only produces a session; access is granted by `redeem_invitation` creating an active membership row. Deep links carry invite tokens to the app; the router gates app entry on ADR-016 active-organization resolution. `pg_cron` deletes orphan `auth.users` rows after 24 hours.

**Tech Stack:** Postgres + Supabase Auth + RLS + `pg_cron`; Flutter (`supabase_flutter`, `flutter_riverpod`, `go_router`, new `app_links` dependency); existing Drift offline stores; ADR-007 capability model.

**Pre-existing code this slice extends:**
- `apps/lyron_app/lib/src/application/auth/auth_repository.dart` — repository interface (currently password-only)
- `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart` — auth state controller
- `apps/lyron_app/lib/src/domain/auth/app_auth_status.dart` — `AppAuthStatus` enum
- `apps/lyron_app/lib/src/infrastructure/auth/supabase_auth_repository.dart` — Supabase wrapper
- `apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart` — current email+password screen (to be replaced)
- `apps/lyron_app/lib/src/router/app_router.dart` — router gate location
- `apps/lyron_app/lib/src/application/providers.dart` — DI graph
- `apps/lyron_app/lib/src/shared/app_strings.dart` — i18n strings

---

## File Structure (created or modified)

### Backend (Supabase)

| Path | Action | Responsibility |
|---|---|---|
| `supabase/migrations/202605160001_invitations_schema.sql` | create | `invitations` table, indexes |
| `supabase/migrations/202605160002_invitations_functions.sql` | create | `create_invitation`, `redeem_invitation`, error contract |
| `supabase/migrations/202605160003_invitations_rls.sql` | create | RLS policies on `invitations` |
| `supabase/migrations/202605160004_last_modified_by_on_delete_set_null.sql` | create | Adjust FKs so `auth.users` delete preserves audit-less rows |
| `supabase/migrations/202605160005_delete_account_function.sql` | create | `delete_account` RPC |
| `supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql` | create | `pg_cron` hourly cleanup |
| `supabase/migrations/202605160007_auth_boundary_hardening.sql` | create | Revoke anon table/RPC access, grant app-facing RPCs explicitly, set helper `search_path` |
| `supabase/migrations/202605160008_revoke_anon_rls_auto_enable.sql` | create | Revoke anon execution from Supabase-created `rls_auto_enable` when present |
| `supabase/snippets/auth_invite_tests.sql` | create | SQL contract tests (executable via `psql`) |
| `supabase/config.toml` | modify | Enable `pg_cron`, Apple + Google providers, magic link settings |
| `supabase/seed/seed.sql` | modify (only if seed needs admin bootstrap) | Add singleton organization + first admin invite |

### Flutter (`apps/lyron_app/lib/src/`)

| Path | Action | Responsibility |
|---|---|---|
| `domain/auth/sign_in_method.dart` | create | `enum SignInMethod { google, apple, magicLink }` |
| `domain/auth/invitation_error.dart` | create | `enum InvitationError { notFound, expired, alreadyRedeemed, alreadyMember, network, unknown }` |
| `domain/auth/redeem_result.dart` | create | `sealed class RedeemResult` with `success(orgId)` / `failure(error)` variants |
| `domain/auth/pending_invite_token.dart` | create | Value type wrapping a captured token + capture timestamp |
| `domain/auth/app_auth_session.dart` | modify | Add `linkedIdentities: List<String>` (provider names) |
| `domain/auth/app_auth_status.dart` | leave | Existing enum reused |
| `application/auth/auth_repository.dart` | modify | Replace `signIn(email,password)` with `signInWithOAuth(SignInMethod)`, `signInWithMagicLink(email)`, `signOut`, `deleteAccount` |
| `application/auth/invitation_repository.dart` | create | Wraps `redeem_invitation` RPC |
| `application/auth/app_auth_controller.dart` | modify | New methods aligned with the updated repository; remove password sign-in |
| `application/auth/redeem_controller.dart` | create | Drives redeem state machine |
| `application/auth/pending_invite_token_controller.dart` | create | Holds the captured token in memory until redeemed or discarded |
| `application/auth/deep_link_listener.dart` | create | Subscribes to `app_links` streams, routes `/invite` and `/auth/callback` |
| `infrastructure/auth/supabase_auth_repository.dart` | modify | Replace password flow with OAuth + OTP; expose linked identities |
| `infrastructure/auth/supabase_invitation_repository.dart` | create | `redeem_invitation` RPC client |
| `presentation/auth/sign_in_screen.dart` | rewrite | Three provider entry points + magic-link email field |
| `presentation/auth/magic_link_sent_screen.dart` | create | Confirmation after magic-link send |
| `presentation/auth/invite_required_screen.dart` | create | Paste-link fallback when authenticated user has no membership and no pending token |
| `presentation/auth/redeem_progress_screen.dart` | create | Spinner + error display during auto-redeem |
| `presentation/account/account_screen.dart` | create | Sign out + delete account |
| `router/app_router.dart` | modify | Add `/invite`, `/auth/callback`, `/magic-link-sent`, `/invite-required`, `/redeem`, `/account` routes; update redirect logic |
| `application/providers.dart` | modify | Wire new controllers and repositories |
| `shared/app_strings.dart` | modify | Add new copy keys (Hungarian + English forms — keep existing scheme) |
| `bootstrap/app_bootstrap.dart` (or equivalent main wiring) | modify | Register deep-link listener at startup |

### Flutter tests

| Path | Action |
|---|---|
| `test/application/auth/redeem_controller_test.dart` | create |
| `test/application/auth/pending_invite_token_controller_test.dart` | create |
| `test/application/auth/deep_link_listener_test.dart` | create |
| `test/infrastructure/auth/supabase_invitation_repository_test.dart` | create |
| `test/infrastructure/auth/supabase_auth_repository_test.dart` | rewrite for OAuth + OTP |
| `test/application/auth/app_auth_controller_test.dart` | rewrite for OAuth + OTP |
| `test/presentation/auth/sign_in_screen_test.dart` | rewrite for provider buttons |
| `test/presentation/auth/invite_required_screen_test.dart` | create |
| `test/presentation/account/account_screen_test.dart` | create |
| `test/router/router_redirect_test.dart` | create (or extend existing router tests) |
| `test/integration/invite_redeem_flow_test.dart` | create |

### Mobile platform configuration

| Path | Action | Responsibility |
|---|---|---|
| `apps/lyron_app/ios/Runner/Runner.entitlements` | modify | Add `com.apple.developer.applesignin` and Associated Domains |
| `apps/lyron_app/ios/Runner/Info.plist` | modify | Add URL types + `CFBundleURLSchemes` |
| `apps/lyron_app/android/app/src/main/AndroidManifest.xml` | modify | Add intent filters for App Links + custom scheme |
| `apps/lyron_app/web/.well-known/apple-app-site-association` | create (stub) | Sample file; production version is deployed via the staging host |
| `apps/lyron_app/web/.well-known/assetlinks.json` | create (stub) | Sample file |

### Documentation

| Path | Action |
|---|---|
| `docs/architecture/decisions/ADR-018-invite-only-auth-with-token-redemption.md` | create |
| `docs/architecture/state-machines.md` | modify (auth + invitation lifecycles) |
| `docs/domain/domain-model.md` | modify (Invitation entity) |
| `docs/domain/domain-vocabulary.md` | modify (`Invitation`, `Redeem`, `Magic link`) |
| `docs/architecture/architecture.md` | modify (auth boundary description) |
| `docs/workflows/development-workflow.md` | modify only if invite-issuance steps belong here |
| `README.md` | modify only if onboarding steps change for contributors |

---

## Phase 1 — Backend: invitations schema, functions, RLS

### Task 1: Create `invitations` table migration

**Files:**
- Create: `supabase/migrations/202605160001_invitations_schema.sql`
- Test: `supabase/snippets/auth_invite_tests.sql` (initial scaffold)

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/202605160001_invitations_schema.sql
create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  token text not null unique,
  email text,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  role_code public.role_code not null
    check (role_code in ('organization_admin', 'organization_member')),
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id),
  issued_by uuid references auth.users(id),
  created_at timestamptz not null default timezone('utc', now())
);

create index invitations_active_token_idx
  on public.invitations(token)
  where redeemed_at is null;
```

- [ ] **Step 2: Scaffold the SQL test file**

```sql
-- supabase/snippets/auth_invite_tests.sql
-- Run with: ./scripts/supabase.sh db reset && psql "$(./scripts/supabase.sh status --json | jq -r .DB_URL)" -f supabase/snippets/auth_invite_tests.sql
\set ON_ERROR_STOP on
begin;

-- Sanity: invitations table exists with expected columns
do $$
begin
  perform 1 from public.invitations limit 0;
end$$;

rollback;
```

- [ ] **Step 3: Apply migration locally**

```bash
./scripts/supabase.sh db reset
```

Expected: migration applies cleanly; no errors.

- [ ] **Step 4: Run the sanity test**

```bash
psql "postgres://postgres:postgres@localhost:54322/postgres" -f supabase/snippets/auth_invite_tests.sql
```

Expected: `do` block runs without error; transaction rolls back.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/202605160001_invitations_schema.sql supabase/snippets/auth_invite_tests.sql
git commit -m "feat(db): add invitations table for token-based onboarding"
```

### Task 2: `create_invitation` and `redeem_invitation` functions

**Files:**
- Create: `supabase/migrations/202605160002_invitations_functions.sql`
- Modify: `supabase/snippets/auth_invite_tests.sql`

- [ ] **Step 1: Write the function migration**

```sql
-- supabase/migrations/202605160002_invitations_functions.sql
create or replace function public.create_invitation(
  p_organization_id uuid,
  p_role public.role_code,
  p_email text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_token text;
  v_is_admin boolean;
begin
  if v_caller is not null then
    select exists (
      select 1
      from public.memberships m
      where m.user_id = v_caller
        and m.organization_id = p_organization_id
        and m.scope_type = 'organization'
        and m.role_code = 'organization_admin'
        and m.status = 'active'
    ) into v_is_admin;

    if not v_is_admin then
      raise exception using
        errcode = '42501',
        message = 'invitation_create_not_authorized';
    end if;
  end if;

  v_token := translate(encode(gen_random_bytes(32), 'base64'), '+/=', '-_');

  insert into public.invitations (
    token, email, organization_id, role_code,
    expires_at, issued_by
  ) values (
    v_token, p_email, p_organization_id, p_role,
    now() + interval '30 days', v_caller
  );

  return v_token;
end;
$$;

create or replace function public.redeem_invitation(
  p_token text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_inv public.invitations%rowtype;
begin
  if v_caller is null then
    raise exception using
      errcode = '42501',
      message = 'invitation_redeem_requires_auth';
  end if;

  select * into v_inv
  from public.invitations
  where token = p_token
  for update;

  if not found then
    raise exception using errcode = 'P0001', message = 'invitation_not_found';
  end if;

  if v_inv.redeemed_at is not null then
    raise exception using errcode = 'P0001', message = 'invitation_already_redeemed';
  end if;

  if v_inv.expires_at <= now() then
    raise exception using errcode = 'P0001', message = 'invitation_expired';
  end if;

  if exists (
    select 1
    from public.memberships m
    where m.user_id = v_caller
      and m.organization_id = v_inv.organization_id
      and m.scope_type = 'organization'
      and m.status = 'active'
  ) then
    raise exception using errcode = 'P0001', message = 'already_member';
  end if;

  insert into public.memberships (
    organization_id, user_id, scope_type, role_code, status
  ) values (
    v_inv.organization_id, v_caller, 'organization', v_inv.role_code, 'active'
  );

  update public.invitations
  set redeemed_at = now(),
      redeemed_by = v_caller
  where id = v_inv.id;

  return v_inv.organization_id;
end;
$$;
```

- [ ] **Step 2: Extend the test snippet**

Append to `supabase/snippets/auth_invite_tests.sql` before the existing `rollback;`:

```sql
-- Seed an organization and an admin user
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000001', 'admin@test.local'),
  ('00000000-0000-0000-0000-000000000002', 'invitee@test.local');

insert into public.organizations (id, name, slug)
values ('00000000-0000-0000-0000-0000000000aa', 'Test Org', 'test-org');

insert into public.memberships (
  organization_id, user_id, scope_type, role_code, status
) values (
  '00000000-0000-0000-0000-0000000000aa',
  '00000000-0000-0000-0000-000000000001',
  'organization', 'organization_admin', 'active'
);

-- Service-role caller (auth.uid() = null) can create an invite
do $$
declare
  v_token text;
begin
  v_token := public.create_invitation(
    '00000000-0000-0000-0000-0000000000aa',
    'organization_member',
    'invitee@test.local'
  );
  if v_token is null or length(v_token) < 16 then
    raise exception 'expected token, got %', v_token;
  end if;
end$$;

-- Redeem path: simulate auth.uid via local config
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000002"}';

do $$
declare
  v_token text;
  v_org uuid;
begin
  select token into v_token from public.invitations limit 1;
  v_org := public.redeem_invitation(v_token);
  if v_org is null then
    raise exception 'redeem returned null';
  end if;
end$$;

-- Second redeem must fail with invitation_already_redeemed
do $$
declare
  v_token text;
begin
  select token into v_token from public.invitations limit 1;
  begin
    perform public.redeem_invitation(v_token);
    raise exception 'expected already_redeemed';
  exception when others then
    if sqlerrm not like '%invitation_already_redeemed%' then
      raise;
    end if;
  end;
end$$;
```

- [ ] **Step 3: Apply migration and run tests**

```bash
./scripts/supabase.sh db reset
psql "postgres://postgres:postgres@localhost:54322/postgres" -f supabase/snippets/auth_invite_tests.sql
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/202605160002_invitations_functions.sql supabase/snippets/auth_invite_tests.sql
git commit -m "feat(db): add create_invitation and redeem_invitation functions"
```

### Task 3: Invitations RLS policies

**Files:**
- Create: `supabase/migrations/202605160003_invitations_rls.sql`
- Modify: `supabase/snippets/auth_invite_tests.sql`

- [ ] **Step 1: Write the policies**

```sql
-- supabase/migrations/202605160003_invitations_rls.sql
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
```

- [ ] **Step 2: Extend the test snippet**

Append to `supabase/snippets/auth_invite_tests.sql`:

```sql
-- A non-admin authenticated user cannot select an invitation they did not issue
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000099"}';
set local role = 'authenticated';

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from public.invitations;
  if v_count <> 0 then
    raise exception 'expected 0 visible invitations, got %', v_count;
  end if;
end$$;

reset role;
```

- [ ] **Step 3: Apply and verify**

```bash
./scripts/supabase.sh db reset
psql "postgres://postgres:postgres@localhost:54322/postgres" -f supabase/snippets/auth_invite_tests.sql
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/202605160003_invitations_rls.sql supabase/snippets/auth_invite_tests.sql
git commit -m "feat(db): enforce invitations RLS (admin/issuer read, function-only writes)"
```

### Task 4: Convert `last_modified_by` FKs to `on delete set null`

**Files:**
- Create: `supabase/migrations/202605160004_last_modified_by_on_delete_set_null.sql`
- Modify: `supabase/snippets/auth_invite_tests.sql`

- [ ] **Step 1: Inspect current FKs**

```bash
psql "postgres://postgres:postgres@localhost:54322/postgres" -c "\d+ public.songs"
```

Identify any `last_modified_by` FK without `on delete set null` (initial schema declared the column without an explicit delete rule, so the default is `no action`).

- [ ] **Step 2: Write the migration**

```sql
-- supabase/migrations/202605160004_last_modified_by_on_delete_set_null.sql
alter table public.songs
  drop constraint if exists songs_last_modified_by_fkey,
  add constraint songs_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.plans
  drop constraint if exists plans_last_modified_by_fkey,
  add constraint plans_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.sessions
  drop constraint if exists sessions_last_modified_by_fkey,
  add constraint sessions_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.attachments
  drop constraint if exists attachments_last_modified_by_fkey,
  add constraint attachments_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;

alter table public.session_items
  drop constraint if exists session_items_last_modified_by_fkey,
  add constraint session_items_last_modified_by_fkey
    foreign key (last_modified_by) references auth.users(id)
    on delete set null;
```

(Adjust this set if `\d+` shows additional tables with `last_modified_by`; the rule is: every `last_modified_by` becomes `on delete set null`.)

- [ ] **Step 3: Test**

Append:

```sql
-- Deleting an author preserves their songs but nulls out last_modified_by
insert into public.songs (
  id, organization_id, title, chordpro_source, last_modified_by
) values (
  '00000000-0000-0000-0000-0000000000bb',
  '00000000-0000-0000-0000-0000000000aa',
  'Sample Song',
  '{title: Sample}',
  '00000000-0000-0000-0000-000000000002'
);

delete from auth.users where id = '00000000-0000-0000-0000-000000000002';

do $$
declare
  v_modified_by uuid;
begin
  select last_modified_by into v_modified_by
  from public.songs
  where id = '00000000-0000-0000-0000-0000000000bb';
  if v_modified_by is not null then
    raise exception 'expected last_modified_by null after author delete, got %', v_modified_by;
  end if;
end$$;
```

- [ ] **Step 4: Apply, run, commit**

```bash
./scripts/supabase.sh db reset
psql "postgres://postgres:postgres@localhost:54322/postgres" -f supabase/snippets/auth_invite_tests.sql
git add supabase/migrations/202605160004_last_modified_by_on_delete_set_null.sql supabase/snippets/auth_invite_tests.sql
git commit -m "fix(db): preserve content rows when authoring users are deleted"
```

### Task 5: `delete_account` function

**Files:**
- Create: `supabase/migrations/202605160005_delete_account_function.sql`

- [ ] **Step 1: Write the function**

```sql
-- supabase/migrations/202605160005_delete_account_function.sql
create or replace function public.delete_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception using
      errcode = '42501',
      message = 'delete_account_requires_auth';
  end if;

  delete from auth.users where id = v_caller;
end;
$$;

revoke all on function public.delete_account() from public;
grant execute on function public.delete_account() to authenticated;
```

- [ ] **Step 2: Test**

Append:

```sql
-- Re-seed a user, sign in, call delete_account, verify gone
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-000000000077', 'deletable@test.local');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-000000000077"}';

do $$ begin perform public.delete_account(); end$$;

do $$
declare
  v_count integer;
begin
  select count(*) into v_count from auth.users where id = '00000000-0000-0000-0000-000000000077';
  if v_count <> 0 then
    raise exception 'expected 0, got %', v_count;
  end if;
end$$;
```

- [ ] **Step 3: Apply, run, commit**

```bash
./scripts/supabase.sh db reset
psql "postgres://postgres:postgres@localhost:54322/postgres" -f supabase/snippets/auth_invite_tests.sql
git add supabase/migrations/202605160005_delete_account_function.sql supabase/snippets/auth_invite_tests.sql
git commit -m "feat(db): add delete_account RPC for self-serve hard delete"
```

### Task 6: `pg_cron` orphan cleanup

**Files:**
- Create: `supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql`
- Modify: `supabase/config.toml`

- [ ] **Step 1: Enable `pg_cron` in `config.toml`**

In `supabase/config.toml`, ensure the `[db]` section enables required extensions. If the file does not currently list extensions, append after the `[db]` block:

```toml
[db.extensions]
enabled = ["pg_cron"]
```

(Verify the precise key against `./scripts/supabase.sh config` output; this codebase uses Supabase CLI version that supports `db.extensions`. If the local CLI does not, the migration enables the extension on its own and the only change needed is in SQL.)

- [ ] **Step 2: Write the migration**

```sql
-- supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql
create extension if not exists pg_cron;

select cron.schedule(
  'cleanup-orphan-auth-users',
  '0 * * * *',
  $cron$
    delete from auth.users u
    where u.created_at < now() - interval '24 hours'
      and not exists (
        select 1
        from public.memberships m
        where m.user_id = u.id
          and m.status = 'active'
      )
  $cron$
);
```

- [ ] **Step 3: Test (manual)**

```bash
./scripts/supabase.sh db reset
psql "postgres://postgres:postgres@localhost:54322/postgres" -c "select jobname from cron.job;"
```

Expected output includes `cleanup-orphan-auth-users`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql supabase/config.toml
git commit -m "feat(db): hourly pg_cron cleanup of orphan auth.users"
```

---

## Phase 2 — Supabase Auth configuration

### Task 7: Configure providers and same-email linking

**Files:**
- Modify: `supabase/config.toml`
- Create: `docs/workflows/auth-provider-setup.md` (operational notes — staging keys and dashboard steps)

- [ ] **Step 1: Update `config.toml` auth section**

Replace or extend the `[auth]` block:

```toml
[auth]
enabled = true
site_url = "http://localhost:3000"
additional_redirect_urls = [
  "http://localhost:3000",
  "http://localhost:8080",
  "io.lyron.app://auth/callback"
]
jwt_expiry = 3600
enable_signup = true

[auth.email]
enable_signup = true
double_confirm_changes = true
enable_confirmations = false

[auth.external.google]
enabled = true
client_id = "env(SUPABASE_AUTH_GOOGLE_CLIENT_ID)"
secret = "env(SUPABASE_AUTH_GOOGLE_SECRET)"
redirect_uri = ""
skip_nonce_check = false

[auth.external.apple]
enabled = true
client_id = "env(SUPABASE_AUTH_APPLE_CLIENT_ID)"
secret = "env(SUPABASE_AUTH_APPLE_SECRET)"
redirect_uri = ""
```

Add a `[auth.identities]` section if the CLI supports it; otherwise the same-email linking flag is configured in the hosted dashboard and recorded in the new operational doc.

- [ ] **Step 2: Write the operational note**

Create `docs/workflows/auth-provider-setup.md`:

```markdown
# Auth Provider Setup

This document captures the dashboard-only configuration that cannot be expressed in `supabase/config.toml`.

## Google

1. Create OAuth client IDs for iOS, Android, and Web in the Google Cloud Console.
2. Configure them as `SUPABASE_AUTH_GOOGLE_CLIENT_ID` (web client) and `SUPABASE_AUTH_GOOGLE_SECRET` in the Supabase project secrets and locally in `.env.local`.

## Apple

1. Create a Services ID, key, and team ID in the Apple Developer portal.
2. Configure them as `SUPABASE_AUTH_APPLE_CLIENT_ID` (Services ID) and `SUPABASE_AUTH_APPLE_SECRET` (signing payload).
3. iOS native sign-in additionally requires `com.apple.developer.applesignin` capability in the entitlements file.

## Same-email linking

In the Supabase dashboard, navigate to Authentication → Providers → "Manually link same emails" and enable it. There is no `config.toml` flag for this option at the CLI version pinned in `tooling/supabase`.

## Magic-link email template

The default Supabase template is acceptable for staging. Production rollout replaces the template via `auth/email-templates/magic_link.html` once a transactional provider is wired (deferred from this slice).
```

- [ ] **Step 3: Commit**

```bash
git add supabase/config.toml docs/workflows/auth-provider-setup.md
git commit -m "feat(auth): configure Google + Apple + magic link in supabase config"
```

---

## Phase 3 — Flutter domain + data + application

### Task 8: Domain types

**Files:**
- Create: `apps/lyron_app/lib/src/domain/auth/sign_in_method.dart`
- Create: `apps/lyron_app/lib/src/domain/auth/invitation_error.dart`
- Create: `apps/lyron_app/lib/src/domain/auth/redeem_result.dart`
- Create: `apps/lyron_app/lib/src/domain/auth/pending_invite_token.dart`
- Modify: `apps/lyron_app/lib/src/domain/auth/app_auth_session.dart`

- [ ] **Step 1: Write `SignInMethod`**

```dart
// apps/lyron_app/lib/src/domain/auth/sign_in_method.dart
enum SignInMethod { google, apple, magicLink }
```

- [ ] **Step 2: Write `InvitationError`**

```dart
// apps/lyron_app/lib/src/domain/auth/invitation_error.dart
enum InvitationError {
  notFound,
  expired,
  alreadyRedeemed,
  alreadyMember,
  network,
  unknown,
}

InvitationError invitationErrorFromMessage(String? message) {
  switch (message) {
    case 'invitation_not_found':
      return InvitationError.notFound;
    case 'invitation_expired':
      return InvitationError.expired;
    case 'invitation_already_redeemed':
      return InvitationError.alreadyRedeemed;
    case 'already_member':
      return InvitationError.alreadyMember;
    default:
      return InvitationError.unknown;
  }
}
```

- [ ] **Step 3: Write `RedeemResult`**

```dart
// apps/lyron_app/lib/src/domain/auth/redeem_result.dart
import 'package:lyron_app/src/domain/auth/invitation_error.dart';

sealed class RedeemResult {
  const RedeemResult();
}

class RedeemSuccess extends RedeemResult {
  const RedeemSuccess(this.organizationId);
  final String organizationId;
}

class RedeemFailure extends RedeemResult {
  const RedeemFailure(this.error);
  final InvitationError error;
}
```

- [ ] **Step 4: Write `PendingInviteToken`**

```dart
// apps/lyron_app/lib/src/domain/auth/pending_invite_token.dart
class PendingInviteToken {
  const PendingInviteToken({required this.token, required this.capturedAt});

  final String token;
  final DateTime capturedAt;
}
```

- [ ] **Step 5: Extend `AppAuthSession`**

```dart
// apps/lyron_app/lib/src/domain/auth/app_auth_session.dart
class AppAuthSession {
  const AppAuthSession({
    required this.userId,
    required this.email,
    this.linkedProviders = const <String>[],
  });

  final String userId;
  final String email;
  final List<String> linkedProviders;
}
```

- [ ] **Step 6: Commit**

```bash
git add apps/lyron_app/lib/src/domain/auth/
git commit -m "feat(auth): add SignInMethod, InvitationError, RedeemResult, PendingInviteToken types"
```

### Task 9: Refactor `AuthRepository` interface

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/auth_repository.dart`

- [ ] **Step 1: Replace contents**

```dart
// apps/lyron_app/lib/src/application/auth/auth_repository.dart
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

abstract interface class AuthRepository {
  Future<AppAuthSession?> restoreSession();

  Stream<AppAuthSession?> watchSession();

  Future<void> signInWithOAuth(SignInMethod method, {required String redirectTo});

  Future<void> sendMagicLink({required String email, required String redirectTo});

  Future<void> signOut();

  Future<void> deleteAccount();
}
```

Notes:
- `signInWithOAuth` returns `void` because the actual session lands via the `watchSession` stream after the OAuth callback completes.
- `sendMagicLink` triggers an email; session arrives via the stream when the user opens the link.

- [ ] **Step 2: Run dart analyze to confirm callers break**

```bash
cd apps/lyron_app && flutter analyze
```

Expected: errors in `app_auth_controller.dart`, `supabase_auth_repository.dart`, `sign_in_screen.dart`, and their tests. These are fixed in subsequent tasks.

- [ ] **Step 3: Do NOT commit yet**

Commit happens once all consumers compile (Task 12).

### Task 10: Update `AppAuthController`

**Files:**
- Modify: `apps/lyron_app/lib/src/application/auth/app_auth_controller.dart`
- Rewrite: `apps/lyron_app/test/application/auth/app_auth_controller_test.dart`

- [ ] **Step 1: Write the new controller test first (TDD)**

```dart
// apps/lyron_app/test/application/auth/app_auth_controller_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AppAuthSession?>.broadcast();
  AppAuthSession? currentSession;
  bool oauthCalled = false;
  bool magicLinkCalled = false;
  bool signOutCalled = false;
  bool deleteCalled = false;

  @override
  Future<AppAuthSession?> restoreSession() async => currentSession;

  @override
  Stream<AppAuthSession?> watchSession() => _controller.stream;

  @override
  Future<void> signInWithOAuth(SignInMethod method, {required String redirectTo}) async {
    oauthCalled = true;
  }

  @override
  Future<void> sendMagicLink({required String email, required String redirectTo}) async {
    magicLinkCalled = true;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }

  @override
  Future<void> deleteAccount() async {
    deleteCalled = true;
  }

  void emit(AppAuthSession? session) => _controller.add(session);
}

void main() {
  test('restoreSession surfaces signedIn when a session exists', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(repo);

    await controller.restoreSession();

    expect(controller.state.status, AppAuthStatus.signedIn);
    expect(controller.state.session?.userId, 'u');
  });

  test('signInWithOAuth delegates to the repository', () async {
    final repo = _FakeAuthRepository();
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.signInWithOAuth(SignInMethod.google, redirectTo: 'redir');

    expect(repo.oauthCalled, isTrue);
  });

  test('sendMagicLink delegates to the repository', () async {
    final repo = _FakeAuthRepository();
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.sendMagicLink(email: 'a@b', redirectTo: 'redir');

    expect(repo.magicLinkCalled, isTrue);
  });

  test('deleteAccount delegates and clears state', () async {
    final repo = _FakeAuthRepository();
    repo.currentSession = const AppAuthSession(userId: 'u', email: 'e@x');
    final controller = AppAuthController(repo);
    await controller.restoreSession();

    await controller.deleteAccount();

    expect(repo.deleteCalled, isTrue);
    expect(controller.state.status, AppAuthStatus.signedOut);
  });
}
```

- [ ] **Step 2: Implement controller changes**

Replace `signIn` with `signInWithOAuth`, `sendMagicLink`, add `deleteAccount`:

```dart
// apps/lyron_app/lib/src/application/auth/app_auth_controller.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/app_auth_state.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';

class AppAuthController extends ChangeNotifier {
  AppAuthController(this._repository)
    : _state = const AppAuthState(status: AppAuthStatus.initializing);

  final AuthRepository _repository;

  AppAuthState _state;
  StreamSubscription<AppAuthSession?>? _subscription;
  bool _isSigningOut = false;

  AppAuthState get state => _state;

  Future<void> restoreSession() async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);
    final session = await _repository.restoreSession();
    _setState(_stateForSession(session, fromStream: false));
  }

  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);
    await _repository.signInWithOAuth(method, redirectTo: redirectTo);
  }

  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) async {
    _subscription ??= _repository.watchSession().listen(_handleSessionUpdate);
    await _repository.sendMagicLink(email: email, redirectTo: redirectTo);
  }

  Future<void> signOut() async {
    _isSigningOut = true;
    try {
      await _repository.signOut();
      _setState(const AppAuthState(status: AppAuthStatus.signedOut));
    } finally {
      _isSigningOut = false;
    }
  }

  Future<void> deleteAccount() async {
    _isSigningOut = true;
    try {
      await _repository.deleteAccount();
      _setState(const AppAuthState(status: AppAuthStatus.signedOut));
    } finally {
      _isSigningOut = false;
    }
  }

  void _handleSessionUpdate(AppAuthSession? session) {
    _setState(_stateForSession(session, fromStream: true));
  }

  AppAuthState _stateForSession(
    AppAuthSession? session, {
    required bool fromStream,
  }) {
    if (session != null) {
      return AppAuthState(status: AppAuthStatus.signedIn, session: session);
    }
    if (fromStream && !_isSigningOut && _state.status == AppAuthStatus.signedIn) {
      return const AppAuthState(status: AppAuthStatus.sessionExpired);
    }
    return const AppAuthState(status: AppAuthStatus.signedOut);
  }

  void _setState(AppAuthState nextState) {
    _state = nextState;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 3: Run tests**

```bash
cd apps/lyron_app && flutter test test/application/auth/app_auth_controller_test.dart
```

Expected: 4 passing.

### Task 11: Rewrite `SupabaseAuthRepository`

**Files:**
- Modify: `apps/lyron_app/lib/src/infrastructure/auth/supabase_auth_repository.dart`
- Rewrite: `apps/lyron_app/test/infrastructure/auth/supabase_auth_repository_test.dart`

- [ ] **Step 1: Write the new repository test**

```dart
// apps/lyron_app/test/infrastructure/auth/supabase_auth_repository_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_auth_repository.dart';

void main() {
  test('restoreSession returns null when no session', () async {
    final repo = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signInWithOAuth: (_, {required redirectTo}) async {},
      sendMagicLink: ({required email, required redirectTo}) async {},
      signOut: () async {},
      deleteAccount: () async {},
    );

    expect(await repo.restoreSession(), isNull);
  });

  test('signInWithOAuth dispatches the chosen provider', () async {
    SignInMethod? captured;
    final repo = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signInWithOAuth: (method, {required redirectTo}) async {
        captured = method;
      },
      sendMagicLink: ({required email, required redirectTo}) async {},
      signOut: () async {},
      deleteAccount: () async {},
    );

    await repo.signInWithOAuth(SignInMethod.apple, redirectTo: 'r');

    expect(captured, SignInMethod.apple);
  });

  test('deleteAccount invokes the RPC', () async {
    var called = false;
    final repo = SupabaseAuthRepository.testing(
      restoreSession: () async => null,
      watchSession: () => const Stream.empty(),
      signInWithOAuth: (_, {required redirectTo}) async {},
      sendMagicLink: ({required email, required redirectTo}) async {},
      signOut: () async {},
      deleteAccount: () async => called = true,
    );

    await repo.deleteAccount();

    expect(called, isTrue);
  });
}
```

- [ ] **Step 2: Implement the repository**

```dart
// apps/lyron_app/lib/src/infrastructure/auth/supabase_auth_repository.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Restore = Future<AppAuthSession?> Function();
typedef _Watch = Stream<AppAuthSession?> Function();
typedef _OAuth = Future<void> Function(
  SignInMethod method, {
  required String redirectTo,
});
typedef _Magic = Future<void> Function({
  required String email,
  required String redirectTo,
});
typedef _SignOut = Future<void> Function();
typedef _Delete = Future<void> Function();

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(SupabaseClient client)
    : this.testing(
        restoreSession: () async => _mapSession(client.auth.currentSession),
        watchSession: () => client.auth.onAuthStateChange
            .map((event) => _mapSession(event.session)),
        signInWithOAuth: (method, {required redirectTo}) async {
          final provider = switch (method) {
            SignInMethod.google => OAuthProvider.google,
            SignInMethod.apple => OAuthProvider.apple,
            SignInMethod.magicLink => throw ArgumentError(
                'magic link must use sendMagicLink',
              ),
          };
          await client.auth.signInWithOAuth(provider, redirectTo: redirectTo);
        },
        sendMagicLink: ({required email, required redirectTo}) async {
          await client.auth.signInWithOtp(email: email, emailRedirectTo: redirectTo);
        },
        signOut: client.auth.signOut,
        deleteAccount: () async {
          await client.rpc('delete_account');
        },
      );

  @visibleForTesting
  SupabaseAuthRepository.testing({
    required _Restore restoreSession,
    required _Watch watchSession,
    required _OAuth signInWithOAuth,
    required _Magic sendMagicLink,
    required _SignOut signOut,
    required _Delete deleteAccount,
  }) : _restoreSession = restoreSession,
       _watchSession = watchSession,
       _signInWithOAuth = signInWithOAuth,
       _sendMagicLink = sendMagicLink,
       _signOut = signOut,
       _deleteAccount = deleteAccount;

  final _Restore _restoreSession;
  final _Watch _watchSession;
  final _OAuth _signInWithOAuth;
  final _Magic _sendMagicLink;
  final _SignOut _signOut;
  final _Delete _deleteAccount;

  @override
  Future<AppAuthSession?> restoreSession() => _restoreSession();

  @override
  Stream<AppAuthSession?> watchSession() => _watchSession();

  @override
  Future<void> signInWithOAuth(
    SignInMethod method, {
    required String redirectTo,
  }) => _signInWithOAuth(method, redirectTo: redirectTo);

  @override
  Future<void> sendMagicLink({
    required String email,
    required String redirectTo,
  }) => _sendMagicLink(email: email, redirectTo: redirectTo);

  @override
  Future<void> signOut() => _signOut();

  @override
  Future<void> deleteAccount() => _deleteAccount();

  static AppAuthSession? _mapSession(Session? session) {
    if (session == null) return null;
    final email = session.user.email;
    if (email == null || email.isEmpty) {
      throw StateError('Supabase session is missing a user email.');
    }
    final providers = session.user.identities
            ?.map((i) => i.provider)
            .whereType<String>()
            .toList() ??
        const <String>[];
    return AppAuthSession(
      userId: session.user.id,
      email: email,
      linkedProviders: providers,
    );
  }
}
```

- [ ] **Step 3: Run tests**

```bash
cd apps/lyron_app && flutter test test/infrastructure/auth/supabase_auth_repository_test.dart
```

Expected: 3 passing.

### Task 12: Commit the repository + controller refactor

- [ ] **Step 1: Run analyzer and full unit tests**

```bash
cd apps/lyron_app && flutter analyze && flutter test test/application/auth test/infrastructure/auth
```

Expected: clean.

- [ ] **Step 2: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/ apps/lyron_app/lib/src/infrastructure/auth/ apps/lyron_app/test/application/auth/ apps/lyron_app/test/infrastructure/auth/
git commit -m "refactor(auth): replace password sign-in with OAuth + magic link in repository and controller"
```

### Task 13: Invitation repository

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/invitation_repository.dart`
- Create: `apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart`
- Create: `apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart`

- [ ] **Step 1: Write the test**

```dart
// apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:lyron_app/src/infrastructure/auth/supabase_invitation_repository.dart';

void main() {
  test('redeem returns success when RPC returns an organization id', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async => '00000000-0000-0000-0000-0000000000aa',
    );
    final result = await repo.redeem('tok');
    expect(result, isA<RedeemSuccess>());
    expect((result as RedeemSuccess).organizationId,
        '00000000-0000-0000-0000-0000000000aa');
  });

  test('redeem maps SQL error messages to InvitationError', () async {
    final repo = SupabaseInvitationRepository.testing(
      redeem: (token) async {
        throw Exception('invitation_expired');
      },
    );
    final result = await repo.redeem('tok');
    expect((result as RedeemFailure).error, InvitationError.expired);
  });
}
```

- [ ] **Step 2: Write the interface**

```dart
// apps/lyron_app/lib/src/application/auth/invitation_repository.dart
import 'package:lyron_app/src/domain/auth/redeem_result.dart';

abstract interface class InvitationRepository {
  Future<RedeemResult> redeem(String token);
}
```

- [ ] **Step 3: Write the Supabase implementation**

```dart
// apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef _Redeem = Future<String> Function(String token);

class SupabaseInvitationRepository implements InvitationRepository {
  SupabaseInvitationRepository(SupabaseClient client)
    : this.testing(
        redeem: (token) async {
          final result = await client.rpc(
            'redeem_invitation',
            params: {'p_token': token},
          );
          return result as String;
        },
      );

  @visibleForTesting
  SupabaseInvitationRepository.testing({required _Redeem redeem})
    : _redeem = redeem;

  final _Redeem _redeem;

  @override
  Future<RedeemResult> redeem(String token) async {
    try {
      final orgId = await _redeem(token);
      return RedeemSuccess(orgId);
    } on Exception catch (e) {
      final message = e.toString();
      InvitationError mapped;
      if (message.contains('invitation_not_found')) {
        mapped = InvitationError.notFound;
      } else if (message.contains('invitation_expired')) {
        mapped = InvitationError.expired;
      } else if (message.contains('invitation_already_redeemed')) {
        mapped = InvitationError.alreadyRedeemed;
      } else if (message.contains('already_member')) {
        mapped = InvitationError.alreadyMember;
      } else {
        mapped = InvitationError.unknown;
      }
      return RedeemFailure(mapped);
    }
  }
}
```

- [ ] **Step 4: Run tests, commit**

```bash
cd apps/lyron_app && flutter test test/infrastructure/auth/supabase_invitation_repository_test.dart
git add apps/lyron_app/lib/src/application/auth/invitation_repository.dart apps/lyron_app/lib/src/infrastructure/auth/supabase_invitation_repository.dart apps/lyron_app/test/infrastructure/auth/supabase_invitation_repository_test.dart
git commit -m "feat(auth): add InvitationRepository for redeem_invitation RPC"
```

### Task 14: Pending invite token controller

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/pending_invite_token_controller.dart`
- Create: `apps/lyron_app/test/application/auth/pending_invite_token_controller_test.dart`

- [ ] **Step 1: Write the test**

```dart
// apps/lyron_app/test/application/auth/pending_invite_token_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';

void main() {
  test('captures and clears token', () {
    final c = PendingInviteTokenController();
    expect(c.current, isNull);

    c.capture('abc');
    expect(c.current?.token, 'abc');

    c.clear();
    expect(c.current, isNull);
  });

  test('capture replaces the previous token', () {
    final c = PendingInviteTokenController();
    c.capture('one');
    c.capture('two');
    expect(c.current?.token, 'two');
  });
}
```

- [ ] **Step 2: Implement**

```dart
// apps/lyron_app/lib/src/application/auth/pending_invite_token_controller.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/domain/auth/pending_invite_token.dart';

class PendingInviteTokenController extends ChangeNotifier {
  PendingInviteToken? _current;

  PendingInviteToken? get current => _current;

  void capture(String token) {
    _current = PendingInviteToken(token: token, capturedAt: DateTime.now());
    notifyListeners();
  }

  void clear() {
    _current = null;
    notifyListeners();
  }
}
```

- [ ] **Step 3: Run, commit**

```bash
cd apps/lyron_app && flutter test test/application/auth/pending_invite_token_controller_test.dart
git add apps/lyron_app/lib/src/application/auth/pending_invite_token_controller.dart apps/lyron_app/test/application/auth/pending_invite_token_controller_test.dart
git commit -m "feat(auth): add pending invite token controller"
```

### Task 15: Redeem controller

**Files:**
- Create: `apps/lyron_app/lib/src/application/auth/redeem_controller.dart`
- Create: `apps/lyron_app/test/application/auth/redeem_controller_test.dart`

- [ ] **Step 1: Write the test**

```dart
// apps/lyron_app/test/application/auth/redeem_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';

class _FakeInv implements InvitationRepository {
  _FakeInv(this._result);
  final RedeemResult _result;
  String? lastToken;

  @override
  Future<RedeemResult> redeem(String token) async {
    lastToken = token;
    return _result;
  }
}

void main() {
  test('success transitions idle -> inFlight -> success', () async {
    final repo = _FakeInv(const RedeemSuccess('org-1'));
    final c = RedeemController(repo);
    final transitions = <RedeemState>[];
    c.addListener(() => transitions.add(c.state));

    await c.redeem('tok');

    expect(c.state, isA<RedeemStateSuccess>());
    expect((c.state as RedeemStateSuccess).organizationId, 'org-1');
    expect(transitions.length, greaterThanOrEqualTo(2));
  });

  test('failure surfaces invitation error', () async {
    final repo = _FakeInv(const RedeemFailure(InvitationError.expired));
    final c = RedeemController(repo);

    await c.redeem('tok');

    expect((c.state as RedeemStateFailure).error, InvitationError.expired);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// apps/lyron_app/lib/src/application/auth/redeem_controller.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/auth/invitation_repository.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/domain/auth/redeem_result.dart';

sealed class RedeemState {
  const RedeemState();
}

class RedeemStateIdle extends RedeemState {
  const RedeemStateIdle();
}

class RedeemStateInFlight extends RedeemState {
  const RedeemStateInFlight();
}

class RedeemStateSuccess extends RedeemState {
  const RedeemStateSuccess(this.organizationId);
  final String organizationId;
}

class RedeemStateFailure extends RedeemState {
  const RedeemStateFailure(this.error);
  final InvitationError error;
}

class RedeemController extends ChangeNotifier {
  RedeemController(this._repository);

  final InvitationRepository _repository;
  RedeemState _state = const RedeemStateIdle();

  RedeemState get state => _state;

  Future<void> redeem(String token) async {
    _set(const RedeemStateInFlight());
    final result = await _repository.redeem(token);
    switch (result) {
      case RedeemSuccess(:final organizationId):
        _set(RedeemStateSuccess(organizationId));
      case RedeemFailure(:final error):
        _set(RedeemStateFailure(error));
    }
  }

  void reset() => _set(const RedeemStateIdle());

  void _set(RedeemState next) {
    _state = next;
    notifyListeners();
  }
}
```

- [ ] **Step 3: Run, commit**

```bash
cd apps/lyron_app && flutter test test/application/auth/redeem_controller_test.dart
git add apps/lyron_app/lib/src/application/auth/redeem_controller.dart apps/lyron_app/test/application/auth/redeem_controller_test.dart
git commit -m "feat(auth): add redeem controller with state machine"
```

### Task 16: Deep link listener

**Files:**
- Modify: `apps/lyron_app/pubspec.yaml` — add `app_links` dependency
- Create: `apps/lyron_app/lib/src/application/auth/deep_link_listener.dart`
- Create: `apps/lyron_app/test/application/auth/deep_link_listener_test.dart`

- [ ] **Step 1: Add dependency**

In `apps/lyron_app/pubspec.yaml` under `dependencies:`:

```yaml
  app_links: ^6.3.2
```

Then:

```bash
cd apps/lyron_app && flutter pub get
```

- [ ] **Step 2: Write the test**

```dart
// apps/lyron_app/test/application/auth/deep_link_listener_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/deep_link_listener.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';

void main() {
  test('captures token from /invite?token=X', () async {
    final controller = StreamController<Uri>();
    final pending = PendingInviteTokenController();
    final listener = DeepLinkListener(
      stream: controller.stream,
      pendingTokens: pending,
    );

    listener.start();
    controller.add(Uri.parse('https://app.lyron.example/invite?token=ABC'));

    await Future<void>.delayed(Duration.zero);

    expect(pending.current?.token, 'ABC');

    await listener.dispose();
  });

  test('ignores unrelated paths', () async {
    final controller = StreamController<Uri>();
    final pending = PendingInviteTokenController();
    final listener = DeepLinkListener(
      stream: controller.stream,
      pendingTokens: pending,
    );
    listener.start();
    controller.add(Uri.parse('https://app.lyron.example/other'));
    await Future<void>.delayed(Duration.zero);
    expect(pending.current, isNull);
    await listener.dispose();
  });
}
```

- [ ] **Step 3: Implement**

```dart
// apps/lyron_app/lib/src/application/auth/deep_link_listener.dart
import 'dart:async';

import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';

class DeepLinkListener {
  DeepLinkListener({
    required Stream<Uri> stream,
    required PendingInviteTokenController pendingTokens,
  })  : _stream = stream,
        _pendingTokens = pendingTokens;

  final Stream<Uri> _stream;
  final PendingInviteTokenController _pendingTokens;
  StreamSubscription<Uri>? _sub;

  void start() {
    _sub ??= _stream.listen(_handle);
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  void _handle(Uri uri) {
    if (uri.path == '/invite') {
      final token = uri.queryParameters['token'];
      if (token != null && token.isNotEmpty) {
        _pendingTokens.capture(token);
      }
    }
  }
}
```

- [ ] **Step 4: Run, commit**

```bash
cd apps/lyron_app && flutter test test/application/auth/deep_link_listener_test.dart
git add apps/lyron_app/pubspec.yaml apps/lyron_app/pubspec.lock apps/lyron_app/lib/src/application/auth/deep_link_listener.dart apps/lyron_app/test/application/auth/deep_link_listener_test.dart
git commit -m "feat(auth): add deep link listener that captures invite tokens"
```

---

## Phase 4 — Flutter presentation

### Task 17: Replace `SignInScreen`

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart`
- Rewrite: `apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart`
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

- [ ] **Step 1: Add strings**

In `app_strings.dart`, append inside the class:

```dart
  static const continueWithGoogle = 'Continue with Google';
  static const continueWithApple = 'Continue with Apple';
  static const magicLinkLabel = 'Email for magic link';
  static const sendMagicLinkAction = 'Send magic link';
  static const magicLinkSentTitle = 'Check your inbox';
  static const magicLinkSentMessage =
      'We sent you a sign-in link. Open it on this device to continue.';
  static const inviteRequiredTitle = 'Invitation required';
  static const inviteRequiredMessage =
      'Paste your invite link to join an organization.';
  static const invitePasteLabel = 'Invite link';
  static const inviteRedeemAction = 'Redeem invite';
  static const inviteErrorNotFound = 'Invalid invite link.';
  static const inviteErrorExpired = 'Invite expired. Ask for a new one.';
  static const inviteErrorAlreadyRedeemed = 'Invite already used.';
  static const inviteErrorAlreadyMember = 'You are already a member.';
  static const accountTitle = 'Account';
  static const deleteAccountAction = 'Delete account';
  static const deleteAccountConfirmTitle = 'Delete account?';
  static const deleteAccountConfirmMessage =
      'Your account, memberships, and any pending offline changes will be removed permanently.';
  static const deleteAccountConfirmAction = 'Delete permanently';
  static const cancelAction = 'Cancel';
```

- [ ] **Step 2: Rewrite the sign-in test**

```dart
// apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/auth/sign_in_screen.dart';

class _StubRepo implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;
  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();
  @override
  Future<void> signInWithOAuth(SignInMethod method, {required String redirectTo}) async {}
  @override
  Future<void> sendMagicLink({required String email, required String redirectTo}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

class _RecordingController extends AppAuthController {
  _RecordingController() : super(_StubRepo());
  SignInMethod? lastOAuth;
  String? lastMagicLinkEmail;

  @override
  Future<void> signInWithOAuth(SignInMethod method, {required String redirectTo}) async {
    lastOAuth = method;
  }

  @override
  Future<void> sendMagicLink({required String email, required String redirectTo}) async {
    lastMagicLinkEmail = email;
  }
}

void main() {
  testWidgets('shows three sign-in entry points', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => controller),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Send magic link'), findsOneWidget);
  });

  testWidgets('tapping Google triggers OAuth', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => controller),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(controller.lastOAuth, SignInMethod.google);
  });
}
```

(Note: the test uses a `_RecordingController` shaped like the production controller. If overriding `AppAuthController` via Riverpod requires a different override pattern, mirror whatever convention existing tests already use; the closest precedent is `test/application/auth/app_auth_controller_test.dart`.)

- [ ] **Step 3: Rewrite the screen**

```dart
// apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

const _kRedirectUrl = 'io.lyron.app://auth/callback';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(appAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  AppStrings.signInTitle,
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => controller.signInWithOAuth(
                    SignInMethod.google,
                    redirectTo: _kRedirectUrl,
                  ),
                  child: const Text(AppStrings.continueWithGoogle),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => controller.signInWithOAuth(
                    SignInMethod.apple,
                    redirectTo: _kRedirectUrl,
                  ),
                  child: const Text(AppStrings.continueWithApple),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: AppStrings.magicLinkLabel,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final email = _emailController.text.trim();
                    if (email.isEmpty) return;
                    await controller.sendMagicLink(
                      email: email,
                      redirectTo: _kRedirectUrl,
                    );
                    if (mounted) {
                      Navigator.of(context).pushReplacementNamed('/magic-link-sent');
                    }
                  },
                  child: const Text(AppStrings.sendMagicLinkAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run, commit**

```bash
cd apps/lyron_app && flutter test test/presentation/auth/sign_in_screen_test.dart
git add apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart apps/lyron_app/lib/src/shared/app_strings.dart apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart
git commit -m "feat(auth): replace sign-in screen with Google + Apple + magic link entry points"
```

### Task 18: Magic link sent + invite required + redeem progress screens

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/auth/magic_link_sent_screen.dart`
- Create: `apps/lyron_app/lib/src/presentation/auth/invite_required_screen.dart`
- Create: `apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart`
- Create: `apps/lyron_app/test/presentation/auth/invite_required_screen_test.dart`

- [ ] **Step 1: Magic link sent screen**

```dart
// apps/lyron_app/lib/src/presentation/auth/magic_link_sent_screen.dart
import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class MagicLinkSentScreen extends StatelessWidget {
  const MagicLinkSentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.magicLinkSentTitle)),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(AppStrings.magicLinkSentMessage),
      ),
    );
  }
}
```

- [ ] **Step 2: Invite required screen + test**

```dart
// apps/lyron_app/lib/src/presentation/auth/invite_required_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class InviteRequiredScreen extends ConsumerStatefulWidget {
  const InviteRequiredScreen({super.key});

  @override
  ConsumerState<InviteRequiredScreen> createState() =>
      _InviteRequiredScreenState();
}

class _InviteRequiredScreenState extends ConsumerState<InviteRequiredScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pendingTokens = ref.watch(pendingInviteTokenControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.inviteRequiredTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(AppStrings.inviteRequiredMessage),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: AppStrings.invitePasteLabel,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final raw = _controller.text.trim();
                if (raw.isEmpty) return;
                final token = _extractToken(raw);
                if (token == null) return;
                pendingTokens.capture(token);
              },
              child: const Text(AppStrings.inviteRedeemAction),
            ),
          ],
        ),
      ),
    );
  }

  String? _extractToken(String raw) {
    final uri = Uri.tryParse(raw);
    if (uri == null) return null;
    final token = uri.queryParameters['token'];
    return token?.isEmpty ?? true ? (raw.contains('://') ? null : raw) : token;
  }
}
```

```dart
// apps/lyron_app/test/presentation/auth/invite_required_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/pending_invite_token_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';

void main() {
  testWidgets('extracts token from pasted invite URL', (tester) async {
    final pending = PendingInviteTokenController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pendingInviteTokenControllerProvider.overrideWith((_) => pending),
        ],
        child: const MaterialApp(home: InviteRequiredScreen()),
      ),
    );

    await tester.enterText(
      find.byType(TextFormField),
      'https://app.lyron.example/invite?token=ABCDEF',
    );
    await tester.tap(find.text('Redeem invite'));
    await tester.pump();

    expect(pending.current?.token, 'ABCDEF');
  });
}
```

- [ ] **Step 3: Redeem progress screen**

```dart
// apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/invitation_error.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class RedeemProgressScreen extends ConsumerWidget {
  const RedeemProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(redeemControllerProvider).state;

    return Scaffold(
      body: Center(
        child: switch (state) {
          RedeemStateIdle() ||
          RedeemStateInFlight() => const CircularProgressIndicator(),
          RedeemStateSuccess() => const SizedBox.shrink(),
          RedeemStateFailure(:final error) => Text(_messageFor(error)),
        },
      ),
    );
  }

  String _messageFor(InvitationError error) => switch (error) {
        InvitationError.notFound => AppStrings.inviteErrorNotFound,
        InvitationError.expired => AppStrings.inviteErrorExpired,
        InvitationError.alreadyRedeemed => AppStrings.inviteErrorAlreadyRedeemed,
        InvitationError.alreadyMember => AppStrings.inviteErrorAlreadyMember,
        InvitationError.network ||
        InvitationError.unknown => AppStrings.inviteErrorNotFound,
      };
}
```

- [ ] **Step 4: Run, commit**

```bash
cd apps/lyron_app && flutter test test/presentation/auth/
git add apps/lyron_app/lib/src/presentation/auth/ apps/lyron_app/test/presentation/auth/
git commit -m "feat(auth): add magic-link-sent, invite-required, and redeem-progress screens"
```

### Task 19: Account screen with sign-out and delete

**Files:**
- Create: `apps/lyron_app/lib/src/presentation/account/account_screen.dart`
- Create: `apps/lyron_app/test/presentation/account/account_screen_test.dart`

- [ ] **Step 1: Write the test**

```dart
// apps/lyron_app/test/presentation/account/account_screen_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/app_auth_controller.dart';
import 'package:lyron_app/src/application/auth/auth_repository.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/auth/sign_in_method.dart';
import 'package:lyron_app/src/presentation/account/account_screen.dart';

class _StubRepo implements AuthRepository {
  @override
  Future<AppAuthSession?> restoreSession() async => null;
  @override
  Stream<AppAuthSession?> watchSession() => const Stream.empty();
  @override
  Future<void> signInWithOAuth(SignInMethod method, {required String redirectTo}) async {}
  @override
  Future<void> sendMagicLink({required String email, required String redirectTo}) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() async {}
}

class _RecordingController extends AppAuthController {
  _RecordingController() : super(_StubRepo());
  bool deleted = false;
  bool signedOut = false;

  @override
  Future<void> deleteAccount() async {
    deleted = true;
  }

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

void main() {
  testWidgets('delete confirmation triggers deleteAccount', (tester) async {
    final controller = _RecordingController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appAuthControllerProvider.overrideWith((_) => controller),
        ],
        child: const MaterialApp(home: AccountScreen()),
      ),
    );

    await tester.tap(find.text('Delete account'));
    await tester.pump();
    await tester.tap(find.text('Delete permanently'));
    await tester.pumpAndSettle();

    expect(controller.deleted, isTrue);
  });
}
```

- [ ] **Step 2: Implement**

```dart
// apps/lyron_app/lib/src/presentation/account/account_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(appAuthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.accountTitle)),
      body: ListView(
        children: [
          ListTile(
            title: const Text(AppStrings.signOutAction),
            onTap: () => controller.signOut(),
          ),
          ListTile(
            title: const Text(AppStrings.deleteAccountAction),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text(AppStrings.deleteAccountConfirmTitle),
                  content: const Text(AppStrings.deleteAccountConfirmMessage),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text(AppStrings.cancelAction),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text(AppStrings.deleteAccountConfirmAction),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await controller.deleteAccount();
              }
            },
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: Run, commit**

```bash
cd apps/lyron_app && flutter test test/presentation/account/account_screen_test.dart
git add apps/lyron_app/lib/src/presentation/account/ apps/lyron_app/test/presentation/account/
git commit -m "feat(auth): add account screen with sign-out and delete"
```

---

## Phase 5 — Wiring, providers, router

### Task 20: Wire new providers

**Files:**
- Modify: `apps/lyron_app/lib/src/application/providers.dart`

- [ ] **Step 1: Register providers**

Add to `providers.dart` (placement near other `provider` declarations; if Riverpod overrides require `Provider`-style override patterns elsewhere in the file, mirror that style):

```dart
final invitationRepositoryProvider = Provider<InvitationRepository>((ref) {
  final client = ref.watch(supabaseClientProvider); // existing
  return SupabaseInvitationRepository(client);
});

final pendingInviteTokenControllerProvider =
    ChangeNotifierProvider<PendingInviteTokenController>(
  (_) => PendingInviteTokenController(),
);

final redeemControllerProvider = ChangeNotifierProvider<RedeemController>((ref) {
  return RedeemController(ref.watch(invitationRepositoryProvider));
});

final deepLinkListenerProvider = Provider<DeepLinkListener>((ref) {
  final pending = ref.watch(pendingInviteTokenControllerProvider);
  final stream = AppLinks().uriLinkStream;
  final listener = DeepLinkListener(stream: stream, pendingTokens: pending);
  ref.onDispose(() => listener.dispose());
  return listener;
});
```

Update imports at the top of the file (add `app_links`, new domain/application paths). Confirm `appAuthControllerProvider` is exposed as a `ChangeNotifierProvider` consistent with the existing pattern.

- [ ] **Step 2: Initialize the deep-link listener at app bootstrap**

Search for the bootstrap entry point (`apps/lyron_app/lib/src/bootstrap/` or `apps/lyron_app/lib/main.dart`) and add inside the post-`ProviderScope` build phase:

```dart
final listener = container.read(deepLinkListenerProvider);
listener.start();
```

(Adapt to the existing wiring style; if the bootstrap uses a hook-based approach, follow that.)

- [ ] **Step 3: Run analyzer**

```bash
cd apps/lyron_app && flutter analyze
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add apps/lyron_app/lib/src/application/providers.dart apps/lyron_app/lib/main.dart apps/lyron_app/lib/src/bootstrap/
git commit -m "feat(auth): wire invitation repository, redeem controller, deep link listener"
```

### Task 21: Router redirect + MembershipGate

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`
- Modify: `apps/lyron_app/lib/src/router/app_routes.dart`
- Create: `apps/lyron_app/lib/src/application/auth/active_membership_controller.dart`
- Create: `apps/lyron_app/lib/src/presentation/auth/membership_gate.dart`

**Why two pieces (not a redirect-only fix):**
`activeOrganizationResolutionProvider` returns an async `ActiveOrganizationResolutionReader` (see `lib/src/application/active_organization_resolution.dart`); the `go_router` redirect callback is synchronous, so the router cannot await it. Membership gating therefore lives in a `ChangeNotifier`-backed cache (`ActiveMembershipController`) populated at app start and after each auth state change, plus a thin `MembershipGate` widget that wraps the authenticated route tree and switches between the home shell, the auto-redeem screen, and the invite-required screen.

The router redirect itself remains responsible only for: (1) auth status (signed-in vs. signed-out), and (2) routing the bare `/invite` deep link to capture the token before sign-in.

- [ ] **Step 1: Add new routes (enum cases)**

The existing `AppRoutes` is an enum with a `path` field (see `apps/lyron_app/lib/src/router/app_routes.dart`). Append new cases:

```dart
enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  magicLinkSent('/magic-link-sent'),
  invite('/invite'),
  inviteRequired('/invite-required'),
  redeem('/redeem'),
  account('/account'),
  planList('/plans'),
  planDetail('/plans/:planSlug'),
  planSessionSongReader(
    '/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug',
  ),
  songCreate('/songs/new'),
  songEditor('/songs/:songSlug/edit'),
  songReader('/songs/:songSlug');

  const AppRoutes(this.path);
  final String path;
}
```

All uses must reference `AppRoutes.<name>.path` when a string is needed.

- [ ] **Step 2: Write `ActiveMembershipController`**

```dart
// apps/lyron_app/lib/src/application/auth/active_membership_controller.dart
import 'package:flutter/foundation.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';

class ActiveMembershipController extends ChangeNotifier {
  ActiveOrganizationResolution _last =
      const ActiveOrganizationUnknownConnectivityFailure();

  ActiveOrganizationResolution get last => _last;

  void update(ActiveOrganizationResolution next) {
    _last = next;
    notifyListeners();
  }
}
```

Wire it in `providers.dart`:

```dart
final activeMembershipControllerProvider =
    ChangeNotifierProvider<ActiveMembershipController>(
  (_) => ActiveMembershipController(),
);
```

A new bootstrap effect (added in the same task) calls `activeOrganizationResolutionProvider` after each sign-in and writes the result into the controller.

- [ ] **Step 3: Update router redirect (auth-only)**

In `app_router.dart`:

```dart
redirect: (context, state) {
  final auth = container.read(appAuthControllerProvider).state;

  if (auth.status == AppAuthStatus.initializing) return null;

  final loc = state.matchedLocation;
  final isAuthRoute = loc == AppRoutes.signIn.path ||
      loc == AppRoutes.invite.path ||
      loc == AppRoutes.magicLinkSent.path;

  if (auth.status != AppAuthStatus.signedIn) {
    return isAuthRoute ? null : AppRoutes.signIn.path;
  }

  // Authenticated: do not bounce inside the gate.
  return null;
},
```

Register `GoRoute` entries for the new paths. Wrap authenticated routes in `MembershipGate` so membership decisions stay synchronous:

```dart
ShellRoute(
  builder: (_, __, child) => MembershipGate(child: child),
  routes: [
    GoRoute(path: AppRoutes.home.path, builder: (_, __) => const HomeScreen()),
    GoRoute(path: AppRoutes.account.path, builder: (_, __) => const AccountScreen()),
    // ...existing authenticated routes
  ],
),
GoRoute(path: AppRoutes.signIn.path, builder: (_, __) => const SignInScreen()),
GoRoute(path: AppRoutes.magicLinkSent.path, builder: (_, __) => const MagicLinkSentScreen()),
GoRoute(path: AppRoutes.invite.path, builder: (_, __) => const InviteLandingRedirect()),
GoRoute(path: AppRoutes.inviteRequired.path, builder: (_, __) => const InviteRequiredScreen()),
GoRoute(path: AppRoutes.redeem.path, builder: (_, __) => const RedeemProgressScreen()),
```

`InviteLandingRedirect` is a trivial stateless widget: in `build`, capture `state.uri.queryParameters['token']` into `pendingInviteTokenControllerProvider` and immediately redirect to `AppRoutes.signIn.path`.

- [ ] **Step 4: Write `MembershipGate`**

```dart
// apps/lyron_app/lib/src/presentation/auth/membership_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/active_organization_resolution.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/presentation/auth/invite_required_screen.dart';
import 'package:lyron_app/src/presentation/auth/redeem_progress_screen.dart';

class MembershipGate extends ConsumerWidget {
  const MembershipGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membership = ref.watch(activeMembershipControllerProvider).last;
    final pending = ref.watch(pendingInviteTokenControllerProvider).current;

    return switch (membership) {
      ActiveOrganizationSelected() => child,
      ActiveOrganizationVerifiedEmpty() => pending != null
          ? const RedeemProgressScreen()
          : const InviteRequiredScreen(),
      ActiveOrganizationUnknownConnectivityFailure() ||
      ActiveOrganizationUnknownNonConnectivityFailure() => child,
    };
  }
}
```

- [ ] **Step 5: Wire post-sign-in membership refresh**

In `providers.dart`, add an effect that watches `appAuthControllerProvider`. On transition to `signedIn`, call `await ref.read(activeOrganizationResolutionProvider)()` and push the result into `activeMembershipControllerProvider`. The same effect runs after successful `RedeemController` completion.

A small helper:

```dart
final membershipRefreshEffectProvider = Provider<void>((ref) {
  ref.listen<AppAuthState>(
    appAuthControllerProvider.select((c) => c.state),
    (prev, next) async {
      if (next.status != AppAuthStatus.signedIn) return;
      final reader = ref.read(activeOrganizationResolutionProvider);
      final result = await reader();
      ref.read(activeMembershipControllerProvider).update(result);
    },
  );
  ref.listen<RedeemState>(
    redeemControllerProvider.select((c) => c.state),
    (prev, next) async {
      if (next is! RedeemStateSuccess) return;
      final reader = ref.read(activeOrganizationResolutionProvider);
      final result = await reader();
      ref.read(activeMembershipControllerProvider).update(result);
    },
  );
});
```

Register the effect at bootstrap with `container.read(membershipRefreshEffectProvider)`.

- [ ] **Step 3: Test**

```dart
// apps/lyron_app/test/router/router_redirect_test.dart
import 'package:flutter_test/flutter_test.dart';
// ...harness similar to existing router tests if any; otherwise smoke-test
// by constructing a router with overridden providers and probing redirects.
void main() {
  test('placeholder: documented in plan task 21', () {
    // Implementation must match the existing router test conventions.
  });
}
```

Replace the placeholder with concrete cases once the existing router test conventions are inspected (if there is no prior router test, follow the smoke pattern used in `test/app/lyron_app_test.dart`).

- [ ] **Step 4: Commit**

```bash
cd apps/lyron_app && flutter analyze && flutter test
git add apps/lyron_app/lib/src/router/ apps/lyron_app/test/router/
git commit -m "feat(auth): gate router on membership resolution and pending invite token"
```

### Task 22: Auto-redeem effect

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart` (effect side)
- Create: `apps/lyron_app/lib/src/application/auth/redeem_effect.dart`

- [ ] **Step 1: Implement the effect**

```dart
// apps/lyron_app/lib/src/application/auth/redeem_effect.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth/redeem_controller.dart';
import 'package:lyron_app/src/application/providers.dart';

class RedeemEffect {
  RedeemEffect(this.ref);
  final Ref ref;

  Future<void> tryConsumePending() async {
    final pending = ref.read(pendingInviteTokenControllerProvider);
    final token = pending.current?.token;
    if (token == null) return;

    final controller = ref.read(redeemControllerProvider);
    await controller.redeem(token);

    if (controller.state is RedeemStateSuccess) {
      pending.clear();
    }
  }
}
```

- [ ] **Step 2: Use the effect from `RedeemProgressScreen` on `initState` / via a Riverpod listener**

Update the progress screen to a stateful widget that calls `tryConsumePending` once, then renders state-driven UI.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/lib/src/application/auth/redeem_effect.dart apps/lyron_app/lib/src/presentation/auth/redeem_progress_screen.dart
git commit -m "feat(auth): auto-redeem captured invite token after sign-in"
```

---

## Phase 6 — Mobile platform configuration

### Task 23: iOS configuration

**Files:**
- Modify: `apps/lyron_app/ios/Runner/Runner.entitlements`
- Modify: `apps/lyron_app/ios/Runner/Info.plist`

- [ ] **Step 1: Enable Sign in with Apple + Associated Domains**

In `Runner.entitlements` (create the file if missing — Xcode generates it on first capability toggle, but the plan documents the desired final state):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.developer.applesignin</key>
  <array>
    <string>Default</string>
  </array>
  <key>com.apple.developer.associated-domains</key>
  <array>
    <string>applinks:app.lyron.&lt;staging-domain&gt;</string>
  </array>
</dict>
</plist>
```

- [ ] **Step 2: Custom URL scheme in `Info.plist`**

Inside the top-level `<dict>`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>app.lyron.auth</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>io.lyron.app</string>
    </array>
  </dict>
</array>
```

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/ios/
git commit -m "feat(auth): iOS entitlements and URL scheme for Apple sign-in and deep links"
```

### Task 24: Android configuration

**Files:**
- Modify: `apps/lyron_app/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: Add intent filters**

Inside the main `<activity>` element:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="https"
        android:host="app.lyron.<staging-domain>"
        android:pathPrefix="/invite" />
    <data
        android:scheme="https"
        android:host="app.lyron.<staging-domain>"
        android:pathPrefix="/auth/callback" />
</intent-filter>

<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="io.lyron.app" android:host="auth" />
</intent-filter>
```

- [ ] **Step 2: Commit**

```bash
git add apps/lyron_app/android/
git commit -m "feat(auth): Android App Links and custom scheme intent filters"
```

### Task 25: AASA + assetlinks stubs

**Files:**
- Create: `apps/lyron_app/web/.well-known/apple-app-site-association`
- Create: `apps/lyron_app/web/.well-known/assetlinks.json`

- [ ] **Step 1: AASA**

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "<APPLE_TEAM_ID>.io.lyron.app",
        "paths": ["/invite/*", "/auth/callback/*"]
      }
    ]
  }
}
```

- [ ] **Step 2: assetlinks**

```json
[
  {
    "relation": ["delegate_permission/common.handle_all_urls"],
    "target": {
      "namespace": "android_app",
      "package_name": "io.lyron.app",
      "sha256_cert_fingerprints": ["<FINGERPRINT_HEX>"]
    }
  }
]
```

These files are stubs in the repository; production values are filled in when the staging domain and signing certificates are decided.

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/web/.well-known/
git commit -m "feat(auth): AASA and assetlinks stubs for deep-link verification"
```

---

## Phase 7 — Integration test

### Task 26: Invite redeem integration test

**Files:**
- Create: `apps/lyron_app/test/integration/invite_redeem_flow_test.dart`

- [ ] **Step 1: Write the test**

Mirror the structure of `test/integration/authenticated_song_reader_flow_test.dart`. The test should:

1. Boot the app with a `ProviderScope` whose Supabase client is overridden to a test harness already populated with a singleton organization and a fresh invitation token.
2. Capture the token into `PendingInviteTokenController`.
3. Simulate a magic-link callback that yields a fake `AppAuthSession`.
4. Pump the router; expect navigation to `/redeem` then `/` (home) after `RedeemController` reports success.

(Use the existing harness conventions; do not invent a separate setup.)

- [ ] **Step 2: Run**

```bash
cd apps/lyron_app && flutter test test/integration/invite_redeem_flow_test.dart
```

- [ ] **Step 3: Commit**

```bash
git add apps/lyron_app/test/integration/invite_redeem_flow_test.dart
git commit -m "test(auth): integration test for invite redeem after sign-in"
```

---

## Phase 8 — Documentation

### Task 27: ADR

**Files:**
- Create: `docs/architecture/decisions/ADR-018-invite-only-auth-with-token-redemption.md`

- [ ] **Step 1: Author ADR**

```markdown
# ADR-018: Invite-Only Auth with Token Redemption

## Status

Accepted

## Context

Lyron Chords is invite-only and supports three identity providers (Google, Apple, magic link). Apple Private Relay breaks email-based whitelisting, so we cannot gate access on email alone. We also need a path to delete the account on user request.

## Decision

Identity and authorization are separated:

- Supabase Auth owns identity (Google OAuth, Apple OAuth, magic link).
- An `invitations` table plus a `redeem_invitation` SQL function owns authorization. The function inserts a membership row only when a non-expired, unredeemed token is presented by an authenticated caller.
- A deep-link landing route (`/invite?token=...`) captures the token before sign-in; after sign-in, the client calls the RPC. The router blocks app entry until the user holds an active membership.
- Provider sign-in alone is insufficient to enter the app, so `auth.users` rows may exist without authorization. An hourly `pg_cron` job deletes orphan rows older than 24 hours.
- Account deletion runs a `delete_account` security-definer RPC that removes the caller's `auth.users` row and cascades memberships. `last_modified_by` foreign keys on content tables migrate to `on delete set null`.
- Supabase's "same-email linking" setting is enabled, so a user who arrives through Google and later through magic link with the same verified email becomes one identity. Apple Private Relay users cannot auto-link.

## Consequences

- Backend enforces authorization end-to-end; the client cannot grant itself membership.
- The single-organization product model is preserved; tokens already carry `organization_id` so multi-org work later does not require schema migration.
- Manual identity linking for Apple Private Relay is deferred; users are advised to keep their email-sharing choice consistent.
- Orphan auth identities can be observed in the dashboard for up to 24 hours; this is acceptable for staging.
```

- [ ] **Step 2: Commit**

```bash
git add docs/architecture/decisions/ADR-018-invite-only-auth-with-token-redemption.md
git commit -m "docs: ADR-018 invite-only auth with token redemption"
```

### Task 28: Domain, vocabulary, state machines, architecture updates

**Files:**
- Modify: `docs/domain/domain-model.md`
- Modify: `docs/domain/domain-vocabulary.md`
- Modify: `docs/architecture/state-machines.md`
- Modify: `docs/architecture/architecture.md`

- [ ] **Step 1: Add `Invitation` to the domain model**

Insert an `Invitation` entity into `docs/domain/domain-model.md` with attributes: token, email (optional, informational), organization, role, expires_at, redeemed_at, redeemed_by, issued_by, created_at. Note its lifecycle: created → redeemed | expired.

- [ ] **Step 2: Vocabulary**

Add to `docs/domain/domain-vocabulary.md`:

- `Invitation` — a single-use credential that grants membership when redeemed.
- `Redeem` — the act of converting an invitation into an active membership.
- `Magic link` — a one-time email link that authenticates the recipient on Supabase Auth.
- `Orphan auth identity` — an `auth.users` row without an active membership; eligible for cleanup after 24 hours.

- [ ] **Step 3: State machines**

Append two state machines:

```
Authentication
==============
unauthenticated
  -> initiating-oauth (user taps Google/Apple)
  -> magic-link-sent (user requested email)
  -> authenticated
authenticated
  -> session-expired
  -> signed-out (explicit) -> unauthenticated
  -> deleted (delete_account) -> unauthenticated

Invitation
==========
issued -> redeemed
issued -> expired (>= expires_at without redemption)
```

- [ ] **Step 4: Architecture diagram update**

Mention in `docs/architecture/architecture.md` that the authentication boundary is split: provider-managed identity vs. database-enforced membership; the client cannot bypass `redeem_invitation`.

- [ ] **Step 5: Commit**

```bash
git add docs/domain/ docs/architecture/state-machines.md docs/architecture/architecture.md
git commit -m "docs: document Invitation entity, auth + invitation state machines"
```

---

## Verification

### Task 29: Full local CI

- [ ] **Step 1: Run the local CI entrypoint**

```bash
./scripts/local-ci.sh   # if such a script exists; otherwise the canonical equivalent
```

Expected: green.

- [ ] **Step 2: Smoke deep-link flow on a real iOS device**

Build a TestFlight or local sideload, tap an invite link on the device, complete Google sign-in, redeem, observe the home screen.

- [ ] **Step 3: Smoke deep-link flow on an Android device**

Same procedure via App Links.

- [ ] **Step 4: Open a pull request**

```bash
git push -u origin feat/auth-invite-sso
gh pr create --title "feat(auth): invite-only onboarding, SSO, magic link, account delete" \
  --body "Implements docs/specs/2026-05-16-auth-invite-sso.md."
```

---

## Open follow-ups (deferred)

- Admin UI for issuing invitations
- Transactional email provider rollout (Resend/Postmark) and bilingual email templates
- Manual identity linking for Apple Private Relay
- Production domain and AASA/assetlinks publishing pipeline
- Org-admin role promotion UI
