import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/sync/unified_discard_controller.dart';

void main() {
  test('discardAll runs both domain steps with active context', () async {
    final calls = <String>[];
    final controller = UnifiedDiscardController(
      activeContextReader: () =>
          const UnifiedDiscardContext(userId: 'u1', organizationId: 'o1'),
      discardSongs: (ctx) async => calls.add('songs:${ctx.organizationId}'),
      discardPlanning: (ctx) async => calls.add('plans:${ctx.organizationId}'),
    );
    await controller.discardAll();
    expect(calls, ['songs:o1', 'plans:o1']);
  });

  test('discardAll is a no-op when no active context', () async {
    var ran = false;
    final controller = UnifiedDiscardController(
      activeContextReader: () => null,
      discardSongs: (_) async => ran = true,
      discardPlanning: (_) async => ran = true,
    );
    await controller.discardAll();
    expect(ran, isFalse);
  });
}
