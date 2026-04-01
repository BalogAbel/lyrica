import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/offline/sync_policy.dart';

void main() {
  test('manual conflict resolution is retained for MVP', () {
    expect(defaultSyncPolicy.conflictResolution, ConflictResolution.manual);
    expect(defaultSyncPolicy.maxOfflineWindow, const Duration(days: 7));
  });
}
