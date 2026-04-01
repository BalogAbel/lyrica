import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.appName)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            AppStrings.songLibraryHeading,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          Text(
            AppStrings.songLibraryFlowHeading,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(AppStrings.songLibraryFlowSummary),
        ],
      ),
    );
  }
}
