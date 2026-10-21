import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/planning/planning_write_service.dart';
import 'package:lyron_app/src/application/planning/session_item_key_edit.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/planning/planning_providers.dart';

/// What the reader's key controls offer besides the `±` steps (PS7): Reset in
/// every reader, Save to plan inside a plan for a member who may edit it. A
/// null callback is a disabled button, so neither button comes and goes as the
/// key changes (the compact rail is vertically centered). Built by the screen;
/// the rail and the tools panel only place the buttons.
class SongReaderKeyActions {
  const SongReaderKeyActions({
    required this.isSaveToPlanAvailable,
    this.onReset,
    this.onSaveToPlan,
  });

  /// Reset only, disabled: the reader has no key to act on.
  static const none = SongReaderKeyActions(isSaveToPlanAvailable: false);

  /// Whether the Save to plan button exists at all; [onSaveToPlan] decides
  /// whether it is enabled.
  final bool isSaveToPlanAvailable;
  final VoidCallback? onReset;
  final VoidCallback? onSaveToPlan;
}

/// The plan-key edit that saves the temporary fields of [key] (PS7, PS26):
/// `set` with the resolved value for each field whose source is the temporary
/// layer, `keep` for the other. The instrument view does not matter: a capo
/// still temporary in piano view is saved. Null when nothing is temporary or
/// a temporary value lies outside the PS9 range (the plan never gets one).
SessionItemKeyEdit? planKeyEditFor(ResolvedSongKey key) {
  final temporaryFields = [
    for (final field in SongKeyField.values)
      if (key.field(field).source == SongKeyLayerId.temporary) field,
  ];
  if (temporaryFields.isEmpty ||
      temporaryFields.any(
        (field) => !SongKeyRange.contains(field, key.field(field).value),
      )) {
    return null;
  }

  int? temporaryValue(SongKeyField field) =>
      temporaryFields.contains(field) ? key.field(field).value : null;
  final transpose = temporaryValue(SongKeyField.transpose);
  final capo = temporaryValue(SongKeyField.capo);
  return SessionItemKeyEdit(
    transposeMode: transpose == null
        ? SessionItemKeyFieldMode.keep
        : SessionItemKeyFieldMode.set,
    transpose: transpose,
    capoMode: capo == null
        ? SessionItemKeyFieldMode.keep
        : SessionItemKeyFieldMode.set,
    capo: capo,
  );
}

/// Writes the plan key of a session item for the reader (PS26). The caller
/// captures [ProviderContainer] with `ProviderScope.containerOf(context,
/// listen: false)` before calling, so a reader closed during the write still
/// refreshes the plan detail.
class SongReaderPlanKeyWriter {
  const SongReaderPlanKeyWriter();

  /// Records [edit] as the plan key of the item. False, with nothing written,
  /// when there is no active planning context; a failed write throws.
  Future<bool> saveToPlan(
    ProviderContainer container, {
    required String planId,
    required String sessionId,
    required String sessionItemId,
    required SessionItemKeyEdit edit,
  }) {
    return _write(
      container,
      planId: planId,
      sessionId: sessionId,
      sessionItemId: sessionItemId,
      edit: edit,
    );
  }

  /// Clears both plan fields of the item; the song base applies again.
  Future<bool> clearPlanValue(
    ProviderContainer container, {
    required String planId,
    required String sessionId,
    required String sessionItemId,
  }) {
    return _write(
      container,
      planId: planId,
      sessionId: sessionId,
      sessionItemId: sessionItemId,
      edit: SessionItemKeyEdit(
        transposeMode: SessionItemKeyFieldMode.clear,
        capoMode: SessionItemKeyFieldMode.clear,
      ),
    );
  }

  Future<bool> _write(
    ProviderContainer container, {
    required String planId,
    required String sessionId,
    required String sessionItemId,
    required SessionItemKeyEdit edit,
  }) async {
    final context = container.read(activePlanningContextProvider);
    if (context == null) {
      return false;
    }
    await container
        .read(planningWriteServiceProvider)
        .setSessionItemKey(
          context: PlanningWriteContext(
            userId: context.userId,
            organizationId: context.organizationId,
          ),
          draft: SessionItemKeyDraft(
            planId: planId,
            sessionId: sessionId,
            sessionItemId: sessionItemId,
            edit: edit,
          ),
          // The write returns only after a sync attempt; the reader must show
          // the recorded value before that.
          onRecorded: () {
            container.invalidate(planningPlanDetailProvider(planId));
            container.invalidate(planningMutationEntriesProvider);
          },
        );
    return true;
  }
}
