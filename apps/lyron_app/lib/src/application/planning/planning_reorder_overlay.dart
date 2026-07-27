/// Decides whether an optimistic reorder overlay should survive the arrival of
/// a refreshed projection.
///
/// The overlay exists so a drag stays visible while the local write and the
/// provider invalidation settle. It must not outlive that window: once the
/// projection agrees with it, or can no longer be reconciled with it, the
/// projection is the single source of truth again.
///
/// The invalidation issued when the write completes can be overtaken by a
/// read that was already in flight, so the very first projection to arrive
/// after the write completes may still reflect the pre-invalidation state.
/// To avoid flashing that stale order, the overlay gets exactly one
/// post-write reload of grace: if that first reload disagrees with the
/// optimistic order, the overlay survives once more. Any later disagreement
/// — a concurrent reorder from another device, a server-side
/// reconciliation, a rejected-but-not-failed write — is treated as
/// authoritative and the overlay is dropped.
List<String>? resolveReorderOverlay({
  required List<String>? optimisticOrder,
  required List<String> projectionOrder,
  required bool hasWriteInFlight,
  required bool hasConsumedPostWriteReload,
}) {
  if (optimisticOrder == null) {
    return null;
  }
  if (hasWriteInFlight) {
    return optimisticOrder;
  }
  if (optimisticOrder.length != projectionOrder.length ||
      !optimisticOrder.toSet().containsAll(projectionOrder)) {
    return null;
  }
  for (var index = 0; index < optimisticOrder.length; index++) {
    if (optimisticOrder[index] != projectionOrder[index]) {
      return hasConsumedPostWriteReload ? null : optimisticOrder;
    }
  }
  return null;
}
