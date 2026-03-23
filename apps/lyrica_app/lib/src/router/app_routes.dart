enum AppRoutes {
  home('/'),
  songReader('/songs/:songId');

  const AppRoutes(this.path);

  final String path;
}
