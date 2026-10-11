import 'package:lyron_app/src/shared/app_strings.dart';

/// SG7: relative "last synced" copy. [at] is a device wall-clock value used
/// for display only (ADR-030); a time after [now] reads as "just now".
String formatLastSynced(DateTime? at, {required DateTime now}) {
  if (at == null) {
    return AppStrings.unifiedSyncLastSyncedNever;
  }
  final elapsed = now.difference(at);
  if (elapsed.inMinutes < 1) {
    return AppStrings.unifiedSyncLastSyncedJustNow;
  }
  if (elapsed.inHours < 1) {
    return AppStrings.unifiedSyncLastSyncedMinutesAgo(elapsed.inMinutes);
  }
  if (elapsed.inDays < 1) {
    return AppStrings.unifiedSyncLastSyncedHoursAgo(elapsed.inHours);
  }
  return AppStrings.unifiedSyncLastSyncedDaysAgo(elapsed.inDays);
}
