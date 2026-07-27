import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/planning/planning_reorder_overlay.dart';

void main() {
  test('keeps the overlay while a write is in flight', () {
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['b', 'a'],
        hasWriteInFlight: true,
        hasConsumedPostWriteReload: false,
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
          hasConsumedPostWriteReload: false,
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
        hasConsumedPostWriteReload: false,
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
          hasConsumedPostWriteReload: false,
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
        hasConsumedPostWriteReload: false,
      ),
      isNull,
    );
  });

  test('keeps the overlay for the first projection that arrives after the '
      'write', () {
    // Write no longer in flight, projection disagrees, nothing consumed
    // yet: the one-reload grace keeps the overlay alive so the screen
    // does not flash the pre-invalidation projection.
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['a', 'b'],
        hasWriteInFlight: false,
        hasConsumedPostWriteReload: false,
      ),
      const ['b', 'a'],
    );
  });

  test('drops the overlay when a second disagreeing projection arrives', () {
    // Same inputs as above, but the grace is already consumed: the
    // projection is authoritative now, so the overlay must not survive a
    // second disagreement.
    expect(
      resolveReorderOverlay(
        optimisticOrder: const ['b', 'a'],
        projectionOrder: const ['a', 'b'],
        hasWriteInFlight: false,
        hasConsumedPostWriteReload: true,
      ),
      isNull,
    );
  });
}
