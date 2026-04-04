// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'planning_local_database.dart';

// ignore_for_file: type=lint
class $PlanningProjectionOwnersTable extends PlanningProjectionOwners
    with TableInfo<$PlanningProjectionOwnersTable, PlanningProjectionOwner> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlanningProjectionOwnersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotVersionMeta = const VerificationMeta(
    'snapshotVersion',
  );
  @override
  late final GeneratedColumn<int> snapshotVersion = GeneratedColumn<int>(
    'snapshot_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refreshedAtMeta = const VerificationMeta(
    'refreshedAt',
  );
  @override
  late final GeneratedColumn<DateTime> refreshedAt = GeneratedColumn<DateTime>(
    'refreshed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    organizationId,
    snapshotVersion,
    refreshedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'planning_projection_owners';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlanningProjectionOwner> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('snapshot_version')) {
      context.handle(
        _snapshotVersionMeta,
        snapshotVersion.isAcceptableOrUnknown(
          data['snapshot_version']!,
          _snapshotVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotVersionMeta);
    }
    if (data.containsKey('refreshed_at')) {
      context.handle(
        _refreshedAtMeta,
        refreshedAt.isAcceptableOrUnknown(
          data['refreshed_at']!,
          _refreshedAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_refreshedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, organizationId};
  @override
  PlanningProjectionOwner map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlanningProjectionOwner(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      snapshotVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_version'],
      )!,
      refreshedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}refreshed_at'],
      )!,
    );
  }

  @override
  $PlanningProjectionOwnersTable createAlias(String alias) {
    return $PlanningProjectionOwnersTable(attachedDatabase, alias);
  }
}

class PlanningProjectionOwner extends DataClass
    implements Insertable<PlanningProjectionOwner> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final DateTime refreshedAt;
  const PlanningProjectionOwner({
    required this.userId,
    required this.organizationId,
    required this.snapshotVersion,
    required this.refreshedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['snapshot_version'] = Variable<int>(snapshotVersion);
    map['refreshed_at'] = Variable<DateTime>(refreshedAt);
    return map;
  }

  PlanningProjectionOwnersCompanion toCompanion(bool nullToAbsent) {
    return PlanningProjectionOwnersCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      refreshedAt: Value(refreshedAt),
    );
  }

  factory PlanningProjectionOwner.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlanningProjectionOwner(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      snapshotVersion: serializer.fromJson<int>(json['snapshotVersion']),
      refreshedAt: serializer.fromJson<DateTime>(json['refreshedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'snapshotVersion': serializer.toJson<int>(snapshotVersion),
      'refreshedAt': serializer.toJson<DateTime>(refreshedAt),
    };
  }

  PlanningProjectionOwner copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    DateTime? refreshedAt,
  }) => PlanningProjectionOwner(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
  PlanningProjectionOwner copyWithCompanion(
    PlanningProjectionOwnersCompanion data,
  ) {
    return PlanningProjectionOwner(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      snapshotVersion: data.snapshotVersion.present
          ? data.snapshotVersion.value
          : this.snapshotVersion,
      refreshedAt: data.refreshedAt.present
          ? data.refreshedAt.value
          : this.refreshedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlanningProjectionOwner(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('refreshedAt: $refreshedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, organizationId, snapshotVersion, refreshedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlanningProjectionOwner &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.refreshedAt == this.refreshedAt);
}

class PlanningProjectionOwnersCompanion
    extends UpdateCompanion<PlanningProjectionOwner> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<DateTime> refreshedAt;
  final Value<int> rowid;
  const PlanningProjectionOwnersCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PlanningProjectionOwnersCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required DateTime refreshedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       refreshedAt = Value(refreshedAt);
  static Insertable<PlanningProjectionOwner> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<int>? snapshotVersion,
    Expression<DateTime>? refreshedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (snapshotVersion != null) 'snapshot_version': snapshotVersion,
      if (refreshedAt != null) 'refreshed_at': refreshedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PlanningProjectionOwnersCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<DateTime>? refreshedAt,
    Value<int>? rowid,
  }) {
    return PlanningProjectionOwnersCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      refreshedAt: refreshedAt ?? this.refreshedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (snapshotVersion.present) {
      map['snapshot_version'] = Variable<int>(snapshotVersion.value);
    }
    if (refreshedAt.present) {
      map['refreshed_at'] = Variable<DateTime>(refreshedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlanningProjectionOwnersCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPlanningPlansTable extends CachedPlanningPlans
    with TableInfo<$CachedPlanningPlansTable, CachedPlanningPlan> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPlanningPlansTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotVersionMeta = const VerificationMeta(
    'snapshotVersion',
  );
  @override
  late final GeneratedColumn<int> snapshotVersion = GeneratedColumn<int>(
    'snapshot_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _scheduledForMeta = const VerificationMeta(
    'scheduledFor',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledFor = GeneratedColumn<DateTime>(
    'scheduled_for',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    organizationId,
    snapshotVersion,
    planId,
    slug,
    name,
    description,
    scheduledFor,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_planning_plans';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPlanningPlan> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('snapshot_version')) {
      context.handle(
        _snapshotVersionMeta,
        snapshotVersion.isAcceptableOrUnknown(
          data['snapshot_version']!,
          _snapshotVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotVersionMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_for')) {
      context.handle(
        _scheduledForMeta,
        scheduledFor.isAcceptableOrUnknown(
          data['scheduled_for']!,
          _scheduledForMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, organizationId, planId};
  @override
  CachedPlanningPlan map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPlanningPlan(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      snapshotVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_version'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      scheduledFor: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_for'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CachedPlanningPlansTable createAlias(String alias) {
    return $CachedPlanningPlansTable(attachedDatabase, alias);
  }
}

class CachedPlanningPlan extends DataClass
    implements Insertable<CachedPlanningPlan> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final String planId;
  final String slug;
  final String name;
  final String? description;
  final DateTime? scheduledFor;
  final DateTime updatedAt;
  const CachedPlanningPlan({
    required this.userId,
    required this.organizationId,
    required this.snapshotVersion,
    required this.planId,
    required this.slug,
    required this.name,
    this.description,
    this.scheduledFor,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['snapshot_version'] = Variable<int>(snapshotVersion);
    map['plan_id'] = Variable<String>(planId);
    map['slug'] = Variable<String>(slug);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || scheduledFor != null) {
      map['scheduled_for'] = Variable<DateTime>(scheduledFor);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  CachedPlanningPlansCompanion toCompanion(bool nullToAbsent) {
    return CachedPlanningPlansCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      planId: Value(planId),
      slug: Value(slug),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      scheduledFor: scheduledFor == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledFor),
      updatedAt: Value(updatedAt),
    );
  }

  factory CachedPlanningPlan.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPlanningPlan(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      snapshotVersion: serializer.fromJson<int>(json['snapshotVersion']),
      planId: serializer.fromJson<String>(json['planId']),
      slug: serializer.fromJson<String>(json['slug']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      scheduledFor: serializer.fromJson<DateTime?>(json['scheduledFor']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'snapshotVersion': serializer.toJson<int>(snapshotVersion),
      'planId': serializer.toJson<String>(planId),
      'slug': serializer.toJson<String>(slug),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'scheduledFor': serializer.toJson<DateTime?>(scheduledFor),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  CachedPlanningPlan copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    String? planId,
    String? slug,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<DateTime?> scheduledFor = const Value.absent(),
    DateTime? updatedAt,
  }) => CachedPlanningPlan(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    planId: planId ?? this.planId,
    slug: slug ?? this.slug,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    scheduledFor: scheduledFor.present ? scheduledFor.value : this.scheduledFor,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CachedPlanningPlan copyWithCompanion(CachedPlanningPlansCompanion data) {
    return CachedPlanningPlan(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      snapshotVersion: data.snapshotVersion.present
          ? data.snapshotVersion.value
          : this.snapshotVersion,
      planId: data.planId.present ? data.planId.value : this.planId,
      slug: data.slug.present ? data.slug.value : this.slug,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      scheduledFor: data.scheduledFor.present
          ? data.scheduledFor.value
          : this.scheduledFor,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlanningPlan(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('planId: $planId, ')
          ..write('slug: $slug, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    organizationId,
    snapshotVersion,
    planId,
    slug,
    name,
    description,
    scheduledFor,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPlanningPlan &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.planId == this.planId &&
          other.slug == this.slug &&
          other.name == this.name &&
          other.description == this.description &&
          other.scheduledFor == this.scheduledFor &&
          other.updatedAt == this.updatedAt);
}

class CachedPlanningPlansCompanion extends UpdateCompanion<CachedPlanningPlan> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<String> planId;
  final Value<String> slug;
  final Value<String> name;
  final Value<String?> description;
  final Value<DateTime?> scheduledFor;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const CachedPlanningPlansCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.planId = const Value.absent(),
    this.slug = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.scheduledFor = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPlanningPlansCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required String planId,
    required String slug,
    required String name,
    this.description = const Value.absent(),
    this.scheduledFor = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       planId = Value(planId),
       slug = Value(slug),
       name = Value(name),
       updatedAt = Value(updatedAt);
  static Insertable<CachedPlanningPlan> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<int>? snapshotVersion,
    Expression<String>? planId,
    Expression<String>? slug,
    Expression<String>? name,
    Expression<String>? description,
    Expression<DateTime>? scheduledFor,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (snapshotVersion != null) 'snapshot_version': snapshotVersion,
      if (planId != null) 'plan_id': planId,
      if (slug != null) 'slug': slug,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (scheduledFor != null) 'scheduled_for': scheduledFor,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPlanningPlansCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<String>? planId,
    Value<String>? slug,
    Value<String>? name,
    Value<String?>? description,
    Value<DateTime?>? scheduledFor,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return CachedPlanningPlansCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      planId: planId ?? this.planId,
      slug: slug ?? this.slug,
      name: name ?? this.name,
      description: description ?? this.description,
      scheduledFor: scheduledFor ?? this.scheduledFor,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (snapshotVersion.present) {
      map['snapshot_version'] = Variable<int>(snapshotVersion.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (scheduledFor.present) {
      map['scheduled_for'] = Variable<DateTime>(scheduledFor.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlanningPlansCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('planId: $planId, ')
          ..write('slug: $slug, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('scheduledFor: $scheduledFor, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPlanningSessionsTable extends CachedPlanningSessions
    with TableInfo<$CachedPlanningSessionsTable, CachedPlanningSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPlanningSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotVersionMeta = const VerificationMeta(
    'snapshotVersion',
  );
  @override
  late final GeneratedColumn<int> snapshotVersion = GeneratedColumn<int>(
    'snapshot_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _slugMeta = const VerificationMeta('slug');
  @override
  late final GeneratedColumn<String> slug = GeneratedColumn<String>(
    'slug',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    organizationId,
    snapshotVersion,
    sessionId,
    planId,
    slug,
    position,
    name,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_planning_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPlanningSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('snapshot_version')) {
      context.handle(
        _snapshotVersionMeta,
        snapshotVersion.isAcceptableOrUnknown(
          data['snapshot_version']!,
          _snapshotVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotVersionMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, organizationId, sessionId};
  @override
  CachedPlanningSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPlanningSession(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      snapshotVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_version'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
    );
  }

  @override
  $CachedPlanningSessionsTable createAlias(String alias) {
    return $CachedPlanningSessionsTable(attachedDatabase, alias);
  }
}

class CachedPlanningSession extends DataClass
    implements Insertable<CachedPlanningSession> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final String sessionId;
  final String planId;
  final String slug;
  final int position;
  final String name;
  const CachedPlanningSession({
    required this.userId,
    required this.organizationId,
    required this.snapshotVersion,
    required this.sessionId,
    required this.planId,
    required this.slug,
    required this.position,
    required this.name,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['snapshot_version'] = Variable<int>(snapshotVersion);
    map['session_id'] = Variable<String>(sessionId);
    map['plan_id'] = Variable<String>(planId);
    map['slug'] = Variable<String>(slug);
    map['position'] = Variable<int>(position);
    map['name'] = Variable<String>(name);
    return map;
  }

  CachedPlanningSessionsCompanion toCompanion(bool nullToAbsent) {
    return CachedPlanningSessionsCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      sessionId: Value(sessionId),
      planId: Value(planId),
      slug: Value(slug),
      position: Value(position),
      name: Value(name),
    );
  }

  factory CachedPlanningSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPlanningSession(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      snapshotVersion: serializer.fromJson<int>(json['snapshotVersion']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      planId: serializer.fromJson<String>(json['planId']),
      slug: serializer.fromJson<String>(json['slug']),
      position: serializer.fromJson<int>(json['position']),
      name: serializer.fromJson<String>(json['name']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'snapshotVersion': serializer.toJson<int>(snapshotVersion),
      'sessionId': serializer.toJson<String>(sessionId),
      'planId': serializer.toJson<String>(planId),
      'slug': serializer.toJson<String>(slug),
      'position': serializer.toJson<int>(position),
      'name': serializer.toJson<String>(name),
    };
  }

  CachedPlanningSession copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    String? sessionId,
    String? planId,
    String? slug,
    int? position,
    String? name,
  }) => CachedPlanningSession(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    sessionId: sessionId ?? this.sessionId,
    planId: planId ?? this.planId,
    slug: slug ?? this.slug,
    position: position ?? this.position,
    name: name ?? this.name,
  );
  CachedPlanningSession copyWithCompanion(
    CachedPlanningSessionsCompanion data,
  ) {
    return CachedPlanningSession(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      snapshotVersion: data.snapshotVersion.present
          ? data.snapshotVersion.value
          : this.snapshotVersion,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      planId: data.planId.present ? data.planId.value : this.planId,
      slug: data.slug.present ? data.slug.value : this.slug,
      position: data.position.present ? data.position.value : this.position,
      name: data.name.present ? data.name.value : this.name,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlanningSession(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('sessionId: $sessionId, ')
          ..write('planId: $planId, ')
          ..write('slug: $slug, ')
          ..write('position: $position, ')
          ..write('name: $name')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    organizationId,
    snapshotVersion,
    sessionId,
    planId,
    slug,
    position,
    name,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPlanningSession &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.sessionId == this.sessionId &&
          other.planId == this.planId &&
          other.slug == this.slug &&
          other.position == this.position &&
          other.name == this.name);
}

class CachedPlanningSessionsCompanion
    extends UpdateCompanion<CachedPlanningSession> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<String> sessionId;
  final Value<String> planId;
  final Value<String> slug;
  final Value<int> position;
  final Value<String> name;
  final Value<int> rowid;
  const CachedPlanningSessionsCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.planId = const Value.absent(),
    this.slug = const Value.absent(),
    this.position = const Value.absent(),
    this.name = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPlanningSessionsCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required String sessionId,
    required String planId,
    required String slug,
    required int position,
    required String name,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       sessionId = Value(sessionId),
       planId = Value(planId),
       slug = Value(slug),
       position = Value(position),
       name = Value(name);
  static Insertable<CachedPlanningSession> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<int>? snapshotVersion,
    Expression<String>? sessionId,
    Expression<String>? planId,
    Expression<String>? slug,
    Expression<int>? position,
    Expression<String>? name,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (snapshotVersion != null) 'snapshot_version': snapshotVersion,
      if (sessionId != null) 'session_id': sessionId,
      if (planId != null) 'plan_id': planId,
      if (slug != null) 'slug': slug,
      if (position != null) 'position': position,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPlanningSessionsCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<String>? sessionId,
    Value<String>? planId,
    Value<String>? slug,
    Value<int>? position,
    Value<String>? name,
    Value<int>? rowid,
  }) {
    return CachedPlanningSessionsCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      sessionId: sessionId ?? this.sessionId,
      planId: planId ?? this.planId,
      slug: slug ?? this.slug,
      position: position ?? this.position,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (snapshotVersion.present) {
      map['snapshot_version'] = Variable<int>(snapshotVersion.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlanningSessionsCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('sessionId: $sessionId, ')
          ..write('planId: $planId, ')
          ..write('slug: $slug, ')
          ..write('position: $position, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedPlanningSessionItemsTable extends CachedPlanningSessionItems
    with
        TableInfo<$CachedPlanningSessionItemsTable, CachedPlanningSessionItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedPlanningSessionItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _organizationIdMeta = const VerificationMeta(
    'organizationId',
  );
  @override
  late final GeneratedColumn<String> organizationId = GeneratedColumn<String>(
    'organization_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotVersionMeta = const VerificationMeta(
    'snapshotVersion',
  );
  @override
  late final GeneratedColumn<int> snapshotVersion = GeneratedColumn<int>(
    'snapshot_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionItemIdMeta = const VerificationMeta(
    'sessionItemId',
  );
  @override
  late final GeneratedColumn<String> sessionItemId = GeneratedColumn<String>(
    'session_item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _planIdMeta = const VerificationMeta('planId');
  @override
  late final GeneratedColumn<String> planId = GeneratedColumn<String>(
    'plan_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _songTitleMeta = const VerificationMeta(
    'songTitle',
  );
  @override
  late final GeneratedColumn<String> songTitle = GeneratedColumn<String>(
    'song_title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    organizationId,
    snapshotVersion,
    sessionItemId,
    planId,
    sessionId,
    position,
    songId,
    songTitle,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_planning_session_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedPlanningSessionItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_organizationIdMeta);
    }
    if (data.containsKey('snapshot_version')) {
      context.handle(
        _snapshotVersionMeta,
        snapshotVersion.isAcceptableOrUnknown(
          data['snapshot_version']!,
          _snapshotVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_snapshotVersionMeta);
    }
    if (data.containsKey('session_item_id')) {
      context.handle(
        _sessionItemIdMeta,
        sessionItemId.isAcceptableOrUnknown(
          data['session_item_id']!,
          _sessionItemIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionItemIdMeta);
    }
    if (data.containsKey('plan_id')) {
      context.handle(
        _planIdMeta,
        planId.isAcceptableOrUnknown(data['plan_id']!, _planIdMeta),
      );
    } else if (isInserting) {
      context.missing(_planIdMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('song_title')) {
      context.handle(
        _songTitleMeta,
        songTitle.isAcceptableOrUnknown(data['song_title']!, _songTitleMeta),
      );
    } else if (isInserting) {
      context.missing(_songTitleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    userId,
    organizationId,
    sessionItemId,
  };
  @override
  CachedPlanningSessionItem map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedPlanningSessionItem(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      snapshotVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}snapshot_version'],
      )!,
      sessionItemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_item_id'],
      )!,
      planId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plan_id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      songTitle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_title'],
      )!,
    );
  }

  @override
  $CachedPlanningSessionItemsTable createAlias(String alias) {
    return $CachedPlanningSessionItemsTable(attachedDatabase, alias);
  }
}

class CachedPlanningSessionItem extends DataClass
    implements Insertable<CachedPlanningSessionItem> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final String sessionItemId;
  final String planId;
  final String sessionId;
  final int position;
  final String songId;
  final String songTitle;
  const CachedPlanningSessionItem({
    required this.userId,
    required this.organizationId,
    required this.snapshotVersion,
    required this.sessionItemId,
    required this.planId,
    required this.sessionId,
    required this.position,
    required this.songId,
    required this.songTitle,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['snapshot_version'] = Variable<int>(snapshotVersion);
    map['session_item_id'] = Variable<String>(sessionItemId);
    map['plan_id'] = Variable<String>(planId);
    map['session_id'] = Variable<String>(sessionId);
    map['position'] = Variable<int>(position);
    map['song_id'] = Variable<String>(songId);
    map['song_title'] = Variable<String>(songTitle);
    return map;
  }

  CachedPlanningSessionItemsCompanion toCompanion(bool nullToAbsent) {
    return CachedPlanningSessionItemsCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      sessionItemId: Value(sessionItemId),
      planId: Value(planId),
      sessionId: Value(sessionId),
      position: Value(position),
      songId: Value(songId),
      songTitle: Value(songTitle),
    );
  }

  factory CachedPlanningSessionItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedPlanningSessionItem(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      snapshotVersion: serializer.fromJson<int>(json['snapshotVersion']),
      sessionItemId: serializer.fromJson<String>(json['sessionItemId']),
      planId: serializer.fromJson<String>(json['planId']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      position: serializer.fromJson<int>(json['position']),
      songId: serializer.fromJson<String>(json['songId']),
      songTitle: serializer.fromJson<String>(json['songTitle']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'snapshotVersion': serializer.toJson<int>(snapshotVersion),
      'sessionItemId': serializer.toJson<String>(sessionItemId),
      'planId': serializer.toJson<String>(planId),
      'sessionId': serializer.toJson<String>(sessionId),
      'position': serializer.toJson<int>(position),
      'songId': serializer.toJson<String>(songId),
      'songTitle': serializer.toJson<String>(songTitle),
    };
  }

  CachedPlanningSessionItem copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    String? sessionItemId,
    String? planId,
    String? sessionId,
    int? position,
    String? songId,
    String? songTitle,
  }) => CachedPlanningSessionItem(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    sessionItemId: sessionItemId ?? this.sessionItemId,
    planId: planId ?? this.planId,
    sessionId: sessionId ?? this.sessionId,
    position: position ?? this.position,
    songId: songId ?? this.songId,
    songTitle: songTitle ?? this.songTitle,
  );
  CachedPlanningSessionItem copyWithCompanion(
    CachedPlanningSessionItemsCompanion data,
  ) {
    return CachedPlanningSessionItem(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      snapshotVersion: data.snapshotVersion.present
          ? data.snapshotVersion.value
          : this.snapshotVersion,
      sessionItemId: data.sessionItemId.present
          ? data.sessionItemId.value
          : this.sessionItemId,
      planId: data.planId.present ? data.planId.value : this.planId,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      position: data.position.present ? data.position.value : this.position,
      songId: data.songId.present ? data.songId.value : this.songId,
      songTitle: data.songTitle.present ? data.songTitle.value : this.songTitle,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlanningSessionItem(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('sessionItemId: $sessionItemId, ')
          ..write('planId: $planId, ')
          ..write('sessionId: $sessionId, ')
          ..write('position: $position, ')
          ..write('songId: $songId, ')
          ..write('songTitle: $songTitle')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    organizationId,
    snapshotVersion,
    sessionItemId,
    planId,
    sessionId,
    position,
    songId,
    songTitle,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedPlanningSessionItem &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.sessionItemId == this.sessionItemId &&
          other.planId == this.planId &&
          other.sessionId == this.sessionId &&
          other.position == this.position &&
          other.songId == this.songId &&
          other.songTitle == this.songTitle);
}

class CachedPlanningSessionItemsCompanion
    extends UpdateCompanion<CachedPlanningSessionItem> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<String> sessionItemId;
  final Value<String> planId;
  final Value<String> sessionId;
  final Value<int> position;
  final Value<String> songId;
  final Value<String> songTitle;
  final Value<int> rowid;
  const CachedPlanningSessionItemsCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.sessionItemId = const Value.absent(),
    this.planId = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.position = const Value.absent(),
    this.songId = const Value.absent(),
    this.songTitle = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedPlanningSessionItemsCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required String sessionItemId,
    required String planId,
    required String sessionId,
    required int position,
    required String songId,
    required String songTitle,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       sessionItemId = Value(sessionItemId),
       planId = Value(planId),
       sessionId = Value(sessionId),
       position = Value(position),
       songId = Value(songId),
       songTitle = Value(songTitle);
  static Insertable<CachedPlanningSessionItem> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<int>? snapshotVersion,
    Expression<String>? sessionItemId,
    Expression<String>? planId,
    Expression<String>? sessionId,
    Expression<int>? position,
    Expression<String>? songId,
    Expression<String>? songTitle,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (snapshotVersion != null) 'snapshot_version': snapshotVersion,
      if (sessionItemId != null) 'session_item_id': sessionItemId,
      if (planId != null) 'plan_id': planId,
      if (sessionId != null) 'session_id': sessionId,
      if (position != null) 'position': position,
      if (songId != null) 'song_id': songId,
      if (songTitle != null) 'song_title': songTitle,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedPlanningSessionItemsCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<String>? sessionItemId,
    Value<String>? planId,
    Value<String>? sessionId,
    Value<int>? position,
    Value<String>? songId,
    Value<String>? songTitle,
    Value<int>? rowid,
  }) {
    return CachedPlanningSessionItemsCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      sessionItemId: sessionItemId ?? this.sessionItemId,
      planId: planId ?? this.planId,
      sessionId: sessionId ?? this.sessionId,
      position: position ?? this.position,
      songId: songId ?? this.songId,
      songTitle: songTitle ?? this.songTitle,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (snapshotVersion.present) {
      map['snapshot_version'] = Variable<int>(snapshotVersion.value);
    }
    if (sessionItemId.present) {
      map['session_item_id'] = Variable<String>(sessionItemId.value);
    }
    if (planId.present) {
      map['plan_id'] = Variable<String>(planId.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (songTitle.present) {
      map['song_title'] = Variable<String>(songTitle.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedPlanningSessionItemsCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('sessionItemId: $sessionItemId, ')
          ..write('planId: $planId, ')
          ..write('sessionId: $sessionId, ')
          ..write('position: $position, ')
          ..write('songId: $songId, ')
          ..write('songTitle: $songTitle, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$PlanningLocalDatabase extends GeneratedDatabase {
  _$PlanningLocalDatabase(QueryExecutor e) : super(e);
  $PlanningLocalDatabaseManager get managers =>
      $PlanningLocalDatabaseManager(this);
  late final $PlanningProjectionOwnersTable planningProjectionOwners =
      $PlanningProjectionOwnersTable(this);
  late final $CachedPlanningPlansTable cachedPlanningPlans =
      $CachedPlanningPlansTable(this);
  late final $CachedPlanningSessionsTable cachedPlanningSessions =
      $CachedPlanningSessionsTable(this);
  late final $CachedPlanningSessionItemsTable cachedPlanningSessionItems =
      $CachedPlanningSessionItemsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    planningProjectionOwners,
    cachedPlanningPlans,
    cachedPlanningSessions,
    cachedPlanningSessionItems,
  ];
}

typedef $$PlanningProjectionOwnersTableCreateCompanionBuilder =
    PlanningProjectionOwnersCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required DateTime refreshedAt,
      Value<int> rowid,
    });
typedef $$PlanningProjectionOwnersTableUpdateCompanionBuilder =
    PlanningProjectionOwnersCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<DateTime> refreshedAt,
      Value<int> rowid,
    });

class $$PlanningProjectionOwnersTableFilterComposer
    extends Composer<_$PlanningLocalDatabase, $PlanningProjectionOwnersTable> {
  $$PlanningProjectionOwnersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PlanningProjectionOwnersTableOrderingComposer
    extends Composer<_$PlanningLocalDatabase, $PlanningProjectionOwnersTable> {
  $$PlanningProjectionOwnersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlanningProjectionOwnersTableAnnotationComposer
    extends Composer<_$PlanningLocalDatabase, $PlanningProjectionOwnersTable> {
  $$PlanningProjectionOwnersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get refreshedAt => $composableBuilder(
    column: $table.refreshedAt,
    builder: (column) => column,
  );
}

class $$PlanningProjectionOwnersTableTableManager
    extends
        RootTableManager<
          _$PlanningLocalDatabase,
          $PlanningProjectionOwnersTable,
          PlanningProjectionOwner,
          $$PlanningProjectionOwnersTableFilterComposer,
          $$PlanningProjectionOwnersTableOrderingComposer,
          $$PlanningProjectionOwnersTableAnnotationComposer,
          $$PlanningProjectionOwnersTableCreateCompanionBuilder,
          $$PlanningProjectionOwnersTableUpdateCompanionBuilder,
          (
            PlanningProjectionOwner,
            BaseReferences<
              _$PlanningLocalDatabase,
              $PlanningProjectionOwnersTable,
              PlanningProjectionOwner
            >,
          ),
          PlanningProjectionOwner,
          PrefetchHooks Function()
        > {
  $$PlanningProjectionOwnersTableTableManager(
    _$PlanningLocalDatabase db,
    $PlanningProjectionOwnersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlanningProjectionOwnersTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$PlanningProjectionOwnersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$PlanningProjectionOwnersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<int> snapshotVersion = const Value.absent(),
                Value<DateTime> refreshedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PlanningProjectionOwnersCompanion(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required int snapshotVersion,
                required DateTime refreshedAt,
                Value<int> rowid = const Value.absent(),
              }) => PlanningProjectionOwnersCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                refreshedAt: refreshedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PlanningProjectionOwnersTableProcessedTableManager =
    ProcessedTableManager<
      _$PlanningLocalDatabase,
      $PlanningProjectionOwnersTable,
      PlanningProjectionOwner,
      $$PlanningProjectionOwnersTableFilterComposer,
      $$PlanningProjectionOwnersTableOrderingComposer,
      $$PlanningProjectionOwnersTableAnnotationComposer,
      $$PlanningProjectionOwnersTableCreateCompanionBuilder,
      $$PlanningProjectionOwnersTableUpdateCompanionBuilder,
      (
        PlanningProjectionOwner,
        BaseReferences<
          _$PlanningLocalDatabase,
          $PlanningProjectionOwnersTable,
          PlanningProjectionOwner
        >,
      ),
      PlanningProjectionOwner,
      PrefetchHooks Function()
    >;
typedef $$CachedPlanningPlansTableCreateCompanionBuilder =
    CachedPlanningPlansCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required String planId,
      required String slug,
      required String name,
      Value<String?> description,
      Value<DateTime?> scheduledFor,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$CachedPlanningPlansTableUpdateCompanionBuilder =
    CachedPlanningPlansCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<String> planId,
      Value<String> slug,
      Value<String> name,
      Value<String?> description,
      Value<DateTime?> scheduledFor,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$CachedPlanningPlansTableFilterComposer
    extends Composer<_$PlanningLocalDatabase, $CachedPlanningPlansTable> {
  $$CachedPlanningPlansTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPlanningPlansTableOrderingComposer
    extends Composer<_$PlanningLocalDatabase, $CachedPlanningPlansTable> {
  $$CachedPlanningPlansTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPlanningPlansTableAnnotationComposer
    extends Composer<_$PlanningLocalDatabase, $CachedPlanningPlansTable> {
  $$CachedPlanningPlansTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get scheduledFor => $composableBuilder(
    column: $table.scheduledFor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$CachedPlanningPlansTableTableManager
    extends
        RootTableManager<
          _$PlanningLocalDatabase,
          $CachedPlanningPlansTable,
          CachedPlanningPlan,
          $$CachedPlanningPlansTableFilterComposer,
          $$CachedPlanningPlansTableOrderingComposer,
          $$CachedPlanningPlansTableAnnotationComposer,
          $$CachedPlanningPlansTableCreateCompanionBuilder,
          $$CachedPlanningPlansTableUpdateCompanionBuilder,
          (
            CachedPlanningPlan,
            BaseReferences<
              _$PlanningLocalDatabase,
              $CachedPlanningPlansTable,
              CachedPlanningPlan
            >,
          ),
          CachedPlanningPlan,
          PrefetchHooks Function()
        > {
  $$CachedPlanningPlansTableTableManager(
    _$PlanningLocalDatabase db,
    $CachedPlanningPlansTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPlanningPlansTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedPlanningPlansTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedPlanningPlansTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<int> snapshotVersion = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<DateTime?> scheduledFor = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPlanningPlansCompanion(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                planId: planId,
                slug: slug,
                name: name,
                description: description,
                scheduledFor: scheduledFor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required int snapshotVersion,
                required String planId,
                required String slug,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<DateTime?> scheduledFor = const Value.absent(),
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CachedPlanningPlansCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                planId: planId,
                slug: slug,
                name: name,
                description: description,
                scheduledFor: scheduledFor,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPlanningPlansTableProcessedTableManager =
    ProcessedTableManager<
      _$PlanningLocalDatabase,
      $CachedPlanningPlansTable,
      CachedPlanningPlan,
      $$CachedPlanningPlansTableFilterComposer,
      $$CachedPlanningPlansTableOrderingComposer,
      $$CachedPlanningPlansTableAnnotationComposer,
      $$CachedPlanningPlansTableCreateCompanionBuilder,
      $$CachedPlanningPlansTableUpdateCompanionBuilder,
      (
        CachedPlanningPlan,
        BaseReferences<
          _$PlanningLocalDatabase,
          $CachedPlanningPlansTable,
          CachedPlanningPlan
        >,
      ),
      CachedPlanningPlan,
      PrefetchHooks Function()
    >;
typedef $$CachedPlanningSessionsTableCreateCompanionBuilder =
    CachedPlanningSessionsCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required String sessionId,
      required String planId,
      required String slug,
      required int position,
      required String name,
      Value<int> rowid,
    });
typedef $$CachedPlanningSessionsTableUpdateCompanionBuilder =
    CachedPlanningSessionsCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<String> sessionId,
      Value<String> planId,
      Value<String> slug,
      Value<int> position,
      Value<String> name,
      Value<int> rowid,
    });

class $$CachedPlanningSessionsTableFilterComposer
    extends Composer<_$PlanningLocalDatabase, $CachedPlanningSessionsTable> {
  $$CachedPlanningSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPlanningSessionsTableOrderingComposer
    extends Composer<_$PlanningLocalDatabase, $CachedPlanningSessionsTable> {
  $$CachedPlanningSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPlanningSessionsTableAnnotationComposer
    extends Composer<_$PlanningLocalDatabase, $CachedPlanningSessionsTable> {
  $$CachedPlanningSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$CachedPlanningSessionsTableTableManager
    extends
        RootTableManager<
          _$PlanningLocalDatabase,
          $CachedPlanningSessionsTable,
          CachedPlanningSession,
          $$CachedPlanningSessionsTableFilterComposer,
          $$CachedPlanningSessionsTableOrderingComposer,
          $$CachedPlanningSessionsTableAnnotationComposer,
          $$CachedPlanningSessionsTableCreateCompanionBuilder,
          $$CachedPlanningSessionsTableUpdateCompanionBuilder,
          (
            CachedPlanningSession,
            BaseReferences<
              _$PlanningLocalDatabase,
              $CachedPlanningSessionsTable,
              CachedPlanningSession
            >,
          ),
          CachedPlanningSession,
          PrefetchHooks Function()
        > {
  $$CachedPlanningSessionsTableTableManager(
    _$PlanningLocalDatabase db,
    $CachedPlanningSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPlanningSessionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedPlanningSessionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedPlanningSessionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<int> snapshotVersion = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPlanningSessionsCompanion(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                sessionId: sessionId,
                planId: planId,
                slug: slug,
                position: position,
                name: name,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required int snapshotVersion,
                required String sessionId,
                required String planId,
                required String slug,
                required int position,
                required String name,
                Value<int> rowid = const Value.absent(),
              }) => CachedPlanningSessionsCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                sessionId: sessionId,
                planId: planId,
                slug: slug,
                position: position,
                name: name,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPlanningSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$PlanningLocalDatabase,
      $CachedPlanningSessionsTable,
      CachedPlanningSession,
      $$CachedPlanningSessionsTableFilterComposer,
      $$CachedPlanningSessionsTableOrderingComposer,
      $$CachedPlanningSessionsTableAnnotationComposer,
      $$CachedPlanningSessionsTableCreateCompanionBuilder,
      $$CachedPlanningSessionsTableUpdateCompanionBuilder,
      (
        CachedPlanningSession,
        BaseReferences<
          _$PlanningLocalDatabase,
          $CachedPlanningSessionsTable,
          CachedPlanningSession
        >,
      ),
      CachedPlanningSession,
      PrefetchHooks Function()
    >;
typedef $$CachedPlanningSessionItemsTableCreateCompanionBuilder =
    CachedPlanningSessionItemsCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required String sessionItemId,
      required String planId,
      required String sessionId,
      required int position,
      required String songId,
      required String songTitle,
      Value<int> rowid,
    });
typedef $$CachedPlanningSessionItemsTableUpdateCompanionBuilder =
    CachedPlanningSessionItemsCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<String> sessionItemId,
      Value<String> planId,
      Value<String> sessionId,
      Value<int> position,
      Value<String> songId,
      Value<String> songTitle,
      Value<int> rowid,
    });

class $$CachedPlanningSessionItemsTableFilterComposer
    extends
        Composer<_$PlanningLocalDatabase, $CachedPlanningSessionItemsTable> {
  $$CachedPlanningSessionItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionItemId => $composableBuilder(
    column: $table.sessionItemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get songTitle => $composableBuilder(
    column: $table.songTitle,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedPlanningSessionItemsTableOrderingComposer
    extends
        Composer<_$PlanningLocalDatabase, $CachedPlanningSessionItemsTable> {
  $$CachedPlanningSessionItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionItemId => $composableBuilder(
    column: $table.sessionItemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get planId => $composableBuilder(
    column: $table.planId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get songTitle => $composableBuilder(
    column: $table.songTitle,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedPlanningSessionItemsTableAnnotationComposer
    extends
        Composer<_$PlanningLocalDatabase, $CachedPlanningSessionItemsTable> {
  $$CachedPlanningSessionItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get snapshotVersion => $composableBuilder(
    column: $table.snapshotVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sessionItemId => $composableBuilder(
    column: $table.sessionItemId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get planId =>
      $composableBuilder(column: $table.planId, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get songTitle =>
      $composableBuilder(column: $table.songTitle, builder: (column) => column);
}

class $$CachedPlanningSessionItemsTableTableManager
    extends
        RootTableManager<
          _$PlanningLocalDatabase,
          $CachedPlanningSessionItemsTable,
          CachedPlanningSessionItem,
          $$CachedPlanningSessionItemsTableFilterComposer,
          $$CachedPlanningSessionItemsTableOrderingComposer,
          $$CachedPlanningSessionItemsTableAnnotationComposer,
          $$CachedPlanningSessionItemsTableCreateCompanionBuilder,
          $$CachedPlanningSessionItemsTableUpdateCompanionBuilder,
          (
            CachedPlanningSessionItem,
            BaseReferences<
              _$PlanningLocalDatabase,
              $CachedPlanningSessionItemsTable,
              CachedPlanningSessionItem
            >,
          ),
          CachedPlanningSessionItem,
          PrefetchHooks Function()
        > {
  $$CachedPlanningSessionItemsTableTableManager(
    _$PlanningLocalDatabase db,
    $CachedPlanningSessionItemsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedPlanningSessionItemsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedPlanningSessionItemsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedPlanningSessionItemsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<int> snapshotVersion = const Value.absent(),
                Value<String> sessionItemId = const Value.absent(),
                Value<String> planId = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> songTitle = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedPlanningSessionItemsCompanion(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                sessionItemId: sessionItemId,
                planId: planId,
                sessionId: sessionId,
                position: position,
                songId: songId,
                songTitle: songTitle,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required int snapshotVersion,
                required String sessionItemId,
                required String planId,
                required String sessionId,
                required int position,
                required String songId,
                required String songTitle,
                Value<int> rowid = const Value.absent(),
              }) => CachedPlanningSessionItemsCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                sessionItemId: sessionItemId,
                planId: planId,
                sessionId: sessionId,
                position: position,
                songId: songId,
                songTitle: songTitle,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedPlanningSessionItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$PlanningLocalDatabase,
      $CachedPlanningSessionItemsTable,
      CachedPlanningSessionItem,
      $$CachedPlanningSessionItemsTableFilterComposer,
      $$CachedPlanningSessionItemsTableOrderingComposer,
      $$CachedPlanningSessionItemsTableAnnotationComposer,
      $$CachedPlanningSessionItemsTableCreateCompanionBuilder,
      $$CachedPlanningSessionItemsTableUpdateCompanionBuilder,
      (
        CachedPlanningSessionItem,
        BaseReferences<
          _$PlanningLocalDatabase,
          $CachedPlanningSessionItemsTable,
          CachedPlanningSessionItem
        >,
      ),
      CachedPlanningSessionItem,
      PrefetchHooks Function()
    >;

class $PlanningLocalDatabaseManager {
  final _$PlanningLocalDatabase _db;
  $PlanningLocalDatabaseManager(this._db);
  $$PlanningProjectionOwnersTableTableManager get planningProjectionOwners =>
      $$PlanningProjectionOwnersTableTableManager(
        _db,
        _db.planningProjectionOwners,
      );
  $$CachedPlanningPlansTableTableManager get cachedPlanningPlans =>
      $$CachedPlanningPlansTableTableManager(_db, _db.cachedPlanningPlans);
  $$CachedPlanningSessionsTableTableManager get cachedPlanningSessions =>
      $$CachedPlanningSessionsTableTableManager(
        _db,
        _db.cachedPlanningSessions,
      );
  $$CachedPlanningSessionItemsTableTableManager
  get cachedPlanningSessionItems =>
      $$CachedPlanningSessionItemsTableTableManager(
        _db,
        _db.cachedPlanningSessionItems,
      );
}
