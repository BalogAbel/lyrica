import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Riverpod 3 retries a failed provider up to ten times by default, which keeps
/// the failure from ever settling into `AsyncError` and so from ever reaching
/// the UI. Every async provider therefore opts out explicitly. See ADR-032.
void main() {
  test('every async provider declares the no-retry policy', () {
    final declaration = RegExp(r'=\s*(FutureProvider|StreamProvider)\b');
    final offenders = <String>[];

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;

      final source = entity.readAsStringSync();
      // Parenthesis depth is only meaningful over code, so comments and string
      // literals are blanked out first — an unbalanced bracket inside either
      // would otherwise run the scan past the real end of a declaration and
      // let it read a neighbouring provider's policy as this one's.
      final code = _maskCommentsAndStrings(source);

      for (final match in declaration.allMatches(code)) {
        final end = _declarationEnd(code, match.end);
        final body = code.substring(match.start, end);

        if (body.contains('retry: noAutomaticProviderRetry')) continue;

        final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
        offenders.add('${entity.path}:$line');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'These async providers do not declare '
          'retry: noAutomaticProviderRetry, so Riverpod 3 will retry them on '
          'failure and their error will never reach the UI. See ADR-032.\n'
          '${offenders.join('\n')}',
    );
  });

  test('the scan is not fooled by brackets inside comments or strings', () {
    const source = '''
final a = FutureProvider<int>((ref) {
  // a stray ( in a comment
  return int.parse(')(');
}, retry: noAutomaticProviderRetry);

final b = FutureProvider<int>((ref) => 0);
''';

    final code = _maskCommentsAndStrings(source);
    final matches = RegExp(
      r'=\s*(FutureProvider|StreamProvider)\b',
    ).allMatches(code).toList();

    expect(matches, hasLength(2));

    final first = code.substring(
      matches[0].start,
      _declarationEnd(code, matches[0].end),
    );
    final second = code.substring(
      matches[1].start,
      _declarationEnd(code, matches[1].end),
    );

    expect(first.contains('retry: noAutomaticProviderRetry'), isTrue);
    expect(
      second.contains('retry: noAutomaticProviderRetry'),
      isFalse,
      reason: 'the second declaration must not absorb the first one\'s policy',
    );
  });
}

/// Replaces the contents of comments and string literals with spaces, leaving
/// every other character and the source's length untouched so offsets computed
/// over the result still address the original.
String _maskCommentsAndStrings(String source) {
  final out = source.split('');
  var i = 0;

  void blank(int from, int to) {
    for (var j = from; j < to && j < out.length; j++) {
      if (out[j] != '\n') out[j] = ' ';
    }
  }

  while (i < source.length) {
    final rest = source.length - i;

    if (rest >= 2 && source.startsWith('//', i)) {
      final end = source.indexOf('\n', i);
      final stop = end == -1 ? source.length : end;
      blank(i, stop);
      i = stop;
      continue;
    }

    if (rest >= 2 && source.startsWith('/*', i)) {
      final end = source.indexOf('*/', i + 2);
      final stop = end == -1 ? source.length : end + 2;
      blank(i, stop);
      i = stop;
      continue;
    }

    final quote = _quoteAt(source, i);
    if (quote != null) {
      final isRaw = i > 0 && source[i - 1] == 'r';
      final contentStart = i + quote.length;
      var j = contentStart;

      while (j < source.length) {
        if (!isRaw && source[j] == r'\') {
          j += 2;
          continue;
        }
        if (source.startsWith(quote, j)) break;
        j++;
      }

      final stop = j >= source.length ? source.length : j + quote.length;
      blank(i, stop);
      i = stop;
      continue;
    }

    i++;
  }

  return out.join();
}

/// Returns the quote delimiter starting at [index], preferring the triple
/// forms, or `null` when the character there does not open a string.
String? _quoteAt(String source, int index) {
  for (final quote in const ["'''", '"""', "'", '"']) {
    if (source.startsWith(quote, index)) return quote;
  }
  return null;
}

/// Returns the offset just past the `)` that closes the provider declaration
/// whose argument list starts at or after [start], by tracking parenthesis
/// depth over code with comments and strings already masked out.
int _declarationEnd(String source, int start) {
  var depth = 0;
  var seenOpen = false;

  for (var i = start; i < source.length; i++) {
    final char = source[i];
    if (char == '(') {
      depth++;
      seenOpen = true;
    } else if (char == ')') {
      depth--;
      if (seenOpen && depth == 0) return i + 1;
    }
  }

  return source.length;
}
