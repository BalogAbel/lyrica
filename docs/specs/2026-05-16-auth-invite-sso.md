# Auth Slice: Invite-Only Onboarding, SSO, Magic Link, Account Delete

- **Date:** 2026-05-16
- **Branch:** `feat/auth-invite-sso`
- **Related ADRs:** ADR-007 (RBAC + RLS), ADR-016 (Active Organization Resolution Semantics)
- **Status:** Draft

## Purpose

Establish the first executable authentication slice for Lyron Chords. The product is invite-only, single-organization for now, and supports three identity providers (Google SSO, Apple SSO, email magic link) plus self-serve account deletion. The slice owns onboarding (invite token redemption), sign-in, account recovery, and account deletion. It does not deliver organization administration UI or transactional email infrastructure.

## Scope

### In Scope

- `invitations` table, SQL functions, RLS, and tests
- `pg_cron` cleanup of orphaned `auth.users` rows older than 24 hours
- Supabase Auth configuration: Google, Apple, magic link, same-email identity linking
- Flutter `auth` feature module: data, domain, application, presentation
- Deep link handling (iOS Universal Links, Android App Links, Web routes) for `/invite` and `/auth/callback`
- AASA + `assetlinks.json` deployment to staging domain
- Router gate logic that reconciles authentication state with active-organization resolution from ADR-016
- TDD coverage: SQL contract tests, Flutter unit, widget, and integration tests
- New ADR documenting the invite-redeem decision

### Out of Scope (Deferred)

- Admin UI for invitation issuance (use SQL or service-role tooling)
- Transactional email provider (Resend / Postmark); Supabase built-in SMTP is acceptable for staging
- Manual identity-linking UI for Apple Private Relay edge case
- Multi-organization UX (tokens already carry `organization_id`, but the UI assumes one active org)
- Custom production domain registration; the slice can land on a staging domain
- Organization-admin role promotion UI

## Decisions Captured

The following user-confirmed decisions drive the design. Each is restated here so the spec stands alone.

1. **Invite mechanism:** single-use token-based link. Email is not a gate (Apple Private Relay breaks email whitelisting).
2. **Email auth flavor:** magic link only. No password, no `forgot-password` flow; account recovery is "request a new magic link to the verified email."
3. **Identity linking:** Supabase native auto-link on verified email. Apple Private Relay users cannot auto-link across providers; this is an accepted limitation in the slice.
4. **Invite delivery (now):** SQL/CLI only. Admin UI is deferred.
5. **Account delete:** hard delete of `auth.users`; cascades memberships; `last_modified_by` on songs/plans is set to `NULL`.
6. **Default org/role on redeem:** token carries `organization_id` and `role_code`. Current product has one organization, but the token shape is forward-compatible.
7. **Platform scope:** iOS, Android, Web.
8. **Token lifetime:** single-use, 30-day expiry from issuance.
9. **Account recovery (lost provider/email):** magic link to verified email is the self-serve path. Email loss escalates to admin SQL.
10. **Identity creation policy:** ephemeral `auth.users` is acceptable when no redeem follows; `pg_cron` deletes orphan rows older than 24 hours.

## Architecture Overview

```
+----------------+       +------------------------+       +------------------+
| Flutter client | <---> | Supabase Auth (OAuth + | <---> | Postgres (RLS,   |
| (iOS/Android/  |       | magic link)            |       | invitations,    |
|  Web)          |       |                        |       | memberships,    |
+----------------+       +------------------------+       | RPC functions,  |
        |                                                 | pg_cron)        |
        |     deep links: /invite?token=, /auth/callback  +------------------+
        |
        +--> redeem_invitation(token) RPC
        +--> delete_account() RPC
```

Identity (Supabase Auth) and authorization (membership) are deliberately separated. Provider sign-in produces an authenticated session only. The application gains access to data exclusively after `redeem_invitation` creates an active membership row. The router enforces this gate using ADR-016 resolution outcomes.

## Backend Design

### `invitations` table

```sql
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

Notes:

- `token` is a 32-byte URL-safe random string generated server-side.
- `email` is informational only (e.g., for admin recall); it must not gate redemption.
- The active-token partial index supports fast lookup during redemption while letting historical rows accumulate.
- `expires_at` defaults to `now() + interval '30 days'` when produced through `create_invitation`.

### SQL functions (`security definer`, `search_path = public`)

#### `create_invitation(p_organization_id uuid, p_role role_code, p_email text default null) returns text`

- Caller must be an active `organization_admin` of `p_organization_id`, validated by `auth.uid()` lookup in `memberships`.
- Generates `token` from `encode(gen_random_bytes(32), 'base64')` and strips URL-unsafe characters.
- Inserts the row with `issued_by = auth.uid()`, `expires_at = now() + interval '30 days'`.
- Returns the raw token string.
- For initial bootstrap (no admin yet), the service-role key can call this function; the function bypasses the admin check when `auth.uid()` is null (i.e., service-role context).

#### `redeem_invitation(p_token text) returns uuid`

- Caller must be authenticated (`auth.uid() is not null`).
- Acquires `for update` lock on the matching invitation row.
- Validates: row exists, `redeemed_at is null`, `expires_at > now()`.
- Inserts into `memberships` (`scope_type = 'organization'`, `role_code` from the invitation, `status = 'active'`).
- Updates the invitation row with `redeemed_at = now()`, `redeemed_by = auth.uid()`.
- Returns `organization_id`.
- Defined error contract (raised via `raise exception using errcode = 'P0001', message = '<code>'` or a dedicated `lyron_error` enum if introduced):
  - `invitation_not_found`
  - `invitation_expired`
  - `invitation_already_redeemed`
  - `already_member` (caller already has an active membership for that `organization_id`)

#### `delete_account() returns void`

- Caller must be authenticated.
- Executes `delete from auth.users where id = auth.uid()`.
- Schema-level FKs already cascade memberships and pending mutations through `on delete cascade`.
- `songs.last_modified_by`, `plans.last_modified_by`, `sessions.last_modified_by`, etc., must be migrated to `on delete set null` if they are not already. (Verify during implementation; add migration as needed.)

### RLS

- `invitations`:
  - `select`: `auth.uid() = issued_by` OR caller is an active `organization_admin` of `invitations.organization_id`.
  - `insert`, `update`, `delete`: denied to authenticated users; functions perform writes under `security definer`.
- `memberships`: existing policies remain authoritative; `redeem_invitation` writes through `security definer`.

### Orphan cleanup with `pg_cron`

```sql
create extension if not exists pg_cron;

select cron.schedule(
  'cleanup-orphan-auth-users',
  '0 * * * *',
  $$
    delete from auth.users u
    where u.created_at < now() - interval '24 hours'
      and not exists (
        select 1 from public.memberships m
        where m.user_id = u.id and m.status = 'active'
      )
  $$
);
```

- Runs hourly; deletes any `auth.users` row that is more than 24 hours old without an active membership.
- The local Supabase config (`supabase/config.toml`) must enable `pg_cron`.
- Verified through `cron.job_run_details` during testing.

### Database tests

Use the existing Supabase SQL test infrastructure (consistent with prior write-contract migrations). Required cases:

- `create_invitation` rejects non-admins; admins receive a token.
- `redeem_invitation` succeeds; second call by another user with the same token returns `invitation_already_redeemed`.
- `redeem_invitation` honors expiry; expired tokens raise `invitation_expired`.
- `redeem_invitation` raises `already_member` when the caller already holds a membership.
- `delete_account` removes `auth.users`, cascades memberships, sets `last_modified_by` to null on referenced rows.
- `pg_cron` orphan cleanup deletes a synthetic orphan row older than 24 hours; preserves rows with active memberships and orphans younger than 24 hours.

## Supabase Auth Configuration

| Setting | Value |
|---|---|
| Google provider | enabled; client IDs registered for iOS, Android, Web |
| Apple provider | enabled; Services ID, key ID, team ID, private key configured |
| Magic link (`signInWithOtp`) | enabled |
| `Allow linking same emails across providers` | ON |
| Redirect URLs | `https://app.lyron.<staging-domain>/auth/callback`, `io.lyron.app://auth/callback` |
| Email template | Lyron-branded; bilingual (Hungarian, English) magic-link copy |

Custom domain registration is deferred. The staging domain `app.lyron.<staging-domain>` is sufficient for the slice; the exact subdomain is recorded in the implementation plan.

## Deep Linking

| Path | Purpose | Web behavior | Mobile behavior |
|---|---|---|---|
| `/invite?token=...` | Capture invite token | `go_router` route stores token in app state | `app_links` route stores token; navigates to sign-in |
| `/auth/callback?...` | OAuth + magic link return | Supabase JS handles | Supabase Flutter handles |

Mobile deep-link configuration:

- iOS: deploy `apple-app-site-association` at `https://app.lyron.<staging-domain>/.well-known/apple-app-site-association`.
- Android: deploy `assetlinks.json` at the same `.well-known/` path.
- Flutter: `app_links` package for a unified deep-link API.

## Flutter Application Architecture

New feature module at `apps/lyron_app/lib/features/auth/`:

- `domain/` — `Invitation`, `AuthIdentity`, `RedeemResult` types; error code enum aligned with SQL error codes.
- `data/` — `AuthRepository` wraps Supabase `Auth` (Google, Apple, magic link, sign-out, delete account); `InvitationRepository` wraps `redeem_invitation`.
- `application/` — Riverpod providers:
  - `authStateProvider` exposes the Supabase auth state stream.
  - `pendingInviteTokenProvider` holds the token captured from a deep link until it can be redeemed.
  - `redeemControllerProvider` exposes the redeem state machine (`idle`, `inFlight`, `succeeded(orgId)`, `failed(code)`).
- `presentation/` — screens: `SignInScreen` (provider buttons), `InviteLandingScreen` (deep-link landing surface), `MagicLinkSentScreen`, `InviteRequiredScreen` (paste fallback), `AccountScreen` (sign out + delete account).

Router gate logic (executed inside `go_router` redirect):

```
authenticated == false                                     -> /sign-in
authenticated == true:
  membershipResolution == selected(orgId)                  -> /
  membershipResolution == verifiedEmpty:
    pendingInviteToken != null                             -> auto-redeem
    pendingInviteToken == null                             -> /invite-required
  membershipResolution == unknownConnectivityFailure       -> /offline-blocked
  membershipResolution == unknownNonConnectivityFailure    -> /error
```

Sign-out and account-delete flows reuse the ADR-016 `verifiedEmpty` cleanup path: clear active catalog and planning contexts, delete authenticated local snapshots, drop pending mutations.

## Error Mapping (RPC → UI)

| SQL error | Hungarian copy | Recommended action |
|---|---|---|
| `invitation_not_found` | "Érvénytelen meghívó link." | Show paste fallback or instruct user to request a new invite |
| `invitation_expired` | "Lejárt meghívó (30 nap)." | Instruct user to request a new invite |
| `invitation_already_redeemed` | "Meghívó már felhasználva." | If caller was the original redeemer, route them to sign-in with their original provider |
| `already_member` | "Már tagja vagy a szervezetnek." | Redirect to home |
| Network / timeout | "Nincs hálózat." | Retry; treat as `unknownConnectivityFailure` per ADR-016 |

## Edge Cases

1. Two providers, two `auth.users` rows: Supabase same-email linking merges them automatically. Apple Private Relay produces a relay address and cannot auto-link with a Google or magic-link identity. The slice does not provide manual linking; users are advised in copy to keep their Apple email-sharing choice consistent.
2. OAuth completes but redeem never runs: the orphan `auth.users` row is deleted by the hourly cron after 24 hours. The invitation remains usable (`redeemed_at` is still null) and can be retried.
3. Authenticated user opens `/invite` with a new token: the slice ignores it (single-org model). A future multi-org slice may surface a "switch organization" prompt.
4. Two concurrent redeem attempts on the same token: `select ... for update` serializes them; the loser receives `invitation_already_redeemed`.
5. Apple sign-in: first session "Share My Email," second session "Hide My Email." Apple returns the same `sub`, so Supabase recognizes the same identity. No user-visible regression.
6. Magic-link rate limit on Supabase built-in SMTP: UI surfaces a `"Túl sok próbálkozás, várj N percet"` toast. Production rollout will switch to a transactional provider.
7. Pending offline mutations at account delete: confirmation dialog warns the user; hard delete cascades remove pending mutation rows.

## Definition of Done

- A newly invited user can complete onboarding with Google, Apple, or magic link, and lands on the home screen with an active membership.
- Same-email auto-linking is observed: a user who first signs in with magic link and later with Google ends up as one `auth.users` row.
- Account deletion removes `auth.users`, cascades memberships, and triggers the ADR-016 `verifiedEmpty` cleanup on the device.
- The hourly orphan cleanup cron removes an `auth.users` row that is older than 24 hours and lacks an active membership.
- All new SQL contract tests, Flutter unit tests, widget tests, and integration tests pass locally and in CI.
- AASA and `assetlinks.json` are deployed to the staging domain and verified on real iOS and Android devices.
- Documentation updated:
  - New ADR (working title `ADR-018: Invite-Only Auth with Token Redemption`) documenting the identity-vs-authorization split, ephemeral-orphan policy, and same-email linking decision.
  - Domain model and state-machine docs updated for auth and invitation lifecycles.
  - README pointers refreshed where applicable.

## Open Questions

- Exact staging subdomain for AASA and `assetlinks.json` (to be recorded in the implementation plan).
- Whether `last_modified_by` FKs require migration to `on delete set null` or already have that behavior; confirm during implementation and include the migration only if needed.
- Initial seed plan for the singleton organization and the first organization-admin user (likely a one-off SQL script invoked with the service-role key).
