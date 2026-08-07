import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';

void main() {
  group('LocalStorageBudget', () {
    const budget = LocalStorageBudget(
      mutationWarnBytes: 100,
      mutationRefuseBytes: 200,
      totalWarnBytes: 1000,
      totalCriticalBytes: 2000,
    );

    LocalStorageFootprint footprint({
      int mutationBytes = 0,
      int projectionBytes = 0,
      int catalogBytes = 0,
    }) => LocalStorageFootprint(
      mutationBytes: mutationBytes,
      mutationCount: 0,
      projectionBytes: projectionBytes,
      catalogBytes: catalogBytes,
    );

    test('totalBytes sums every measured segment', () {
      expect(
        footprint(
          mutationBytes: 1,
          projectionBytes: 2,
          catalogBytes: 4,
        ).totalBytes,
        7,
      );
    });

    test('classifies ok below every threshold', () {
      expect(
        budget.classify(footprint(mutationBytes: 99)),
        LocalStoragePressure.ok,
      );
    });

    test('classifies warning at the mutation warn threshold', () {
      expect(
        budget.classify(footprint(mutationBytes: 100)),
        LocalStoragePressure.warning,
      );
    });

    test('classifies critical at the mutation refuse threshold', () {
      expect(
        budget.classify(footprint(mutationBytes: 200)),
        LocalStoragePressure.critical,
      );
    });

    test('classifies warning and critical on total bytes too', () {
      expect(
        budget.classify(footprint(catalogBytes: 1000)),
        LocalStoragePressure.warning,
      );
      expect(
        budget.classify(footprint(catalogBytes: 2000)),
        LocalStoragePressure.critical,
      );
    });

    test('refusesNewMutation only at or above the refuse threshold', () {
      expect(budget.refusesNewMutation(199), isFalse);
      expect(budget.refusesNewMutation(200), isTrue);
    });
  });
}
