enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  planList('/plans'),
  planDetail('/plans/:planId'),
  songReader('/songs/:songId');

  const AppRoutes(this.path);

  final String path;
}
