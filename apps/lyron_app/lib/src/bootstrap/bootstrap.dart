import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(url: config.url, anonKey: config.anonKey);
  runApp(ProviderScope(child: LyronApp()));
}
