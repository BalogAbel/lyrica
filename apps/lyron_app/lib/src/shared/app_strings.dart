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
  static const reauthRequiredMessage =
      'You are offline. Sign in again to sync your changes.';
  static const reauthSignInAction = 'Sign in';
  static const continueOfflineAction = 'Continue offline';
  static const reauthDifferentUserTitle = 'A different account signed in.';
  static String reauthDifferentUserPendingMessage({
    required String email,
    required int count,
  }) => count == 1
      ? 'A different account signed in. $email has 1 unsynced change. Continuing deletes it.'
      : 'A different account signed in. $email has $count unsynced changes. Continuing deletes them.';
  static String reauthDifferentUserUnknownPendingMessage({
    required String email,
  }) =>
      'A different account signed in. $email has unsynced changes on this device, but their exact number could not be determined. Continuing deletes them.';
  static const reauthConfirmWipeAction = 'Continue';
  static const reauthCancelAction = 'Cancel';
  static const membershipRevocationPurgeTitle =
      'Your organization membership has ended.';
  static String membershipRevocationPurgePendingMessage({required int count}) =>
      count == 1
      ? 'Your organization membership has ended on this device. Continuing permanently deletes all locally stored songs and plans, including 1 unsynced change.'
      : 'Your organization membership has ended on this device. Continuing permanently deletes all locally stored songs and plans, including $count unsynced changes.';
  static const membershipRevocationPurgeUnknownPendingMessage =
      'Your organization membership has ended on this device. Continuing permanently deletes all locally stored songs and plans. The exact number of unsynced changes could not be determined, but continuing deletes them too.';
  static const membershipRevocationPurgeConfirmAction = 'Delete';
  static const membershipRevocationPurgeCancelAction = 'Cancel';
  static const retryAction = 'Try again';
  static const signOutAction = 'Sign out';
  static const songCatalogRefreshAction = 'Refresh catalog';
  static const songMutationSyncAction = 'Sync changes';
  static const songCreateAction = 'Add song';
  static const songEditAction = 'Edit song';
  static const songCreateTitle = 'New song';
  static const songDeleteAction = 'Delete song';
  static const songSaveAction = 'Save';
  static const songCancelAction = 'Cancel';
  static const songEditorDiscardChangesTitle = 'Discard changes?';
  static const songEditorDiscardChangesMessage = 'You have unsaved song edits.';
  static const songEditorKeepEditingAction = 'Keep editing';
  static const songEditorDiscardAction = 'Discard';
  static const songTitleLabel = 'Title';
  static const songSourceLabel = 'ChordPro source';
  static const unsyncedSignOutTitle = 'Discard unsynced changes?';
  static String unsyncedSignOutPendingMessage({required int count}) =>
      count == 1
      ? 'You have 1 unsynced change. Signing out will permanently discard it.'
      : 'You have $count unsynced changes. Signing out will permanently discard them.';
  static const unsyncedSignOutUnknownPendingMessage =
      'Unsynced changes could not be counted. Signing out will permanently discard any changes that have not synced.';
  static const unsyncedSignOutConfirmAction = 'Discard and sign out';
  static const signOutBlockedByImportMessage =
      'Sign-out is unavailable while an import is running. Try again when it finishes.';
  static const signOutFailedMessage = 'Sign-out did not complete. Try again.';
  static const signOutSupersededMessage =
      'The signed-in account changed, so this sign-out was stopped.';
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
  static const songReaderTransposeSectionLabel = 'Transpose';
  static const songReaderCapoSectionLabel = 'Capo';
  static const songReaderScaleSectionLabel = 'Scale';
  static const songReaderLyricsOnlyAction = 'Lyrics only';
  static const songReaderChordsAndLyricsAction = 'Chords + lyrics';
  static const songReaderGuitarViewAction = 'Guitar View';
  static const songReaderPianoViewAction = 'Piano View';
  static const songReaderDarkThemeAction = 'Dark view';
  static const songReaderLightThemeAction = 'Light view';
  static const songReaderCapoDirectivePrefix = 'Capo ';
  static const songReaderShowControlsSemantics = 'Show reader controls';
  static const songReaderHideControlsSemantics = 'Hide reader controls';
  static const songReaderTransposeDownSemantics = 'Transpose down';
  static const songReaderTransposeUpSemantics = 'Transpose up';
  static const songReaderCapoDownSemantics = 'Capo down';
  static const songReaderCapoUpSemantics = 'Capo up';
  static const songReaderDecreaseFontSemantics = 'Decrease text size';
  static const songReaderIncreaseFontSemantics = 'Increase text size';
  static const songReaderKeyLabelPrefix = 'Key: ';
  static const songReaderKeySourceSong = 'Song';
  static const songReaderKeySourcePlan = 'Plan';
  static const songReaderKeySourceTemporary = 'Temporary';
  static const songReaderResetKeyAction = 'Reset';
  static const songReaderSaveToPlanAction = 'Save to plan';
  static const songReaderClearPlanValueAction = 'Clear plan value';
  static const songReaderWarningDialogTitle = 'Reading warnings';
  static const songReaderWarningsSemantics = 'Show reading warnings';
  static const songReaderWarningSingular =
      '1 recoverable warning while reading this song.';
  static String songReaderWarningPlural(int count) =>
      '$count recoverable warnings while reading this song.';
  static const songReaderCloseAction = 'Close';
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
  static const planScheduledForLabel = 'Scheduled for';
  static const planScheduledForPickAction = 'Pick date & time';
  static const planScheduledForClearAction = 'Clear scheduled date';
  static const planScheduledForEmptyLabel = 'Not scheduled';
  static const planEditorTitleCreate = 'Create plan';
  static const planEditorTitleEdit = 'Edit plan';
  static const planListLoadingMessage = 'Loading plans...';
  static const planListLoadFailureMessage =
      'Unable to load plans. Please try again.';
  static const planListEmptyMessage = 'No plans available.';
  static const planListUnscheduledLabel = 'Unscheduled';
  static const planDetailTitle = 'Plan detail';
  static const planEditAction = 'Edit plan';
  static const planMoreActions = 'More plan actions';
  static const planDeleteAction = 'Delete plan';
  static const planDeleteConfirmTitle = 'Delete plan?';
  static const planDeleteConfirmAction = 'Delete';
  static String planDeleteConfirmMessage({
    required String planName,
    required int sessionCount,
    required int songCount,
  }) =>
      '“$planName” and its ${_count(sessionCount, 'session', 'sessions')} '
      '(${_count(songCount, 'song', 'songs')}) will be deleted. '
      'The songs stay in the song library.';
  static const planningUnsyncedChangesDiscardedMessage =
      'Unsynced changes to this plan will be discarded.';
  static const planDeleteTargetChangedMessage =
      'This plan changed while you were deciding. Nothing was deleted; '
      'review it and try again.';

  static String _count(int count, String one, String other) =>
      count == 1 ? '$count $one' : '$count $other';
  static const sessionEditAction = 'Edit session';
  static const sessionCreateAction = 'Add session';
  static const sessionReorderAction = 'Reorder session';
  static const planningReorderFailedMessage =
      'Could not save the new order. The previous order was restored.';
  static const sessionMoveUpAction = 'Move session up';
  static const sessionMoveDownAction = 'Move session down';
  static const sessionRenameAction = 'Rename session';
  static const sessionDeleteAction = 'Delete session';
  static const sessionItemAddSongAction = 'Add song';
  static const sessionItemReorderAction = 'Reorder item';
  static const sessionItemMoveUpAction = 'Move item up';
  static const sessionItemMoveDownAction = 'Move item down';
  static const sessionItemDeleteAction = 'Delete item';
  static const sessionItemSongPickerTitle = 'Add song to session';
  static const sessionItemSongUnavailableMessage =
      'Offline song add is unavailable until a local song catalog is available.';
  static const sessionListEmptyMessage =
      'No sessions yet. Add a session to start building this plan.';
  static const sessionItemsEmptyMessage = 'No songs in this session yet.';
  static const sessionDeleteConfirmTitle = 'Delete session?';
  static const sessionDeleteEmptyConfirmMessage = 'This removes the session.';
  static String sessionDeleteConfirmMessage({
    required String sessionName,
    required int songCount,
  }) =>
      '“$sessionName” and its ${_count(songCount, 'song', 'songs')} will be '
      'removed from this plan. The songs stay in the song library.';
  static const sessionDeleteConfirmAction = 'Delete session';
  static const sessionUnsyncedChangesDiscardedMessage =
      'Unsynced changes to this session will be discarded.';
  static const sessionDeleteTargetChangedMessage =
      'This session changed while you were deciding. Nothing was deleted; '
      'review it and try again.';
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
  static const unifiedSyncSyncedLabel = 'Synced';
  static const unifiedSyncUnsyncedLabel = 'Unsynced';
  static const unifiedSyncConflictLabel = 'Conflict';
  static const unifiedSyncNowAction = 'Sync now';
  static const unifiedSyncPopupTitle = 'Workspace sync';
  static const unifiedSyncEmptyMessage =
      'All local changes are synced with the server.';
  static const unifiedSyncSongsHeading = 'Songs';
  static const unifiedSyncPlansHeading = 'Plans';
  static const unifiedSyncSongStateCreated = 'Created';
  static const unifiedSyncSongStateEdited = 'Edited';
  static const unifiedSyncSongStateRemoved = 'Removed';
  static const unifiedSyncSongStateCreatedConflict = 'Created (conflict)';
  static const unifiedSyncSongStateEditedConflict = 'Edited (conflict)';
  static const unifiedSyncSongStateRemovedConflict = 'Removed (conflict)';
  // The reason chips of the sync popup (song rows and plan rows). Each is a
  // short phrase for one domain reason; the reason names (pending_local and so
  // on) stay in logic and tests, not on screen.
  static const unifiedSyncReasonPendingLocal = 'Waiting to sync';
  // Makes no promise about retrying: not every path that maps here retries on
  // its own (the automatic triggers do nothing under sessionExpired, and a
  // dependency-blocked song row keeps failing until the referenced data
  // changes). The plan rows' Try again button and "Sync now" carry the retry.
  static const unifiedSyncReasonSyncFailed = 'Sync failed';
  static const unifiedSyncReasonConflict = 'Conflicts with the server version';
  // spec D5.6 / ADR-035: this one must let the user tell "access may have
  // ended and retrying will not help" apart from an ordinary retryable
  // failure, so it names the likely cause and keeps "retrying will not help".
  static const unifiedSyncReasonAuthorizationDenied =
      'Access may have ended — retrying will not help';
  static const unifiedSyncReasonDependencyBlocked = 'Blocked by a related item';
  // One honest phrase for both causes of this reason: the backend answers
  // `plan_not_found` for a plan removed on the server and for a plan the
  // member can no longer edit, so the client cannot tell them apart.
  static const unifiedSyncReasonRemoteMissing =
      'Not found on the server, or access may have ended';
  static const unifiedSyncReasonUnknown = 'Unexpected sync error';
  static const unifiedSyncFreshnessStale = 'Not up to date';
  static const unifiedSyncFreshnessOfflineCached =
      'Offline, showing saved data';
  static const unifiedSyncLastSyncedSongsLabel = 'Songs last synced';
  static const unifiedSyncLastSyncedPlansLabel = 'Plans last synced';
  static const unifiedSyncLastSyncedNever = 'never';
  static const unifiedSyncLastSyncedJustNow = 'just now';
  static String unifiedSyncLastSyncedMinutesAgo(int minutes) =>
      '$minutes min ago';
  static String unifiedSyncLastSyncedHoursAgo(int hours) => '$hours h ago';
  static String unifiedSyncLastSyncedDaysAgo(int days) =>
      days == 1 ? '1 day ago' : '$days days ago';
  static const unifiedSyncActivitySyncing = 'syncing';
  static const unifiedSyncDiscardAllAction = 'Discard all';
  static const unifiedSyncDiscardAllTitle = 'Discard all local changes?';
  static const unifiedSyncDiscardAllMessagePrefix =
      'This permanently discards all local changes for this organization';
  static const unifiedSyncDiscardAllConfirmAction = 'Discard all';
  static const unifiedSyncDiscardAllFailedMessage =
      'Some changes could not be discarded. Try again.';
  static const unifiedSyncWaitForSyncMessage =
      'Sync is in progress. Try again after it finishes.';
  static const unifiedSyncActionFailedMessage =
      'Action could not be completed. Try again.';
  static const unifiedSyncActionPartialFailureMessage =
      'Some actions could not be completed.';

  // ChordPro import
  static const songImportAction = 'Import';
  static const songImportPickerTitle = 'Import ChordPro files';
  static const songImportDuplicateDialogTitle = 'Duplicate songs';
  static const songImportDuplicateDialogMessage =
      'Some files match songs already in your library. Choose how to handle each.';
  static const songImportDuplicateOverwriteAction = 'Overwrite';
  static const songImportDuplicateSkipAction = 'Skip';
  static const songImportDuplicateOverwriteAllAction = 'Overwrite all';
  static const songImportDuplicateSkipAllAction = 'Skip all';
  static const songImportDuplicateConfirmAction = 'Continue';
  static const songImportSummaryTitle = 'Import complete';
  static const songImportSummaryImportedLabel = 'Imported';
  static const songImportSummarySkippedLabel = 'Skipped';
  static const songImportSummaryErrorsLabel = 'Errors';
  static const songImportSummaryDoneAction = 'Done';
  static const songImportNoContextMessage = 'Sign in before importing songs.';
  static const songImportContextChangedMessage =
      'The account or workspace changed, so the import was stopped and '
      'nothing was imported. Start the import again.';
  static const songImportInterruptedMessage =
      'The import stopped before it finished.';
  static const songImportReadErrorReason = 'Unreadable';
  static const songImportUtf8ErrorReason = 'Invalid encoding';
  static const songImportEmptyFileReason = 'Empty file';
  static const songImportSaveErrorPrefix = 'Save error';
  static const songImportUntitledFallback = 'Untitled Song';

  // Auth invite-sso additions
  static const continueWithGoogle = 'Continue with Google';
  static const continueWithApple = 'Continue with Apple';
  static const magicLinkLabel = 'Email for magic link';
  static const sendMagicLinkAction = 'Send magic link';
  static const magicLinkSentTitle = 'Check your inbox';
  static const magicLinkSentMessage =
      'We sent you a sign-in link. Open it on this device to continue.';
  static const inviteRequiredTitle = 'Invitation required';
  static const inviteRequiredMessage =
      'Paste your invite link to join an organization.';
  static const invitePasteLabel = 'Invite link';
  static const inviteRedeemAction = 'Redeem invite';
  static const inviteErrorNotFound = 'Invalid invite link.';
  static const inviteErrorExpired = 'Invite expired. Ask for a new one.';
  static const inviteErrorAlreadyRedeemed = 'Invite already used.';
  static const inviteErrorAlreadyMember = 'You are already a member.';
  static const inviteErrorEmailMismatch =
      'This invite was issued to a different email address.';
  static const inviteErrorRateLimited =
      'Too many attempts. Wait a few minutes and try again.';
  static const inviteErrorNetwork =
      'Connection error. Check your network and try again.';
  static const accountTitle = 'Account';
  static const deleteAccountAction = 'Delete account';
  static const deleteAccountConfirmTitle = 'Delete account?';
  static const deleteAccountConfirmMessage =
      'Your account, memberships, and any pending offline changes will be removed permanently.';
  static const deleteAccountConfirmAction = 'Delete permanently';
  static const deleteAccountFailedMessage =
      'Could not confirm the account deletion. Check your connection and try again.';
  static const deleteAccountSupersededMessage =
      'The signed-in account changed, so the account deletion was stopped.';
  static const cancelAction = 'Cancel';
  static const magicLinkSendFailureMessage =
      'Could not send magic link. Please try again.';
  static const membershipResolvingMessage = 'Checking access...';
  static const membershipConnectivityFailureMessage =
      'Could not verify access. Check your network.';
  static const membershipNonConnectivityFailureMessage =
      'Could not verify access. Please sign out and sign in again.';
  static const localDataEventsAction = 'Local data activity';
  static const localDataEventsTitle = 'Local data activity';
  static const localDataEventsEmptyMessage =
      'No local data activity recorded yet.';
  static const localDataEventsLoadErrorMessage =
      'Could not load local data activity.';
}
