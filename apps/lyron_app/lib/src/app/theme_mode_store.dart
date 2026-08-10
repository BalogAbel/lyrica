import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/provider_retry_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists an explicit app-wide light/dark choice.
///
/// Absence of a stored value means "follow the system", so a user who never
/// touches the switch keeps the platform behaviour. This is app-wide state and
/// deliberately does not live in [SongReaderPreferencesStore], whose keys are
/// scoped to a user and a song.
abstract class ThemeModeStore {
  Future<ThemeMode> read();
  Future<void> write(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  SharedPreferencesThemeModeStore(this._prefs);

  static const _key = 'app_theme_mode';

  final SharedPreferences _prefs;

  @override
  Future<ThemeMode> read() async {
    return switch (_prefs.getString(_key)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  @override
  Future<void> write(ThemeMode mode) async {
    switch (mode) {
      case ThemeMode.light:
        await _prefs.setString(_key, 'light');
      case ThemeMode.dark:
        await _prefs.setString(_key, 'dark');
      case ThemeMode.system:
        await _prefs.remove(_key);
    }
  }
}

/// A [FutureProvider] that resolves a [ThemeModeStore] backed by
/// [SharedPreferences]. Tests can override this with a fake implementation.
final themeModeStoreProvider = FutureProvider<ThemeModeStore>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return SharedPreferencesThemeModeStore(prefs);
}, retry: noAutomaticProviderRetry);

class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() async {
    final store = await ref.watch(themeModeStoreProvider.future);
    return store.read();
  }

  /// Flips to the opposite of what is currently on screen.
  ///
  /// Takes the rendered brightness rather than reading state, so that the
  /// first tap while still following the system flips away from what the
  /// user is actually looking at, not away from `ThemeMode.system`.
  Future<void> toggle(Brightness activeBrightness) async {
    final next = activeBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    final store = await ref.read(themeModeStoreProvider.future);
    await store.write(next);
    state = AsyncData(next);
  }
}

final themeModeControllerProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeMode>(
      ThemeModeController.new,
      retry: noAutomaticProviderRetry,
    );
