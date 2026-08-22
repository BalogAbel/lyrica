import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lyron_app/src/application/auth_providers.dart';
import 'package:lyron_app/src/presentation/planning/widgets/retryable_error_state.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Read-only diagnostics screen rendering the `local_data_events` audit log:
/// when a purge/eviction happened, why, and (once a later phase wires row
/// counts into the store primitives) how much data it touched.
class LocalDataEventsScreen extends ConsumerWidget {
  const LocalDataEventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(localDataEventsRecordsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.localDataEventsTitle)),
      body: recordsAsync.when(
        data: (records) {
          if (records.isEmpty) {
            return const Center(
              child: Text(AppStrings.localDataEventsEmptyMessage),
            );
          }
          return ListView.builder(
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return ListTile(
                title: Text(record.target),
                subtitle: Text(
                  '${_formatOccurredAt(record.occurredAt)} · '
                  '${record.kind} · '
                  '${record.reason ?? '—'}',
                ),
                trailing: Text(
                  record.rowsAffected == null
                      ? 'unknown'
                      : '${record.rowsAffected}',
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => RetryableErrorState(
          message: AppStrings.localDataEventsLoadErrorMessage,
          onRetry: () => ref.invalidate(localDataEventsRecordsProvider),
        ),
      ),
    );
  }
}

/// Manual ISO-ish formatting: `intl` is not a dependency of this app, and
/// this diagnostics screen doesn't warrant adding one.
String _formatOccurredAt(DateTime occurredAt) {
  final local = occurredAt.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
}
