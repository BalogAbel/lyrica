import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/catalog_connection_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_refresh_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_session_status.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/plan_summary.dart';
import 'package:lyron_app/src/domain/planning/planning_repository.dart';
import 'package:lyron_app/src/domain/planning/session_item_summary.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/presentation/planning/plan_detail_screen.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';
import 'package:lyron_app/src/presentation/song_library/song_list_screen.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'keeps browse query across song navigation and adds a searched picker song into plan detail',
    (tester) async {
      late GoRouter router;
      final visibleSongs = <SongSummary>[
        const SongSummary(id: 'song-1', slug: 'alpha', title: 'Alpha'),
        const SongSummary(id: 'song-2', slug: 'beta', title: 'Beta'),
        const SongSummary(id: 'song-3', slug: 'egy-ut', title: 'Egy út'),
      ];
      final mutationEntries = <SongMutationRecord>[
        const SongMutationRecord(
          id: 'song-2',
          organizationId: 'org-1',
          slug: 'beta',
          title: 'Beta',
          chordproSource: '{title: Beta}',
          version: 2,
          baseVersion: 1,
          syncStatus: SongSyncStatus.pendingUpdate,
        ),
      ];
      var planDetail = _planDetailFixture();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            songLibraryListProvider.overrideWith((ref) async => visibleSongs),
            songMutationEntriesProvider.overrideWith(
              (ref) async => mutationEntries,
            ),
            planningPlanDetailProvider(
              'plan-1',
            ).overrideWith((ref) async => planDetail),
            planningWriteServiceProvider.overrideWithValue(
              _IntegrationPlanningWriteService(
                planDetailReader: () => planDetail,
                planDetailWriter: (value) => planDetail = value,
                visibleSongs: visibleSongs,
              ),
            ),
            catalogSnapshotStateProvider.overrideWithValue(
              const CatalogSnapshotState(
                context: null,
                connectionStatus: CatalogConnectionStatus.online,
                refreshStatus: CatalogRefreshStatus.idle,
                sessionStatus: CatalogSessionStatus.verified,
                hasCachedCatalog: true,
              ),
            ),
            activePlanningContextProvider.overrideWithValue(
              const ActivePlanningReadContext(
                userId: 'user-1',
                organizationId: 'org-1',
              ),
            ),
          ],
          child: Builder(
            builder: (context) {
              router = GoRouter(
                initialLocation: '/',
                routes: [
                  GoRoute(
                    path: '/',
                    builder: (context, state) => const SongListScreen(),
                  ),
                  GoRoute(
                    path: '/songs/:songSlug',
                    builder: (context, state) {
                      final songSlug = state.pathParameters['songSlug']!;
                      return Material(
                        child: Scaffold(
                          appBar: AppBar(title: Text('reader:$songSlug')),
                          body: const Center(child: Text('reader')),
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: AppRoutes.planDetail.path,
                    builder: (context, state) =>
                        const PlanDetailScreen(planId: 'plan-1'),
                  ),
                ],
              );
              return MaterialApp.router(routerConfig: router);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('song-list-search-field')),
        'egy',
      );
      await tester.pumpAndSettle();

      router.push('/songs/egy-ut');
      await tester.pumpAndSettle();
      expect(find.text('reader:egy-ut'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(SongListScreen), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.byKey(const ValueKey('song-list-search-field')),
            )
            .controller
            ?.text,
        'egy',
      );
      await tester.enterText(
        find.byKey(const ValueKey('song-list-search-field')),
        '',
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('song-list-filter-control')),
          matching: find.text(AppStrings.songLibraryFilterPendingSyncLabel),
        ),
      );
      await tester.pumpAndSettle();

      Finder browseRowText(String text) => find.descendant(
        of: find.byKey(const ValueKey('song-library-results-list')),
        matching: find.text(text),
      );

      expect(browseRowText('Beta'), findsOneWidget);
      expect(browseRowText('Alpha'), findsNothing);

      router.go(AppRoutes.planDetail.path.replaceFirst(':planSlug', 'team'));
      await tester.pumpAndSettle();

      expect(find.byType(PlanDetailScreen), findsOneWidget);
      expect(find.text('Team Rehearsal'), findsOneWidget);

      await tester.tap(find.text(AppStrings.sessionItemAddSongAction).first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('session-song-option-song-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-song-option-song-2')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-song-option-song-3')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('session-song-option-song-2')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlanDetailScreen), findsOneWidget);
      expect(find.textContaining('Beta'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-song-picker-search-field')),
        findsNothing,
      );
    },
  );
}

PlanDetail _planDetailFixture() {
  return PlanDetail(
    plan: PlanSummary(
      id: 'plan-1',
      slug: 'team-rehearsal',
      name: 'Team Rehearsal',
      description: 'Integration fixture',
      scheduledFor: null,
      updatedAt: DateTime(2026, 4, 19, 12),
    ),
    sessions: const [
      SessionSummary(
        id: 'session-1',
        slug: 'warm-up',
        name: 'Warm-Up',
        position: 10,
        items: [],
      ),
    ],
  );
}

class _IntegrationPlanningWriteService extends PlanningWriteService {
  _IntegrationPlanningWriteService({
    required this.planDetailReader,
    required this.planDetailWriter,
    required this.visibleSongs,
  }) : super(
         const _NoopPlanningRepository(),
         mutationStore: const _NoopPlanningMutationStore(),
         activeContextReader: () async => const ActivePlanningReadContext(
           userId: 'user-1',
           organizationId: 'org-1',
         ),
         listVisibleSongs: ({required userId, required organizationId}) async =>
             visibleSongs,
       );

  final PlanDetail Function() planDetailReader;
  final void Function(PlanDetail) planDetailWriter;
  final List<SongSummary> visibleSongs;

  @override
  Future<void> addSongSessionItem({
    required PlanningWriteContext context,
    required SessionItemCreateSongDraft draft,
  }) async {
    final detail = planDetailReader();
    final song = visibleSongs.firstWhere(
      (candidate) => candidate.id == draft.songId,
    );
    final updatedSessions = detail.sessions
        .map((session) {
          if (session.id != draft.sessionId) {
            return session;
          }

          final nextPosition = session.items.isEmpty
              ? 10
              : session.items.last.position + 10;
          return SessionSummary(
            id: session.id,
            slug: session.slug,
            name: session.name,
            position: session.position,
            version: session.version,
            items: [
              ...session.items,
              SessionItemSummary(
                id: 'session-item-${draft.songId}',
                position: nextPosition,
                song: song,
              ),
            ],
          );
        })
        .toList(growable: false);

    planDetailWriter(PlanDetail(plan: detail.plan, sessions: updatedSessions));
  }
}

class _NoopPlanningRepository implements PlanningRepository {
  const _NoopPlanningRepository();

  @override
  Future<List<PlanSummary>> listPlans() async => const [];

  @override
  Future<PlanDetail> getPlanDetail(String planId) async =>
      throw UnimplementedError();

  @override
  Future<PlanSummary?> getPlanSummaryBySlug(String planSlug) async => null;

  @override
  Future<PlanDetail?> getPlanDetailBySlug(String planSlug) async => null;
}

class _NoopPlanningMutationStore implements PlanningMutationStore {
  const _NoopPlanningMutationStore();

  @override
  Future<void> clearMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {}

  @override
  Future<String> allocatePlanSlug({
    required String userId,
    required String organizationId,
    required String name,
  }) async => 'plan';

  @override
  Future<String> allocateSessionSlug({
    required String userId,
    required String organizationId,
    required String planId,
    required String name,
  }) async => 'session';

  @override
  Future<List<PlanningMutationRecord>> readAllMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<PlanningMutationRecord?> readMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async => null;

  @override
  Future<List<PlanningMutationRecord>> readPendingMutations({
    required String userId,
    required String organizationId,
  }) async => const [];

  @override
  Future<void> recordPlanCreate({
    required PlanningMutationContext context,
    required PlanningPlanCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordPlanEdit({
    required PlanningMutationContext context,
    required PlanningPlanEditMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionCreate({
    required PlanningMutationContext context,
    required PlanningSessionCreateMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionDelete({
    required PlanningMutationContext context,
    required PlanningSessionDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemCreateSong({
    required PlanningMutationContext context,
    required PlanningSessionItemCreateSongMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemDelete({
    required PlanningMutationContext context,
    required PlanningSessionItemDeleteMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionItemReorder({
    required PlanningMutationContext context,
    required PlanningSessionItemReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionReorder({
    required PlanningMutationContext context,
    required PlanningSessionReorderMutationDraft draft,
  }) async {}

  @override
  Future<void> recordSessionRename({
    required PlanningMutationContext context,
    required PlanningSessionRenameMutationDraft draft,
  }) async {}

  @override
  Future<void> retryMutation({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
  }) async {}

  @override
  Future<void> saveSyncAttemptResult({
    required String userId,
    required String organizationId,
    required String aggregateType,
    required String aggregateId,
    required PlanningMutationSyncStatus syncStatus,
    PlanningMutationSyncErrorCode? errorCode,
    String? errorMessage,
  }) async {}

  @override
  Future<bool> hasUnsyncedMutations({required String userId}) async => false;
}
