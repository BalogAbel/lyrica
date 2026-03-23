enum AppRoutes {
  bootstrap('/bootstrap'),
  home('/'),
  signIn('/sign-in'),
  songReader('/songs/:songId');

  const AppRoutes(this.path);

  final String path;
}
