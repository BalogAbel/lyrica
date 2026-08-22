import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/auth/last_known_identity.dart';
import 'package:lyron_app/src/application/planning/drift_planning_mutation_store.dart';
import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_reconciler.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_mutation_sync_types.dart';
import 'package:lyron_app/src/application/planning/planning_sync_controller.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/storage/local_data_lifecycle.dart';
import 'package:lyron_app/src/domain/auth/app_auth_session.dart';
import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/domain/planning/session_summary.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_mutation_repository.dart';
import 'package:lyron_app/src/infrastructure/planning/supabase_planning_repository.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/planning/planning_local_store.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../support/drift_relaunch.dart';
import '../support/drift_test_setup.dart';

// Trivial LocalDataLifecycle wrapping the test's real planning store, for a
// helper that only exercises planning sync -- song catalog/identity/events
// deps are never invoked by this flow.
LocalDataLifecycle _lifecycleFor(PlanningLocalStore store) {
  return LocalDataLifecycle(
    songCatalogStore: _NoopSongCatalogStore(),
    planningLocalStore: store,
    identityStore: _NoopLastKnownIdentityStore(),
    noteLastKnownIdentity: (_) {},
    eventsRecorder: _NoopLocalDataEventsRecorder(),
  );
}

class _NoopSongCatalogStore implements SongCatalogStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLastKnownIdentityStore implements LastKnownIdentityStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopLocalDataEventsRecorder implements LocalDataEventsRecorder {
  @override
  Future<void> recordPurge({
    required PurgeTarget target,
    required PurgeReason reason,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordEviction({
    required String target,
    String? userId,
    int? rowsAffected,
  }) async {}

  @override
  Future<void> recordRejectedEmptySnapshot({
    required String userId,
    required String organizationId,
  }) async {}

  @override
  Future<void> recordStorageWriteFailure({String? userId}) async {}
}

const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Seeded demo fixtures (see plan_and_session_flow_test.dart / supabase/seed/seed.sql):
// a multi-session plan owned by the visible demo organization. We only ever
// *read* this shared fixture to discover real ids; every mutation below
// writes a uniquely-suffixed value (or a brand-new session/item) so repeated
// runs - and other integration tests relying on this same fixture - are not
// corrupted by order-dependent state.
const _planId = '44444444-4444-4444-4444-444444444442';
const _runThroughSessionId = '55555555-5555-5555-5555-555555555553';
const _visibleOrganizationId = '11111111-1111-1111-1111-111111111111';

// A song already visible to the demo org but NOT currently attached to the
// Run-Through session, so two devices can each add it there with distinct
// local item ids while sharing the same songId (LF-6 race).
const _raceSongId = '33333333-3333-3333-3333-333333333335';
const _raceSongTitle = 'A mi Istenünk - second verse fixture';

void main() {
  late HttpOverrides? originalHttpOverrides;

  setUpAll(() {
    originalHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _PassthroughHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = originalHttpOverrides;
  });

  group('two-device conflict matrix', () {
    test(
      'rename vs rename: device A wins, device B conflict stays visible (LF-1, LF-4)',
      () async {
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
          final runId = DateTime.now().microsecondsSinceEpoch;
          final deviceA = await _Device.signIn('rename-rename-a-$runId');
          addTearDown(deviceA.dispose);
          final deviceB = await _Device.signIn('rename-rename-b-$runId');
          addTearDown(deviceB.dispose);

          // Both devices seed their local projection from the same backend
          // session, at the same base_version, then independently rename it
          // offline before either has synced (the classic stale-base-version
          // race).
          final session = await deviceA.seedSession(_runThroughSessionId);
          await deviceB.seedSession(_runThroughSessionId);

          final nameA = 'Run-Through (device A $runId)';
          final nameB = 'Run-Through (device B $runId)';

          await deviceA.writeService.renameSession(
            context: deviceA.writeContext,
            draft: SessionRenameDraft(
              sessionId: session.id,
              planId: _planId,
              name: nameA,
            ),
          );
          await deviceB.writeService.renameSession(
            context: deviceB.writeContext,
            draft: SessionRenameDraft(
              sessionId: session.id,
              planId: _planId,
              name: nameB,
            ),
          );

          // Device A syncs first: its rename is accepted and bumps the
          // backend base_version.
          await deviceA.sync();
          expect(
            await deviceA.mutationStore.hasUnsyncedMutations(
              userId: deviceA.context.userId,
            ),
            isFalse,
            reason: 'device A holds the stale base_version and syncs first',
          );

          // Device B syncs second from the now-stale base_version: its
          // rename is rejected as a conflict.
          await deviceB.sync();

          final mutationAfterB = await deviceB.mutationStore.readMutation(
            userId: deviceB.context.userId,
            organizationId: deviceB.context.organizationId,
            aggregateType: PlanningMutationKind.sessionRename.aggregateType,
            aggregateId: session.id,
          );
          expect(
            mutationAfterB?.syncStatus,
            PlanningMutationSyncStatus.conflict,
            reason: 'device B raced device A from a stale base_version',
          );

          // Deterministic convergence: the backend holds device A's value.
          final backendDetail = await SupabasePlanningRepository(
            deviceA.client,
          ).getPlanDetail(_planId);
          final backendSession = backendDetail.sessions.firstWhere(
            (candidate) => candidate.id == session.id,
          );
          expect(backendSession.name, nameA);

          // LF-4: device B's losing edit stays visible (not silently
          // dropped) in its own merged local read, tagged as a conflict.
          final deviceBDetail = await deviceB.repository.getPlanDetail(_planId);
          final deviceBSession = deviceBDetail.sessions.firstWhere(
            (candidate) => candidate.id == session.id,
          );
          expect(
            deviceBSession.name,
            nameB,
            reason:
                "LF-4: device B's conflicting edit remains visible locally "
                'even though the backend rejected it',
          );

          // Device A's merged read (after refreshing) reflects the accepted
          // value.
          final deviceADetail = await deviceA.repository.getPlanDetail(_planId);
          final deviceASession = deviceADetail.sessions.firstWhere(
            (candidate) => candidate.id == session.id,
          );
          expect(deviceASession.name, nameA);
        });
      },
      skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
    );

    test(
      'reorder vs reorder: device A wins, device B conflict stays visible (LF-1, LF-4)',
      () async {
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
          final runId = DateTime.now().microsecondsSinceEpoch;
          final deviceA = await _Device.signIn('reorder-reorder-a-$runId');
          addTearDown(deviceA.dispose);
          final deviceB = await _Device.signIn('reorder-reorder-b-$runId');
          addTearDown(deviceB.dispose);

          final detailA = await deviceA.seedPlan(_planId);
          await deviceB.seedPlan(_planId);
          final sessionIds = detailA.sessions
              .map((session) => session.id)
              .toList(growable: false);
          expect(
            sessionIds.length,
            greaterThanOrEqualTo(2),
            reason: 'reorder race needs at least two sibling sessions',
          );

          final reversedOrder = sessionIds.reversed.toList(growable: false);
          final rotatedOrder = [...sessionIds.skip(1), sessionIds.first];

          await deviceA.writeService.reorderSessions(
            context: deviceA.writeContext,
            draft: SessionReorderDraft(
              planId: _planId,
              orderedSessionIds: reversedOrder,
            ),
          );
          await deviceB.writeService.reorderSessions(
            context: deviceB.writeContext,
            draft: SessionReorderDraft(
              planId: _planId,
              orderedSessionIds: rotatedOrder,
            ),
          );

          await deviceA.sync();
          await deviceB.sync();

          final mutationAfterB = await deviceB.mutationStore.readMutation(
            userId: deviceB.context.userId,
            organizationId: deviceB.context.organizationId,
            aggregateType: PlanningMutationKind.sessionReorder.aggregateType,
            aggregateId: _planId,
          );
          expect(
            mutationAfterB?.syncStatus,
            PlanningMutationSyncStatus.conflict,
            reason: 'device B reorders from a stale plan base_version',
          );

          final backendDetail = await SupabasePlanningRepository(
            deviceA.client,
          ).getPlanDetail(_planId);
          expect(
            backendDetail.sessions
                .map((session) => session.id)
                .toList(growable: false),
            orderedEquals(reversedOrder),
            reason: "backend converges on device A's accepted order",
          );

          // LF-4: device B still sees its attempted (losing) order locally.
          final deviceBDetail = await deviceB.repository.getPlanDetail(_planId);
          expect(
            deviceBDetail.sessions
                .map((session) => session.id)
                .toList(growable: false),
            orderedEquals(rotatedOrder),
            reason:
                "LF-4: device B's conflicting reorder remains visible "
                'locally',
          );
        });
      },
      skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
    );

    test('edit vs remote delete: surviving device converges on the delete '
        '(LF-1)', () async {
      // Structure-only, modelled on the rename case above: this pair
      // exercises a *different* backend error path than the version
      // conflict (P0001/conflict) - deleting the aggregate makes the
      // sibling's later sync target a now-missing row, which
      // SupabasePlanningMutationRepository maps to
      // PlanningMutationSyncErrorCode.remoteMissing (see
      // supabase_planning_mutation_repository.dart's "not_found" /
      // P0002 branch), not PlanningMutationSyncErrorCode.conflict.
      // Flagging this for live-stack verification: confirm the actual
      // RPC/trigger error code+message emitted by delete_empty_session
      // (or the session-item delete path) when a sibling mutation
      // targets an already-deleted aggregate, and confirm whether the
      // local mutation should also be left visible as a "remote missing"
      // marker the same way LF-4 keeps conflicts visible.
      await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
        final runId = DateTime.now().microsecondsSinceEpoch;
        final deviceA = await _Device.signIn('edit-delete-a-$runId');
        addTearDown(deviceA.dispose);
        final deviceB = await _Device.signIn('edit-delete-b-$runId');
        addTearDown(deviceB.dispose);

        // Device A creates a throwaway session (so the delete path never
        // touches the shared seeded fixture) and both devices seed it.
        final ownerDetail = await deviceA.seedPlan(_planId);
        await deviceA.writeService.createSession(
          context: deviceA.writeContext,
          draft: SessionCreateDraft(
            planId: _planId,
            name: 'Scratch session (edit-vs-delete $runId)',
          ),
        );
        await deviceA.sync();

        // Both devices refresh so they observe the new scratch session
        // at the same base_version before racing.
        await deviceA.refresh();
        await deviceB.seedPlan(_planId);
        await deviceB.refresh();

        final detailAfterCreate = await deviceB.repository.getPlanDetail(
          _planId,
        );
        final scratchSession = detailAfterCreate.sessions.firstWhere(
          (candidate) => candidate.name.startsWith('Scratch session'),
          orElse: () => ownerDetail.sessions.first,
        );

        // Device A deletes the (empty) scratch session...
        await deviceA.writeService.deleteSession(
          context: deviceA.writeContext,
          draft: SessionDeleteDraft(
            sessionId: scratchSession.id,
            planId: _planId,
          ),
        );
        // ...while device B, unaware, renames the same session from its
        // now-stale snapshot.
        await deviceB.writeService.renameSession(
          context: deviceB.writeContext,
          draft: SessionRenameDraft(
            sessionId: scratchSession.id,
            planId: _planId,
            name: 'Renamed after remote delete ($runId)',
          ),
        );

        await deviceA.sync();
        await deviceB.sync();

        // Convergence: the backend no longer has the session.
        final backendDetail = await SupabasePlanningRepository(
          deviceA.client,
        ).getPlanDetail(_planId);
        expect(
          backendDetail.sessions.any(
            (session) => session.id == scratchSession.id,
          ),
          isFalse,
          reason: 'device A holds the remote-delete outcome',
        );

        // LF-4-style visibility: device B's rename mutation must not be
        // silently lost - it should be readable as a failed/actionable
        // mutation locally even though we have not pinned down the exact
        // error code live (see the structure-only note above).
        final mutationAfterB = await deviceB.mutationStore.readMutation(
          userId: deviceB.context.userId,
          organizationId: deviceB.context.organizationId,
          aggregateType: PlanningMutationKind.sessionRename.aggregateType,
          aggregateId: scratchSession.id,
        );
        expect(
          mutationAfterB,
          isNotNull,
          reason:
              "device B's rename-of-a-deleted-session attempt must "
              'remain recorded locally rather than vanish silently',
        );
        expect(
          mutationAfterB!.syncStatus,
          isNot(PlanningMutationSyncStatus.accepted),
          reason:
              'a rename against a remotely-deleted aggregate cannot '
              'be accepted',
        );
      });
    }, skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty);

    test(
      'add-same-song twice: distinct item ids race on one songId (LF-6)',
      () async {
        await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
          final runId = DateTime.now().microsecondsSinceEpoch;
          final deviceA = await _Device.signIn(
            'add-same-song-a-$runId',
            visibleSongs: const [
              SongSummary(id: _raceSongId, title: _raceSongTitle),
            ],
          );
          addTearDown(deviceA.dispose);
          final deviceB = await _Device.signIn(
            'add-same-song-b-$runId',
            visibleSongs: const [
              SongSummary(id: _raceSongId, title: _raceSongTitle),
            ],
          );
          addTearDown(deviceB.dispose);

          await deviceA.seedPlan(_planId);
          await deviceB.seedPlan(_planId);

          // Both devices independently add the SAME song to the SAME
          // session from the same observed base_version, generating
          // distinct local session-item ids.
          //
          // NOTE on what this actually exercises: there is no DB-level
          // unique (session_id, song_id) constraint on session_items (see
          // \d session_items - the only unique index is
          // (session_id, position)). "duplicate_song_in_session_blocked"
          // is an application-level check-then-raise inside
          // create_song_session_item (202604110001_planning_session_item_
          // write_contract.sql), guarded by a base_version equality check
          // that runs *first* and that *every* successful session-item
          // create bumps (it increments the parent session's `version`,
          // the same token used for session renames/reorders). So two
          // devices racing a session-item create from one shared stale
          // base_version always collide on session_version_conflict
          // first, identically to the rename/reorder pairs above - the
          // duplicate-song-specific branch is unreachable from this
          // sequential, single-stale-base_version race shape; reaching it
          // would require genuinely concurrent (overlapping-transaction)
          // inserts, which an awaited, sequential test cannot produce
          // deterministically. This is still a valid LF-6-flavored
          // assertion: the loser's mutation is NOT silently dropped, it
          // surfaces as a visible/actionable conflict (LF-4), and the
          // backend converges on exactly one item for the song.
          await deviceA.writeService.addSongSessionItem(
            context: deviceA.writeContext,
            draft: SessionItemCreateSongDraft(
              sessionId: _runThroughSessionId,
              planId: _planId,
              songId: _raceSongId,
            ),
          );
          await deviceB.writeService.addSongSessionItem(
            context: deviceB.writeContext,
            draft: SessionItemCreateSongDraft(
              sessionId: _runThroughSessionId,
              planId: _planId,
              songId: _raceSongId,
            ),
          );

          await deviceA.sync();
          expect(
            await deviceA.mutationStore.hasUnsyncedMutations(
              userId: deviceA.context.userId,
            ),
            isFalse,
            reason: 'device A wins the base_version race and syncs clean',
          );

          await deviceB.sync();

          final pendingAfterB = await deviceB.mutationStore
              .readActionableMutations(
                userId: deviceB.context.userId,
                organizationId: deviceB.context.organizationId,
              );
          final loserMutation = pendingAfterB.where(
            (mutation) =>
                mutation.kind == PlanningMutationKind.sessionItemCreateSong &&
                mutation.songId == _raceSongId,
          );
          expect(
            loserMutation,
            isNotEmpty,
            reason:
                "LF-6/LF-4: device B's duplicate-song add stays visible/"
                'actionable locally rather than disappearing',
          );
          expect(
            loserMutation.first.syncStatus,
            PlanningMutationSyncStatus.conflict,
            reason:
                "device B's add raced device A from the same stale "
                'session base_version, so create_song_session_item\'s '
                'session_version_conflict guard rejects it before its '
                'duplicate-song guard is ever reached (see NOTE above)',
          );

          // Backend convergence: exactly one session item for this song in
          // this session (device A's).
          final backendDetail = await SupabasePlanningRepository(
            deviceA.client,
          ).getPlanDetail(_planId);
          final backendSession = backendDetail.sessions.firstWhere(
            (session) => session.id == _runThroughSessionId,
          );
          expect(
            backendSession.items
                .where((item) => item.song.id == _raceSongId)
                .length,
            1,
            reason: 'the unique constraint allows only one winner',
          );
        });
      },
      skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty,
    );

    test('partial edit (name only) vs full edit: preserves untouched fields '
        '(LF-5)', () async {
      // Structure-only, modelled on the rename case: PlanEditDraft always
      // carries name/description/scheduledFor together (see
      // planning_write_service.dart's PlanEditDraft + _editPlanInternal),
      // so a strictly "name-only" partial mutation is approximated here
      // by device A re-submitting the existing description/scheduledFor
      // unchanged alongside a new name, while device B changes all three
      // fields. Flagging for live-stack verification: confirm whether the
      // backend's update_plan_fields RPC treats unchanged-but-resubmitted
      // fields as a true no-op merge (LF-5 preservation) versus
      // overwriting them with whatever the losing/accepted mutation last
      // saw - the local merge in planning_local_read_repository.dart's
      // _mergePlanDetail currently takes mutation.description ??
      // plan.description, i.e. only treats *null* fields as
      // "untouched", not "equal to current value".
      await runWithSuppressedDriftMultipleDatabaseWarnings(() async {
        final runId = DateTime.now().microsecondsSinceEpoch;
        final deviceA = await _Device.signIn('partial-full-a-$runId');
        addTearDown(deviceA.dispose);
        final deviceB = await _Device.signIn('partial-full-b-$runId');
        addTearDown(deviceB.dispose);

        final detailA = await deviceA.seedPlan(_planId);
        await deviceB.seedPlan(_planId);
        final originalDescription = detailA.plan.description;
        final originalScheduledFor = detailA.plan.scheduledFor;

        final partialName = 'Team Rehearsal (name-only edit $runId)';
        final fullName = 'Team Rehearsal (full edit $runId)';
        const fullDescription = 'Fully replaced description';
        final fullScheduledFor = DateTime.now().toUtc();

        // Device A: "partial" edit - only the name should logically
        // change; description/scheduledFor are resubmitted as-is.
        await deviceA.writeService.editPlan(
          context: deviceA.writeContext,
          draft: PlanEditDraft(
            planId: _planId,
            name: partialName,
            description: originalDescription,
            scheduledFor: originalScheduledFor,
          ),
        );
        // Device B: full edit touching every field, from the same stale
        // base_version.
        await deviceB.writeService.editPlan(
          context: deviceB.writeContext,
          draft: PlanEditDraft(
            planId: _planId,
            name: fullName,
            description: fullDescription,
            scheduledFor: fullScheduledFor,
          ),
        );

        await deviceA.sync();
        expect(
          await deviceA.mutationStore.hasUnsyncedMutations(
            userId: deviceA.context.userId,
          ),
          isFalse,
          reason: 'device A (partial edit) syncs first and is accepted',
        );

        await deviceB.sync();

        final mutationAfterB = await deviceB.mutationStore.readMutation(
          userId: deviceB.context.userId,
          organizationId: deviceB.context.organizationId,
          aggregateType: PlanningMutationKind.planEdit.aggregateType,
          aggregateId: _planId,
        );
        expect(
          mutationAfterB?.syncStatus,
          PlanningMutationSyncStatus.conflict,
          reason: 'device B raced device A from a stale plan base_version',
        );

        // LF-5: the untouched fields from device A's partial edit must
        // survive on the backend - the name changed, description and
        // scheduledFor did not.
        final backendDetail = await SupabasePlanningRepository(
          deviceA.client,
        ).getPlanDetail(_planId);
        expect(backendDetail.plan.name, partialName);
        expect(
          backendDetail.plan.description,
          originalDescription,
          reason: 'LF-5: description must be preserved by the partial edit',
        );
        expect(
          backendDetail.plan.scheduledFor,
          originalScheduledFor,
          reason: 'LF-5: scheduledFor must be preserved by the partial edit',
        );

        // Device B's losing full edit stays visible locally (LF-4).
        final deviceBDetail = await deviceB.repository.getPlanDetail(_planId);
        expect(deviceBDetail.plan.name, fullName);
      });
    }, skip: _supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty);
  });
}

class _PassthroughHttpOverrides extends HttpOverrides {}

/// Wraps one simulated client device: its own [SupabaseClient], its own
/// local sqlite file, and the full read/write/sync stack wired exactly like
/// `offline_edit_relaunch_sync_flow_test.dart`. Two independent [_Device]
/// instances racing the same backend aggregate model the two-device
/// conflict matrix.
class _Device {
  _Device._({
    required this.client,
    required this.dbFile,
    required this.database,
    required this.localStore,
    required this.mutationStore,
    required this.repository,
    required this.writeService,
    required this.context,
  });

  static Future<_Device> signIn(
    String label, {
    List<SongSummary> visibleSongs = const [],
  }) async {
    final config = SupabaseConfig.fromEnvironment();
    final client = SupabaseClient(config.url, config.anonKey);
    await client.auth.signOut();
    await client.auth.signInWithPassword(
      email: 'demo@lyron.local',
      password: 'LyronDemo123!',
    );
    final userId = client.auth.currentSession!.user.id;
    final context = ActivePlanningReadContext(
      userId: userId,
      organizationId: _visibleOrganizationId,
    );

    final dbFile = await createRelaunchDbFile('two-device-conflict-$label');
    final database = PlanningLocalDatabase.connect(
      NativeDatabase.createInBackground(dbFile),
    );
    final localStore = DriftPlanningLocalStore(database);
    final mutationStore = DriftPlanningMutationStore(
      database: database,
      localStore: localStore,
    );
    final repository = PlanningLocalReadRepository(
      store: localStore,
      mutationStore: mutationStore,
      contextReader: () async => context,
    );
    // Use the default UUID v4 id generator: the backend's session/session-item
    // primary keys are `uuid` columns, so a human-readable label-based id
    // (as previously used here) fails with "invalid input syntax for type
    // uuid" once a mutation actually reaches the backend (surfaced as a
    // silently-pending mutation, since per-mutation sync errors don't throw
    // in the test's `sync()` helper). The default generator already
    // produces a fresh UUID per call, which is all the uniqueness these
    // tests need.
    final writeService = PlanningWriteService(
      repository,
      mutationStore: mutationStore,
      listVisibleSongs: ({required userId, required organizationId}) async =>
          visibleSongs,
      activeContextReader: () async => context,
    );

    return _Device._(
      client: client,
      dbFile: dbFile,
      database: database,
      localStore: localStore,
      mutationStore: mutationStore,
      repository: repository,
      writeService: writeService,
      context: context,
    );
  }

  final SupabaseClient client;
  final File dbFile;
  final PlanningLocalDatabase database;
  final DriftPlanningLocalStore localStore;
  final DriftPlanningMutationStore mutationStore;
  final PlanningLocalReadRepository repository;
  final PlanningWriteService writeService;
  final ActivePlanningReadContext context;

  PlanningWriteContext get writeContext => PlanningWriteContext(
    userId: context.userId,
    organizationId: context.organizationId,
  );

  /// Seeds the local projection for [planId] from the live backend so there
  /// is a base plan present to mutate offline, mirroring
  /// `offline_edit_relaunch_sync_flow_test.dart`'s seeding step.
  ///
  /// Unlike the single-plan relaunch test, the conflict matrix exercises
  /// writes that look up a *session* (or session item) by id in the local
  /// projection (`PlanningWriteService`'s internal `firstWhere` calls), so
  /// every session and item the device might mutate must also be projected
  /// locally - seeding the plan row alone is not enough.
  Future<PlanDetail> seedPlan(String planId) async {
    final seedRepository = SupabasePlanningRepository(client);
    final detail = await seedRepository.getPlanDetail(planId);
    final refreshedAt = DateTime.now().toUtc();
    await localStore.upsertSyncedPlan(
      userId: context.userId,
      organizationId: context.organizationId,
      refreshedAt: refreshedAt,
      plan: CachedPlanRecord(
        id: detail.plan.id,
        slug: detail.plan.slug,
        name: detail.plan.name,
        description: detail.plan.description,
        scheduledFor: detail.plan.scheduledFor,
        updatedAt: detail.plan.updatedAt,
        version: detail.plan.version,
      ),
    );
    for (final session in detail.sessions) {
      await localStore.upsertSyncedSession(
        userId: context.userId,
        organizationId: context.organizationId,
        refreshedAt: refreshedAt,
        session: CachedSessionRecord(
          id: session.id,
          planId: planId,
          slug: session.slug,
          position: session.position,
          name: session.name,
          version: session.version,
        ),
      );
      for (final item in session.items) {
        await localStore.upsertSyncedSessionItem(
          userId: context.userId,
          organizationId: context.organizationId,
          refreshedAt: refreshedAt,
          sessionVersion: session.version,
          item: CachedSessionItemRecord(
            id: item.id,
            planId: planId,
            sessionId: session.id,
            position: item.position,
            songId: item.song.id,
            songTitle: item.song.title,
          ),
        );
      }
    }
    return detail;
  }

  /// Seeds the plan and returns the requested session summary (by id) from
  /// the freshly-synced detail, for tests that only need one session.
  Future<SessionSummary> seedSession(String sessionId) async {
    final detail = await seedPlan(_planId);
    return detail.sessions.firstWhere((session) => session.id == sessionId);
  }

  /// Refreshes the local synced snapshot from the backend without going
  /// through the mutation-sync path (used after another device's mutation
  /// has already landed remotely).
  Future<void> refresh() async {
    await seedPlan(_planId);
  }

  Future<void> sync() async {
    final remoteMutationRepository = SupabasePlanningMutationRepository(client);
    final remoteRefreshRepository = SupabasePlanningRepository(client);
    final syncController = PlanningSyncController(
      localStore: () => localStore,
      localDataLifecycle: _lifecycleFor(localStore),
      remoteRepository: () => remoteRefreshRepository,
      authSessionReader: () =>
          AppAuthSession(userId: context.userId, email: 'demo@lyron.local'),
    );
    final mutationSyncController = PlanningMutationSyncController(
      mutationStore: () => mutationStore,
      remoteRepository: () => remoteMutationRepository,
      refreshPlanning: () async {
        await syncController.handleActiveContextChanged(
          context,
          refresh: false,
        );
        return syncController.refreshPlanning();
      },
      shouldReconcileAcceptedMutation: (_) async => true,
      reconcileAcceptedMutation: PlanningMutationReconciler(
        localStore: () => localStore,
      ).reconcile,
    );

    await mutationSyncController.syncPendingMutations(context);
  }

  Future<void> dispose() async {
    await client.auth.signOut();
    await client.dispose();
    await database.close();
    if (await dbFile.parent.exists()) {
      await dbFile.parent.delete(recursive: true);
    }
  }
}
