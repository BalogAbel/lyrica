import 'package:flutter/material.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<void> showImportSummaryDialog({
  required BuildContext context,
  required ImportBatchResult result,
  required int skippedCount,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) =>
        _ImportSummaryDialog(result: result, skippedCount: skippedCount),
  );
}

class _ImportSummaryDialog extends StatelessWidget {
  const _ImportSummaryDialog({
    required this.result,
    required this.skippedCount,
  });

  final ImportBatchResult result;
  final int skippedCount;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.songImportSummaryTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CountRow(
                label: AppStrings.songImportSummaryImportedLabel,
                count: result.successes.length,
              ),
              _CountRow(
                label: AppStrings.songImportSummarySkippedLabel,
                count: skippedCount,
              ),
              _CountRow(
                label: AppStrings.songImportSummaryErrorsLabel,
                count: result.errors.length,
              ),
              if (result.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(),
                ...result.errors.map(
                  (e) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          e.filename,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          e.reason,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStrings.songImportSummaryDoneAction),
        ),
      ],
    );
  }
}

class _CountRow extends StatelessWidget {
  const _CountRow({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [Text(label), const Spacer(), Text('$count')]),
    );
  }
}
