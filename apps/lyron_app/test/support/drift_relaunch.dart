import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

/// Creates a temp directory + a sqlite file path for a relaunch-style test.
Future<File> createRelaunchDbFile(String name) async {
  final dir = await Directory.systemTemp.createTemp(name);
  return File(p.join(dir.path, '$name.sqlite'));
}

/// Opens a native executor over [file]. Call once per "launch"; close the
/// returned database, then call again on the same [file] to simulate relaunch.
NativeDatabase openRelaunchExecutor(File file) => NativeDatabase(file);
