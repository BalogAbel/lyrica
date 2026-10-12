# ADR-041: Keyset-Paged Full Pulls

**Status:** Accepted (2026-10-12; implemented on `fix/paged-remote-pulls`)
**Builds on:** ADR-037 (local-first catalog visibility), ADR-035 D4 (the
rejected-empty-snapshot guard), ADR-038 (plan `content_version`, invariant
I7), ADR-036 (observability)
**Context spec:** `docs/specs/2026-10-12-paged-remote-pulls.md` (PG1–PG11)

## Context

The song catalog refresh and the planning refresh each read every visible
row from Supabase. They used single, unpaged PostgREST requests. PostgREST
caps every read node at `db-max-rows` (1000 locally and on hosted projects),
embedded resources included, and truncates silently. A catalog over the cap
lost songs. A plan whose sessions or items were truncated stored a
`content_version` ahead of its projected children, which breaks I7. The
catalog also fetched every song source with its own request, all at once.

## Decision

1. **Every full pull reads in keyset pages.** A stream reads
   `order(<key>, ascending: true)`, `gt(<key>, <last key>)`,
   `limit(<page size>)`, and ends only on an **empty** page. Offset paging
   (`.range()`) and short-page termination are not used: an offset shifts
   when rows are inserted or deleted between pages, and a short page is
   normal whenever the server cap is below the page size. With keyset paging
   the result cannot be truncated, whatever the cap, so no `count=exact`
   check is needed.
2. **One shared helper.** `readAllKeysetPages` in
   `apps/lyron_app/lib/src/shared/keyset_paging.dart` is domain-agnostic. It
   takes a generic key with a mandatory comparator (`compareUuidKeys` is
   valid only for Postgres `uuid` columns). It verifies that keys strictly
   increase and that no page exceeds its limit, and throws
   `PagedReadContractException` otherwise. It checks `shouldContinue` before
   and after every fetch and throws `PagedReadAbortedException` when the
   caller's refresh went stale. Any fetch error propagates; there is never a
   partial result.
3. **Replace only after the whole sequence.** A snapshot or projection is
   replaced only after every page of every stream has been read. A failed
   page is a failed refresh, and the stored data stays. ADR-037 and the D4
   guard are unchanged.
4. **Organization-scoped streams.** Every stream filters by the active
   organization. The catalog reads `chordpro_source` in the same stream as
   the summaries (no per-song requests). Planning reads `plans`, then
   `sessions`, then `session_items` as three organization-wide streams, in
   that order, which keeps I7, and drops children whose parent was not read.
   No pull embeds a to-many resource.
5. **A broken paging contract is reported.** The controllers report a
   `PagedReadContractException` to observability (no row data) and fail the
   refresh. An abort is not reported.

## Consequences

- A library or organization of any size refreshes completely. 1000 songs
  take 11 sequential requests instead of one truncated list plus 1000
  concurrent source requests.
- Each stream costs one extra request: the empty final page.
- A new pull (for example the personal-layer pull of slice S3) reuses the
  helper with its own key and comparator, and follows the same rules.
- `session_items` has no `(organization_id, id)` index, so its stream is a
  filtered primary-key range scan. Adding the index is a separate backend
  chore if it is ever needed.
- The Supabase repositories now expose only their refresh reads; the dead
  per-row remote read methods were removed.
