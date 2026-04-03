enum PlanningRefreshStatus { idle, refreshing, failed }

enum PlanningAccessStatus { signedIn, signedOut }

class PlanningSyncState {
  const PlanningSyncState({
    required this.userId,
    required this.organizationId,
    required this.accessStatus,
    required this.refreshStatus,
    required this.hasLocalPlanningData,
    required this.lastRefreshedAt,
  });

  const PlanningSyncState.initial()
    : this(
        userId: null,
        organizationId: null,
        accessStatus: PlanningAccessStatus.signedOut,
        refreshStatus: PlanningRefreshStatus.idle,
        hasLocalPlanningData: false,
        lastRefreshedAt: null,
      );

  final String? userId;
  final String? organizationId;
  final PlanningAccessStatus accessStatus;
  final PlanningRefreshStatus refreshStatus;
  final bool hasLocalPlanningData;
  final DateTime? lastRefreshedAt;

  PlanningSyncState copyWith({
    String? userId,
    String? organizationId,
    bool clearIdentity = false,
    PlanningAccessStatus? accessStatus,
    PlanningRefreshStatus? refreshStatus,
    bool? hasLocalPlanningData,
    DateTime? lastRefreshedAt,
    bool clearLastRefreshedAt = false,
  }) {
    return PlanningSyncState(
      userId: clearIdentity ? null : (userId ?? this.userId),
      organizationId: clearIdentity
          ? null
          : (organizationId ?? this.organizationId),
      accessStatus: accessStatus ?? this.accessStatus,
      refreshStatus: refreshStatus ?? this.refreshStatus,
      hasLocalPlanningData: hasLocalPlanningData ?? this.hasLocalPlanningData,
      lastRefreshedAt: clearLastRefreshedAt
          ? null
          : (lastRefreshedAt ?? this.lastRefreshedAt),
    );
  }
}
