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

  test(
    'new transpose and capo directives are inserted before section comments',
    () {
      final controller = SongEditorController(
        source: '''
{title: Heart of Worship}
{subtitle: When the music fades}
{key: D}

{comment:<Intro>}
[D]When the music fades
''',
      );

      controller.transposeUp();
      controller.capoUp();

      final source = controller.state.source;
      final transposeIndex = source.indexOf('{transpose: 1}');
      final capoIndex = source.indexOf('{capo: 1}');
      final commentIndex = source.indexOf('{comment:<Intro>}');

      expect(transposeIndex, isNonNegative);
      expect(capoIndex, isNonNegative);
      expect(commentIndex, isNonNegative);
      expect(transposeIndex, lessThan(commentIndex));
      expect(capoIndex, lessThan(commentIndex));
      expect(transposeIndex, lessThan(capoIndex));
    },
  );

  test('directive updates preserve CRLF line endings', () {
    final controller = SongEditorController(
      source:
          '{title: Heart of Worship}\r\n'
          '{comment:<Intro>}\r\n'
          '[D]When the music fades\r\n',
    );

    controller.transposeUp();

    expect(controller.state.source, contains('{transpose: 1}\r\n'));
    expect(controller.state.source, contains('\r\n{comment:<Intro>}\r\n'));
  });

  test('directive updates match case-insensitive names and spaced colons', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{Transpose : 2}
{CAPO : 3}
[D]When the music fades
''',
    );

    controller.transposeUp();
    controller.capoDown();

    expect(controller.state.parsedSong.baseTranspose, 3);
    expect(controller.state.parsedSong.baseCapo, 2);
    expect(controller.state.source, contains('{transpose: 3}'));
    expect(controller.state.source, contains('{capo: 2}'));
    expect(controller.state.source, isNot(contains('{Transpose : 2}')));
    expect(controller.state.source, isNot(contains('{CAPO : 3}')));
  });

  test('default source is non-copyrighted and parses as valid ChordPro', () {
    final controller = SongEditorController();
    final source = controller.state.source;

    // No copyrighted markers from the previous hardcoded worship song.
    expect(source, isNot(contains('Heart of Worship')));
    expect(source, isNot(contains('Matt Redman')));
    expect(source, isNot(contains('When the music fades')));

    // Still a valid, parseable ChordPro sample with the placeholder title.
    expect(controller.state.parsedSong.title, 'My New Song');
  });
}
