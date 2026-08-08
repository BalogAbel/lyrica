import 'package:lyron_app/src/application/sync/unified_sync_overview.dart';

enum UnifiedRowDiscardResult { discarded, syncInProgress, failed }

/// Runs one song row's keep-mine, returning `true` if the operation failed.
typedef UnifiedRowRecoverySongStep = Future<bool> Function(String songId);

/// Preserves the expected sync-ownership rejection separately from an
/// unexpected discard failure so the popup can give specific guidance.
typedef UnifiedRowRecoveryDiscardSongStep =
    Future<UnifiedRowDiscardResult> Function(String songId);

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
    required this._keepMineStep,
    required this._discardMineStep,
    required this._applyToGroupStep,
  });

  final UnifiedRowRecoverySongStep _keepMineStep;
  final UnifiedRowRecoveryDiscardSongStep _discardMineStep;
  final UnifiedRowRecoveryGroupStep _applyToGroupStep;

  Future<bool> keepMine(String songId) => _keepMineStep(songId);

  Future<UnifiedRowDiscardResult> discardMineResult(String songId) =>
      _discardMineStep(songId);

  Future<bool> applyToGroup(
    List<UnifiedSyncPlanMutationRef> refs, {
    required bool retry,
  }) => _applyToGroupStep(refs, retry: retry);
}
