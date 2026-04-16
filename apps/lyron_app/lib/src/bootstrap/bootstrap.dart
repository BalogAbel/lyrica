import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/app/lyron_app.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/infrastructure/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(url: config.url, anonKey: config.anonKey);
  runApp(const _BootstrapScope(child: LyronApp()));
}

class _BootstrapScope extends StatefulWidget {
  const _BootstrapScope({required this.child});

  final Widget child;

  @override
  State<_BootstrapScope> createState() => _BootstrapScopeState();
}

class _BootstrapScopeState extends State<_BootstrapScope> {
  @override
  void dispose() {
    unawaited(closeSharedDatabases());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: widget.child);
  }
}
