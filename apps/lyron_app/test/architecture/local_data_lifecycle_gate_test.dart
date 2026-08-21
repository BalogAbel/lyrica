// Architecture test for Acceptance 8 of
// docs/specs/2026-08-19-local-data-durability-contract.md:
//
//   "Architecture test: LocalDataLifecycle is the sole caller of every
//   purge primitive."
//
// This guards D7 (the purge gate) by source-scanning every .dart file under
// lib/ for direct call-syntax occurrences of the four gated primitives:
//   - SongCatalogStore.deleteCatalogsForUser
//   - PlanningLocalStore.deletePlanningDataForUser
//   - LastKnownIdentityStore.clear()
//   - LastKnownIdentityStore.write()
// and fails if any file outside a small allow-list of definition sites
// (LocalDataLifecycle itself, plus the interface/implementation files that
// declare these methods) contains one. If this test ever fails, a new call
// site has bypassed LocalDataLifecycle and its audit trail -- route it
// through the gate instead of adding it to the allow-list.
//
// This is a plain-text/regex scan, not an AST-based check: the `analyzer`
// package is already a devDependency (see pubspec.yaml, used by
// test/application/provider_retry_policy_test.dart) but a full parse is
// unnecessary machinery for a handful of narrow, fixed call patterns. See
// the false-positive/negative notes on each pattern below.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One purge-primitive call pattern this test guards, and the files
/// permitted to contain it (the primitive's own definition site -- not a
/// caller).
class _GatedPattern {
  const _GatedPattern({
    required this.name,
    required this.regex,
    required this.allowedFiles,
  });

  final String name;
  final RegExp regex;

  /// Paths relative to the `lib/` directory, using forward slashes.
  final Set<String> allowedFiles;
}

void main() {
  test(
    'LocalDataLifecycle is the sole caller of every purge primitive '
    '(Acceptance 8)',
    () {
      final patterns = <_GatedPattern>[
        _GatedPattern(
          name: 'SongCatalogStore.deleteCatalogsForUser',
          // Anchored on a leading `.` so this only matches an invocation
          // (`someStore.deleteCatalogsForUser(...)`), never the method's own
          // declaration (`Future<void> deleteCatalogsForUser(...)`), which
          // has no receiver and thus no leading dot.
          regex: RegExp(r'\.deleteCatalogsForUser\('),
          allowedFiles: {
            'src/application/storage/local_data_lifecycle.dart',
            'src/offline/song_catalog/song_catalog_store.dart',
          },
        ),
        _GatedPattern(
          name: 'PlanningLocalStore.deletePlanningDataForUser',
          regex: RegExp(r'\.deletePlanningDataForUser\('),
          allowedFiles: {
            'src/application/storage/local_data_lifecycle.dart',
            'src/offline/planning/planning_local_store.dart',
          },
        ),
        _GatedPattern(
          name: 'LastKnownIdentityStore.clear()',
          // `.clear()` alone is far too common a method name on unrelated
          // types (collections, controllers, ...) to match bare. Scope it
          // to receivers whose text contains "identityStore"
          // (case-insensitive), matching how the one legitimate call site
          // (LocalDataLifecycle._identityStore.clear()) and the interface's
          // implementer name it. Every non-gate identity-store handle in
          // this codebase (`_identityStore`, `_lastKnownIdentityStore`, ...)
          // follows this convention.
          regex: RegExp(r'identityStore\.clear\(\)', caseSensitive: false),
          allowedFiles: {
            'src/application/storage/local_data_lifecycle.dart',
            'src/offline/auth/drift_last_known_identity_store.dart',
            'src/application/auth/last_known_identity.dart',
          },
        ),
        _GatedPattern(
          name: 'LastKnownIdentityStore.write()',
          regex: RegExp(r'identityStore\.write\(', caseSensitive: false),
          allowedFiles: {
            'src/application/storage/local_data_lifecycle.dart',
            'src/offline/auth/drift_last_known_identity_store.dart',
            'src/application/auth/last_known_identity.dart',
          },
        ),
      ];

      final violations = <String>[];

      final libDir = Directory('lib');
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .where((file) => !file.path.endsWith('.g.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final file in dartFiles) {
        // Path relative to lib/, forward-slash-normalized, to match
        // _GatedPattern.allowedFiles regardless of host OS separators.
        final relativePath = file.path
            .substring(libDir.path.length)
            .replaceAll(r'\', '/')
            .replaceFirst(RegExp(r'^/'), '');
        final libRelativePath = 'lib/$relativePath';

        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final rawLine = lines[i];
          // Strip everything from the first `//` onward so that a call
          // pattern merely mentioned in a comment (e.g. explaining what
          // LocalDataLifecycle does) is not mistaken for a real call site.
          // This is a plain-text heuristic: it does not understand string
          // literals, so a `//` inside a string on the same line as a real
          // call would (incorrectly) hide that call. None of the current
          // lib/ source does this for these patterns.
          final codeOnly = rawLine.split('//').first;

          for (final pattern in patterns) {
            if (!pattern.regex.hasMatch(codeOnly)) continue;
            if (pattern.allowedFiles.contains(relativePath)) continue;
            violations.add(
              '$libRelativePath:${i + 1}: found "${pattern.name}" call '
              'outside LocalDataLifecycle -- route this through '
              'LocalDataLifecycle instead of calling the primitive '
              'directly.\n    ${rawLine.trim()}',
            );
          }
        }
      }

      expect(
        violations,
        isEmpty,
        reason:
            'LocalDataLifecycle must be the sole caller of every purge '
            'primitive (Acceptance 8). Violations found:\n\n'
            '${violations.join('\n\n')}',
      );
    },
  );
}
