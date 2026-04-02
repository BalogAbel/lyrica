import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

QueryExecutor openSongCatalogConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'lyron_song_catalog.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

QueryExecutor openInMemorySongCatalogConnection() {
  return NativeDatabase.memory();
}
