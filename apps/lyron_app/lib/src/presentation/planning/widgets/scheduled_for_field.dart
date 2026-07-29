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

    // The five-year window is the useful planning range, but it must never
    // exclude the value the plan already holds: `showDatePicker` asserts that
    // `initialDate` lies within `firstDate`..`lastDate`, so a plan scheduled
    // outside the window would crash the picker instead of opening on its own
    // date. Stretch whichever bound the stored value falls outside of.
    final seedDate = DateUtils.dateOnly(seedLocal);
    var firstDate = DateTime(now.year - 5, now.month, now.day);
    var lastDate = DateTime(now.year + 5, now.month, now.day);
    if (seedDate.isBefore(firstDate)) {
      firstDate = seedDate;
    }
    if (seedDate.isAfter(lastDate)) {
      lastDate = seedDate;
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: seedLocal,
      firstDate: firstDate,
      lastDate: lastDate,
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

    // Built with the local `DateTime` constructor so the picked wall-clock
    // time is interpreted in the user's zone before conversion to UTC.
    // Known limitation: on a DST spring-forward day the picked time can name
    // an instant that does not exist locally (e.g. 02:30 where the clock
    // jumps 02:00 -> 03:00). Dart normalizes it forward rather than failing,
    // so the stored instant is one hour later than the label the user picked.
    // Rehearsals are not scheduled inside that gap in practice, and rejecting
    // the pick would be worse than shifting it.
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
