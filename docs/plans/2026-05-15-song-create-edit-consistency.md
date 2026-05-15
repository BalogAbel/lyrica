# Song Create/Edit Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `_SongEditorDialog` AlertDialog with a full-screen `SongEditorScreen` create mode, unifying the song create and edit flows.

**Architecture:** `SongEditorScreen` gains two named constructors — `.edit(...)` (existing behaviour) and `.create()` (new). A new `/songs/new` route maps to `SongEditorScreen.create()`. `SongListScreen._createSong()` is simplified to push that route. `_SongEditorDialog` and `_SongEditorDraft` are deleted entirely.

**Tech Stack:** Flutter, Riverpod, go_router, flutter_test

---

## File Map

| Action | Path |
|--------|------|
| Modify | `apps/lyron_app/lib/src/shared/app_strings.dart` |
| Modify | `apps/lyron_app/lib/src/router/app_routes.dart` |
| Modify | `apps/lyron_app/lib/src/router/app_router.dart` |
| Modify | `apps/lyron_app/lib/src/router/slug_route_resolvers.dart` |
| Modify | `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart` |
| Modify | `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart` |
| Modify | `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart` |
| Modify | `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart` |

---

## Task 1: Add constants — `AppStrings.songCreateTitle` and `AppRoutes.songCreate`

**Files:**
- Modify: `apps/lyron_app/lib/src/shared/app_strings.dart`
- Modify: `apps/lyron_app/lib/src/router/app_routes.dart`

No behaviour change — pure additions. No failing test needed.

- [ ] **Step 1: Add `songCreateTitle` to `AppStrings`**

In `app_strings.dart`, add after `static const songEditAction = 'Edit song';`:

```dart
  static const songCreateTitle = 'New song';
```

- [ ] **Step 2: Add `songCreate` to `AppRoutes`**

In `app_routes.dart`, replace the enum body with:

```dart
enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  planList('/plans'),
  planDetail('/plans/:planSlug'),
  planSessionSongReader(
    '/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug',
  ),
  songCreate('/songs/new'),
  songEditor('/songs/:songSlug/edit'),
  songReader('/songs/:songSlug');

  const AppRoutes(this.path);

  final String path;
}
```

`songCreate` must be listed **before** `songEditor` and `songReader` so go_router matches `/songs/new` before the `:songSlug` wildcard pattern.

- [ ] **Step 3: Commit**

```bash
cd apps/lyron_app
git add lib/src/shared/app_strings.dart lib/src/router/app_routes.dart
git commit -m "feat: add songCreateTitle string and songCreate route constant"
```

---

## Task 2: Refactor `SongEditorScreen` to named constructors (TDD)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Modify: `apps/lyron_app/lib/src/router/slug_route_resolvers.dart`
- Modify: `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart`

- [ ] **Step 1: Write failing tests**

In `test/presentation/song_editor/song_editor_screen_test.dart`, replace the existing `_pumpScreen` helper and add two new tests:

Replace `_pumpScreen` at the bottom of the file:

```dart
Future<void> _pumpScreen(
  WidgetTester tester,
  Size physicalSize, {
  String? initialSource,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = physicalSize;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        unifiedSyncOverviewProvider.overrideWithValue(
          const UnifiedSyncOverview.initial(),
        ),
      ],
      child: MaterialApp(
        home: SongEditorScreen.edit(
          songId: 'song-1',
          songSlug: 'egy-ut',
          initialSource: initialSource,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
```

Add these two tests before the closing `}` of `main()`:

```dart
  testWidgets('create mode renders with New song title', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            const UnifiedSyncOverview.initial(),
          ),
        ],
        child: const MaterialApp(
          home: SongEditorScreen.create(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songCreateTitle), findsOneWidget);
    expect(find.text(AppStrings.songEditAction), findsNothing);
  });

  testWidgets('edit mode renders with Edit song title', (tester) async {
    await _pumpScreen(tester, const Size(1440, 1200));
    expect(find.text(AppStrings.songEditAction), findsOneWidget);
    expect(find.text(AppStrings.songCreateTitle), findsNothing);
  });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd apps/lyron_app
flutter test test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: compile errors — `SongEditorScreen.edit` and `SongEditorScreen.create` do not exist yet.

- [ ] **Step 3: Refactor `SongEditorScreen` to named constructors**

In `song_editor_screen.dart`, replace the class declaration and fields:

```dart
class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen.edit({
    super.key,
    required String songId,
    required String songSlug,
    String? initialSource,
  }) : _songId = songId,
       _songSlug = songSlug,
       _initialSource = initialSource,
       _isCreating = false;

  const SongEditorScreen.create({super.key})
      : _songId = null,
        _songSlug = null,
        _initialSource = null,
        _isCreating = true;

  final String? _songId;
  final String? _songSlug;
  final String? _initialSource;
  final bool _isCreating;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}
```

- [ ] **Step 4: Update all `widget.songId/songSlug/initialSource` references inside `_SongEditorScreenState`**

In `_SongEditorScreenState`, rename every reference:
- `widget.songId` → `widget._songId`
- `widget.songSlug` → `widget._songSlug`
- `widget.initialSource` → `widget._initialSource`

Affected locations:
- `initState`: `final seedSource = widget._initialSource ?? _sourceSample;`
- `didUpdateWidget`: `final nextSource = widget._initialSource;` and `nextSource == oldWidget._initialSource`
- `_songViewLocation()`:
  ```dart
  String _songViewLocation() {
    return AppRoutes.songReader.path.replaceFirst(
      ':songSlug',
      widget._songSlug ?? '',
    );
  }
  ```
- `_saveAndReturn`: `final songId = widget._songId;`
- `build` → `_TopBar(songId: widget._songId ?? '', ...)` (will change further in Step 5)

- [ ] **Step 5: Add `title` parameter to `_TopBar` and remove unused `songId`**

In `_TopBar`, replace the `songId` field with `title`:

```dart
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onBack,
    required this.canCancel,
    required this.canSave,
    required this.onSave,
    required this.onCancel,
  });

  final String title;
  final VoidCallback onBack;
  final bool canCancel;
  final bool canSave;
  final VoidCallback onSave;
  final VoidCallback onCancel;
```

In `_TopBar.build`, replace the hardcoded `'Edit song'` text with `title`:

```dart
Text(
  title,
  style: Theme.of(context).textTheme.headlineMedium,
),
```

- [ ] **Step 6: Pass `title` to `_TopBar` in `build`**

In `_SongEditorScreenState.build`, update the `_TopBar` call:

```dart
_TopBar(
  title: widget._isCreating
      ? AppStrings.songCreateTitle
      : AppStrings.songEditAction,
  onBack: () => unawaited(_handleBack(context)),
  canCancel: true,
  canSave: _isDirty,
  onSave: () => _saveAndReturn(context),
  onCancel: () => unawaited(_cancelAndReturn(context)),
),
```

- [ ] **Step 7: Update `SongEditorSlugRouteResolver` to use `.edit()`**

In `slug_route_resolvers.dart`, change the `SongEditorScreen` instantiation:

```dart
return SongEditorScreen.edit(
  songId: song.songId,
  songSlug: song.songSlug,
  initialSource: song.source,
);
```

- [ ] **Step 8: Run tests — all should pass**

```bash
cd apps/lyron_app
flutter test test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: all pass, including the two new title tests.

- [ ] **Step 9: Commit**

```bash
cd apps/lyron_app
git add lib/src/presentation/song_editor/song_editor_screen.dart \
        lib/src/router/slug_route_resolvers.dart \
        test/presentation/song_editor/song_editor_screen_test.dart
git commit -m "feat: refactor SongEditorScreen to named constructors with create mode title"
```

---

## Task 3: Create mode save path (TDD)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Modify: `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart`

- [ ] **Step 1: Write failing test**

In `song_editor_screen_test.dart`, add the following imports at the top:

```dart
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_library_service.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/router/app_routes.dart';
```

Add this test stub helper and test at the bottom of `main()`:

```dart
  testWidgets('create mode save calls createSong and navigates to reader', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final service = _RecordingEditorSongLibraryService();

    final router = GoRouter(
      initialLocation: AppRoutes.songCreate.path,
      routes: [
        GoRoute(
          path: AppRoutes.songCreate.path,
          builder: (context, state) => const SongEditorScreen.create(),
        ),
        GoRoute(
          path: AppRoutes.songReader.path,
          builder: (context, state) {
            final slug = state.pathParameters['songSlug']!;
            return Material(child: Text('reader:$slug'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            const UnifiedSyncOverview.initial(),
          ),
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(
              userId: 'user-1',
              organizationId: 'org-1',
            ),
          ),
          songLibraryServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Edit the source to make the screen dirty, then save
    await tester.enterText(find.byType(TextField), '{title: New Creation}');
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songSaveAction));
    await tester.pumpAndSettle();

    expect(service.createCalledWith?.title, 'New Creation');
    expect(find.textContaining('reader:'), findsOneWidget);
  });
```

Add the stub service class after `main()` at the bottom of the test file:

```dart
class _RecordingEditorSongLibraryService extends Fake
    implements SongLibraryService {
  ({String title, String chordproSource})? createCalledWith;

  @override
  Future<SongMutationRecord> createSong({
    required ActiveCatalogContext context,
    required String title,
    required String chordproSource,
  }) async {
    createCalledWith = (title: title, chordproSource: chordproSource);
    return SongMutationRecord(
      id: 'new-id',
      organizationId: context.organizationId,
      slug: 'new-creation',
      title: title,
      chordproSource: chordproSource,
      version: 1,
      baseVersion: null,
      syncStatus: SongSyncStatus.pendingCreate,
    );
  }

  @override
  Future<void> updateSong({
    required ActiveCatalogContext context,
    required String songId,
    required String title,
    required String chordproSource,
  }) async {
    throw StateError('updateSong must not be called in create mode');
  }
}
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd apps/lyron_app
flutter test test/presentation/song_editor/song_editor_screen_test.dart \
  --name 'create mode save calls createSong'
```

Expected: FAIL — `_saveAndReturn` calls `updateSong` (which throws in this stub) or navigates incorrectly.

- [ ] **Step 3: Implement create-mode save path in `_saveAndReturn`**

In `_SongEditorScreenState._saveAndReturn`, split on `_isCreating`:

```dart
Future<void> _saveAndReturn(BuildContext context) async {
  final activeContext = ref.read(activeCatalogContextProvider);
  if (activeContext == null) {
    _returnToSongView(context);
    return;
  }

  final service = ref.read(songLibraryServiceProvider);
  final projection = SongEditorProjection(state: _controller.state);

  if (widget._isCreating) {
    final record = await service.createSong(
      context: activeContext,
      title: projection.summaryTitle,
      chordproSource: _controller.state.source,
    );

    if (!context.mounted) {
      return;
    }

    ref.invalidate(songLibraryListProvider);
    ref.invalidate(songMutationEntriesProvider);
    _commitChanges();
    context.replace(
      AppRoutes.songReader.path.replaceFirst(':songSlug', record.slug),
    );
    return;
  }

  final songId = widget._songId!;
  final songViewLocation = _songViewLocation();

  try {
    await service.updateSong(
      context: activeContext,
      songId: songId,
      title: projection.summaryTitle,
      chordproSource: _controller.state.source,
    );
  } on SongConflictResolutionRequiredException {
    if (!context.mounted) {
      return;
    }
    await _showConflictResolutionRequiredDialog(context);
    return;
  }

  if (!context.mounted) {
    return;
  }

  ref.invalidate(songLibraryListProvider);
  ref.invalidate(songMutationEntriesProvider);
  ref.invalidate(songLibraryReaderProvider(songId));
  _commitChanges();
  context.replace(songViewLocation);
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd apps/lyron_app
flutter test test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd apps/lyron_app
git add lib/src/presentation/song_editor/song_editor_screen.dart \
        test/presentation/song_editor/song_editor_screen_test.dart
git commit -m "feat: implement create mode save path in SongEditorScreen"
```

---

## Task 4: Create mode cancel path (TDD)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_editor/song_editor_screen.dart`
- Modify: `apps/lyron_app/test/presentation/song_editor/song_editor_screen_test.dart`

- [ ] **Step 1: Write failing tests**

Add these tests at the bottom of `main()` in `song_editor_screen_test.dart`:

```dart
  testWidgets('create mode clean cancel navigates home without confirmation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: AppRoutes.songCreate.path,
      routes: [
        GoRoute(
          path: AppRoutes.home.path,
          builder: (context, state) =>
              const Material(child: Text('song-list')),
        ),
        GoRoute(
          path: AppRoutes.songCreate.path,
          builder: (context, state) => const SongEditorScreen.create(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            const UnifiedSyncOverview.initial(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    // No discard dialog, and navigated to home (song list)
    expect(find.text(AppStrings.songEditorDiscardChangesTitle), findsNothing);
    expect(find.text('song-list'), findsOneWidget);
  });

  testWidgets('create mode dirty cancel shows discard confirmation', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 1200);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: AppRoutes.songCreate.path,
      routes: [
        GoRoute(
          path: AppRoutes.home.path,
          builder: (context, state) =>
              const Material(child: Text('song-list')),
        ),
        GoRoute(
          path: AppRoutes.songCreate.path,
          builder: (context, state) => const SongEditorScreen.create(),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            const UnifiedSyncOverview.initial(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '{title: Draft Song}');
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.songEditorDiscardChangesTitle), findsOneWidget);
  });
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
cd apps/lyron_app
flutter test test/presentation/song_editor/song_editor_screen_test.dart \
  --name 'create mode.*cancel'
```

Expected: FAIL — cancel in create mode currently calls `_returnToSongView` which builds an invalid path (empty slug).

- [ ] **Step 3: Implement create-mode cancel path**

In `_SongEditorScreenState`, update `_returnToSongView` and `_handleBack`:

```dart
String _songViewLocation() {
  return AppRoutes.songReader.path.replaceFirst(
    ':songSlug',
    widget._songSlug ?? '',
  );
}

void _returnToSongView(BuildContext context) {
  _cancelChanges();
  if (widget._isCreating) {
    // Always navigate home; context.go works even without a prior history entry
    context.go(AppRoutes.home.path);
    return;
  }
  context.replace(_songViewLocation());
}

Future<void> _handleBack(BuildContext context) async {
  if (!await _confirmDiscardChangesIfNeeded(context)) {
    return;
  }
  if (!context.mounted) {
    return;
  }
  _returnToSongView(context);
}
```

`_cancelAndReturn` is unchanged — it already delegates to `_returnToSongView` via `_confirmDiscardChangesIfNeeded`.

- [ ] **Step 4: Run all editor tests**

```bash
cd apps/lyron_app
flutter test test/presentation/song_editor/song_editor_screen_test.dart
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
cd apps/lyron_app
git add lib/src/presentation/song_editor/song_editor_screen.dart \
        test/presentation/song_editor/song_editor_screen_test.dart
git commit -m "feat: implement create mode cancel path in SongEditorScreen"
```

---

## Task 5: Wire `songCreate` route into `app_router.dart`

**Files:**
- Modify: `apps/lyron_app/lib/src/router/app_router.dart`

No new tests required — the screen behaviour is already covered by Task 2–4 tests.

- [ ] **Step 1: Add the GoRoute for `/songs/new`**

In `app_router.dart`, add the `songCreate` import (already imported via `app_routes.dart`), and add the GoRoute **before** the `songReader` route. The `routes` list in `createAppRouter` should become:

```dart
routes: [
  GoRoute(
    path: AppRoutes.bootstrap.path,
    builder: (context, state) => const BootstrapScreen(),
  ),
  GoRoute(
    path: AppRoutes.signIn.path,
    builder: (context, state) => const SignInScreen(),
  ),
  GoRoute(
    path: AppRoutes.home.path,
    builder: (context, state) => const SongListScreen(),
  ),
  GoRoute(
    path: AppRoutes.planList.path,
    builder: (context, state) => const PlanListScreen(),
  ),
  GoRoute(
    path: AppRoutes.planDetail.path,
    builder: (context, state) => PlanSlugRouteResolver(
      planSlug: state.pathParameters['planSlug']!,
    ),
  ),
  GoRoute(
    path: AppRoutes.planSessionSongReader.path,
    builder: (context, state) => PlanSessionSongSlugRouteResolver(
      planSlug: state.pathParameters['planSlug']!,
      sessionSlug: state.pathParameters['sessionSlug']!,
      songSlug: state.pathParameters['songSlug']!,
    ),
  ),
  GoRoute(
    path: AppRoutes.songCreate.path,
    builder: (context, state) => const SongEditorScreen.create(),
  ),
  GoRoute(
    path: AppRoutes.songReader.path,
    builder: (context, state) =>
        SongSlugRouteResolver(songSlug: state.pathParameters['songSlug']!),
  ),
  GoRoute(
    path: AppRoutes.songEditor.path,
    builder: (context, state) => SongEditorSlugRouteResolver(
      songSlug: state.pathParameters['songSlug']!,
    ),
  ),
],
```

Add the missing import for `SongEditorScreen` if not already present (check existing imports at top of `app_router.dart`):

```dart
import 'package:lyron_app/src/presentation/song_editor/song_editor_screen.dart';
```

- [ ] **Step 2: Verify no import errors**

```bash
cd apps/lyron_app
flutter analyze lib/src/router/app_router.dart
```

Expected: no errors.

- [ ] **Step 3: Commit**

```bash
cd apps/lyron_app
git add lib/src/router/app_router.dart
git commit -m "feat: add /songs/new route for SongEditorScreen create mode"
```

---

## Task 6: Update `SongListScreen` — replace dialog with navigation (TDD)

**Files:**
- Modify: `apps/lyron_app/lib/src/presentation/song_library/song_list_screen.dart`
- Modify: `apps/lyron_app/test/presentation/song_library/song_list_screen_test.dart`

- [ ] **Step 1: Write failing test**

In `song_list_screen_test.dart`, **replace** the existing test `'create action opens the song editor and saves locally'` with this navigation test:

```dart
  testWidgets('create action navigates to the song create screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildApp(
        songs: const [
          SongSummary(id: 'egy_ut', slug: 'egy-ut', title: 'Egy út'),
        ],
        catalogState: const CatalogSnapshotState(
          context: ActiveCatalogContext(
            userId: 'user-1',
            organizationId: 'org-1',
          ),
          connectionStatus: CatalogConnectionStatus.online,
          refreshStatus: CatalogRefreshStatus.idle,
          sessionStatus: CatalogSessionStatus.verified,
          hasCachedCatalog: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.songCreateAction));
    await tester.pumpAndSettle();

    expect(find.text('create-screen'), findsOneWidget);
    expect(find.byKey(const ValueKey('song-editor-title-field')), findsNothing);
  });
```

For this test to work, the `buildApp` router in `song_list_screen_test.dart` must include a route for `AppRoutes.songCreate.path`. In the `buildApp` helper, add the `songCreate` route before the `'/songs/:songSlug'` route:

```dart
final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const SongListScreen()),
    GoRoute(
      path: AppRoutes.planList.path,
      builder: (context, state) =>
          const Material(child: Text('plans:list')),
    ),
    GoRoute(
      path: AppRoutes.songCreate.path,
      builder: (context, state) =>
          const Material(child: Text('create-screen')),
    ),
    GoRoute(
      path: '/songs/:songSlug',
      builder: (context, state) {
        final songSlug = state.pathParameters['songSlug']!;
        return Material(child: Text('reader:$songSlug'));
      },
    ),
  ],
);
```

- [ ] **Step 2: Run test to confirm it fails**

```bash
cd apps/lyron_app
flutter test test/presentation/song_library/song_list_screen_test.dart \
  --name 'create action navigates'
```

Expected: FAIL — tapping `songCreateAction` still shows the AlertDialog.

- [ ] **Step 3: Update `_createSong` in `SongListScreen`**

In `song_list_screen.dart`, replace `_createSong`:

```dart
Future<void> _createSong(BuildContext context, WidgetRef ref) async {
  final activeContext = ref.read(activeCatalogContextProvider);
  if (activeContext == null) {
    return;
  }
  context.push(AppRoutes.songCreate.path);
}
```

Add the missing `go_router` import if not already present:

```dart
import 'package:go_router/go_router.dart';
```

And add the `app_routes.dart` import:

```dart
import 'package:lyron_app/src/router/app_routes.dart';
```

- [ ] **Step 4: Delete `_SongEditorDraft`, `_SongEditorDialog`, `_SongEditorDialogState`**

Remove the following classes entirely from `song_list_screen.dart`:

- `class _SongEditorDraft { ... }` (lines ~615–620)
- `class _SongEditorDialog extends StatefulWidget { ... }` (lines ~622–688)
- `class _SongEditorDialogState extends State<_SongEditorDialog> { ... }` (included in the above range)

- [ ] **Step 5: Run full test suite**

```bash
cd apps/lyron_app
flutter test test/presentation/song_library/song_list_screen_test.dart
```

Expected: all pass, including the renamed create action test.

- [ ] **Step 6: Run all tests**

```bash
cd apps/lyron_app
flutter test
```

Expected: all pass. Fix any compile errors from removed classes before committing.

- [ ] **Step 7: Commit**

```bash
cd apps/lyron_app
git add lib/src/presentation/song_library/song_list_screen.dart \
        test/presentation/song_library/song_list_screen_test.dart
git commit -m "feat: replace song creation dialog with full-screen route navigation

Removes _SongEditorDialog and _SongEditorDraft. Song creation now
navigates to /songs/new which renders SongEditorScreen in create mode."
```

---

## Task 7: Full suite verification and branch cleanup

- [ ] **Step 1: Run complete test suite**

```bash
cd apps/lyron_app
flutter test
```

Expected: all pass, no skipped tests.

- [ ] **Step 2: Run static analysis**

```bash
cd apps/lyron_app
flutter analyze
```

Expected: no errors or warnings introduced by this change.

- [ ] **Step 3: Invoke finishing-a-development-branch skill**

Use `superpowers:finishing-a-development-branch` to decide on merge/PR approach.
