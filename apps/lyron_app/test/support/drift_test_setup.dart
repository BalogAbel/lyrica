import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

void suppressDriftMultipleDatabaseWarnings() {
  final originalDontWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalDontWarn;
  });
}

Future<T> runWithSuppressedDriftMultipleDatabaseWarnings<T>(
  FutureOr<T> Function() body,
) async {
  final originalDontWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  try {
    return await body();
  } finally {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalDontWarn;
  }
}

ProviderScope isolatedSongCatalogProviderScope({
  required Widget child,
  List<Override> overrides = const [],
}) {
  final database = SongCatalogDatabase.inMemory();
  addTearDown(database.close);
  return ProviderScope(
    overrides: [
      songCatalogDatabaseProvider.overrideWithValue(database),
      ...overrides,
    ],
    child: child,
  );
}
