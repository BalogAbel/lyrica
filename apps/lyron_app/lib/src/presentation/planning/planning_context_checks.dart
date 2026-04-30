import 'package:lyron_app/src/application/planning/planning_local_read_repository.dart';
import 'package:lyron_app/src/application/song_library/active_catalog_context.dart';

bool samePlanningContext(
  ActivePlanningReadContext? left,
  ActivePlanningReadContext? right,
) {
  return left?.userId == right?.userId &&
      left?.organizationId == right?.organizationId;
}

bool sameCatalogContext(
  ActiveCatalogContext? left,
  ActiveCatalogContext? right,
) {
  return left?.userId == right?.userId &&
      left?.organizationId == right?.organizationId;
}
