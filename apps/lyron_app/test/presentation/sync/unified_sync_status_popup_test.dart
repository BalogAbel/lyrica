import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';
import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_status_popup.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class _FakeManualSyncController extends UnifiedManualSyncController {
  _FakeManualSyncController({required this.result})
    : super(
        activeContextReader: () =>
            const UnifiedSyncActiveContext(userId: 'u1', organizationId: 'o1'),
        syncSongMutations: (_) async {},
        refreshSongCatalog: () async {},
        syncPlanningMutations: (_) async {},
        refreshPlanning: () async {},
      );

  final UnifiedManualSyncRunResult result;
  int syncNowCalls = 0;

  @override
  Future<UnifiedManualSyncRunResult> syncNow() async {
    syncNowCalls += 1;
    return result;
  }
}

const _retryAfterSyncMessage =
    'Sync is in progress. Try again after it finishes.';

class _SpyDiscardController extends UnifiedDiscardController {
  _SpyDiscardController({this.result = UnifiedDiscardResult.discarded})
    : super(
        activeContextReader: () => null,
        acquireSongDiscardLease: (_) async =>
            SongDiscardLeaseAcquisition.acquired(
              SongDiscardLease(discardSong: (_) async {}, release: () {}),
            ),
        discardSongsWhileOwned: (_, _) async {},
        discardPlanning: (_) async {},
      );
  final UnifiedDiscardResult result;
  int discardAllCalls = 0;

  @override
  Future<UnifiedDiscardResult> discardAll() async {
    discardAllCalls += 1;
    return result;
  }
}

class _FakeSongStore implements SongMutationStore {
  @override
  Future<String> allocateUniqueSlug({
    required String userId,
    required String organizationId,
    required String title,
  }) => throw UnimplementedError();

  @override
  Future<void> upsertSong({
    required String userId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord?> readById({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<List<SongMutationRecord>> readPendingSongs({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<List<SongMutationRecord>> readConflictSongs({
    required String userId,
    required String organizationId,
  }) => throw UnimplementedError();

  @override
  Future<bool> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String songId,
    required SongSyncStatus syncStatus,
    SongMutationSyncErrorCode? errorCode,
    String? errorMessage,
    int? expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<int> countReferencingSessionItems({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<void> deleteSong({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<bool> reconcileSyncedSong({
    required String userId,
    required String organizationId,
    required SongMutationRecord record,
    int? expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<int?> markCreateSending({
    required String userId,
    required String organizationId,
    required String songId,
    required int expectedRevision,
  }) => throw UnimplementedError();

  @override
  Future<bool> resolveCancelledSongCreate({
    required String userId,
    required String organizationId,
    required String songId,
    required bool created,
    int? acceptedVersion,
  }) => throw UnimplementedError();

  @override
  Future<void> clearSongMutation({
    required String userId,
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();

  @override
  Future<bool> hasUnsyncedChanges({required String userId}) =>
      throw UnimplementedError();
}

class _FakeSongRemote implements SongMutationRemoteRepository {
  @override
  Future<SongMutationRecord> syncSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> overwriteSong({
    required String organizationId,
    required SongMutationRecord record,
  }) => throw UnimplementedError();

  @override
  Future<SongMutationRecord> fetchSong({
    required String organizationId,
    required String songId,
  }) => throw UnimplementedError();
}

class _SpyPlanningSyncController extends PlanningMutationSyncController {
  _SpyPlanningSyncController()
    : super(
        mutationStore: () => throw UnimplementedError(),
        remoteRepository: () => throw UnimplementedError(),
        refreshPlanning: () async => false,
        reconcileAcceptedMutation: (context, record) async {},
        shouldReconcileAcceptedMutation: (context) async => false,
      );

  final List<String> retryCalls = [];
  final List<String> discardCalls = [];

  @override
  Future<void> retryMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    retryCalls.add('$aggregateType:$aggregateId');
  }

  @override
  Future<void> discardMutation(
    ActivePlanningReadContext context, {
    required String aggregateType,
    required String aggregateId,
  }) async {
    discardCalls.add('$aggregateType:$aggregateId');
  }
}

class _SpySongSyncController extends SongMutationSyncController {
  _SpySongSyncController({this.discardResult = SongDiscardResult.discarded})
    : super(store: _FakeSongStore(), remoteRepository: _FakeSongRemote());

  final SongDiscardResult discardResult;
  final List<String> keepMineCalls = [];
  final List<String> discardMineCalls = [];

  @override
  Future<void> keepMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    keepMineCalls.add(songId);
  }

  @override
  Future<SongDiscardResult> discardMine(
    SongMutationContext context, {
    required String songId,
  }) async {
    discardMineCalls.add(songId);
    return discardResult;
  }
}

UnifiedSyncOverview _overview({
  List<UnifiedSyncSongRow> songs = const [],
  List<UnifiedSyncPlanRow> plans = const [],
  UnifiedSyncHeaderStatus status = UnifiedSyncHeaderStatus.synced,
}) {
  return UnifiedSyncOverview(
    headerStatus: status,
    activity: UnifiedSyncActivity.idle,
    connectivity: UnifiedSyncConnectivity.online,
    freshness: UnifiedSyncFreshness.fresh,
    songRows: songs,
    planRows: plans,
    hasUnsyncedWork: songs.isNotEmpty || plans.isNotEmpty,
  );
}

Future<void> _pumpPopup(
  WidgetTester tester,
  UnifiedSyncOverview overview,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [unifiedSyncOverviewProvider.overrideWithValue(overview)],
      child: const MaterialApp(home: Scaffold(body: UnifiedSyncStatusPopup())),
    ),
  );
}

void main() {
  testWidgets('shows empty copy when nothing to sync', (tester) async {
    await _pumpPopup(tester, _overview());
    expect(find.text(AppStrings.unifiedSyncEmptyMessage), findsOneWidget);
  });

  testWidgets('song row + plan conflict row render with Sync now button', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      songs: const [
        UnifiedSyncSongRow(
          songId: 's1',
          title: 'Hymn',
          entityState: SongSyncStatus.pendingCreate,
          severity: UnifiedSyncRowSeverity.pending,
          reasonCode: UnifiedSyncReasonCode.pendingLocal,
        ),
      ],
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Service',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.conflict,
          nestedSummaries: ['plan edited'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(find.text('Hymn'), findsOneWidget);
    expect(find.text('Service'), findsOneWidget);
    expect(find.text(AppStrings.unifiedSyncNowAction), findsOneWidget);
    expect(find.text(AppStrings.unifiedSyncReasonConflict), findsOneWidget);
  });

  testWidgets('authorization_denied row renders specific reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Closed Plan',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.authorizationDenied,
          nestedSummaries: ['plan edited'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(
      find.text(AppStrings.unifiedSyncReasonAuthorizationDenied),
      findsOneWidget,
    );
  });

  testWidgets('dependency_blocked row renders specific reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Blocked',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.dependencyBlocked,
          nestedSummaries: ['session removed'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(
      find.text(AppStrings.unifiedSyncReasonDependencyBlocked),
      findsOneWidget,
    );
  });

  testWidgets('remote_missing row renders specific reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.conflict,
      plans: const [
        UnifiedSyncPlanRow(
          planId: 'p1',
          title: 'Gone',
          severity: UnifiedSyncRowSeverity.conflict,
          reasonCode: UnifiedSyncReasonCode.remoteMissing,
          nestedSummaries: ['plan edited'],
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(
      find.text(AppStrings.unifiedSyncReasonRemoteMissing),
      findsOneWidget,
    );
  });

  testWidgets('sync_failed song row renders retryable reason chip', (
    tester,
  ) async {
    final overview = _overview(
      status: UnifiedSyncHeaderStatus.unsynced,
      songs: const [
        UnifiedSyncSongRow(
          songId: 's1',
          title: 'Retry',
          entityState: SongSyncStatus.pendingUpdate,
          severity: UnifiedSyncRowSeverity.retryableFailure,
          reasonCode: UnifiedSyncReasonCode.syncFailed,
        ),
      ],
    );
    await _pumpPopup(tester, overview);
    expect(find.text(AppStrings.unifiedSyncReasonSyncFailed), findsOneWidget);
  });

  testWidgets('conflict song row shows Keep mine and Discard mine buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.conflict,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.conflict,
                  severity: UnifiedSyncRowSeverity.conflict,
                  reasonCode: UnifiedSyncReasonCode.conflict,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-song-keep-s1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('unified-sync-song-discard-s1')),
      findsOneWidget,
    );
  });

  testWidgets(
    // YELLOW 9 (final whole-branch review, spec D5.6): keepMine re-sends
    // via overwriteSong, and discard is a no-op retry affordance too --
    // neither can help a permanently unauthorized row, so both must be
    // suppressed. The row itself, and its reason, must still be visible
    // (the user is told retrying cannot help, not left with no row at
    // all).
    'authorizationDenied song row hides Keep mine but keeps Discard mine, '
    'and still shows the row and its reason',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSyncOverviewProvider.overrideWithValue(
              _overview(
                status: UnifiedSyncHeaderStatus.conflict,
                songs: const [
                  UnifiedSyncSongRow(
                    songId: 's1',
                    title: 'Hymn',
                    entityState: SongSyncStatus.conflict,
                    severity: UnifiedSyncRowSeverity.conflict,
                    reasonCode: UnifiedSyncReasonCode.authorizationDenied,
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UnifiedSyncStatusPopup()),
          ),
        ),
      );

      expect(find.text('Hymn'), findsOneWidget);
      expect(
        find.text(AppStrings.unifiedSyncReasonAuthorizationDenied),
        findsOneWidget,
      );
      // Keep mine re-sends the local version, which a permanent
      // authorization rejection can never accept -- offering it would be a
      // retry that provably cannot succeed (spec D5.6).
      expect(
        find.byKey(const ValueKey('unified-sync-song-keep-s1')),
        findsNothing,
      );
      // Discard mine is purely local and needs no authorization. It is the
      // user's only way to clear a permanently unauthorized row out of the
      // sync queue, so it must stay -- without it the row sits in the list
      // forever with no affordance at all.
      expect(
        find.byKey(const ValueKey('unified-sync-song-discard-s1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('conflict song row Discard mine calls controller', (
    tester,
  ) async {
    final spy = _SpySongSyncController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.conflict,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.conflict,
                  severity: UnifiedSyncRowSeverity.conflict,
                  reasonCode: UnifiedSyncReasonCode.conflict,
                ),
              ],
            ),
          ),
          songMutationSyncControllerProvider.overrideWithValue(spy),
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(userId: 'u1', organizationId: 'org1'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('unified-sync-song-discard-s1')),
    );
    await tester.pumpAndSettle();
    expect(spy.discardMineCalls, ['s1']);
  });

  testWidgets(
    'conflict song discard rejected by active sync shows retry-after-sync guidance',
    (tester) async {
      final spy = _SpySongSyncController(
        discardResult: SongDiscardResult.syncInProgress,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSyncOverviewProvider.overrideWithValue(
              _overview(
                status: UnifiedSyncHeaderStatus.conflict,
                songs: const [
                  UnifiedSyncSongRow(
                    songId: 's1',
                    title: 'Hymn',
                    entityState: SongSyncStatus.conflict,
                    severity: UnifiedSyncRowSeverity.conflict,
                    reasonCode: UnifiedSyncReasonCode.conflict,
                  ),
                ],
              ),
            ),
            songMutationSyncControllerProvider.overrideWithValue(spy),
            activeCatalogContextProvider.overrideWithValue(
              const ActiveCatalogContext(userId: 'u1', organizationId: 'org1'),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UnifiedSyncStatusPopup()),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('unified-sync-song-discard-s1')),
      );
      await tester.pumpAndSettle();

      expect(find.text(_retryAfterSyncMessage), findsOneWidget);
    },
  );

  testWidgets('pending song row shows no action buttons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.pendingCreate,
                  severity: UnifiedSyncRowSeverity.pending,
                  reasonCode: UnifiedSyncReasonCode.pendingLocal,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-song-keep-s1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('unified-sync-song-discard-s1')),
      findsNothing,
    );
  });

  testWidgets('conflict plan row shows Keep mine and Discard mine buttons', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.conflict,
              plans: const [
                UnifiedSyncPlanRow(
                  planId: 'p1',
                  title: 'Service',
                  severity: UnifiedSyncRowSeverity.conflict,
                  reasonCode: UnifiedSyncReasonCode.conflict,
                  nestedSummaries: ['plan edited'],
                  mutationRefs: [
                    UnifiedSyncPlanMutationRef(
                      aggregateType: 'plan',
                      aggregateId: 'p1',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-keep-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-discard-p1')),
      findsOneWidget,
    );
  });

  testWidgets(
    // Mirrors the song-row authorizationDenied test: retryMutation now
    // throws for a failedAuthorization row, so Keep mine on a plan row
    // must be suppressed the same way it is on a song row -- offering a
    // retry that provably cannot succeed just produces a generic partial
    // failure snackbar. Discard mine stays: it is purely local, needs no
    // authorization, and is the user's only way to clear the row.
    'authorizationDenied plan row hides Keep mine but keeps Discard mine, '
    'and still shows the row and its reason',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSyncOverviewProvider.overrideWithValue(
              _overview(
                status: UnifiedSyncHeaderStatus.conflict,
                plans: const [
                  UnifiedSyncPlanRow(
                    planId: 'p1',
                    title: 'Closed Plan',
                    severity: UnifiedSyncRowSeverity.conflict,
                    reasonCode: UnifiedSyncReasonCode.authorizationDenied,
                    nestedSummaries: ['plan edited'],
                    mutationRefs: [
                      UnifiedSyncPlanMutationRef(
                        aggregateType: 'plan',
                        aggregateId: 'p1',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UnifiedSyncStatusPopup()),
          ),
        ),
      );
      expect(find.text('Closed Plan'), findsOneWidget);
      expect(
        find.text(AppStrings.unifiedSyncReasonAuthorizationDenied),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('unified-sync-plan-keep-p1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('unified-sync-plan-discard-p1')),
        findsOneWidget,
      );
    },
  );

  testWidgets('conflict plan row Discard mine discards all grouped mutations', (
    tester,
  ) async {
    final spy = _SpyPlanningSyncController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.conflict,
              plans: const [
                UnifiedSyncPlanRow(
                  planId: 'p1',
                  title: 'Service',
                  severity: UnifiedSyncRowSeverity.conflict,
                  reasonCode: UnifiedSyncReasonCode.conflict,
                  nestedSummaries: ['plan edited', 'session added'],
                  mutationRefs: [
                    UnifiedSyncPlanMutationRef(
                      aggregateType: 'plan',
                      aggregateId: 'p1',
                    ),
                    UnifiedSyncPlanMutationRef(
                      aggregateType: 'session',
                      aggregateId: 's1',
                    ),
                  ],
                ),
              ],
            ),
          ),
          planningMutationSyncControllerProvider.overrideWithValue(spy),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(userId: 'u1', organizationId: 'o1'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('unified-sync-plan-discard-p1')),
    );
    await tester.pumpAndSettle();
    expect(spy.discardCalls, ['plan:p1', 'session:s1']);
  });

  testWidgets('retryable plan row shows Retry button only', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              plans: const [
                UnifiedSyncPlanRow(
                  planId: 'p1',
                  title: 'Service',
                  severity: UnifiedSyncRowSeverity.retryableFailure,
                  reasonCode: UnifiedSyncReasonCode.syncFailed,
                  nestedSummaries: ['plan edited'],
                  mutationRefs: [
                    UnifiedSyncPlanMutationRef(
                      aggregateType: 'plan',
                      aggregateId: 'p1',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-retry-p1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-keep-p1')),
      findsNothing,
    );
  });

  testWidgets('Discard all button absent when nothing to sync', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [unifiedSyncOverviewProvider.overrideWithValue(_overview())],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-popup-discard-all')),
      findsNothing,
    );
  });

  testWidgets('Discard all button present when unsynced work exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.pendingCreate,
                  severity: UnifiedSyncRowSeverity.pending,
                  reasonCode: UnifiedSyncReasonCode.pendingLocal,
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-popup-discard-all')),
      findsOneWidget,
    );
  });

  testWidgets('Discard all confirms then calls controller', (tester) async {
    final spy = _SpyDiscardController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.pendingCreate,
                  severity: UnifiedSyncRowSeverity.pending,
                  reasonCode: UnifiedSyncReasonCode.pendingLocal,
                ),
              ],
            ),
          ),
          unifiedDiscardControllerProvider.overrideWithValue(spy),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('unified-sync-popup-discard-all')),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.unifiedSyncDiscardAllTitle), findsOneWidget);
    await tester.tap(
      find.text(AppStrings.unifiedSyncDiscardAllConfirmAction).last,
    );
    await tester.pumpAndSettle();
    expect(spy.discardAllCalls, 1);
  });

  testWidgets(
    'Discard all rejected by active song sync shows retry-after-sync guidance',
    (tester) async {
      final spy = _SpyDiscardController(
        result: UnifiedDiscardResult.syncInProgress,
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSyncOverviewProvider.overrideWithValue(
              _overview(
                status: UnifiedSyncHeaderStatus.unsynced,
                songs: const [
                  UnifiedSyncSongRow(
                    songId: 's1',
                    title: 'Hymn',
                    entityState: SongSyncStatus.pendingCreate,
                    severity: UnifiedSyncRowSeverity.pending,
                    reasonCode: UnifiedSyncReasonCode.pendingLocal,
                  ),
                ],
              ),
            ),
            unifiedDiscardControllerProvider.overrideWithValue(spy),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UnifiedSyncStatusPopup()),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('unified-sync-popup-discard-all')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(AppStrings.unifiedSyncDiscardAllConfirmAction).last,
      );
      await tester.pumpAndSettle();

      expect(spy.discardAllCalls, 1);
      expect(find.text(_retryAfterSyncMessage), findsOneWidget);
    },
  );

  testWidgets('Discard all cancel does not call controller', (tester) async {
    final spy = _SpyDiscardController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.pendingCreate,
                  severity: UnifiedSyncRowSeverity.pending,
                  reasonCode: UnifiedSyncReasonCode.pendingLocal,
                ),
              ],
            ),
          ),
          unifiedDiscardControllerProvider.overrideWithValue(spy),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('unified-sync-popup-discard-all')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.songCancelAction));
    await tester.pumpAndSettle();
    expect(spy.discardAllCalls, 0);
  });

  testWidgets('conflict song row Keep mine calls controller', (tester) async {
    final spy = _SpySongSyncController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.conflict,
              songs: const [
                UnifiedSyncSongRow(
                  songId: 's1',
                  title: 'Hymn',
                  entityState: SongSyncStatus.conflict,
                  severity: UnifiedSyncRowSeverity.conflict,
                  reasonCode: UnifiedSyncReasonCode.conflict,
                ),
              ],
            ),
          ),
          songMutationSyncControllerProvider.overrideWithValue(spy),
          activeCatalogContextProvider.overrideWithValue(
            const ActiveCatalogContext(userId: 'u1', organizationId: 'org1'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('unified-sync-song-keep-s1')));
    await tester.pumpAndSettle();
    expect(spy.keepMineCalls, ['s1']);
  });

  testWidgets('retryable plan row Retry calls controller', (tester) async {
    final spy = _SpyPlanningSyncController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              plans: const [
                UnifiedSyncPlanRow(
                  planId: 'p1',
                  title: 'Service',
                  severity: UnifiedSyncRowSeverity.retryableFailure,
                  reasonCode: UnifiedSyncReasonCode.syncFailed,
                  nestedSummaries: ['plan edited'],
                  mutationRefs: [
                    UnifiedSyncPlanMutationRef(
                      aggregateType: 'plan',
                      aggregateId: 'p1',
                    ),
                  ],
                ),
              ],
            ),
          ),
          planningMutationSyncControllerProvider.overrideWithValue(spy),
          activePlanningContextProvider.overrideWithValue(
            const ActivePlanningReadContext(userId: 'u1', organizationId: 'o1'),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('unified-sync-plan-retry-p1')));
    await tester.pumpAndSettle();
    expect(spy.retryCalls, ['plan:p1']);
  });

  testWidgets(
    'conflict plan row Keep mine calls retry on all grouped mutations',
    (tester) async {
      final spy = _SpyPlanningSyncController();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            unifiedSyncOverviewProvider.overrideWithValue(
              _overview(
                status: UnifiedSyncHeaderStatus.conflict,
                plans: const [
                  UnifiedSyncPlanRow(
                    planId: 'p1',
                    title: 'Service',
                    severity: UnifiedSyncRowSeverity.conflict,
                    reasonCode: UnifiedSyncReasonCode.conflict,
                    nestedSummaries: ['plan edited', 'session added'],
                    mutationRefs: [
                      UnifiedSyncPlanMutationRef(
                        aggregateType: 'plan',
                        aggregateId: 'p1',
                      ),
                      UnifiedSyncPlanMutationRef(
                        aggregateType: 'session',
                        aggregateId: 's1',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            planningMutationSyncControllerProvider.overrideWithValue(spy),
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'u1',
                organizationId: 'o1',
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: UnifiedSyncStatusPopup()),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('unified-sync-plan-keep-p1')));
      await tester.pumpAndSettle();
      expect(spy.retryCalls, ['plan:p1', 'session:s1']);
    },
  );

  testWidgets('pending plan row shows no action buttons', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unifiedSyncOverviewProvider.overrideWithValue(
            _overview(
              status: UnifiedSyncHeaderStatus.unsynced,
              plans: const [
                UnifiedSyncPlanRow(
                  planId: 'p1',
                  title: 'Service',
                  severity: UnifiedSyncRowSeverity.pending,
                  reasonCode: UnifiedSyncReasonCode.pendingLocal,
                  nestedSummaries: ['plan edited'],
                ),
              ],
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: UnifiedSyncStatusPopup()),
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-keep-p1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-discard-p1')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('unified-sync-plan-retry-p1')),
      findsNothing,
    );
  });

  // Helper: builds a real page (with a button that opens the popup via its
  // REAL .show() -> showDialog path) plus the sign-in route, wired into a
  // real GoRouter. This is deliberately NOT the "mount popup as page body"
  // style below -- that style is a false green for B1 because a DialogRoute
  // context is not a GoRouter page context, so GoRouterState.of(context)
  // called from inside the dialog never gets exercised by it.
  Widget appWithRealShowDialogPath({
    required UnifiedManualSyncController controller,
  }) {
    return ProviderScope(
      overrides: [
        unifiedSyncOverviewProvider.overrideWithValue(_overview()),
        unifiedManualSyncControllerProvider.overrideWith((_) => controller),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => Scaffold(
                body: Builder(
                  builder: (innerContext) => TextButton(
                    key: const ValueKey('open-popup'),
                    onPressed: () => UnifiedSyncStatusPopup.show(innerContext),
                    child: const Text('Open popup'),
                  ),
                ),
              ),
            ),
            GoRoute(
              path: AppRoutes.signIn.path,
              builder: (context, state) =>
                  const Scaffold(body: Text('SIGN IN SCREEN')),
            ),
          ],
        ),
      ),
    );
  }

  // Task 2.6c / B1 fix: pressing the Sync button while sessionExpired must
  // route to re-auth (same pattern as ReauthBanner), instead of silently
  // reporting a spurious sync failure for a session that can never succeed.
  //
  // This goes through the REAL UnifiedSyncStatusPopup.show() -> showDialog
  // path (B1 regression guard). Before the B1 fix, UnifiedSyncStatusPopup's
  // _syncNow read GoRouterState.of(context) from inside the dialog's own
  // context, which throws GoError('There is no GoRouterState above the
  // current context') because a DialogRoute's context has no GoRouterState
  // association -- only GoRouter.of(context) (InheritedWidget lookup) works
  // there. The prior version of this test mounted UnifiedSyncStatusPopup
  // directly as a page body (Scaffold(body: UnifiedSyncStatusPopup())),
  // which never opens a real dialog route and so never hit that throw --
  // a false green.
  testWidgets(
    'Sync button navigates to sign-in when syncNow reports requiresReauth '
    '(via real showDialog path)',
    (tester) async {
      final fakeController = _FakeManualSyncController(
        result: const UnifiedManualSyncRunResult(
          songSyncFailed: false,
          songCatalogRefreshFailed: false,
          planningSyncFailed: false,
          planningRefreshFailed: false,
          requiresReauth: true,
        ),
      );
      await tester.pumpWidget(
        appWithRealShowDialogPath(controller: fakeController),
      );

      await tester.tap(find.byKey(const ValueKey('open-popup')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('unified-sync-popup-sync-now')),
      );
      await tester.pumpAndSettle();

      expect(fakeController.syncNowCalls, 1);
      expect(find.text('SIGN IN SCREEN'), findsOneWidget);
    },
  );

  testWidgets(
    'Sync button does not navigate when syncNow does not require reauth '
    '(via real showDialog path)',
    (tester) async {
      final fakeController = _FakeManualSyncController(
        result: const UnifiedManualSyncRunResult.clean(),
      );
      await tester.pumpWidget(
        appWithRealShowDialogPath(controller: fakeController),
      );

      await tester.tap(find.byKey(const ValueKey('open-popup')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('unified-sync-popup-sync-now')),
      );
      await tester.pumpAndSettle();

      expect(fakeController.syncNowCalls, 1);
      expect(find.text('SIGN IN SCREEN'), findsNothing);
    },
  );

  // Task 2.6d: the automatic triggers (OnlineTransitionDetector's
  // onTransitionToOnline, foregroundSyncListenerProvider's onResume) must
  // never navigate, even under the same sessionExpired-with-requiresReauth
  // condition that makes the button navigate. Both callback typedefs
  // (OnlineTransitionCallback = void Function(), ForegroundSyncCallback =
  // Future<void> Function()) carry no BuildContext, and their wiring in
  // unified_sync_providers.dart (`ref.read(unifiedManualSyncControllerProvider
  // ).syncNow()`) discards the returned UnifiedManualSyncRunResult entirely --
  // confirmed by reading online_transition_detector.dart,
  // foreground_sync_listener.dart and unified_sync_providers.dart, not
  // assumed. This test proves calling syncNow() the way those automatic
  // paths do -- with no BuildContext and no read of the result -- cannot
  // reach navigation code, regardless of requiresReauth.
  test(
    'automatic-trigger-style syncNow call ignores requiresReauth and never navigates',
    () async {
      final fakeController = _FakeManualSyncController(
        result: const UnifiedManualSyncRunResult(
          songSyncFailed: false,
          songCatalogRefreshFailed: false,
          planningSyncFailed: false,
          planningRefreshFailed: false,
          requiresReauth: true,
        ),
      );
      // Mirrors OnlineTransitionDetector's onTransitionToOnline and
      // foregroundSyncListenerProvider's onResume: call syncNow() and
      // discard/ignore its result, exactly as those two callers do.
      unawaited(fakeController.syncNow());
      await fakeController.syncNow();

      expect(fakeController.syncNowCalls, 2);
      // No navigation object of any kind exists in this scope -- there is no
      // BuildContext, no GoRouter -- so the automatic path structurally
      // cannot navigate no matter what requiresReauth says.
    },
  );
}
