import 'package:flutter_test/flutter_test.dart';
import 'package:lyron_app/src/domain/core/capability.dart';

void main() {
  test('capability codes stay aligned with backend policy names', () {
    expect(Capability.viewSongs.code, 'canViewSongs');
    expect(Capability.editSongs.code, 'canEditSongs');
    expect(
      Capability.manageOrganizationMembers.code,
      'canManageOrganizationMembers',
    );
    expect(Capability.manageGroupMembers.code, 'canManageGroupMembers');
    expect(Capability.editSessions.code, 'canEditSessions');
    expect(Capability.managePlans.code, 'canManagePlans');
  });
}
