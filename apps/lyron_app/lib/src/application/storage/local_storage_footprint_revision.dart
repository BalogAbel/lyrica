/// Framework-neutral callback used by concrete storage boundaries after a
/// committed change to the SQL-measured local-storage footprint.
typedef LocalStorageFootprintChanged = void Function();
