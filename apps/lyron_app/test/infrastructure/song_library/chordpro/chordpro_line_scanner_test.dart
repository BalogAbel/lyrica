import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_line_scanner.dart';

void main() {
  List<ChordproLine> scan(String source) =>
      ChordproLineScanner().scan(source).toList();

  int? boundaryOf(String source) =>
      ChordproBaseRegion.of(scan(source)).boundaryLineNumber;

  group('ChordproBaseRegion', () {
    group('S1 lyric lines close the region', () {
      test('a lyric line is the boundary', () {
        expect(boundaryOf('{capo: 2}\nAmazing grace\n{capo: 3}'), 2);
      });

      test('a chord-only line is the boundary', () {
        expect(boundaryOf('{transpose: 2}\n[A] [C#m/G#]\n{capo: 3}'), 2);
      });

      test('contains is true before the boundary and false from it', () {
        final lines = scan('{capo: 2}\n\n[A] [C#m/G#]\n{capo: 3}');
        final region = ChordproBaseRegion.of(lines);

        expect(region.boundaryLineNumber, 3);
        expect(lines.map(region.contains), [true, true, false, false]);
      });
    });

    group('S2 non-content lines never close the region', () {
      test(
        'comments, environments, unknown directives and blanks stay base',
        () {
          final lines = scan(
            [
              '{comment:<Intro>}',
              '{c: Verse}',
              '{start_of_verse}',
              '{end_of_verse}',
              '{foobar: x}',
              '',
              '   ',
              '{key: G}',
            ].join('\n'),
          );
          final region = ChordproBaseRegion.of(lines);

          expect(region.boundaryLineNumber, isNull);
          expect(lines.every(region.contains), isTrue);
        },
      );

      test('the first lyric after them is still the boundary', () {
        expect(
          boundaryOf(
            '{comment:<Intro>}\n{start_of_verse}\n{foobar: x}\n\nLyric\n',
          ),
          5,
        );
      });
    });

    group('S3 tab environments', () {
      test('the first non-empty tab line closes the region', () {
        expect(boundaryOf('{start_of_tab}\ne|--0--|\n{end_of_tab}'), 2);
      });

      test('a directive-shaped tab line closes the region', () {
        expect(boundaryOf('{start_of_tab}\n{capo: 2}\n{end_of_tab}'), 2);
      });

      test('blank tab lines do not close the region', () {
        expect(boundaryOf('{start_of_tab}\n\n   \ne|--0--|\n{end_of_tab}'), 4);
      });

      test('an empty tab does not close the region', () {
        expect(boundaryOf('{start_of_tab}\n{end_of_tab}\n{capo: 2}'), isNull);
      });

      test('a nested start_of_tab inside a tab is content', () {
        expect(boundaryOf('{start_of_tab}\n{start_of_tab}\n{end_of_tab}'), 2);
      });

      test('any end_of_* line leaves the tab', () {
        expect(
          boundaryOf('{start_of_tab}\n{end_of_verse}\n{capo: 2}\nLyric'),
          4,
        );
      });
    });

    group('S4 sources without song content', () {
      test('an empty source has no boundary', () {
        final region = ChordproBaseRegion.of(scan(''));

        expect(region.boundaryLineNumber, isNull);
      });

      test('every line is contained', () {
        final lines = scan('{title: T}\n{capo: 2}\n\n{c: Intro}');
        final region = ChordproBaseRegion.of(lines);

        expect(region.boundaryLineNumber, isNull);
        expect(lines.every(region.contains), isTrue);
      });
    });

    group('S5 line endings', () {
      test('CRLF sources give the same boundary as LF sources', () {
        const lf = '{comment:<Intro>}\n{capo: 2}\n\n[A] x\n{capo: 3}\n';
        final crlf = lf.replaceAll('\n', '\r\n');

        expect(boundaryOf(crlf), 4);
        expect(boundaryOf(crlf), boundaryOf(lf));
      });

      test('CRLF tab sources give the same boundary as LF sources', () {
        const lf = '{start_of_tab}\n\ne|--0--|\n{end_of_tab}\n';
        final crlf = lf.replaceAll('\n', '\r\n');

        expect(boundaryOf(crlf), 3);
        expect(boundaryOf(crlf), boundaryOf(lf));
      });
    });
  });
}
