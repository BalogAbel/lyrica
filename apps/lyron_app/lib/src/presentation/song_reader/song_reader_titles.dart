import 'package:lyron_app/src/domain/planning/plan_detail.dart';
import 'package:lyron_app/src/presentation/song_reader/session_scoped_reader_context.dart';
import 'package:lyron_app/src/presentation/song_reader/song_reader_projection.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// Title-resolution helpers for the song reader.
///
/// Pure functions — no `BuildContext`, no providers. Callers pass in whatever
/// widget/provider state the original methods used to read implicitly.

/// Prefers the scoped session item's title (if non-empty) over the parsed
/// song's title.
String resolveCurrentTitle({
  required SessionScopedReaderContext? scopedContext,
  required SongReaderProjection projection,
}) {
  final scopedTitle = scopedContext?.selectedItem.title.trim() ?? '';
  if (scopedTitle.isNotEmpty) {
    return scopedTitle;
  }
  return projection.title;
}

/// Resolves a title to show when the parsed song itself is unavailable
/// (loading, deleted, etc.): prefers the scoped session item's title, then
/// falls back to the title preserved in [warmPlanDetail] for the matching
/// session item, then to a generic reader title.
String resolvePreservedScopedTitle({
  required SessionScopedReaderContext? scopedContext,
  required PlanDetail? warmPlanDetail,
  required String? sessionItemId,
  required String songId,
}) {
  final scopedTitle = scopedContext?.selectedItem.title.trim() ?? '';
  if (scopedTitle.isNotEmpty) {
    return scopedTitle;
  }
  if (warmPlanDetail != null && sessionItemId != null) {
    for (final session in warmPlanDetail.sessions) {
      for (final item in session.items) {
        if (item.id == sessionItemId && item.song.id == songId) {
          final preservedTitle = item.song.title.trim();
          if (preservedTitle.isNotEmpty) {
            return preservedTitle;
          }
        }
      }
    }
  }
  return AppStrings.songReaderTitle;
}

/// Trims [title] and returns null when the result is empty, so callers can
/// omit neighbor-title UI rather than rendering blank text.
String? resolveNeighborTitle(String? title) {
  final trimmed = title?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}
