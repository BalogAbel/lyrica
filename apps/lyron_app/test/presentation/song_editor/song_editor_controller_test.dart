import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_controller.dart';

void main() {
  test(
    'loads ChordPro source and derived metadata from the current source',
    () {
      final controller = SongEditorController(
        source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}

[D]When the music fades
''',
      );

      expect(controller.state.source, contains('{title: Heart of Worship}'));
      expect(controller.state.parsedSong.title, 'Heart of Worship');
      expect(controller.state.parsedSong.artist, 'Matt Redman');
      expect(controller.state.parsedSong.sourceKey, 'D');
      expect(controller.state.parsedSong.tempoBpm, 72);
      expect(controller.state.parsedSong.tags, ['worship', 'acoustic']);
      expect(controller.state.parsedSong.baseTranspose, 0);
      expect(controller.state.parsedSong.baseCapo, 0);
    },
  );

  test('transpose and capo controls update the stored ChordPro directives', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}

[D]When the music fades
''',
    );

    controller.transposeUp();
    controller.transposeUp();
    controller.transposeDown();
    controller.capoUp();
    controller.capoUp();
    controller.capoDown();

    expect(controller.state.parsedSong.baseTranspose, 1);
    expect(controller.state.parsedSong.baseCapo, 1);
    expect(controller.state.source, contains('{transpose: 1}'));
    expect(controller.state.source, contains('{capo: 1}'));
  });

  test('transpose and capo controls keep pre-lyric directives canonical', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}

[D]When the music fades
{transpose: 4}
{capo: 4}
''',
    );

    controller.transposeUp();
    controller.capoUp();

    expect(controller.state.parsedSong.baseTranspose, 1);
    expect(controller.state.parsedSong.baseCapo, 1);
    expect(controller.state.source, contains('{transpose: 1}'));
    expect(controller.state.source, contains('{capo: 1}'));
    expect(controller.state.source, isNot(contains('{transpose: 4}')));
    expect(controller.state.source, isNot(contains('{capo: 4}')));
  });
}
