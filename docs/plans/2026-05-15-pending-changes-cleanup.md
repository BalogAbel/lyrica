# Pending Changes Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove `PlanningInlineMutationStatusBadge` and its supporting symbols, so mutation status surfaces entirely through `PlanningWorkspaceStatusSurface` and `UnifiedSyncHeaderControl`.

**Architecture:** Three symbols are deleted from `planning_workspace_status_surface.dart` (`PlanningInlineMutationStatus`, `planningInlineMutationStatusFor`, `PlanningInlineMutationStatusBadge`). All call sites in `plan_list_screen.dart` and `plan_detail_screen.dart` are cleaned up. Tests that asserted on the removed badge widgets are deleted. Four now-unused `AppStrings` constants are removed. Two legacy doc lines are updated.

**Tech Stack:** Flutter/Dart, Riverpod, flutter_test

---

## File map

| File | Action |
|---|---|
| `apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart` | Delete 3 symbols (enum + function + widget class) |
| `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart` | Remove `inlineStatus` local + `ListTile.trailing` badge |
| `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart` | Remove `planInlineStatus` local + plan-header `if` block; remove `inlineStatus` + session-card `if` block in `_SessionCard` |
| `apps/lyron_app/lib/src/shared/app_strings.dart` | Delete 4 unused label constants |
| `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart` | Delete 4 badge test methods |
| `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart` | Delete 1 badge test method |
| `docs/specs/2026-04-24-planning-workspace-ui.md` | Update line 101 |
| `docs/plans/2026-04-28-planning-workspace-ui.md` | Update lines 28 and 31 |

---

### Task 1: Delete badge tests from `plan_list_screen_test.dart`

**Files:**
- Modify: `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`

Remove the following four complete `testWidgets` blocks (lines ~360–514). Their names are:
- `'marks plans with pending local changes inline'`
- `'marks conflict rows inline'`
- `'marks authorization denied rows inline'`
- `'marks sync issue rows inline'`

Each block starts with `testWidgets('marks ...` and ends at the closing `});` before the next `testWidgets`. Confirm `AppStrings.planningConflictLabel`, `AppStrings.planningAuthorizationDeniedLabel`, and `AppStrings.planningSyncIssueLabel` references are gone from this file after deletion.

- [ ] **Step 1: Delete the four test methods**

Open `apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart`. Delete the block from `testWidgets('marks plans with pending local changes inline', (tester) async {` through the closing `});` of `testWidgets('marks sync issue rows inline', ...`. That is approximately lines 360–514.

- [ ] **Step 2: Verify the file still compiles**

```bash
cd apps/lyron_app && flutter analyze lib/src/presentation/planning/ test/presentation/planning/plan_list_screen_test.dart
```

Expected: no errors.

- [ ] **Step 3: Run plan_list_screen tests**

```bash
cd apps/lyron_app && flutter test test/presentation/planning/plan_list_screen_test.dart
```

Expected: all remaining tests pass.

---

### Task 2: Delete badge test from `plan_detail_screen_test.dart`

**Files:**
- Modify: `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`

Remove the `testWidgets('marks pending plan and session edits inline', ...)` block (~lines 417–461). It starts with `testWidgets('marks pending plan and session edits inline',` and ends at the closing `});` before `testWidgets('renders each conflict row...`.

- [ ] **Step 1: Delete the test method**

Open `apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart`. Delete from `testWidgets('marks pending plan and session edits inline',` through its closing `});`.

- [ ] **Step 2: Run plan_detail_screen tests**

```bash
cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart
```

Expected: all remaining tests pass.

---

### Task 3: Delete badge symbols from `planning_workspace_status_surface.dart`

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart`

The file currently starts with three symbols before `PlanningWorkspaceStatusSurface`. Delete all three:

1. `enum PlanningInlineMutationStatus { ... }` — 6 lines
2. `PlanningInlineMutationStatus? planningInlineMutationStatusFor(Iterable<PlanningMutationRecord> entries) { ... }` — ~20 lines
3. `class PlanningInlineMutationStatusBadge extends StatelessWidget { ... }` — ~30 lines

Keep the `import` statements (the `app_strings.dart` import is still needed by `PlanningWorkspaceStatusSurface`). Keep `PlanningWorkspaceStatusSurface`, `_ActionCluster`, and everything below them.

- [ ] **Step 1: Delete the three symbols**

Remove everything from line 5 (`enum PlanningInlineMutationStatus`) through the closing `}` of `PlanningInlineMutationStatusBadge.build`. The file after editing should start with imports then jump directly to `class PlanningWorkspaceStatusSurface`.

- [ ] **Step 2: Verify compilation**

```bash
cd apps/lyron_app && flutter analyze lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart
```

Expected: no errors (there will be errors in plan_list_screen.dart and plan_detail_screen.dart — fix those next).

---

### Task 4: Remove badge call site from `plan_list_screen.dart`

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart`

Two changes inside `itemBuilder`:

**Before:**
```dart
final plan = plans[index];
final inlineStatus = planningInlineMutationStatusFor(
  mutationsAsync.valueOrNull?.where(
        (entry) =>
            entry.aggregateId == plan.id ||
            entry.planId == plan.id,
      ) ??
      const <PlanningMutationRecord>[],
);

return ListTile(
  title: Text(plan.name),
  subtitle: _PlanSummarySubtitle(plan: plan),
  trailing: inlineStatus == null
      ? null
      : PlanningInlineMutationStatusBadge(
          key: ValueKey('plan-row-status-${plan.id}'),
          status: inlineStatus,
        ),
  onTap: () =>
      context.push(PlanningRoutes.planDetailLocation(plan.slug)),
);
```

**After:**
```dart
final plan = plans[index];

return ListTile(
  title: Text(plan.name),
  subtitle: _PlanSummarySubtitle(plan: plan),
  onTap: () =>
      context.push(PlanningRoutes.planDetailLocation(plan.slug)),
);
```

- [ ] **Step 1: Apply the edit**

Remove the `inlineStatus` local variable declaration and the `trailing:` parameter from the `ListTile`.

- [ ] **Step 2: Verify compilation**

```bash
cd apps/lyron_app && flutter analyze lib/src/presentation/planning/plan_list_screen.dart
```

Expected: no errors.

- [ ] **Step 3: Run plan_list_screen tests**

```bash
cd apps/lyron_app && flutter test test/presentation/planning/plan_list_screen_test.dart
```

Expected: all pass.

---

### Task 5: Remove badge call sites from `plan_detail_screen.dart`

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart`

**Change 1 — plan header (inside `data:` callback, ~lines 107–140):**

**Before:**
```dart
final planInlineStatus = planningInlineMutationStatusFor(
  mutationEntries.where(
    (entry) =>
        entry.aggregateId == detail.plan.id &&
        (entry.kind == PlanningMutationKind.planCreate ||
            entry.kind == PlanningMutationKind.planEdit),
  ),
);
return ReorderableListView.builder(
  buildDefaultDragHandles: false,
  padding: EdgeInsets.zero,
  header: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            detail.plan.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (planInlineStatus != null)
            PlanningInlineMutationStatusBadge(
              key: ValueKey('plan-local-status-${detail.plan.id}'),
              status: planInlineStatus,
            ),
        ],
      ),
```

**After:**
```dart
return ReorderableListView.builder(
  buildDefaultDragHandles: false,
  padding: EdgeInsets.zero,
  header: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        detail.plan.name,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
```

(The `Wrap` is no longer needed for a single child — replace it with the `Text` directly.)

**Change 2 — `_SessionCard.build` (~lines 517–565):**

**Before:**
```dart
final inlineStatus = planningInlineMutationStatusFor(
  widget.mutationEntries.where(
    (entry) =>
        entry.aggregateId == session.id || entry.sessionId == session.id,
  ),
);
```
and inside the `Wrap`:
```dart
if (inlineStatus != null)
  PlanningInlineMutationStatusBadge(
    key: ValueKey('session-local-status-${session.id}'),
    status: inlineStatus,
  ),
```

**After:** Remove the `inlineStatus` local variable entirely. Replace the `Wrap` with a plain `Text`:

```dart
Text(
  session.name,
  style: Theme.of(context).textTheme.titleMedium,
),
```

(The `Wrap` held only the `Text` and the conditional badge — with the badge gone, simplify to `Text` directly.)

- [ ] **Step 1: Apply Change 1** — remove `planInlineStatus` local and collapse the `Wrap` to a plain `Text`.

- [ ] **Step 2: Apply Change 2** — remove `inlineStatus` local and collapse the session-header `Wrap` to a plain `Text`.

- [ ] **Step 3: Verify compilation**

```bash
cd apps/lyron_app && flutter analyze lib/src/presentation/planning/plan_detail_screen.dart
```

Expected: no errors.

- [ ] **Step 4: Run plan_detail_screen tests**

```bash
cd apps/lyron_app && flutter test test/presentation/planning/plan_detail_screen_test.dart
```

Expected: all pass.

- [ ] **Step 5: Commit tasks 1–5**

```bash
git add \
  apps/lyron_app/lib/src/presentation/planning/widgets/planning_workspace_status_surface.dart \
  apps/lyron_app/lib/src/presentation/planning/plan_list_screen.dart \
  apps/lyron_app/lib/src/presentation/planning/plan_detail_screen.dart \
  apps/lyron_app/test/presentation/planning/plan_list_screen_test.dart \
  apps/lyron_app/test/presentation/planning/plan_detail_screen_test.dart
git commit -m "chore(sync): remove PlanningInlineMutationStatusBadge

Inline pending/conflict chips on plan rows and session cards are
redundant after the unified sync header and PlanningWorkspaceStatusSurface
cover status discovery and error recovery.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 6: Remove unused AppStrings constants

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`

The four constants below were only used by `PlanningInlineMutationStatusBadge`. Delete them:

```dart
static const planningLocalChangesLabel = 'Local changes';
static const planningConflictLabel = 'Conflict';
static const planningAuthorizationDeniedLabel = 'Authorization changed';
static const planningSyncIssueLabel = 'Sync issue';
```

- [ ] **Step 1: Delete the four constants**

- [ ] **Step 2: Verify no remaining usages**

```bash
cd apps/lyron_app && grep -r "planningLocalChangesLabel\|planningConflictLabel\|planningAuthorizationDeniedLabel\|planningSyncIssueLabel" lib/ test/
```

Expected: no output.

- [ ] **Step 3: Verify compilation**

```bash
cd apps/lyron_app && flutter analyze lib/src/shared/app_strings.dart
```

Expected: no errors.

- [ ] **Step 4: Run full test suite**

```bash
cd apps/lyron_app && flutter test
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/shared/app_strings.dart
git commit -m "chore(sync): remove unused inline badge AppStrings constants

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

### Task 7: Update legacy doc references

**Files:**
- Modify: `docs/specs/2026-04-24-planning-workspace-ui.md`
- Modify: `docs/plans/2026-04-28-planning-workspace-ui.md`

**`docs/specs/2026-04-24-planning-workspace-ui.md` line 101:**

**Before:**
```
- do not invent plan lifecycle statuses such as `Ready` or `Draft`; plan-row badges should represent existing local-first/sync conditions such as local changes, conflict, or authorization denied
```

**After:**
```
- do not invent plan lifecycle statuses such as `Ready` or `Draft`; mutation status surfaces through `PlanningWorkspaceStatusSurface` and the unified sync header, not inline row badges
```

**`docs/plans/2026-04-28-planning-workspace-ui.md` line 28:**

**Before:**
```
- plan rows mark local pending, conflict, authorization-denied, or failed planning mutations inline
```

**After:**
```
- plan rows show name, description, and scheduled date; mutation status surfaces through the workspace action surface and unified sync header
```

**`docs/plans/2026-04-28-planning-workspace-ui.md` line 31:**

**Before:**
```
- plan detail marks pending plan edits beside the plan header and pending session edits beside the session title
```

**After:**
```
- plan detail shows the plan name as a headline and session names as card titles without inline mutation chips
```

- [ ] **Step 1: Apply the three doc edits**

- [ ] **Step 2: Commit**

```bash
git add docs/specs/2026-04-24-planning-workspace-ui.md docs/plans/2026-04-28-planning-workspace-ui.md
git commit -m "docs(sync): update planning workspace docs after badge removal

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Self-review

**Spec coverage:**
- ✅ `PlanningInlineMutationStatus` enum deleted — Task 3
- ✅ `planningInlineMutationStatusFor` function deleted — Task 3
- ✅ `PlanningInlineMutationStatusBadge` widget deleted — Task 3
- ✅ `plan_list_screen.dart` call site removed — Task 4
- ✅ `plan_detail_screen.dart` plan-header call site removed — Task 5
- ✅ `plan_detail_screen.dart` session-card call site removed — Task 5
- ✅ Tests updated (`plan_list_screen_test.dart`) — Task 1
- ✅ Tests updated (`plan_detail_screen_test.dart`) — Task 2
- ✅ `docs/specs/2026-04-24-planning-workspace-ui.md` updated — Task 7
- ✅ `docs/plans/2026-04-28-planning-workspace-ui.md` updated — Task 7
- ✅ Unused `AppStrings` constants removed — Task 6

**Placeholder scan:** No TBDs or vague steps. All edits show exact before/after.

**Type consistency:** No new types introduced. Deletion-only plan — no cross-task type dependencies.
