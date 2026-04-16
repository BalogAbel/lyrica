import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

void suppressDriftMultipleDatabaseWarnings() {
  final originalDontWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;

  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalDontWarn;
  });
}

T runWithSuppressedDriftMultipleDatabaseWarnings<T>(T Function() body) {
  final originalDontWarn = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  addTearDown(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = originalDontWarn;
  });
  return body();
}
