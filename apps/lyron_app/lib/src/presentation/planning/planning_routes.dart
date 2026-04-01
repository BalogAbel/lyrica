import 'package:lyron_app/src/router/app_routes.dart';

class PlanningRoutes {
  const PlanningRoutes._();

  static final planListPath = AppRoutes.planList.path;
  static final planDetailPath = AppRoutes.planDetail.path;
  static final planSessionSongReaderPath = AppRoutes.planSessionSongReader.path;

  static String planDetailLocation(String planId) =>
      AppRoutes.planDetail.path.replaceFirst(':planId', planId);

  static String planSessionSongReaderLocation({
    required String planId,
    required String sessionId,
    required String sessionItemId,
    required String songId,
  }) => AppRoutes.planSessionSongReader.path
      .replaceFirst(':planId', planId)
      .replaceFirst(':sessionId', sessionId)
      .replaceFirst(':sessionItemId', sessionItemId)
      .replaceFirst(':songId', songId);
}
