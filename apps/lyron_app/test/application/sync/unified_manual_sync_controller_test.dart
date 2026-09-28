import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/unified_manual_sync_controller.dart';
import 'package:lyron_app/src/domain/auth/app_auth_status.dart';

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

    test(
      'coalesces concurrent calls into single in-flight + one queued rerun',
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
      },
    );

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

    test(
      'planning refresh failure surfaces in result without throwing',
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
      },
    );

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

    test(
      'sessionExpired with a preserved context skips all four steps and '
      'reports requiresReauth without failures (Task 2.6a)',
      () async {
        var callCount = 0;
        final controller = UnifiedManualSyncController(
          activeContextReader: _ctx,
          authStatusReader: () => AppAuthStatus.sessionExpired,
          syncSongMutations: (_) async => callCount++,
          refreshSongCatalog: () async => callCount++,
          syncPlanningMutations: (_) async => callCount++,
          refreshPlanning: () async => callCount++,
        );

        final result = await controller.syncNow();

        expect(callCount, 0);
        expect(result.requiresReauth, isTrue);
        expect(result.songSyncFailed, isFalse);
        expect(result.songCatalogRefreshFailed, isFalse);
        expect(result.planningSyncFailed, isFalse);
        expect(result.planningRefreshFailed, isFalse);
        expect(result.anyFailure, isFalse);
      },
    );

    test(
      'sessionExpired with null context still reports requiresReauth, not '
      'clean (I1)',
      () async {
        var callCount = 0;
        final controller = UnifiedManualSyncController(
          activeContextReader: () => null,
          authStatusReader: () => AppAuthStatus.sessionExpired,
          syncSongMutations: (_) async => callCount++,
          refreshSongCatalog: () async => callCount++,
          syncPlanningMutations: (_) async => callCount++,
          refreshPlanning: () async => callCount++,
        );

        final result = await controller.syncNow();

        expect(callCount, 0);
        expect(result.requiresReauth, isTrue);
        expect(result.songSyncFailed, isFalse);
        expect(result.songCatalogRefreshFailed, isFalse);
        expect(result.planningSyncFailed, isFalse);
        expect(result.planningRefreshFailed, isFalse);
        expect(result.anyFailure, isFalse);
      },
    );

    test(
      'non-sessionExpired status with null context stays clean, not '
      'requiresReauth (I1 regression, other direction)',
      () async {
        var ran = false;
        final controller = UnifiedManualSyncController(
          activeContextReader: () => null,
          authStatusReader: () => AppAuthStatus.signedIn,
          syncSongMutations: (_) async => ran = true,
          refreshSongCatalog: () async => ran = true,
          syncPlanningMutations: (_) async => ran = true,
          refreshPlanning: () async => ran = true,
        );

        final result = await controller.syncNow();

        expect(ran, isFalse);
        expect(result.requiresReauth, isFalse);
        expect(result.anyFailure, isFalse);
      },
    );

    test(
      'signedIn with a preserved context runs all four steps unchanged '
      '(regression guard for Task 2.6b)',
      () async {
        final calls = <String>[];
        final controller = UnifiedManualSyncController(
          activeContextReader: _ctx,
          authStatusReader: () => AppAuthStatus.signedIn,
          syncSongMutations: (_) async => calls.add('song'),
          refreshSongCatalog: () async => calls.add('catalog'),
          syncPlanningMutations: (_) async => calls.add('planning'),
          refreshPlanning: () async => calls.add('planRefresh'),
        );

        final result = await controller.syncNow();

        expect(calls, ['song', 'catalog', 'planning', 'planRefresh']);
        expect(result.requiresReauth, isFalse);
      },
    );
  });
}
