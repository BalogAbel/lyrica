import 'package:lyrica_app/src/domain/planning/plan_detail.dart';
import 'package:lyrica_app/src/domain/planning/plan_summary.dart';

abstract class PlanningRepository {
  Future<List<PlanSummary>> listPlans();

  Future<PlanDetail> getPlanDetail(String planId);
}
