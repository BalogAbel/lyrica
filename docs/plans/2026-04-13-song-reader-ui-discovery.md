# Song Reader UI Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture and maintain a single repository-owned plan for the song reader UI discovery slice, covering the static prototype, its interaction behavior, and the transition path toward implementation planning.

**Architecture:** Keep the discovery slice confined to one spec and one plan, with the prototype living under `docs/prototypes/`. The prototype demonstrates the approved compact-versus-expanded reader structure, touch-first control reveal, adaptive layout behavior, theme support, and a reviewer-only compact overlay toggle for comparison.

**Tech Stack:** Markdown, static HTML, CSS, vanilla JavaScript

---

### Task 1: Keep The Discovery Documents Canonical

**Files:**
- Modify: `docs/specs/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/plans/2026-04-13-song-reader-ui-discovery.md`

- [ ] **Step 1: Maintain one reader UI spec**

Keep all reader UI discovery decisions in `docs/specs/2026-04-13-song-reader-ui-discovery.md` so the repository has a single source of truth for this slice.

- [ ] **Step 2: Maintain one reader UI plan**

Keep this plan file as the only implementation-plan document for the discovery slice. Do not create follow-up plan fragments for mockup iterations unless the scope expands into a separate sub-project.

### Task 2: Maintain The Static Prototype

**Files:**
- Modify: `docs/prototypes/song-reader-reader-mockup.html`
- Modify: `docs/prototypes/song-reader-reader-mockup.css`
- Modify: `docs/prototypes/song-reader-reader-mockup.js`

- [ ] **Step 1: Preserve compact reader behavior**

The prototype must keep compact mode aligned with the approved design:

- content-first song surface
- persistent bottom context bar
- controls available through overlay only
- overlay reveal and hide behavior tied to direct interaction
- pinch-scale and double-tap auto-fit demonstration

- [ ] **Step 2: Preserve expanded reader behavior**

The prototype must keep expanded mode aligned with the approved design:

- left context panel
- center song surface
- right reader-tools panel
- no reader overlay in expanded mode

- [ ] **Step 3: Preserve comparison tooling as reviewer-only**

The prototype may keep reviewer controls for:

- viewport simulation
- theme switching
- compact-mode overlay visibility comparison

Those controls must remain clearly outside the intended shipped reader chrome.

### Task 3: Preserve Theme And Layout Decisions

**Files:**
- Modify: `docs/specs/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/prototypes/song-reader-reader-mockup.css`
- Modify: `docs/prototypes/song-reader-reader-mockup.js`

- [ ] **Step 1: Keep theme vocabulary consistent**

Use the same theme names everywhere:

- `standard`
- `high-contrast`
- `black`

- [ ] **Step 2: Keep layout adaptation behavior aligned with the spec**

The prototype must continue to model layout adaptation as viewport- and scale-aware behavior rather than as a product-level manual column switch.

### Task 4: Prepare For Later Implementation Planning

**Files:**
- Modify: `docs/specs/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/plans/2026-04-13-song-reader-ui-discovery.md`

- [ ] **Step 1: Treat the current prototype as design validation, not shipped behavior**

Any future Flutter implementation plan should use the prototype as a direction artifact, while still specifying real platform behavior for gestures, animation timing, breakpoints, and accessibility.

- [ ] **Step 2: Move to implementation planning only after visual approval**

Once the compact and expanded reader direction is visually approved, write a separate implementation plan for the actual Flutter work instead of continuing to extend the discovery plan.

### Task 5: Verification

**Files:**
- Modify: `docs/specs/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/plans/2026-04-13-song-reader-ui-discovery.md`
- Modify: `docs/prototypes/song-reader-reader-mockup.html`
- Modify: `docs/prototypes/song-reader-reader-mockup.css`
- Modify: `docs/prototypes/song-reader-reader-mockup.js`

- [ ] **Step 1: Re-read spec, plan, and prototype together**

Confirm they tell the same story about:

- compact versus expanded reader behavior
- touch-first overlay use in compact mode
- no overlay in expanded mode
- adaptive layout behavior
- reviewer-only comparison controls

- [ ] **Step 2: Check repository scope**

Use `git diff -- docs/specs/2026-04-13-song-reader-ui-discovery.md docs/plans/2026-04-13-song-reader-ui-discovery.md docs/prototypes/song-reader-reader-mockup.html docs/prototypes/song-reader-reader-mockup.css docs/prototypes/song-reader-reader-mockup.js` and confirm the change set stays limited to the consolidated discovery slice.

- [ ] **Step 3: State residual prototype limitations explicitly**

Keep it explicit that the static prototype does not replace real implementation work for native gestures, accessibility behavior, and final breakpoint tuning.
