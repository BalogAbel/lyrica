# ADR: Reader Zoom Local Persistence

## Status

Accepted

## Context

The song reader gained pinch-to-zoom and double-tap fit-to-screen, both expressed through the existing shared font scale. The chosen zoom level must survive leaving and reopening a song, and it is a per-musician, per-song reading preference rather than shared catalog data. We needed a place to store a single scalar (the font scale) keyed by user and song, without widening the product into write sync or adding backend surface.

The repository already uses Drift for the local-first authenticated song-catalog cache (see `2026-03-25-local-first-authenticated-song-catalog-cache.md`) and Supabase Auth for identity.

## Decision

Persist the reader zoom locally with `shared_preferences`, keyed by `reader_zoom:{userId}:{songId}` as a double.

The rules are:

- store one zoom value per `(userId, songId)` pair; `userId` comes from the same Supabase Auth identity the offline layer uses
- read the stored value once when the reader opens and seed the shared font scale from it; absent value means the default scale
- write the value debounced after a pinch gesture ends and after a double-tap fit/restore
- skip persistence entirely when there is no authenticated user id
- keep the store behind a `SongReaderPreferencesStore` interface exposed via a Riverpod provider, so it is overridable in tests
- do not persist zoom to Supabase and do not add a Drift table or migration for it

### Alternatives considered

- **Drift table** keyed by user+song: rejected. A schema migration plus code generation is disproportionate overhead for a single scalar reading preference.
- **Supabase-backed preference**: rejected. Zoom is a local reading comfort setting; it needs no backend authority, no RLS, and no cross-row coordination, and the product is intentionally not widening write sync in this slice.

## Consequences

- Zoom is device-local: it is not synced across a user's devices. This is acceptable for a reading-comfort preference and avoids backend and sync complexity.
- The app gains a `shared_preferences` dependency alongside Drift; the two cover different needs (key-value preference vs. structured read cache) and are not consolidated.
- Persistence is best-effort: read/write failures fall back to the default scale and never block reading, consistent with the offline-resilience posture.
- Tests override the store provider (and a small `readerUserIdProvider` seam) to exercise seed-on-open without a live Supabase session.
