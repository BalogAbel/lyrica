import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/presentation/sync/last_synced_format.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

void main() {
  final now = DateTime(2026, 10, 5, 12);

  test('formats a last-synced time relative to now (SG7)', () {
    expect(
      formatLastSynced(null, now: now),
      AppStrings.unifiedSyncLastSyncedNever,
    );
    expect(
      formatLastSynced(now.subtract(const Duration(seconds: 30)), now: now),
      AppStrings.unifiedSyncLastSyncedJustNow,
    );
    expect(
      formatLastSynced(now.subtract(const Duration(minutes: 5)), now: now),
      AppStrings.unifiedSyncLastSyncedMinutesAgo(5),
    );
    expect(
      formatLastSynced(now.subtract(const Duration(hours: 3)), now: now),
      AppStrings.unifiedSyncLastSyncedHoursAgo(3),
    );
    expect(
      formatLastSynced(now.subtract(const Duration(days: 2)), now: now),
      AppStrings.unifiedSyncLastSyncedDaysAgo(2),
    );
  });

  test('a time in the future (clock moved back) reads as just now', () {
    expect(
      formatLastSynced(now.add(const Duration(hours: 1)), now: now),
      AppStrings.unifiedSyncLastSyncedJustNow,
    );
  });

  test('one day reads in the singular', () {
    expect(AppStrings.unifiedSyncLastSyncedDaysAgo(1), '1 day ago');
  });
}
