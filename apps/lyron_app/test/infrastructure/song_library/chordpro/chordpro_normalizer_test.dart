import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/infrastructure/song_library/chordpro/chordpro_normalizer.dart';

void main() {
  final normalizer = ChordproNormalizer();

  group('title aliases', () {
    test('{t: value} becomes {title: value}', () {
      expect(normalizer.normalize('{t: My Song}'), '{title: My Song}');
    });

    test('{st: value} becomes {subtitle: value}', () {
      expect(normalizer.normalize('{st: Sub}'), '{subtitle: Sub}');
    });

    test('{c: text} becomes {comment: text}', () {
      expect(normalizer.normalize('{c: text}'), '{comment: text}');
    });
  });

  group('chorus aliases', () {
    test('{soc} becomes {start_of_chorus}', () {
      expect(normalizer.normalize('{soc}'), '{start_of_chorus}');
    });

    test('{eoc} becomes {end_of_chorus}', () {
      expect(normalizer.normalize('{eoc}'), '{end_of_chorus}');
    });

    test('{soc: My Chorus} becomes {start_of_chorus: My Chorus}', () {
      expect(
        normalizer.normalize('{soc: My Chorus}'),
        '{start_of_chorus: My Chorus}',
      );
    });
  });

  group('verse aliases', () {
    test('{sov} becomes {start_of_verse}', () {
      expect(normalizer.normalize('{sov}'), '{start_of_verse}');
    });

    test('{eov} becomes {end_of_verse}', () {
      expect(normalizer.normalize('{eov}'), '{end_of_verse}');
    });
  });

  group('bridge aliases', () {
    test('{sob} becomes {start_of_bridge}', () {
      expect(normalizer.normalize('{sob}'), '{start_of_bridge}');
    });

    test('{eob} becomes {end_of_bridge}', () {
      expect(normalizer.normalize('{eob}'), '{end_of_bridge}');
    });
  });

  group('tab aliases', () {
    test('{sot} becomes {start_of_tab}', () {
      expect(normalizer.normalize('{sot}'), '{start_of_tab}');
    });

    test('{eot} becomes {end_of_tab}', () {
      expect(normalizer.normalize('{eot}'), '{end_of_tab}');
    });
  });

  test('non-directive lines are unchanged', () {
    const source = '[A]Hello [Bm]world\n';
    expect(normalizer.normalize(source), source);
  });

  test('unknown directives are unchanged', () {
    const source = '{zoom-ipad: 1.9}\n';
    expect(normalizer.normalize(source), source);
  });

  test('canonical directives are unchanged', () {
    const source = '{title: My Song}\n{start_of_chorus}\n';
    expect(normalizer.normalize(source), source);
  });

  test('normalizes multi-line source', () {
    expect(
      normalizer.normalize('{t: My Song}\n{soc}\n[A]Hello\n{eoc}\n'),
      '{title: My Song}\n{start_of_chorus}\n[A]Hello\n{end_of_chorus}\n',
    );
  });

  test('case insensitive alias matching', () {
    expect(normalizer.normalize('{SOC}'), '{start_of_chorus}');
    expect(normalizer.normalize('{T: My Song}'), '{title: My Song}');
  });
}
