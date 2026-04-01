import 'package:lyrica_app/src/router/app_routes.dart';

class PlanningRoutes {
  const PlanningRoutes._();

  static final planListPath = AppRoutes.planList.path;
  static final planDetailPath = AppRoutes.planDetail.path;

  static String planDetailLocation(String planId) =>
      AppRoutes.planDetail.path.replaceFirst(':planId', planId);
}
