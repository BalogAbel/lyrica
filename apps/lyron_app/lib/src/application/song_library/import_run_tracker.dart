/// RW3 (docs/specs/2026-10-11-reauth-wipe-recount.md): whether a ChordPro
/// import run is in a phase that writes pending work in the background
/// (`isImportRunning`, SO7 of
/// docs/specs/2026-10-07-sign-out-pending-work-guard.md).
///
/// The import controller is a presentation-layer notifier; this is the
/// application layer's view of its runs, so the different-user wipe can
/// refuse to start while one may be writing. Keyed by the reporting
/// controller instance: each instance adds and removes only itself, and a
/// disposed instance removes itself, so "running" can never outlive the
/// instance that reported it.
class ImportRunTracker {
  final _running = <Object>{};

  bool get isRunning => _running.isNotEmpty;

  void report(Object owner, {required bool running}) {
    if (running) {
      _running.add(owner);
    } else {
      _running.remove(owner);
    }
  }
}
