import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_sync_state.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';
import 'package:lyron_app/src/application/song_library/catalog_snapshot_state.dart';
import 'package:lyron_app/src/application/sync/sync_freshness_reader.dart';
import 'package:lyron_app/src/domain/song/song_source.dart';
import 'package:lyron_app/src/domain/song/song_summary.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_store.dart';
import 'package:lyron_app/src/presentation/sync/unified_sync_providers.dart';

import '../../support/drift_test_setup.dart';

void main() {
  suppressDriftMultipleDatabaseWarnings();

  late SongCatalogDatabase songs;
  late PlanningLocalDatabase plans;

  setUp(() async {
    songs = SongCatalogDatabase.inMemory();
    plans = PlanningLocalDatabase.inMemory();
    final store = DriftSongCatalogStore(songs);
    for (final entry in {
      'user-1': (DateTime.utc(2026, 10, 1, 8), DateTime.utc(2026, 10, 2, 9)),
      'user-2': (DateTime.utc(2026, 9, 1, 8), DateTime.utc(2026, 9, 2, 9)),
    }.entries) {
      await store.replaceActiveSnapshot(
        userId: entry.key,
        organizationId: 'org-1',
        summaries: const [SongSummary(id: 'song-1', title: 'Song')],
        sources: const [SongSource(id: 'song-1', source: '{title: Song}')],
        refreshedAt: entry.value.$1,
      );
      await plans
          .into(plans.planningProjectionOwners)
          .insert(
            PlanningProjectionOwnersCompanion.insert(
              userId: entry.key,
              organizationId: 'org-1',
              snapshotVersion: 1,
              refreshedAt: entry.value.$2,
            ),
          );
    }
  });

  tearDown(() async {
    await songs.close();
    await plans.close();
  });

  SyncFreshness? current(ProviderContainer container) =>
      container.read(syncFreshnessProvider);

  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  ProviderContainer containerFor(
    ActiveCatalogContext? context, {
    SyncFreshnessReader? reader,
    StateProvider<ActiveCatalogContext?>? mutable,
  }) {
    final container = ProviderContainer(
      overrides: [
        catalogSnapshotStateProvider.overrideWithValue(
          const CatalogSnapshotState.initial(),
        ),
        planningSyncStateProvider.overrideWithValue(
          const PlanningSyncState.initial(),
        ),
        if (mutable != null)
          activeCatalogContextProvider.overrideWith((ref) => ref.watch(mutable))
        else
          activeCatalogContextProvider.overrideWithValue(context),
        syncFreshnessReaderProvider.overrideWithValue(
          reader ??
              SyncFreshnessReader(
                songCatalogDatabase: songs,
                planningLocalDatabase: plans,
              ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(syncFreshnessProvider, (_, _) {});
    return container;
  }

  test('yields the active user\'s refresh times, never another user\'s '
      '(SG7)', () async {
    final container = containerFor(
      const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
    );
    await settle();

    final freshness = current(container);

    expect(freshness?.songsRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 1, 8));
    expect(freshness?.plansRefreshedAt?.toUtc(), DateTime.utc(2026, 10, 2, 9));
  });

  test('yields null without an active context (SG7)', () async {
    final container = containerFor(null);
    await settle();

    expect(current(container), isNull);
  });

  for (final (name, from, to) in [
    (
      'org switch',
      const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-2'),
    ),
    (
      'user switch',
      const ActiveCatalogContext(userId: 'user-1', organizationId: 'org-1'),
      const ActiveCatalogContext(userId: 'user-2', organizationId: 'org-1'),
    ),
  ]) {
    test('hides the previous context\'s times while the new context\'s read '
        'is pending ($name, SG7)', () async {
      final gate = Completer<void>();
      final reader = _GatedReader(songs, plans, gate.future, to);
      final mutable = StateProvider<ActiveCatalogContext?>((_) => from);
      final container = containerFor(null, reader: reader, mutable: mutable);
      await settle();
      expect(current(container)?.songsRefreshedAt, isNotNull);

      container.read(mutable.notifier).state = to;
      await settle();

      expect(current(container), isNull);

      gate.complete();
      await settle();

      expect(current(container), isNotNull);
    });
  }
}

class _GatedReader extends SyncFreshnessReader {
  _GatedReader(
    SongCatalogDatabase songs,
    PlanningLocalDatabase plans,
    this._gate,
    this._gatedContext,
  ) : super(songCatalogDatabase: songs, planningLocalDatabase: plans);

  final Future<void> _gate;
  final ActiveCatalogContext _gatedContext;

  @override
  Future<SyncFreshness> read({
    required String userId,
    required String organizationId,
  }) async {
    if (userId == _gatedContext.userId &&
        organizationId == _gatedContext.organizationId) {
      await _gate;
    }
    return super.read(userId: userId, organizationId: organizationId);
  }
}
