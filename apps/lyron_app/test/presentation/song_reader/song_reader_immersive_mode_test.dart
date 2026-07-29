import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_immersive_mode.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> modeCalls;

  setUp(() {
    modeCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modeCalls.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('applies immersiveSticky the first time active is true', () {
    SongReaderImmersiveMode().apply(true);

    expect(modeCalls, ['SystemUiMode.immersiveSticky']);
  });

  test('applies edgeToEdge the first time active is false', () {
    SongReaderImmersiveMode().apply(false);

    expect(modeCalls, ['SystemUiMode.edgeToEdge']);
  });

  test('re-applying the same state does not repeat the platform call', () {
    final immersiveMode = SongReaderImmersiveMode();

    immersiveMode.apply(true);
    immersiveMode.apply(true);
    immersiveMode.apply(true);

    expect(modeCalls, ['SystemUiMode.immersiveSticky']);
  });

  test('a state change issues exactly one new platform call', () {
    final immersiveMode = SongReaderImmersiveMode();

    immersiveMode.apply(true);
    expect(modeCalls, ['SystemUiMode.immersiveSticky']);

    immersiveMode.apply(false);
    expect(modeCalls, [
      'SystemUiMode.immersiveSticky',
      'SystemUiMode.edgeToEdge',
    ]);

    immersiveMode.apply(false);
    expect(modeCalls, [
      'SystemUiMode.immersiveSticky',
      'SystemUiMode.edgeToEdge',
    ]);

    immersiveMode.apply(true);
    expect(modeCalls, [
      'SystemUiMode.immersiveSticky',
      'SystemUiMode.edgeToEdge',
      'SystemUiMode.immersiveSticky',
    ]);
  });
}
