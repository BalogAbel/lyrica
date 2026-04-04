import 'package:lyron_app/src/router/app_routes.dart';

class PlanningRoutes {
  const PlanningRoutes._();

  static final planListPath = AppRoutes.planList.path;
  static final planDetailPath = AppRoutes.planDetail.path;
  static final planSessionSongReaderPath = AppRoutes.planSessionSongReader.path;

  static String planDetailLocation(String planSlug) =>
      AppRoutes.planDetail.path.replaceFirst(':planSlug', planSlug);

  static String planSessionSongReaderLocation({
    required String planSlug,
    required String sessionSlug,
    required String sessionItemId,
    required String songSlug,
  }) => AppRoutes.planSessionSongReader.path
      .replaceFirst(':planSlug', planSlug)
      .replaceFirst(':sessionSlug', sessionSlug)
      .replaceFirst(':sessionItemId', sessionItemId)
      .replaceFirst(':songSlug', songSlug);
}
