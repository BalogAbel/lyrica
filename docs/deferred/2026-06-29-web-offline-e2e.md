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

## Trigger Condition

Address before committing to web as a supported production target for offline/rehearsal
use, or before relying on IndexedDB capacity assumptions in `LF-T4` storage-eviction work.
Any slice that adds a web CI lane or a `chromedriver` harness should fold this suite in
rather than starting a separate effort.
