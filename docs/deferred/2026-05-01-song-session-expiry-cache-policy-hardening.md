# Song session-expiry cache policy test and documentation hardening

Status: Resolved

Classification: P2

## Context

A targeted audit of song session-expiry cache behavior found that the current policy appears intentional and documented, but is under-tested.

Current behavior:

- Explicit song sign-out deletes the persisted song catalog cache.
- Song session expiry clears the active catalog context and blocks cached authenticated reading, but preserves persisted song cache rows.
- Planning deletes persisted local planning data on both explicit sign-out and session expiry.
- Offline or unverifiable auth/session state still allows cached song fallback for the last authenticated user context.

## Resolution

The repository now defines and verifies the session-expiry song cache policy with regression tests.

Verified coverage:

- `sessionExpired` clears the song active catalog context.
- Persisted song cache rows remain in the store after session expiry.
- Provider/read paths cannot access cached songs while auth state is `sessionExpired`.
- Re-sign-in restores the auth boundary before cached song data becomes readable again.

Verified commands:

- `cd apps/lyron_app && flutter test test/application/song_library/song_catalog_controller_test.dart`
- `cd apps/lyron_app && flutter test test/application/providers_test.dart`

## Documentation

Update `docs/testing/testing-strategy.md` to explicitly mention the song session-expiry cache policy and its required regression coverage.

## Escalation

A mini worker is acceptable for tests and documentation only.

Require stronger review before changing actual session-expiry cache behavior.
