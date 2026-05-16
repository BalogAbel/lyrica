import 'package:flutter/material.dart';
import 'package:lyron_app/src/application/song_library/chordpro_import_types.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

Future<List<ResolvedDuplicate>?> showImportDuplicateDialog({
  required BuildContext context,
  required List<ImportDuplicate> duplicates,
}) {
  return showDialog<List<ResolvedDuplicate>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportDuplicateDialog(duplicates: duplicates),
  );
}

class _ImportDuplicateDialog extends StatefulWidget {
  const _ImportDuplicateDialog({required this.duplicates});

  final List<ImportDuplicate> duplicates;

  @override
  State<_ImportDuplicateDialog> createState() => _ImportDuplicateDialogState();
}

class _ImportDuplicateDialogState extends State<_ImportDuplicateDialog> {
  late final List<DuplicateResolution> _resolutions;

  @override
  void initState() {
    super.initState();
    _resolutions = List.filled(
      widget.duplicates.length,
      DuplicateResolution.skip,
    );
  }

  void _applyAll(DuplicateResolution resolution) {
    setState(() {
      for (var i = 0; i < _resolutions.length; i++) {
        _resolutions[i] = resolution;
      }
    });
  }

  List<ResolvedDuplicate> _buildResult() {
    return [
      for (var i = 0; i < widget.duplicates.length; i++)
        ResolvedDuplicate(
          duplicate: widget.duplicates[i],
          resolution: _resolutions[i],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStrings.songImportDuplicateDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppStrings.songImportDuplicateDialogMessage),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: () => _applyAll(DuplicateResolution.overwrite),
                  child: const Text(
                    AppStrings.songImportDuplicateOverwriteAllAction,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _applyAll(DuplicateResolution.skip),
                  child: const Text(
                    AppStrings.songImportDuplicateSkipAllAction,
                  ),
                ),
              ],
            ),
            const Divider(),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.duplicates.length,
                itemBuilder: (context, index) {
                  final dup = widget.duplicates[index];
                  final resolution = _resolutions[index];
                  return _DuplicateRow(
                    duplicate: dup,
                    resolution: resolution,
                    onChanged: (value) {
                      setState(() => _resolutions[index] = value);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_buildResult()),
          child: const Text(AppStrings.songImportDuplicateConfirmAction),
        ),
      ],
    );
  }
}

class _DuplicateRow extends StatelessWidget {
  const _DuplicateRow({
    required this.duplicate,
    required this.resolution,
    required this.onChanged,
  });

  final ImportDuplicate duplicate;
  final DuplicateResolution resolution;
  final ValueChanged<DuplicateResolution> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(duplicate.incomingTitle)),
          SegmentedButton<DuplicateResolution>(
            segments: const [
              ButtonSegment(
                value: DuplicateResolution.overwrite,
                label: Text(AppStrings.songImportDuplicateOverwriteAction),
              ),
              ButtonSegment(
                value: DuplicateResolution.skip,
                label: Text(AppStrings.songImportDuplicateSkipAction),
              ),
            ],
            selected: {resolution},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) onChanged(selection.first);
            },
          ),
        ],
      ),
    );
  }
}
