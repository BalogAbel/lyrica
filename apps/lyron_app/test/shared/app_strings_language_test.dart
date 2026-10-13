// Language guard for the UI strings (S6a FB15, acceptance criterion L2).
//
// The UI language is English for now (docs/product/vision.md); localization is
// a later product decision. `AppStrings` is the single home of UI copy, so a
// Hungarian accented letter in it means a Hungarian string slipped back in.
//
// The guard is a plain-text scan of `lib/src/shared/app_strings.dart` (the
// test's working directory is the app directory, `apps/lyron_app`). It covers
// `AppStrings` only: song titles in `asset_song_repository.dart` and the
// accent-folding map in `song_catalog_store.dart` are song data, not UI, and
// are intentionally out of scope.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppStrings contains no Hungarian accented letters (UI is English)', () {
    final file = File('lib/src/shared/app_strings.dart');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'run from apps/lyron_app: ${file.absolute.path} must exist',
    );

    final hungarianLetter = RegExp('[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]');
    final lines = file.readAsLinesSync();

    // Guards the guard: a truncated or wrong file would otherwise pass.
    expect(lines.any((line) => line.contains('class AppStrings')), isTrue);

    final violations = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!hungarianLetter.hasMatch(lines[i])) continue;
      violations.add('app_strings.dart:${i + 1}: ${lines[i].trim()}');
    }

    expect(
      violations,
      isEmpty,
      reason:
          'AppStrings is the English UI copy; found Hungarian text:\n'
          '${violations.join('\n')}',
    );
  });
}
