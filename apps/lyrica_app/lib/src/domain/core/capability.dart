enum Capability {
  viewSongs('canViewSongs'),
  editSongs('canEditSongs'),
  manageOrganizationMembers('canManageOrganizationMembers'),
  manageGroupMembers('canManageGroupMembers'),
  editSessions('canEditSessions'),
  managePlans('canManagePlans');

  const Capability(this.code);

  final String code;
}
