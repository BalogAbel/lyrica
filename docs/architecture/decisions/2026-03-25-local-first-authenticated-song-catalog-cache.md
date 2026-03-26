# ADR: Local-First Authenticated Song Catalog Cache

## Status

Accepted

## Context

The authenticated song-reader slice already proved that Supabase-backed song summaries and raw ChordPro source can be read through backend-enforced RLS. The repository still needed an executable local-first read path that keeps songs usable during unstable or missing connectivity without widening the product into write sync.

## Decision

Use a Drift-backed authenticated song-catalog cache as a read model for the current slice.

The cache rules are:

- cache one active full visible catalog snapshot per authenticated user for the currently active organization context
- persist both `SongSummary` values and raw `SongSource` payloads
- replace the active snapshot only after a complete full-catalog refresh succeeds
- keep ChordPro parsing, diagnostics, and reader projection in Flutter
- keep Supabase Auth and Postgres RLS as the authorization and refresh authority
- remove cached authenticated access on explicit sign-out
- do not retain a historical local snapshot archive for this slice

## Consequences

- Native Flutter targets can relaunch into the latest successfully fetched visible catalog snapshot while offline.
- Browser-based offline authenticated relaunch is best-effort for this slice; the repository keeps the web cache path, but does not require browser session persistence to match native behavior.
- Connectivity failures are no longer treated as equivalent to confirmed session expiry.
- UI must surface persistent catalog status for online, offline, refreshing, and refresh-failed modes.
- The app now depends on Drift for an executable read-side cache, but it still avoids introducing write sync, edit flows, or backend-owned reader projections.
