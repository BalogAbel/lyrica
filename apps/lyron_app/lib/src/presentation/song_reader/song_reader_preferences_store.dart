import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/provider_retry_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists per-user, per-song reader preferences locally.
abstract class SongReaderPreferencesStore {
  Future<double?> readZoom({required String userId, required String songId});
  Future<void> writeZoom({
    required String userId,
    required String songId,
    required double zoom,
  });
}

class SharedPreferencesSongReaderPreferencesStore
    implements SongReaderPreferencesStore {
  SharedPreferencesSongReaderPreferencesStore(this._prefs);

  final SharedPreferences _prefs;

  String _key(String userId, String songId) => 'reader_zoom:$userId:$songId';

  @override
  Future<double?> readZoom({
    required String userId,
    required String songId,
  }) async {
    return _prefs.getDouble(_key(userId, songId));
  }

  @override
  Future<void> writeZoom({
    required String userId,
    required String songId,
    required double zoom,
  }) async {
    await _prefs.setDouble(_key(userId, songId), zoom);
  }
}

/// A [FutureProvider] that resolves a [SongReaderPreferencesStore] backed by
/// [SharedPreferences]. Tests can override this with a fake implementation.
final songReaderPreferencesStoreProvider =
    FutureProvider<SongReaderPreferencesStore>((ref) async {
      final prefs = await SharedPreferences.getInstance();
      return SharedPreferencesSongReaderPreferencesStore(prefs);
    }, retry: noAutomaticProviderRetry);
