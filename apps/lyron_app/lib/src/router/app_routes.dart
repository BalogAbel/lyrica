enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  magicLinkSent('/magic-link-sent'),
  invite('/invite'),
  inviteRequired('/invite-required'),
  redeem('/redeem'),
  account('/account'),
  localDataEvents('/account/local-data-events'),
  planList('/plans'),
  planDetail('/plans/:planSlug'),
  planSessionSongReader(
    '/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug',
  ),
  songCreate('/songs/new'),
  songEditor('/songs/:songSlug/edit'),
  songReader('/songs/:songSlug');

  const AppRoutes(this.path);

  final String path;
}
