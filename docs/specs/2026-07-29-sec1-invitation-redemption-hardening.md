# SEC-1: Invitation Redemption Hardening

> Status: Implemented

## Goal

Close SEC-1 from `docs/architecture/repository-review-2026-06-22.md`: invitation
redemption is currently a pure bearer credential with no email binding, no rate
limiting, and no audit trail of attempts. This spec pins a hybrid redemption
model (email-bound when the invitation carries an email, bearer otherwise), a
caller-keyed rate limit, and a persisted audit trail of redemption activity —
with repeated terminal outcomes and rate-limited calls capped as described
below — all enforced in the database, not the Flutter client.

## Problem

`public.redeem_invitation(p_token text)`
(`supabase/migrations/202605160002_invitations_functions.sql:48`) accepts any
authenticated caller presenting a valid, unexpired, unredeemed token and inserts
an organization membership row. It stores `invitations.email` at creation time
but never compares it against the caller.

Three concrete gaps:

1. **No email binding.** A leaked invite link grants unintended organization
   membership. Token entropy (`extensions.gen_random_bytes(32)`) makes brute
   force impractical, so the realistic threat is link leakage — forwarded mail,
   a shared screenshot, a chat history — not guessing.

2. **No rate limiting.** Nothing throttles repeated redemption attempts by an
   authenticated caller, so systematic token probing is unbounded and invisible.

3. **No audit trail of attempts.** `invitations.redeemed_at` / `redeemed_by`
   record only the single successful redemption. Failed attempts leave no trace,
   so probing cannot be detected after the fact.

**The structural obstacle.** `redeem_invitation` signals every business outcome
with `raise exception`. In PostgreSQL an exception aborts the transaction, so an
audit row inserted before the raise is rolled back with it. As long as the
function raises, failed attempts cannot be persisted — which means neither a
real audit trail nor a count-based rate limit is possible. Any fix to gaps 2 and
3 must first resolve this.

## Scope

- New audit table `public.invitation_redemption_attempts` with an outcome enum,
  RLS, a rate-limit-shaped index, and a `pg_cron` retention job.
- `public.redeem_invitation` rewritten: `returns jsonb` instead of
  `returns uuid`, hybrid email binding, caller-keyed rate limit, and an audit
  write on every path that is not a deduplicated repeat (see the audit caps
  added in follow-up hardening).
- Flutter client updated to the new status-based contract
  (`SupabaseInvitationRepository`, `InvitationError`, `app_strings`, redeem UI).
- Backend contract test script covering the full outcome matrix, wired into
  `./scripts/backend-write-contracts.sh`.
- ADR-025 recording the redemption model and the rejected alternatives.

## Non-Goals

- No admin-facing invitation management UI. `create_invitation` has no client
  call site today; invitations are issued out of band. This slice does not
  change that.
- No change to `create_invitation`'s signature or to the 30-day expiry.
- No IP-based or unauthenticated rate limiting. `redeem_invitation` is granted
  to `authenticated` only, so `auth.uid()` is always available as a rate-limit
  key, and request-header-derived client IPs are not a dependable input.
- No change to `role_code` semantics or the read-only role constraints.

## Decisions (from brainstorm)

1. **Hybrid email binding.** When `invitations.email is not null`, redemption
   requires the caller's confirmed account email to match it. When it is null,
   the token remains a bearer credential. The issuing admin chooses per
   invitation: targeted or open link.

   *Rejected — strict binding always* (require `p_email`, always compare): the
   admin types the address, but the user signs in through Google or Apple SSO
   and may arrive with a different verified address; strict binding would lock
   out legitimate invitees with no recovery path short of reissuing.

   *Rejected — documented bearer* ("link == entry ticket"): simplest and matches
   common invite-link behavior, but leaves a leaked link equal to organization
   membership, which is the finding SEC-1 raises.

2. **Return contract change over autonomous logging.** `redeem_invitation`
   returns `jsonb` describing the outcome instead of raising for business
   outcomes, so the transaction commits and the audit row and rate-limit counter
   survive.

   *Rejected — `dblink` autonomous transaction*: preserves the RPC signature but
   adds an extension, a loopback connection with credentials, and a fragile
   local/CI test path.

   *Rejected — success-only audit*: keeps the current raising contract, but
   failed attempts stay invisible, so neither probing detection nor a count-based
   rate limit is achievable — it would close the finding on paper only.

3. **Caller-keyed rate limit on suspicious outcomes only.** Key is `auth.uid()`.
   Only `not_found` and `email_mismatch` count toward the limit: 10 within 15
   minutes trips `rate_limited` for the remainder of the window. Benign outcomes
   (`expired`, `already_redeemed`, `already_member`) do not count, so a real user
   retrying a stale link cannot lock themselves out. Token probing is the only
   attack this limit needs to catch, and both counted outcomes are exactly its
   signature.

## Current State

- `public.invitations` — `token` unique, `email` nullable, `expires_at`,
  `redeemed_at`, `redeemed_by`, `issued_by`
  (`supabase/migrations/202605160001_invitations_schema.sql`).
- RLS denies direct insert/update/delete to `authenticated`; select is allowed to
  the issuer and to organization admins
  (`supabase/migrations/202605160003_invitations_rls.sql`).
- `redeem_invitation` is revoked from `public` and granted to `authenticated`
  (`supabase/migrations/202605160007_auth_boundary_hardening.sql:45,52`).
- `pg_cron` deletes orphan `auth.users` rows with no active membership after 24
  hours (`supabase/migrations/202605160006_pg_cron_orphan_cleanup.sql`).
- Client: `SupabaseInvitationRepository` calls the RPC and casts the result to
  `String`; `invitationErrorFromMessage` maps raised message strings to
  `InvitationError`.

## Target Behavior

### Audit table

```
public.invitation_redemption_outcome  -- enum
  redeemed | not_found | expired | already_redeemed
  | already_member | email_mismatch | rate_limited

public.invitation_redemption_attempts
  id              uuid primary key
  invitation_id   uuid null  references public.invitations(id) on delete set null
  token_sha256    bytea not null
  actor_user_id   uuid null  references auth.users(id)        on delete set null
  outcome         public.invitation_redemption_outcome not null
  organization_id uuid null  references public.organizations(id) on delete cascade
  created_at      timestamptz not null default timezone('utc', now())
```

- **The raw token is never stored.** The token is a bearer credential; copying it
  into an audit table creates a second leak surface. `token_sha256` gives
  correlation across attempts without that exposure.
- `actor_user_id` is nullable with `on delete set null` so the existing hourly
  orphan-user cleanup cannot be blocked by audit rows.
- `invitation_id` is null when the token does not resolve to an invitation.
- Index `(actor_user_id, created_at desc) where outcome in ('not_found',
  'email_mismatch')` — the exact shape of the rate-limit count query.

RLS: enabled. No insert/update/delete policy for `authenticated` (writes happen
only through the security-definer function). Select is allowed to organization
admins of `organization_id`. Rows with a null `organization_id` — failed lookups
— are therefore reachable only via `service_role`, which is intended: they belong
to no organization.

Retention: a daily `pg_cron` job deletes attempts older than 90 days, added
alongside the existing hourly orphan cleanup.

### `redeem_invitation` contract

```
public.redeem_invitation(p_token text) returns jsonb
  -> {"status": <text>, "organization_id": <uuid|null>}
```

`status` is one of the enum values above, with `redeemed` carrying a non-null
`organization_id` and every other status carrying null.

Only one condition still raises: a null `auth.uid()` raises `42501`
`invitation_redeem_requires_auth`. There is no actor to key an audit row or a
rate-limit bucket to, and the function is granted to `authenticated` only, so
this path is unreachable in normal operation.

Evaluation order, with an audit row written on every branch and the existing
`for update` row lock preserved:

1. Authentication — raise if `auth.uid()` is null.
2. Rate limit — count `not_found` + `email_mismatch` attempts by this caller in
   the last 15 minutes; at 10 or more, record `rate_limited` and return.
3. Token lookup — miss records `not_found` (null `invitation_id`) and returns.
4. Prior redemption — non-null `redeemed_at` records `already_redeemed` and
   returns.
5. Expiry — `expires_at <= now()` records `expired` and returns.

Steps 4 and 5 keep the current function's precedence: an invitation that was
redeemed and has since expired still reports `already_redeemed`, which is the
more useful answer. This slice changes the transport, not the precedence.
6. Email binding — if `invitations.email` is not null, compare
   `lower(btrim(invitations.email))` against the caller's account email. A
   mismatch, or a caller with no email on record, records `email_mismatch` and
   returns. A null `invitations.email` skips this check (bearer invitation).

   **Email source.** The comparison reads `auth.users.email` for `auth.uid()`,
   not the JWT `email` claim. The function is already `security definer`, so the
   read is available, and the account record is authoritative and current where a
   claim can be stale after an email change. Supabase's own `auth.email()` helper
   is deprecated in favour of `auth.jwt() ->> 'email'`, but that claim carries the
   same staleness caveat, and reading it would make the contract tests depend on
   the exact JWT-claim GUC shape rather than on data.

   **Binding strength depends on email ownership verification.** The check proves
   the caller's account carries the invited address; it proves that address was
   verified only if the project requires it. `supabase/config.toml` sets
   `[auth.email] enable_confirmations = false` for local development, which would
   let a locally-signed-up account claim an arbitrary address. Redemption
   therefore also requires `auth.users.email_confirmed_at is not null`, and the
   ADR records that the hosted project must keep signup confirmations enabled for
   the binding to mean anything. `double_confirm_changes = true` already prevents
   moving an existing account onto an invited address without controlling the
   inbox.
7. Existing membership — an active organization-scope membership records
   `already_member` and returns.
8. Success — insert the membership, set `redeemed_at` / `redeemed_by`, record
   `redeemed`, return the organization id.

**Migration mechanics.** Changing the return type from `uuid` to `jsonb` cannot
be done with `create or replace`; the migration must `drop function
public.redeem_invitation(text)` and recreate it. The drop discards the grants
established in `202605160007_auth_boundary_hardening.sql`, so the migration must
reapply `revoke all ... from public` and `grant execute ... to authenticated`.
Silent grant loss here is the most likely regression in this change, so it is
covered by an explicit contract test rather than left to review.

### Client

- `InvitationError` gains `emailMismatch` and `rateLimited`.
- `invitationErrorFromMessage` is replaced by `invitationErrorFromStatus`
  (replaced, not added alongside — the message-based mapping has no remaining
  caller).
- `SupabaseInvitationRepository.redeem` reads the returned map's `status` and
  `organization_id` instead of casting to `String`. Unexpected shapes and
  transport failures keep the existing `network` / `unknown` mapping.
- `app_strings.dart` gains user-facing copy for the two new outcomes.
- The redeem flow (`redeem_controller`, `redeem_progress_screen`) renders them.

The client remains UX-only. Every gate above is enforced in the database; no
client change can bypass any of them.

## Testing Strategy

New `scripts/tests/invitation-redemption-contract-test.sh`, wired into
`./scripts/backend-write-contracts.sh` following the existing script pattern.
Written failing first, then made to pass by the migration.

Backend cases:

1. Bearer invitation (`email is null`) redeems successfully for any
   authenticated caller — the hybrid model must not break open links.
2. Email-bound invitation redeems when the caller's confirmed account email
   matches.
3. Email match is case- and whitespace-insensitive.
4. Email mismatch returns `email_mismatch`, creates **no** membership row, and
   writes an audit row.
5. A caller with no account email, and a caller whose email is not confirmed,
   both return `email_mismatch` on an email-bound invitation.
6. Expired invitation returns `expired` with an audit row.
7. Already-redeemed invitation returns `already_redeemed` with an audit row.
8. Caller who is already an active member returns `already_member`.
9. Unknown token returns `not_found` with an audit row carrying a null
   `invitation_id` and a non-null `token_sha256`.
10. Rate limit: after 10 `not_found` attempts within the window, the 11th call
    returns `rate_limited` **even when presented with a valid token**, and no
    membership is created.
11. Benign outcomes do not accumulate toward the limit.
12. `authenticated` cannot insert, update, or delete
    `invitation_redemption_attempts` directly; a non-admin cannot select another
    organization's rows.
13. `redeem_invitation` remains executable by `authenticated` and revoked from
    `public` after the drop-and-recreate.

Flutter cases: `invitationErrorFromStatus` mapping for each status, and
`SupabaseInvitationRepository` translating a jsonb response into
`RedeemSuccess` / `RedeemFailure`, including a malformed response.

## Documentation & Deferred Resolution

- `docs/architecture/decisions/ADR-025-invitation-redemption-model.md` — the
  hybrid model, both rejected alternatives with reasoning, the rate-limit
  policy, and the jsonb contract change. (ADR-017 is unused; 024 is the current
  highest.)
- `docs/architecture/repository-review-2026-06-22.md` — mark SEC-1 fixed using
  the existing `~~struck~~ **Done (...)**` convention.
- `docs/architecture/architecture.md` — update the auth boundary section to
  describe the redemption model.
- `docs/testing/testing-strategy.md` — register the new contract test script.
- `docs/plans/2026-07-29-sec1-invitation-redemption-hardening.md` — the
  implementation plan.

No entry in `docs/deferred/` covers SEC-1, so nothing is removed there by this
slice.

## Risks

- **Grant loss on drop-and-recreate.** Mitigated by an explicit contract test
  (case 13) rather than by review attention.
- **Contract change breaks older clients.** A client built before this migration
  casts the jsonb response to `String` and fails. Acceptable: the app is not yet
  distributed to external users, and redemption failure is visible and
  recoverable rather than silent. Noted in the ADR.
- **Callers without a confirmed email.** A phone-only account, or any account
  whose address is unconfirmed, fails every email-bound invitation. Test case 5
  pins this as an explicit `email_mismatch` rather than an unexplained error, and
  the bearer path (null `invitations.email`) remains available to the issuing
  admin as the escape hatch.
- **Binding depends on project auth configuration.** If the hosted project ever
  disables signup email confirmation, an account can be created claiming an
  address it does not own. The `email_confirmed_at` requirement is the in-database
  half of the guarantee; the configuration is the other half, and the ADR records
  it as a standing constraint rather than a one-time setting.
- **Rate limit locking out a legitimate user.** Bounded by counting only
  `not_found` and `email_mismatch`, and by the 15-minute window expiring on its
  own with no admin action.
- **Audit table growth.** Bounded by the 90-day `pg_cron` retention job.
