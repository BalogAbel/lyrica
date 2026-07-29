# ADR-025: Invitation Redemption Model

- Status: Accepted
- Date: 2026-07-29
- Extends: [ADR-018-invite-only-auth-with-token-redemption.md](ADR-018-invite-only-auth-with-token-redemption.md)
- Spec: `docs/specs/2026-07-29-sec1-invitation-redemption-hardening.md`
- Plan: `docs/plans/2026-07-29-sec1-invitation-redemption-hardening.md`
- Findings: `SEC-1`

## Context

ADR-018 separated identity (Supabase Auth) from authorization (`invitations` +
`memberships` + `redeem_invitation`), but the redemption gate itself was a pure
bearer credential: `redeem_invitation` stored `invitations.email` at creation
time but never compared it against the caller, and nothing throttled or
recorded repeated redemption attempts (SEC-1). Token entropy
(`extensions.gen_random_bytes(32)`) makes brute force impractical, so the
realistic threat is not guessing a token but a leaked link — forwarded mail, a
shared screenshot, a chat history — which, unbound, is equivalent to
organization membership.

## Decision

`public.redeem_invitation(p_token text)` now enforces a hybrid binding, a
caller-keyed rate limit, and a per-attempt audit trail, all in the database.

**Hybrid email binding.** When `invitations.email` is not null, redemption
requires the caller's own account to hold that address, confirmed, compared
case- and whitespace-insensitively (`lower(btrim(...))`). A null
`invitations.email` stays a bearer link, chosen per invitation by the issuing
admin.

**Caller-keyed rate limit.** Keyed on `auth.uid()`. Ten `not_found` or
`email_mismatch` outcomes by the same caller within 15 minutes trip
`rate_limited` for the remainder of the window.

**Per-attempt audit.** Every call — successful or not — writes a row to
`public.invitation_redemption_attempts`
(`supabase/migrations/202607290001_invitation_redemption_audit.sql`), storing
a `sha256` digest of the token, never the raw token. RLS denies all direct
writes to `authenticated`; the only writer is the security-definer redemption
path. Select is scoped to organization admins of the row's `organization_id`;
rows with no organization (unresolved tokens) are `service_role`-only. A daily
`pg_cron` job deletes attempts older than 90 days.

**Returned-status contract.** `redeem_invitation` returns
`jsonb {"status": <outcome>, "organization_id": <uuid|null>}`
(`supabase/migrations/202607290002_invitation_redemption_contract.sql`)
instead of `uuid`, and no longer raises for business outcomes. `status` is one
of `redeemed | not_found | expired | already_redeemed | already_member |
email_mismatch | rate_limited`, with only `redeemed` carrying a non-null
`organization_id`. The single remaining raise is a null `auth.uid()`
(`42501 invitation_redeem_requires_auth`) — unreachable in normal operation,
since the function is granted to `authenticated` only and there is no actor to
audit or rate-limit in that case.

## Why outcomes are returned rather than raised

This is the constraint that forced the contract change. In PostgreSQL, an
exception aborts the enclosing transaction, so an audit row inserted before a
`raise` is rolled back with it. As long as `redeem_invitation` signaled
business outcomes by raising, a failed attempt could never be persisted —
which rules out both a real audit trail and a count-based rate limit at once,
since the limit is itself a count over persisted audit rows. Returning a
status instead of raising lets the transaction commit on every path, so the
audit row and the rate-limit counter it feeds both survive.

## Rejected alternatives

**Strict email binding, always required.** Require `p_email` and always
compare it against the caller. Simpler, but the admin types the address at
invite time while the invitee may sign in through Google or Apple SSO and
arrive with a different verified address — strict binding would lock out a
legitimate invitee with no recovery short of reissuing the invitation.

**Documented bearer model** ("link == entry ticket"). Accept the current
behavior, document it as intentional, and stop there. Simplest option and
matches common invite-link conventions elsewhere, but it leaves a leaked link
equal to organization membership — which is the finding SEC-1 raises, not a
resolution of it.

**`dblink` autonomous transaction for logging.** Use `dblink` to open a second
connection and commit an audit row independently of the calling transaction's
outcome, preserving `redeem_invitation`'s `uuid`-returning signature. Rejected:
it adds an extension, a loopback connection carrying its own credentials, and
a fragile local/CI test path, to avoid a contract change that is otherwise
straightforward and machine-checkable.

## Why only `not_found` and `email_mismatch` count toward the rate limit

Those two outcomes are the signature of token probing: an attacker working
through guessed or stolen tokens produces exactly this pattern. `expired`,
`already_redeemed`, and `already_member` are benign — a real user retrying a
stale link, or clicking an old invite a second time, produces them without any
adversarial intent. Counting benign outcomes would let ordinary retry behavior
lock a legitimate user out of their own redemption attempt.

## Email source: `auth.users.email`, not the JWT claim

The binding check reads `auth.users.email` and `auth.users.email_confirmed_at`
directly rather than the JWT's `email` claim. Supabase's own `auth.email()`
helper is deprecated in favor of `auth.jwt() ->> 'email'`, but a JWT claim can
be stale after an address change until the token is refreshed, while the
account row is current. `redeem_invitation` is already `security definer`, so
the account record is directly and authoritatively readable — there is no
reason to prefer a claim that can lag behind it.

## Standing constraint: binding strength depends on email confirmation

The check proves the caller's account carries the invited address; it proves
that address was *verified* only if the project requires email confirmation
at signup. `supabase/config.toml` sets `[auth.email] enable_confirmations =
false` for local development only — that setting must not carry over to the
hosted project, or an account could claim an arbitrary address at signup and
redeem an email-bound invitation meant for someone else. This is why
redemption additionally requires `email_confirmed_at is not null`, and why
this is recorded here as a standing operational constraint rather than a
one-time implementation detail. Separately, `double_confirm_changes = true`
already prevents an existing account from moving onto an invited address
without controlling that inbox, so the risk is confined to signup-time
confirmation.

## Consequences

- **Breaking RPC contract.** Any client built before this migration casts the
  RPC result to `String` and will fail against the new `jsonb` shape. The
  Flutter client (`InvitationError`, `invitationErrorFromStatus`,
  `SupabaseInvitationRepository`, `app_strings`, `redeem_progress_screen`) is
  updated in the same slice; there is no other caller today.
- **Audit table growth is bounded.** The 90-day `pg_cron` retention job
  (`supabase/migrations/202607290001_invitation_redemption_audit.sql`) deletes
  old attempts; only token digests are ever stored, never raw tokens.
- **A caller with no confirmed account email cannot redeem an email-bound
  invitation.** This includes phone-only accounts and accounts with an
  unconfirmed address. The bearer path (null `invitations.email`) remains the
  issuing admin's escape hatch when this matters.
- **Model and rejected alternatives are pinned by test, not just by this
  document.** `scripts/tests/invitation-redemption-contract-test.sh` (16
  cases, chained from `./scripts/backend-write-contracts.sh`) covers the full
  outcome matrix, including grant survival across the function's
  drop-and-recreate.
