import 'package:lyron_app/src/shared/keyset_paging.dart';

/// Serves [rows] as keyset pages ordered by `id` (uuid order), the way
/// PostgREST would for `order(id.asc).gt(id, after).limit(limit)`,
/// optionally capped at [cap] rows per page (a server-side `max_rows`).
///
/// Row ids must be canonical lowercase uuids, so a plain string comparison
/// matches the server's order (see [compareUuidKeys]).
List<Map<String, dynamic>> keysetPage(
  List<Map<String, dynamic>> rows, {
  required String? after,
  required int limit,
  int? cap,
}) {
  final sorted = [...rows]
    ..sort((a, b) => compareUuidKeys(a['id'] as String, b['id'] as String));
  final filtered = after == null
      ? sorted
      : sorted
            .where((row) => compareUuidKeys(row['id'] as String, after) > 0)
            .toList();
  final size = cap != null && cap < limit ? cap : limit;
  return filtered.take(size).toList(growable: false);
}
