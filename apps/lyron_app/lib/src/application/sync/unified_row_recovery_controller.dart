import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';

/// Runs one song row's keep-mine or discard-mine, returning `true` if the
/// operation failed. A thrown exception from the underlying sync call must
/// never escape -- the widget half only needs to know whether to show its
/// failure snackbar.
typedef UnifiedRowRecoverySongStep = Future<bool> Function(String songId);

/// Runs a plan group's retry-or-discard across every mutation ref, returning
/// `true` if any of them failed. A partial failure across several refs is
/// not one exception -- every ref gets attempted regardless of an earlier
/// one failing, and the caller learns only whether *any* failed.
typedef UnifiedRowRecoveryGroupStep =
    Future<bool> Function(
      List<UnifiedSyncPlanMutationRef> refs, {
      required bool retry,
    });

/// The `ref` half of the popup's row recovery actions (keep-mine,
/// discard-mine, apply-to-group), split out so it can run to completion on
/// a controller that outlives the popup widget that started it.
///
/// Holds no `Ref` of its own -- same shape as [UnifiedDiscardController].
/// The provider wiring these steps together (in unified_sync_providers.dart)
/// closes over its own `ref`, taking `ref.keepAlive()` for the duration of
/// each step so the mutation, the revision bump and the invalidations all
/// still happen even if nothing is watching this controller by the time
/// they run.
class UnifiedRowRecoveryController {
  UnifiedRowRecoveryController({
    required UnifiedRowRecoverySongStep keepMineStep,
    required UnifiedRowRecoverySongStep discardMineStep,
    required UnifiedRowRecoveryGroupStep applyToGroupStep,
  }) : _keepMineStep = keepMineStep,
       _discardMineStep = discardMineStep,
       _applyToGroupStep = applyToGroupStep;

  final UnifiedRowRecoverySongStep _keepMineStep;
  final UnifiedRowRecoverySongStep _discardMineStep;
  final UnifiedRowRecoveryGroupStep _applyToGroupStep;

  Future<bool> keepMine(String songId) => _keepMineStep(songId);

  Future<bool> discardMine(String songId) => _discardMineStep(songId);

  Future<bool> applyToGroup(
    List<UnifiedSyncPlanMutationRef> refs, {
    required bool retry,
  }) => _applyToGroupStep(refs, retry: retry);
}
