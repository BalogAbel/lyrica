# Local Environment via Dart Defines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded demo credentials in `sign_in_screen.dart` with compile-time dart-define constants, extend `run-authenticated-app.sh` to pass them, and remove the broken `run-app.sh` script along with its documentation references.

**Architecture:** Single `main.dart` entry point for all environments. `String.fromEnvironment` compile-time constants control pre-fill behavior — present in local dev builds, absent (empty string) in prod/release builds. No runtime branching needed.

**Tech Stack:** Flutter / Dart (`--dart-define`, `String.fromEnvironment`), Bash scripts.

---

## File Map

| File | Action |
|---|---|
| `apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart` | Modify lines 15–16: hardcoded strings → `String.fromEnvironment` |
| `apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart` | Add test case: initial field values are empty without dart-defines |
| `scripts/run-authenticated-app.sh` | Modify lines 30–35: add `DEMO_EMAIL` + `DEMO_PASSWORD` dart-defines |
| `scripts/run-app.sh` | Delete |
| `README.md` | Remove line 182 (`./scripts/run-app.sh`) |
| `apps/lyron_app/README.md` | Remove line 95 (`./scripts/run-app.sh`) |

---

## Task 1: Replace hardcoded credentials with dart-define constants

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart:15-16`
- Test: `apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart`

- [ ] **Step 1: Add a failing test for empty initial field values**

Open `apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart` and add a second test case after the closing brace of the first `testWidgets` block (before the `_StubAuthRepository` class):

```dart
  testWidgets('sign-in fields are empty when no dart-defines are set',
      (tester) async {
    final repository = _StubAuthRepository();
    final controller = AppAuthController(repository);
    await controller.restoreSession();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(repository),
          appAuthControllerProvider.overrideWithValue(controller),
          appAuthListenableProvider.overrideWithValue(controller),
        ],
        child: const MaterialApp(home: SignInScreen()),
      ),
    );
    await tester.pump();

    final emailField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(0));
    final passwordField =
        tester.widget<TextFormField>(find.byType(TextFormField).at(1));

    expect(emailField.controller?.text, isEmpty);
    expect(passwordField.controller?.text, isEmpty);
  });
```

- [ ] **Step 2: Run the new test to verify it fails**

```bash
cd apps/lyron_app && flutter test test/presentation/auth/sign_in_screen_test.dart -v
```

Expected: the new test FAILS because fields currently contain hardcoded text (`demo@lyron.local`, `LyronDemo123!`).

- [ ] **Step 3: Replace hardcoded strings in sign_in_screen.dart**

In `apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart`, replace lines 15–16:

```dart
// Before
  final _emailController = TextEditingController(text: 'demo@lyron.local');
  final _passwordController = TextEditingController(text: 'LyronDemo123!');

// After
  final _emailController = TextEditingController(
    text: const String.fromEnvironment('DEMO_EMAIL'),
  );
  final _passwordController = TextEditingController(
    text: const String.fromEnvironment('DEMO_PASSWORD'),
  );
```

- [ ] **Step 4: Run all sign_in_screen tests to verify both pass**

```bash
cd apps/lyron_app && flutter test test/presentation/auth/sign_in_screen_test.dart -v
```

Expected: both test cases PASS. The first test passes because it uses `enterText` (ignores initial value). The second passes because `String.fromEnvironment` defaults to `''` when the dart-define is absent.

- [ ] **Step 5: Commit**

```bash
git add apps/lyron_app/lib/src/presentation/auth/sign_in_screen.dart \
        apps/lyron_app/test/presentation/auth/sign_in_screen_test.dart
git commit -m "feat: replace hardcoded demo credentials with dart-define constants

Sign-in fields are now empty in prod/release builds.
Local dev builds pre-fill via DEMO_EMAIL and DEMO_PASSWORD dart-defines."
```

---

## Task 2: Extend run-authenticated-app.sh with demo credential dart-defines

**Files:**
- Modify: `scripts/run-authenticated-app.sh:30-35`

- [ ] **Step 1: Add DEMO_EMAIL and DEMO_PASSWORD to the flutter run invocation**

In `scripts/run-authenticated-app.sh`, replace the `flutter run` block (lines 30–35):

```bash
# Before
cd "$app_dir"
"$flutter_bin" run \
  -d "$flutter_device" \
  --target lib/main.dart \
  --dart-define=SUPABASE_URL="$resolved_api_url" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  "$@"

# After
cd "$app_dir"
"$flutter_bin" run \
  -d "$flutter_device" \
  --target lib/main.dart \
  --dart-define=SUPABASE_URL="$resolved_api_url" \
  --dart-define=SUPABASE_ANON_KEY="$ANON_KEY" \
  --dart-define=DEMO_EMAIL="demo@lyron.local" \
  --dart-define=DEMO_PASSWORD="LyronDemo123!" \
  "$@"
```

- [ ] **Step 2: Verify script syntax**

```bash
bash -n scripts/run-authenticated-app.sh
```

Expected: no output (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add scripts/run-authenticated-app.sh
git commit -m "chore: pass demo credentials as dart-defines in local run script"
```

---

## Task 3: Delete run-app.sh and remove its documentation references

**Files:**
- Delete: `scripts/run-app.sh`
- Modify: `README.md` (remove line `./scripts/run-app.sh`)
- Modify: `apps/lyron_app/README.md` (remove line `./scripts/run-app.sh`)

- [ ] **Step 1: Delete the script**

```bash
rm scripts/run-app.sh
```

- [ ] **Step 2: Remove run-app.sh from root README.md**

In `README.md` around line 182, find and remove the line:
```
./scripts/run-app.sh
```

Also remove it from the Verification section (around line 95 in the same file context — check both occurrences with `grep -n "run-app" README.md`).

- [ ] **Step 3: Remove run-app.sh from apps/lyron_app/README.md**

In `apps/lyron_app/README.md` around line 95, find and remove the line:
```
./scripts/run-app.sh
```

- [ ] **Step 4: Verify no remaining references**

```bash
grep -r "run-app" . --include="*.md" --include="*.sh" --include="*.yaml"
```

Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add -u scripts/run-app.sh README.md apps/lyron_app/README.md
git commit -m "chore: remove broken run-app.sh script and its documentation references

Script was non-functional (missing --dart-define flags) and never called
by any other script or CI. Use run-authenticated-app.sh for local dev."
```

---

## Self-Review Notes

- Spec requirement: single `main.dart` entry point → no `main_local.dart` created ✓
- Spec requirement: `DEMO_EMAIL`/`DEMO_PASSWORD` via dart-define → Task 1 + Task 2 ✓
- Spec requirement: empty fields in prod → `String.fromEnvironment` default `''` ✓
- Spec requirement: delete `run-app.sh` + docs cleanup → Task 3 ✓
- No TBD or placeholders present ✓
- Type/method names consistent across all tasks ✓
- Existing test (submit flow) unaffected — it uses `enterText` which overrides initial value ✓
