enum CatalogRefreshStatus {
  idle,
  refreshing,
  failed,

  /// D4 (docs/specs/2026-08-19-local-data-durability-contract.md): a
  /// `listSongs()` refresh came back empty against a non-empty cached
  /// snapshot and was rejected rather than treated as a normal success or
  /// failure -- the cache was left untouched. Distinct from `failed` so a
  /// future caller can tell this apart from a genuine refresh error; today's
  /// existing consumers (sync overview, online-transition detector, song
  /// list/reader screens, slug route resolvers) only branch on `== failed`,
  /// so this value does not yet surface anywhere -- a known, deliberate gap
  /// left for later work.
  implausibleEmpty,
}
