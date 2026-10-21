import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/song/song_key_layers.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_controller.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';

void main() {
  test('derives the summary from ChordPro source metadata', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{subtitle: When the music fades}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
    );

    final projection = SongEditorProjection(state: controller.state);

    expect(projection.summaryTitle, 'Heart of Worship');
    expect(projection.summaryArtist, 'Matt Redman');
    expect(projection.summaryKey, 'D');
    expect(projection.summaryTempo, '72 bpm');
    expect(projection.summaryTags, 'worship, acoustic');
    expect(projection.summaryTranspose, '+1');
    expect(projection.summaryCapo, '2');
    expect(projection.preview.subtitle, 'When the music fades');
  });

  test('preview reflects the stored transpose and capo settings only', () {
    final controller = SongEditorController(
      source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{tempo: 72}
{tags: worship, acoustic}
{transpose: 1}
{capo: 2}

[D]When the music fades
''',
    );

    final projection = SongEditorProjection(state: controller.state);

    expect(
      projection.preview.key,
      const ResolvedSongKey(
        transpose: ResolvedSongKeyField(value: 1, source: SongKeyLayerId.song),
        capo: ResolvedSongKeyField(value: 2, source: SongKeyLayerId.song),
      ),
    );
    expect(projection.preview.effectiveTranspose, 1);
    expect(projection.preview.effectiveCapo, 2);
    expect(
      (projection.preview.sections.first.lines.first
              as SongReaderLyricLineProjection)
          .segments
          .first
          .displayChord,
      'C#',
    );
    expect(projection.preview.capoDirectiveText, 'Capo 2');
  });

  test('preview never shows a capo below open capo', () {
    final controller = SongEditorController(
      source: '{title: T}\n{capo: -2}\n[A]x\n',
    );

    final projection = SongEditorProjection(state: controller.state);

    expect(
      projection.preview.key.capo,
      const ResolvedSongKeyField(value: 0, source: SongKeyLayerId.song),
    );
  });

  test(
    'summary and preview track transpose and capo directives before lyrics',
    () {
      final controller = SongEditorController(
        source: '''
{title: Heart of Worship}
{artist: Matt Redman}
{key: D}
{comment:<Intro>}
{transpose: 2}
{capo: 3}
[D]When the music fades
''',
      );

      final projection = SongEditorProjection(state: controller.state);

      expect(projection.summaryTranspose, '+2');
      expect(projection.summaryCapo, '3');
      expect(projection.preview.effectiveTranspose, 2);
      expect(projection.preview.effectiveCapo, 3);
      expect(projection.preview.capoDirectiveText, 'Capo 3');
    },
  );

  test('summary reads key, transpose and capo past a comment (E9)', () {
    final controller = SongEditorController(
      source:
          '{title: T}\n{comment:<Intro>}\n{key: G}\n{transpose: 2}\n{capo: 3}\n[A]x\n',
    );

    final projection = SongEditorProjection(state: controller.state);

    expect(projection.summaryKey, 'G');
    expect(projection.summaryTranspose, '+2');
    expect(projection.summaryCapo, '3');
  });

  test('a transpose line inside a tab is tab text, not a base value (BD5)', () {
    final controller = SongEditorController(
      source:
          '{title: T}\n{start_of_tab}\n{transpose: 2}\ne|--|\n{end_of_tab}\n[A]x\n',
    );

    final projection = SongEditorProjection(state: controller.state);

    expect(controller.state.parsedSong.baseTranspose, 0);
    expect(projection.summaryTranspose, '0');
  });
}
