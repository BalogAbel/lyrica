class UnifiedDiscardContext {
  const UnifiedDiscardContext({
    required this.userId,
    required this.organizationId,
  });

  final String userId;
  final String organizationId;
}

typedef UnifiedDiscardContextReader = UnifiedDiscardContext? Function();
typedef UnifiedDiscardStep =
    Future<void> Function(UnifiedDiscardContext context);

class UnifiedDiscardController {
  UnifiedDiscardController({
    required UnifiedDiscardContextReader activeContextReader,
    required UnifiedDiscardStep discardSongs,
    required UnifiedDiscardStep discardPlanning,
  }) : _activeContextReader = activeContextReader,
       _discardSongs = discardSongs,
       _discardPlanning = discardPlanning;

  final UnifiedDiscardContextReader _activeContextReader;
  final UnifiedDiscardStep _discardSongs;
  final UnifiedDiscardStep _discardPlanning;

  Future<void> discardAll() async {
    final context = _activeContextReader();
    if (context == null) return;
    await Future.wait([
      _discardSongs(context),
      _discardPlanning(context),
    ], eagerError: false);
  }
}
