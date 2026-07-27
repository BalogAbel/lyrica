/// Decides whether an optimistic reorder overlay should survive the arrival of
/// a refreshed projection.
///
/// The overlay exists so a drag stays visible while the local write and the
/// provider invalidation settle. It must not outlive that window: once the
/// projection agrees with it, or can no longer be reconciled with it, the
/// projection is the single source of truth again.
List<String>? resolveReorderOverlay({
  required List<String>? optimisticOrder,
  required List<String> projectionOrder,
  required bool hasWriteInFlight,
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
      return optimisticOrder;
    }
  }
  return null;
}
