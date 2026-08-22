// Architecture test guarding the web build against an accidental
// `dart:ffi` dependency creeping into unconditionally-imported lib/ code.
//
// `package:sqlite3/sqlite3.dart` (the native FFI binding) transitively
// imports `dart:ffi`, which does not exist on the web compiler target. This
// codebase already has an established platform-split idiom for code that
// genuinely needs native sqlite3 (see e.g.
// lib/src/offline/song_catalog/song_catalog_database_connection.dart, which
// uses a `dart.library.io`-conditional import so the native-only branch is
// never reached by the web compiler). Anything that is NOT behind such a
// conditional import must use the shared, ffi+wasm-safe
// `package:sqlite3/common.dart` surface instead (same public API for types
// like `SqliteException`).
//
// This regression-guards the bug fixed in ADR-028's Task 3.4 amendment:
// local_storage_write_recovery.dart imported sqlite3.dart directly to get
// `SqliteException`, which broke `flutter build web --release` outright
// ("Dart library 'dart:ffi' is not available on this platform") because the
// file is reached unconditionally from song_catalog_store.dart -> providers
// -> main.dart.
//
// This is a plain-text scan, matching the style and rationale of
// local_data_lifecycle_gate_test.dart in this same directory.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'no lib/ file imports package:sqlite3/sqlite3.dart directly '
    '(that pulls in dart:ffi and breaks the web build)',
    () {
      final forbiddenImport = RegExp(
        r'''import\s+['"]package:sqlite3/sqlite3\.dart['"]''',
      );

      final violations = <String>[];

      final libDir = Directory('lib');
      final dartFiles =
          libDir
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where((file) => !file.path.endsWith('.g.dart'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in dartFiles) {
        final relativePath = file.path
            .substring(libDir.path.length)
            .replaceAll(r'\', '/')
            .replaceFirst(RegExp(r'^/'), '');
        final libRelativePath = 'lib/$relativePath';

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final rawLine = lines[i];
          final codeOnly = rawLine.split('//').first;
          if (!forbiddenImport.hasMatch(codeOnly)) continue;
          violations.add(
            '$libRelativePath:${i + 1}: imports '
            'package:sqlite3/sqlite3.dart directly -- this pulls in '
            "dart:ffi and will break 'flutter build web'. Use "
            'package:sqlite3/common.dart instead (same public API, '
            'ffi+wasm-safe), or move the native-only code behind a '
            'dart.library.io-conditional import if it genuinely needs '
            'FFI-only functionality.\n    ${rawLine.trim()}',
          );
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'lib/ must stay buildable for web (no unconditional dart:ffi '
            'dependency). Violations found:\n\n'
            '${violations.join('\n\n')}',
      );
    },
  );
}
