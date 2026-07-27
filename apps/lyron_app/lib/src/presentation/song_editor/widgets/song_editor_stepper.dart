import 'package:flutter/material.dart';

class SongEditorStepper extends StatelessWidget {
  const SongEditorStepper({
    super.key,
    required this.label,
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
    required this.enabled,
  });

  final String label;
  final String value;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 10),
        OutlinedButton(
          key: Key('${label.toLowerCase()}-decrease'),
          onPressed: enabled ? onDecrease : null,
          child: const Text('-'),
        ),
        const SizedBox(width: 8),
        Chip(label: Text(value)),
        const SizedBox(width: 8),
        OutlinedButton(
          key: Key('${label.toLowerCase()}-increase'),
          onPressed: enabled ? onIncrease : null,
          child: const Text('+'),
        ),
      ],
    );
  }
}
