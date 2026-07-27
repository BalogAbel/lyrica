import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Formats a stored UTC instant as a local date and time string, using the
/// ambient [MaterialLocalizations]. Shared between [ScheduledForField] and
/// any other place that renders a plan's scheduled-for instant, so the two
/// can never disagree on formatting.
String formatScheduledForInstant(BuildContext context, DateTime utcInstant) {
  final localizations = MaterialLocalizations.of(context);
  final local = utcInstant.toLocal();
  final date = localizations.formatMediumDate(local);
  final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
  return '$date $time';
}

/// Edits an optional "scheduled for" instant through the Material date and
/// time pickers, keeping the persisted UTC instant and the displayed local
/// time in agreement.
///
/// [value] is a UTC instant (or null when unscheduled). [onChanged] is
/// called with a new UTC instant when the user completes both pickers, or
/// with null when the value is cleared. Cancelling either picker leaves the
/// value untouched.
class ScheduledForField extends StatelessWidget {
  const ScheduledForField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final currentValue = value;
    final label = currentValue == null
        ? AppStrings.planScheduledForEmptyLabel
        : formatScheduledForInstant(context, currentValue);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppStrings.planScheduledForLabel,
                style: Theme.of(context).textTheme.labelMedium,
              ),
              Text(label),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey('scheduled-for-pick'),
          onPressed: () => _pick(context),
          child: const Text(AppStrings.planScheduledForPickAction),
        ),
        if (currentValue != null)
          IconButton(
            key: const ValueKey('scheduled-for-clear'),
            tooltip: AppStrings.planScheduledForClearAction,
            icon: const Icon(Icons.clear),
            onPressed: () => onChanged(null),
          ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final seedLocal = value?.toLocal() ?? now;

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: seedLocal,
      firstDate: DateTime(now.year - 5, now.month, now.day),
      lastDate: DateTime(now.year + 5, now.month, now.day),
    );
    if (pickedDate == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(seedLocal),
    );
    if (pickedTime == null) {
      return;
    }

    final combinedLocal = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    onChanged(combinedLocal.toUtc());
  }
}
