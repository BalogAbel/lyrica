enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  planList('/plans'),
  planDetail('/plans/:planId'),
  planSessionSongReader(
    '/plans/:planId/sessions/:sessionId/items/:sessionItemId/songs/:songId',
  ),
  songReader('/songs/:songId');

  const AppRoutes(this.path);

  final String path;
}
