# Song session-expiry cache policy test and documentation hardening

Status: Deferred

Classification: P2

## Context

A targeted audit of song session-expiry cache behavior found that the current policy appears intentional and documented, but is under-tested.

Current behavior:

- Explicit song sign-out deletes the persisted song catalog cache.
- Song session expiry clears the active catalog context and blocks cached authenticated reading, but preserves persisted song cache rows.
- Planning deletes persisted local planning data on both explicit sign-out and session expiry.
- Offline or unverifiable auth/session state still allows cached song fallback for the last authenticated user context.

## Risk

This is not a proven unsafe access path.

The risk is regression or ambiguity around the distinction between:

- preserving persisted song cache rows after session expiry; and
- blocking active cached song access while the app is in `sessionExpired`.

## Required future tests

- `sessionExpired` clears the song active catalog context.
- Persisted song cache remains after session expiry, or is intentionally deleted if the policy changes.
- Re-sign-in after expiry can reuse the persisted song cache only after `signedIn` and auth context are restored.
- Provider/read path cannot access cached songs while auth state is `sessionExpired`.

## Documentation

Update `docs/testing/testing-strategy.md` to explicitly mention the song session-expiry cache policy and its required regression coverage.

## Escalation

A mini worker is acceptable for tests and documentation only.

Require stronger review before changing actual session-expiry cache behavior.
