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

      for (final match in declaration.allMatches(source)) {
        final end = _declarationEnd(source, match.end);
        final body = source.substring(match.start, end);

        if (body.contains('retry: noAutomaticProviderRetry')) continue;

        final line = '\n'.allMatches(source.substring(0, match.start)).length + 1;
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
}

/// Returns the offset of the `)` that closes the provider declaration whose
/// argument list starts at or after [start], by tracking parenthesis depth.
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
