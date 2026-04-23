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
  static const songSyncIssueTitle = 'Song sync issue';
  static const songKeepMineAction = 'Keep mine';
  static const songDiscardMineAction = 'Discard mine';
  static const songListLoadingMessage = 'Loading songs...';
  static const songListLoadFailureMessage =
      'Unable to load songs. Please try again.';
  static const songListMutationStatusLoadingMessage = 'Loading song status...';
  static const songListMutationStatusFailedMessage =
      'Song status could not load. Showing songs without operational filters.';
  static const songListEmptyMessage = 'No songs available.';
  static const songListNoResultsMessage = 'No songs match your current search.';
  static const songListSearchLabel = 'Search songs';
  static const songListSearchHint = 'Type a title...';
  static const songLibraryFilterAllLabel = 'All';
  static const songLibraryFilterPendingSyncLabel = 'Pending sync';
  static const songLibraryFilterConflictsLabel = 'Conflicts';
  static const sessionItemSongPickerSearchLabel = 'Search songs';
  static const sessionItemSongPickerSearchHint = 'Type a title...';
  static const sessionItemSongPickerLoadingMessage =
      'Loading eligible songs...';
  static const sessionItemSongPickerUnavailableMessage =
      'This picker is unavailable until a local song catalog is ready.';
  static const sessionItemSongPickerNoResultsMessage =
      'No eligible songs match your search.';
  static const sessionItemSongPickerEmptyMessage =
      'All visible songs are already present in this session.';
  static const sessionItemSongPickerAddInProgressMessage = 'Adding song...';
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
  static const songReaderDeletedTitle = 'Deleted song';
  static const songReaderDeletedMessage =
      'This song was removed from the canonical library. Planning still keeps the preserved reference title.';
  static const songReaderDeletedConflictMessage =
      'This song was removed from the canonical library while your local changes were still unresolved.';
  static const songReaderAccessDeniedMessage =
      'You do not have access to this song.';
  static const songReaderTitle = 'Song reader';
  static const routeNotFoundMessage = 'The requested page was not found.';
  static const songReaderBackAction = 'Back to song list';
  static const songReaderViewSectionLabel = 'View';
  static const songReaderTransposeSectionLabel = 'Transpose';
  static const songReaderCapoSectionLabel = 'Capo';
  static const songReaderScaleSectionLabel = 'Scale';
  static const songReaderLyricsOnlyAction = 'Lyrics only';
  static const songReaderChordsAndLyricsAction = 'Chords + lyrics';
  static const songReaderGuitarViewAction = 'Guitar View';
  static const songReaderPianoViewAction = 'Piano View';
  static const songReaderCapoDirectivePrefix = 'Capo ';
  static const songReaderShowControlsSemantics = 'Show reader controls';
  static const songReaderHideControlsSemantics = 'Hide reader controls';
  static const planDetailUnavailableMessage = 'This plan is unavailable.';
  static const scopedReaderRouteUnavailableMessage =
      'This session-scoped reader route is unavailable.';
  static const scopedReaderSetContextTitle = 'Set context';
  static const scopedReaderCurrentSongLabel = 'Current song';
  static const scopedReaderPreviousLabel = 'Previous';
  static const scopedReaderPreviousAction = 'Previous song';
  static const scopedReaderNextLabel = 'Next';
  static const scopedReaderNextAction = 'Next song';
  static const scopedReaderNoNeighborLabel = 'None';
  static const scopedReaderContextUnavailableMessage =
      'This session-scoped reader context is unavailable.';
  static const planningEntryAction = 'Plans';
  static const planListTitle = 'Plans';
  static const planCreateAction = 'Create plan';
  static const planSaveAction = 'Save';
  static const planNameLabel = 'Plan name';
  static const planDescriptionLabel = 'Description';
  static const planScheduledForLabel = 'Scheduled for (UTC ISO-8601)';
  static const planScheduledForInvalidMessage =
      'Enter a valid UTC ISO-8601 timestamp or leave the field empty.';
  static const planEditorTitleCreate = 'Create plan';
  static const planEditorTitleEdit = 'Edit plan';
  static const planListLoadingMessage = 'Loading plans...';
  static const planListLoadFailureMessage =
      'Unable to load plans. Please try again.';
  static const planListEmptyMessage = 'No plans available.';
  static const planListUnscheduledLabel = 'Unscheduled';
  static const planMutationPendingMessage =
      'Planning changes are pending sync.';
  static const planConflictMessage =
      'Planning changes conflict with a newer server version.';
  static const planAuthorizationRevokedMessage =
      'Planning sync is blocked because edit access was revoked.';
  static const planRemoteMissingMessage =
      'Planning sync could not find the target item on the server.';
  static const planDetailTitle = 'Plan detail';
  static const planEditAction = 'Edit plan';
  static const sessionCreateAction = 'Add session';
  static const sessionMoveUpAction = 'Move session up';
  static const sessionMoveDownAction = 'Move session down';
  static const sessionRenameAction = 'Rename session';
  static const sessionDeleteAction = 'Delete session';
  static const sessionItemAddSongAction = 'Add song';
  static const sessionItemMoveUpAction = 'Move item up';
  static const sessionItemMoveDownAction = 'Move item down';
  static const sessionItemDeleteAction = 'Delete item';
  static const sessionItemSongPickerTitle = 'Add song to session';
  static const sessionItemSongUnavailableMessage =
      'Offline song add is unavailable until a local song catalog is available.';
  static const sessionDeleteConfirmTitle = 'Delete empty session?';
  static const sessionDeleteConfirmMessage =
      'This removes the local session immediately and syncs the delete when possible.';
  static const sessionDeleteConfirmAction = 'Delete session';
  static const sessionDeleteBlockedMessage =
      'This session cannot be deleted because it is no longer empty.';
  static const sessionNameLabel = 'Session name';
  static const sessionEditorTitleCreate = 'Add session';
  static const sessionEditorTitleRename = 'Rename session';
  static const planDetailLoadingMessage = 'Loading plan...';
  static const planDetailLoadFailureMessage =
      'Unable to load plan. Please try again.';
  static const sessionLabel = 'Session';
  static const songLibraryHeading = 'Tablet-first song library';
  static const songLibraryFlowHeading = 'Mock song catalog in progress';
  static const songLibraryFlowSummary =
      'This shell anchors the tablet-first song reader slice';
}
