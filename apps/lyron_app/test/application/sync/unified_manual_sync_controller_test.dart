import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';

UnifiedSyncActiveContext _ctx() =>
    const UnifiedSyncActiveContext(userId: 'u', organizationId: 'o');

void main() {
  group('UnifiedManualSyncController.syncNow', () {
    test('runs all four steps in order with active context', () async {
      final calls = <String>[];
      final controller = UnifiedManualSyncController(
        activeContextReader: _ctx,
        syncSongMutations: (c) async {
          calls.add('song:${c.organizationId}');
        },
        refreshSongCatalog: () async => calls.add('catalog'),
        syncPlanningMutations: (c) async {
          calls.add('planning:${c.organizationId}');
        },
        refreshPlanning: () async => calls.add('planRefresh'),
      );

      final result = await controller.syncNow();
      expect(calls, ['song:o', 'catalog', 'planning:o', 'planRefresh']);
      expect(result.anyFailure, isFalse);
    });

    test('coalesces concurrent calls into single in-flight + one queued rerun',
        () async {
      var runCount = 0;
      final completer = <Completer<void>>[];
      final controller = UnifiedManualSyncController(
        activeContextReader: _ctx,
        syncSongMutations: (_) async {
          runCount++;
          final c = Completer<void>();
          completer.add(c);
          await c.future;
        },
        refreshSongCatalog: () async {},
        syncPlanningMutations: (_) async {},
        refreshPlanning: () async {},
      );

      final first = controller.syncNow();
      // Allow the first run to start before queuing.
      await Future<void>.delayed(Duration.zero);
      final second = controller.syncNow();
      final third = controller.syncNow();

      completer[0].complete();
      await Future<void>.delayed(Duration.zero);
      // Queued rerun started; complete it.
      completer[1].complete();

      await Future.wait([first, second, third]);
      expect(runCount, 2);
    });

    test('catalog refresh failure does not skip planning sync', () async {
      final calls = <String>[];
      final controller = UnifiedManualSyncController(
        activeContextReader: _ctx,
        syncSongMutations: (_) async => calls.add('song'),
        refreshSongCatalog: () async {
          calls.add('catalog-fail');
          throw StateError('boom');
        },
        syncPlanningMutations: (_) async => calls.add('planning'),
        refreshPlanning: () async => calls.add('planRefresh'),
      );

      final result = await controller.syncNow();
      expect(calls, ['song', 'catalog-fail', 'planning', 'planRefresh']);
      expect(result.songCatalogRefreshFailed, isTrue);
      expect(result.planningSyncFailed, isFalse);
    });

    test('planning refresh failure surfaces in result without throwing',
        () async {
      final controller = UnifiedManualSyncController(
        activeContextReader: _ctx,
        syncSongMutations: (_) async {},
        refreshSongCatalog: () async {},
        syncPlanningMutations: (_) async {},
        refreshPlanning: () async => throw StateError('refresh failed'),
      );
      final result = await controller.syncNow();
      expect(result.planningRefreshFailed, isTrue);
      expect(result.anyFailure, isTrue);
    });

    test('skips run when no active context exists', () async {
      var ran = false;
      final controller = UnifiedManualSyncController(
        activeContextReader: () => null,
        syncSongMutations: (_) async => ran = true,
        refreshSongCatalog: () async => ran = true,
        syncPlanningMutations: (_) async => ran = true,
        refreshPlanning: () async => ran = true,
      );
      await controller.syncNow();
      expect(ran, isFalse);
    });
  });
}
