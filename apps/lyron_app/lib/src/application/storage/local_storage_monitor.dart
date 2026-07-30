import 'package:lyron_app/src/application/storage/catalog_storage_accountant.dart';
import 'package:lyron_app/src/application/storage/local_storage_budget.dart';
import 'package:lyron_app/src/application/storage/local_storage_footprint.dart';
import 'package:lyron_app/src/application/storage/planning_storage_accountant.dart';

/// Composes the planning and catalog accountants into one footprint and its
/// pressure level.
///
/// Runs on demand — when the sync surface asks — not on the write path. The
/// write path measures only mutation bytes, which is a single aggregate over
/// a small table.
class LocalStorageMonitor {
  const LocalStorageMonitor({
    required PlanningStorageAccountant planningAccountant,
    required CatalogStorageAccountant catalogAccountant,
    required LocalStorageBudget budget,
  }) : _planningAccountant = planningAccountant,
       _catalogAccountant = catalogAccountant,
       _budget = budget;

  final PlanningStorageAccountant _planningAccountant;
  final CatalogStorageAccountant _catalogAccountant;
  final LocalStorageBudget _budget;

  Future<LocalStorageFootprint> measure({
    required String userId,
    required String organizationId,
  }) async {
    final mutationBytes = await _planningAccountant.measureMutationBytes(
      userId: userId,
      organizationId: organizationId,
    );
    final mutationCount = await _planningAccountant.measureMutationCount(
      userId: userId,
      organizationId: organizationId,
    );
    final projectionBytes = await _planningAccountant.measureProjectionBytes();
    final catalogBytes = await _catalogAccountant.measureCatalogBytes();

    return LocalStorageFootprint(
      mutationBytes: mutationBytes,
      mutationCount: mutationCount,
      projectionBytes: projectionBytes,
      catalogBytes: catalogBytes,
    );
  }

  LocalStoragePressure pressureOf(LocalStorageFootprint footprint) =>
      _budget.classify(footprint);
}
