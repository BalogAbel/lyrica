# Online-Preferred Local-First Sync Contract Planning Slice

> **For agentic workers:** This is a documentation and decision-record slice. Implementation plans for code changes should be written after this contract is reviewed.

**Goal:** Establish the repository-owned product and architecture contract for online-preferred, offline-safe, local-first synchronization.

**Assumptions:** Existing song and planning local-first guarantees remain valid. This slice does not implement realtime subscriptions or unified sync UI.

**Architecture:** Document the sync contract first, then use it as the source for two follow-up implementation slices: shared sync/status modeling, then unified sync/freshness UX. Keep backend authorization and repository-owned local projections as non-negotiable boundaries.

**Tech Stack:** Markdown repository docs, existing Flutter/Riverpod/Drift/Supabase architecture references

---

### Task 1: Record the product and architecture contract

**Files:**
- Add: `docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md`
- Add: `docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md`

- [x] **Step 1: Define the product contract**

State that Lyron is online-preferred, offline-safe, and local-first.

Verify:

```bash
rg -n "online-preferred|offline-safe|local-first" docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md
```

- [x] **Step 2: Define subscription boundaries**

Document realtime subscription events as invalidation triggers, not UI data sources.

Verify:

```bash
rg -n "invalidation|Subscription events|UI data source" docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md
```

### Task 2: Align durable repository docs

**Files:**
- Modify: `docs/product/vision.md`
- Modify: `docs/architecture/architecture.md`
- Modify: `docs/deferred/2026-04-29-unified-manual-sync.md`

- [x] **Step 1: Update product language**

Clarify that offline operation remains first-class while online availability should improve freshness and collaboration.

Verify:

```bash
rg -n "online-preferred|offline-safe|freshness" docs/product/vision.md
```

- [x] **Step 2: Update architecture language**

Align system summary, data flow, and offline strategy with the new sync contract.

Verify:

```bash
rg -n "online-preferred|invalidation|foreground|offline-to-online" docs/architecture/architecture.md
```

- [x] **Step 3: Update deferred sync note**

Mark unified manual sync as pulled into planned follow-up scope instead of an unowned deferred idea.

Verify:

```bash
rg -n "online-preferred|follow-up|superseded|planned" docs/deferred/2026-04-29-unified-manual-sync.md
```

### Task 3: Review the planning slice

**Files:**
- Review: `docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md`
- Review: `docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md`
- Review: `docs/product/vision.md`
- Review: `docs/architecture/architecture.md`
- Review: `docs/deferred/2026-04-29-unified-manual-sync.md`

- [x] **Step 1: Run incomplete-marker and contradiction checks**

Verify:

```bash
rg -n "TBD|TODO|implement later|PLACEHOLDER" docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md docs/product/vision.md docs/architecture/architecture.md docs/deferred/2026-04-29-unified-manual-sync.md
```

- [x] **Step 2: Check changed files**

Verify:

```bash
git diff -- docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md docs/plans/2026-05-09-online-preferred-local-first-sync-contract.md docs/product/vision.md docs/architecture/architecture.md docs/deferred/2026-04-29-unified-manual-sync.md
```

- [ ] **Step 3: Commit after review**

After the user approves the written contract:

```bash
git add docs/specs/2026-05-09-online-preferred-local-first-sync-contract.md docs/architecture/decisions/ADR-015-online-preferred-local-first-sync.md docs/plans/2026-05-09-online-preferred-local-first-sync-contract.md docs/product/vision.md docs/architecture/architecture.md docs/deferred/2026-04-29-unified-manual-sync.md
git commit -m "docs: define online-preferred local-first sync"
```
