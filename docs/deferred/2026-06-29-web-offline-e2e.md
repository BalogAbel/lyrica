# Web/IndexedDB Offline E2E

**Slice:** local-first-validation
**Files:**
- `apps/lyron_app/test/integration/offline_edit_relaunch_sync_flow_test.dart` (native relaunch coverage, skip-gated on Supabase env)
- `apps/lyron_app/test/support/drift_relaunch.dart` (native close/reopen harness)

## Problem

The adversarial local-first validation slice proves offline-edit-then-relaunch-then-sync
behavior (`LF-T1`) on the **native** Drift/sqlite3 backend by closing and reopening the
database in-process. It does not exercise the **web** target, where Drift persists to
IndexedDB and the browser owns eviction policy. Web-specific failure modes — IndexedDB
quota eviction, tab-close-vs-reload semantics, service-worker caching interaction with the
Supabase auth token in `localStorage` — are entirely unverified.

## Deferred Because

A web offline e2e suite needs a `chromedriver`-driven Flutter web test lane: a new CI
job, browser driver provisioning, and a way to simulate offline (network condition
override) and storage pressure (forcing IndexedDB eviction) inside a real browser. This is
new test infrastructure, not an extension of the existing native `flutter test` harness, and
was out of scope for a slice focused on closing native correctness/characterization gaps
(`LF-1` through `LF-8`, `LF-T4`, `LF-T6`, `LF-T7`).

## What Covers It Instead

The native relaunch suite (`offline_edit_relaunch_sync_flow_test.dart`) faithfully exercises
the same offline-edit → relaunch → reconnect → sync flow against the native backend, and the
Drift migration/catalog suites (`planning_migration_test.dart`,
`song_catalog_migration_test.dart`) cover reopen-survival for pending mutations. These give
confidence in the local-first **logic**; they do not exercise the **browser storage
substrate**.

**Update (2026-07-30, security read-boundary phase 3, DX-2).** CI now has a
`web_build` job (`.github/workflows/ci.yml`) that runs `flutter build web
--release`. This does **not** narrow the gap described above: it proves the web
target compiles and nothing about IndexedDB behaviour, offline semantics or
storage pressure. It is recorded here so a future slice does not add a second web
job — the existing one is the place to attach a `chromedriver` lane. It has
already earned its keep: the `file_picker` 11 bump in the same slice broke the web
build, and the compile gate is what surfaced it.

**Update (2026-08-08, web catalog refresh race).** The gap described here has
now cost something concrete. The song catalog never loaded on web at all —
`GET /rest/v1/songs` was never issued — because of a startup trigger race that
native platforms win by accident
(`docs/specs/2026-08-08-web-catalog-refresh-race.md`, ADR-031). The `web_build`
compile gate passed throughout: the bug was behavioural, not a compile failure,
and nothing in the native suite exercised the web startup ordering that exposed
it. It was found by hand, by serving a web build and reading the browser
console. The regressions are now covered by native unit tests, so this does not
close the deferral — it is evidence for the trigger condition below, and for
web behaviour being unobserved rather than observed-and-passing.

## Trigger Condition

Address before committing to web as a supported production target for offline/rehearsal
use, or before relying on IndexedDB capacity assumptions in `LF-T4` storage-eviction work.
Any slice that adds a web CI lane or a `chromedriver` harness should fold this suite in
rather than starting a separate effort.
