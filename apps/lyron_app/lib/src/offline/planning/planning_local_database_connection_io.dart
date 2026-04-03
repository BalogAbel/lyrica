import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openPlanningLocalConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lyron_planning.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

QueryExecutor openInMemoryPlanningLocalConnection() {
  return NativeDatabase.memory();
}
