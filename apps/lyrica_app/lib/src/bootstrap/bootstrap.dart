import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/app/lyrica_app.dart';

void bootstrap() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(child: LyricaApp()));
}
