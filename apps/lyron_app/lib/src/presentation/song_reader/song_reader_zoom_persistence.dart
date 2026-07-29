import 'dart:async';

import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';

/// Debounced zoom (shared font scale) persistence for the song reader.
///
/// Owns the one-shot seed guard and the 400 ms persist-debounce timer. Holds
/// no `Ref`/`WidgetRef` — callers pass already-resolved values (like the user
/// id) or small closures for anything that must be evaluated lazily at the
/// moment the timer fires (reading the live scale, resolving the preferences
/// store, checking `mounted`), since those can only be answered by the
/// screen's own lifecycle at that instant.
class SongReaderZoomPersistence {
  Timer? _persistZoomTimer;
  bool _seededZoom = false;

  /// Reads the stored zoom for [songId] under [userId] once per instance.
  ///
  /// Guards with an internal one-shot flag so the read fires only once per
  /// reader open and never clobbers a subsequent user change. [isMounted] is
  /// checked between the two awaits so a disposed reader does not issue the
  /// zoom read; the caller checks it again before applying the returned value.
  Future<double?> seedFromStorage({
    required String? userId,
    required String songId,
    required bool Function() isMounted,
    required Future<SongReaderPreferencesStore> Function() resolveStore,
  }) async {
    if (_seededZoom) {
      return null;
    }
    _seededZoom = true;

    if (userId == null) {
      return null;
    }

    try {
      final store = await resolveStore();
      if (!isMounted()) {
        return null;
      }
      final zoom = await store.readZoom(userId: userId, songId: songId);
      return zoom;
    } catch (_) {
      // Best-effort — ignore read failures so the reader still opens.
      return null;
    }
  }

  /// (Re)starts a 400 ms debounce timer that persists the current shared font
  /// scale for [songId] under [userId]. Called on pinch-end and double-tap
  /// fit. No-ops when there is no signed-in user.
  void schedulePersist({
    required String? userId,
    required String songId,
    required bool Function() isMounted,
    required double Function() readScale,
    required Future<SongReaderPreferencesStore> Function() resolveStore,
  }) {
    if (userId == null) {
      return;
    }

    _persistZoomTimer?.cancel();
    _persistZoomTimer = Timer(const Duration(milliseconds: 400), () async {
      if (!isMounted()) {
        return;
      }

      final scale = readScale();

      try {
        final store = await resolveStore();
        await store.writeZoom(userId: userId, songId: songId, zoom: scale);
      } catch (_) {
        // Best-effort — ignore write failures silently.
      }
    });
  }

  void dispose() {
    _persistZoomTimer?.cancel();
  }
}
