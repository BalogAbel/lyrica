import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_reorder_overlay.dart';

void main() {
  test('keeps the overlay while a write is in flight', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['b', 'a'],
        hasWriteInFlight: true,
      ),
      const ['b', 'a'],
    );
  });

  test(
    'clears the overlay once the projection agrees and nothing is in flight',
    () {
      expect(
        resolveReorderOverlay(
          optimisticOrder: const ['b', 'a'],
          projectionOrder: const ['b', 'a'],
          hasWriteInFlight: false,
        ),
        isNull,
      );
    },
  );

  test('keeps the overlay when the projection has not caught up yet', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['a', 'b'],
        hasWriteInFlight: false,
      ),
      const ['b', 'a'],
    );
  });

  test(
    'clears the overlay when the projection is structurally incompatible',
    () {
      expect(
        resolveReorderOverlay(
          optimisticOrder: const ['b', 'a'],
          projectionOrder: const ['a', 'b', 'c'],
          hasWriteInFlight: false,
        ),
        isNull,
      );
    },
  );

  test('is a no-op when there is no overlay', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: null,
        projectionOrder: const ['a', 'b'],
        hasWriteInFlight: false,
      ),
      isNull,
    );
  });
}
