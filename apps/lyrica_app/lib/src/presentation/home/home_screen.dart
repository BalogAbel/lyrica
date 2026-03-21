import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyrica_app/src/application/providers.dart';
import 'package:lyrica_app/src/shared/app_strings.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncOverview = ref.watch(syncOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            AppStrings.appTagline,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Text(
            'Architecture foundation',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text('Capabilities are enforced in Supabase/Postgres.'),
          const SizedBox(height: 12),
          Text('Local store: ${syncOverview.storeContract.engine}'),
          Text('Read strategy: ${syncOverview.storeContract.readStrategy}'),
          Text(
            'Conflict resolution: ${syncOverview.policy.conflictResolution.name}',
          ),
          Text(
            'Offline window: ${syncOverview.policy.maxOfflineWindow.inDays} days',
          ),
        ],
      ),
    );
  }
}
