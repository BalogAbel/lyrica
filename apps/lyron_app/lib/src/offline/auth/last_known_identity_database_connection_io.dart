import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openLastKnownIdentityConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lyron_last_known_identity.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

QueryExecutor openInMemoryLastKnownIdentityConnection() {
  return NativeDatabase.memory();
}
