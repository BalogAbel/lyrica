enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  planList('/plans'),
  planDetail('/plans/:planSlug'),
  planSessionSongReader(
    '/plans/:planSlug/sessions/:sessionSlug/items/songs/:songSlug',
  ),
  songReader('/songs/:songSlug');

  const AppRoutes(this.path);

  final String path;
}
