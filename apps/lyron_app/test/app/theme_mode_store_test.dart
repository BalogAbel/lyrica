import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/app/theme_mode_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferencesThemeModeStore> store(
    Map<String, Object> initial,
  ) async {
    SharedPreferences.setMockInitialValues(initial);
    return SharedPreferencesThemeModeStore(
      await SharedPreferences.getInstance(),
    );
  }

  test('with nothing stored it follows the system', () async {
    expect(await (await store({})).read(), ThemeMode.system);
  });

  test('round-trips an explicit dark choice', () async {
    final subject = await store({});
    await subject.write(ThemeMode.dark);

    expect(await subject.read(), ThemeMode.dark);
  });

  test('writing system clears the stored override', () async {
    final subject = await store({'app_theme_mode': 'dark'});
    await subject.write(ThemeMode.system);

    expect(await subject.read(), ThemeMode.system);
  });

  test('an unrecognised stored value falls back to the system', () async {
    expect(
      await (await store({'app_theme_mode': 'sepia'})).read(),
      ThemeMode.system,
    );
  });
}
