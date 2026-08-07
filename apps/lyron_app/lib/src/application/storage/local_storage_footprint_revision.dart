/// Framework-neutral callback used by concrete storage boundaries after a
/// committed change to the SQL-measured local-storage footprint.
///
/// Implementations emit once after the outermost storage commit and do not
/// emit for rolled-back or persisted-payload-identical operations.
typedef LocalStorageFootprintChanged = void Function();
