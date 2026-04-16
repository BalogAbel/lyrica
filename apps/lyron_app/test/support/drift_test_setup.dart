import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/offline/planning/planning_local_database.dart';
import 'package:lyron_app/src/offline/song_catalog/song_catalog_database.dart';

void suppressDriftMultipleDatabaseWarnings() {
  late bool originalDontWarn;

  setUpAll(() {
    originalDontWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
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
  SongCatalogDatabase? songCatalogDatabase,
  PlanningLocalDatabase? planningLocalDatabase,
}) {
  final effectiveSongCatalogDatabase =
      songCatalogDatabase ?? SongCatalogDatabase.inMemory();
  final effectivePlanningLocalDatabase =
      planningLocalDatabase ?? PlanningLocalDatabase.inMemory();
  addTearDown(() async {
    await Future.wait([
      if (songCatalogDatabase == null) effectiveSongCatalogDatabase.close(),
      if (planningLocalDatabase == null) effectivePlanningLocalDatabase.close(),
    ]);
  });
  return ProviderScope(
    overrides: [
      songCatalogDatabaseProvider.overrideWithValue(
        effectiveSongCatalogDatabase,
      ),
      planningLocalDatabaseProvider.overrideWithValue(
        effectivePlanningLocalDatabase,
      ),
      ...overrides,
    ],
    child: child,
  );
}
