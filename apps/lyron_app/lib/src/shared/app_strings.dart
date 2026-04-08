class AppStrings {
  const AppStrings._();

  static const appName = 'Lyron Chords';
  static const signInTitle = 'Sign in';
  static const signInSummary =
      'Use the local demo account to load backend songs.';
  static const restoringSessionMessage = 'Restoring session...';
  static const signInAction = 'Continue';
  static const emailLabel = 'Email';
  static const passwordLabel = 'Password';
  static const sessionExpiredMessage =
      'Your session expired. Please sign in again.';
  static const retryAction = 'Try again';
  static const signOutAction = 'Sign out';
  static const songCatalogRefreshAction = 'Refresh catalog';
  static const songMutationSyncAction = 'Sync changes';
  static const songCreateAction = 'Add song';
  static const songEditAction = 'Edit song';
  static const songDeleteAction = 'Delete song';
  static const songSaveAction = 'Save';
  static const songCancelAction = 'Cancel';
  static const songTitleLabel = 'Title';
  static const songSourceLabel = 'ChordPro source';
  static const unsyncedSignOutTitle = 'Discard unsynced changes?';
  static const unsyncedSignOutMessage =
      'You have unsynced modifications. Signing out will permanently discard these changes.';
  static const unsyncedSignOutConfirmAction = 'Discard and sign out';
  static const songDeleteBlockedMessage =
      'This song cannot be deleted because a session still references it.';
  static const songConflictTitle = 'Song conflict';
  static const songConflictMessage =
      'A song was modified elsewhere. Keep your version or discard it and pull the latest server version.';
  static const songKeepMineAction = 'Keep mine';
  static const songDiscardMineAction = 'Discard mine';
  static const songListLoadingMessage = 'Loading songs...';
  static const songListLoadFailureMessage =
      'Unable to load songs. Please try again.';
  static const songListEmptyMessage = 'No songs available.';
  static const songCatalogOnlineStatus = 'Online. Songs are up to date.';
  static const songCatalogOfflineStatus = 'Offline. Showing cached songs.';
  static const songCatalogRefreshingStatus = 'Refreshing song catalog...';
  static const songCatalogRefreshFailedStatus =
      'Unable to refresh songs. Showing the last cached catalog.';
  static const songCatalogUnavailableMessage =
      'No cached song catalog is available yet.';
  static const songReaderLoadingMessage = 'Loading song...';
  static const songReaderLoadFailureMessage =
      'Unable to load song. Please try again.';
  static const songReaderUnavailableMessage = 'This song is unavailable.';
  static const songReaderAccessDeniedMessage =
      'You do not have access to this song.';
  static const routeNotFoundMessage = 'The requested page was not found.';
  static const songReaderBackAction = 'Back to song list';
  static const planDetailUnavailableMessage = 'This plan is unavailable.';
  static const scopedReaderRouteUnavailableMessage =
      'This session-scoped reader route is unavailable.';
  static const scopedReaderPreviousAction = 'Previous song';
  static const scopedReaderNextAction = 'Next song';
  static const scopedReaderContextUnavailableMessage =
      'This session-scoped reader context is unavailable.';
  static const planningEntryAction = 'Plans';
  static const planListTitle = 'Plans';
  static const planListLoadingMessage = 'Loading plans...';
  static const planListLoadFailureMessage =
      'Unable to load plans. Please try again.';
  static const planListEmptyMessage = 'No plans available.';
  static const planListUnscheduledLabel = 'Unscheduled';
  static const planDetailTitle = 'Plan detail';
  static const planDetailLoadingMessage = 'Loading plan...';
  static const planDetailLoadFailureMessage =
      'Unable to load plan. Please try again.';
  static const sessionLabel = 'Session';
  static const songLibraryHeading = 'Tablet-first song library';
  static const songLibraryFlowHeading = 'Mock song catalog in progress';
  static const songLibraryFlowSummary =
      'This shell anchors the tablet-first song reader slice';
}
