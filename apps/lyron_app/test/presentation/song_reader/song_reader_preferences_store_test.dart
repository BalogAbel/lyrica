import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesSongReaderPreferencesStore', () {
    late SharedPreferencesSongReaderPreferencesStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      store = SharedPreferencesSongReaderPreferencesStore(prefs);
    });

    test('readZoom returns null when no value stored', () async {
      final result = await store.readZoom(userId: 'u1', songId: 'song-1');
      expect(result, isNull);
    });

    test('writeZoom then readZoom returns the written value', () async {
      await store.writeZoom(userId: 'u1', songId: 'song-1', zoom: 1.6);
      final result = await store.readZoom(userId: 'u1', songId: 'song-1');
      expect(result, closeTo(1.6, 0.0001));
    });

    test(
      'zoom is keyed by userId + songId — different user returns null',
      () async {
        await store.writeZoom(userId: 'u1', songId: 'song-1', zoom: 1.6);
        final result = await store.readZoom(userId: 'u2', songId: 'song-1');
        expect(result, isNull);
      },
    );

    test(
      'zoom is keyed by userId + songId — different song returns null',
      () async {
        await store.writeZoom(userId: 'u1', songId: 'song-1', zoom: 1.6);
        final result = await store.readZoom(userId: 'u1', songId: 'song-2');
        expect(result, isNull);
      },
    );

    test('multiple entries stored independently', () async {
      await store.writeZoom(userId: 'u1', songId: 'song-1', zoom: 1.6);
      await store.writeZoom(userId: 'u1', songId: 'song-2', zoom: 2.0);
      await store.writeZoom(userId: 'u2', songId: 'song-1', zoom: 0.8);

      expect(
        await store.readZoom(userId: 'u1', songId: 'song-1'),
        closeTo(1.6, 0.0001),
      );
      expect(
        await store.readZoom(userId: 'u1', songId: 'song-2'),
        closeTo(2.0, 0.0001),
      );
      expect(
        await store.readZoom(userId: 'u2', songId: 'song-1'),
        closeTo(0.8, 0.0001),
      );
    });

    test('overwriting a value updates the stored zoom', () async {
      await store.writeZoom(userId: 'u1', songId: 'song-1', zoom: 1.0);
      await store.writeZoom(userId: 'u1', songId: 'song-1', zoom: 2.5);
      final result = await store.readZoom(userId: 'u1', songId: 'song-1');
      expect(result, closeTo(2.5, 0.0001));
    });
  });
}
