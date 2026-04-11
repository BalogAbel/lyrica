class PlanningSyncPayload {
  const PlanningSyncPayload({
    required this.plans,
    required this.sessions,
    required this.items,
  });

  final List<PlanningSyncPlan> plans;
  final List<PlanningSyncSession> sessions;
  final List<PlanningSyncSessionItem> items;
}

class PlanningSyncPlan {
  const PlanningSyncPlan({
    required this.id,
    required this.slug,
    required this.name,
    required this.description,
    required this.scheduledFor,
    required this.updatedAt,
    required this.version,
  });

  final String id;
  final String slug;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
  final int version;
}

class PlanningSyncSession {
  const PlanningSyncSession({
    required this.id,
    required this.planId,
    required this.slug,
    required this.position,
    required this.name,
    required this.version,
  });

  final String id;
  final String planId;
  final String slug;
  final int position;
  final String name;
  final int version;
}

class PlanningSyncSessionItem {
  const PlanningSyncSessionItem({
    required this.id,
    required this.planId,
    required this.sessionId,
    required this.position,
    required this.songId,
    required this.songTitle,
  });

  final String id;
  final String planId;
  final String sessionId;
  final int position;
  final String songId;
  final String songTitle;
}
