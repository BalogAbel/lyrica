// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_data_events_database.dart';

// ignore_for_file: type=lint
class $LocalDataEventsTable extends LocalDataEvents
    with TableInfo<$LocalDataEventsTable, LocalDataEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LocalDataEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _targetMeta = const VerificationMeta('target');
  @override
  late final GeneratedColumn<String> target = GeneratedColumn<String>(
    'target',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rowsAffectedMeta = const VerificationMeta(
    'rowsAffected',
  );
  @override
  late final GeneratedColumn<int> rowsAffected = GeneratedColumn<int>(
    'rows_affected',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    occurredAt,
    kind,
    target,
    reason,
    userId,
    rowsAffected,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'local_data_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<LocalDataEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('target')) {
      context.handle(
        _targetMeta,
        target.isAcceptableOrUnknown(data['target']!, _targetMeta),
      );
    } else if (isInserting) {
      context.missing(_targetMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('rows_affected')) {
      context.handle(
        _rowsAffectedMeta,
        rowsAffected.isAcceptableOrUnknown(
          data['rows_affected']!,
          _rowsAffectedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  LocalDataEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LocalDataEvent(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      target: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}target'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      rowsAffected: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rows_affected'],
      ),
    );
  }

  @override
  $LocalDataEventsTable createAlias(String alias) {
    return $LocalDataEventsTable(attachedDatabase, alias);
  }
}

class LocalDataEvent extends DataClass implements Insertable<LocalDataEvent> {
  final int id;
  final DateTime occurredAt;
  final String kind;
  final String target;
  final String? reason;
  final String? userId;
  final int? rowsAffected;
  const LocalDataEvent({
    required this.id,
    required this.occurredAt,
    required this.kind,
    required this.target,
    this.reason,
    this.userId,
    this.rowsAffected,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['kind'] = Variable<String>(kind);
    map['target'] = Variable<String>(target);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    if (!nullToAbsent || rowsAffected != null) {
      map['rows_affected'] = Variable<int>(rowsAffected);
    }
    return map;
  }

  LocalDataEventsCompanion toCompanion(bool nullToAbsent) {
    return LocalDataEventsCompanion(
      id: Value(id),
      occurredAt: Value(occurredAt),
      kind: Value(kind),
      target: Value(target),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      rowsAffected: rowsAffected == null && nullToAbsent
          ? const Value.absent()
          : Value(rowsAffected),
    );
  }

  factory LocalDataEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LocalDataEvent(
      id: serializer.fromJson<int>(json['id']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      kind: serializer.fromJson<String>(json['kind']),
      target: serializer.fromJson<String>(json['target']),
      reason: serializer.fromJson<String?>(json['reason']),
      userId: serializer.fromJson<String?>(json['userId']),
      rowsAffected: serializer.fromJson<int?>(json['rowsAffected']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'kind': serializer.toJson<String>(kind),
      'target': serializer.toJson<String>(target),
      'reason': serializer.toJson<String?>(reason),
      'userId': serializer.toJson<String?>(userId),
      'rowsAffected': serializer.toJson<int?>(rowsAffected),
    };
  }

  LocalDataEvent copyWith({
    int? id,
    DateTime? occurredAt,
    String? kind,
    String? target,
    Value<String?> reason = const Value.absent(),
    Value<String?> userId = const Value.absent(),
    Value<int?> rowsAffected = const Value.absent(),
  }) => LocalDataEvent(
    id: id ?? this.id,
    occurredAt: occurredAt ?? this.occurredAt,
    kind: kind ?? this.kind,
    target: target ?? this.target,
    reason: reason.present ? reason.value : this.reason,
    userId: userId.present ? userId.value : this.userId,
    rowsAffected: rowsAffected.present ? rowsAffected.value : this.rowsAffected,
  );
  LocalDataEvent copyWithCompanion(LocalDataEventsCompanion data) {
    return LocalDataEvent(
      id: data.id.present ? data.id.value : this.id,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      kind: data.kind.present ? data.kind.value : this.kind,
      target: data.target.present ? data.target.value : this.target,
      reason: data.reason.present ? data.reason.value : this.reason,
      userId: data.userId.present ? data.userId.value : this.userId,
      rowsAffected: data.rowsAffected.present
          ? data.rowsAffected.value
          : this.rowsAffected,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LocalDataEvent(')
          ..write('id: $id, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('kind: $kind, ')
          ..write('target: $target, ')
          ..write('reason: $reason, ')
          ..write('userId: $userId, ')
          ..write('rowsAffected: $rowsAffected')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, occurredAt, kind, target, reason, userId, rowsAffected);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LocalDataEvent &&
          other.id == this.id &&
          other.occurredAt == this.occurredAt &&
          other.kind == this.kind &&
          other.target == this.target &&
          other.reason == this.reason &&
          other.userId == this.userId &&
          other.rowsAffected == this.rowsAffected);
}

class LocalDataEventsCompanion extends UpdateCompanion<LocalDataEvent> {
  final Value<int> id;
  final Value<DateTime> occurredAt;
  final Value<String> kind;
  final Value<String> target;
  final Value<String?> reason;
  final Value<String?> userId;
  final Value<int?> rowsAffected;
  const LocalDataEventsCompanion({
    this.id = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.kind = const Value.absent(),
    this.target = const Value.absent(),
    this.reason = const Value.absent(),
    this.userId = const Value.absent(),
    this.rowsAffected = const Value.absent(),
  });
  LocalDataEventsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime occurredAt,
    required String kind,
    required String target,
    this.reason = const Value.absent(),
    this.userId = const Value.absent(),
    this.rowsAffected = const Value.absent(),
  }) : occurredAt = Value(occurredAt),
       kind = Value(kind),
       target = Value(target);
  static Insertable<LocalDataEvent> custom({
    Expression<int>? id,
    Expression<DateTime>? occurredAt,
    Expression<String>? kind,
    Expression<String>? target,
    Expression<String>? reason,
    Expression<String>? userId,
    Expression<int>? rowsAffected,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (kind != null) 'kind': kind,
      if (target != null) 'target': target,
      if (reason != null) 'reason': reason,
      if (userId != null) 'user_id': userId,
      if (rowsAffected != null) 'rows_affected': rowsAffected,
    });
  }

  LocalDataEventsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? occurredAt,
    Value<String>? kind,
    Value<String>? target,
    Value<String?>? reason,
    Value<String?>? userId,
    Value<int?>? rowsAffected,
  }) {
    return LocalDataEventsCompanion(
      id: id ?? this.id,
      occurredAt: occurredAt ?? this.occurredAt,
      kind: kind ?? this.kind,
      target: target ?? this.target,
      reason: reason ?? this.reason,
      userId: userId ?? this.userId,
      rowsAffected: rowsAffected ?? this.rowsAffected,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (target.present) {
      map['target'] = Variable<String>(target.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (rowsAffected.present) {
      map['rows_affected'] = Variable<int>(rowsAffected.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LocalDataEventsCompanion(')
          ..write('id: $id, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('kind: $kind, ')
          ..write('target: $target, ')
          ..write('reason: $reason, ')
          ..write('userId: $userId, ')
          ..write('rowsAffected: $rowsAffected')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDataEventsDatabase extends GeneratedDatabase {
  _$LocalDataEventsDatabase(QueryExecutor e) : super(e);
  $LocalDataEventsDatabaseManager get managers =>
      $LocalDataEventsDatabaseManager(this);
  late final $LocalDataEventsTable localDataEvents = $LocalDataEventsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [localDataEvents];
}

typedef $$LocalDataEventsTableCreateCompanionBuilder =
    LocalDataEventsCompanion Function({
      Value<int> id,
      required DateTime occurredAt,
      required String kind,
      required String target,
      Value<String?> reason,
      Value<String?> userId,
      Value<int?> rowsAffected,
    });
typedef $$LocalDataEventsTableUpdateCompanionBuilder =
    LocalDataEventsCompanion Function({
      Value<int> id,
      Value<DateTime> occurredAt,
      Value<String> kind,
      Value<String> target,
      Value<String?> reason,
      Value<String?> userId,
      Value<int?> rowsAffected,
    });

class $$LocalDataEventsTableFilterComposer
    extends Composer<_$LocalDataEventsDatabase, $LocalDataEventsTable> {
  $$LocalDataEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowsAffected => $composableBuilder(
    column: $table.rowsAffected,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LocalDataEventsTableOrderingComposer
    extends Composer<_$LocalDataEventsDatabase, $LocalDataEventsTable> {
  $$LocalDataEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get target => $composableBuilder(
    column: $table.target,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowsAffected => $composableBuilder(
    column: $table.rowsAffected,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LocalDataEventsTableAnnotationComposer
    extends Composer<_$LocalDataEventsDatabase, $LocalDataEventsTable> {
  $$LocalDataEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get target =>
      $composableBuilder(column: $table.target, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get rowsAffected => $composableBuilder(
    column: $table.rowsAffected,
    builder: (column) => column,
  );
}

class $$LocalDataEventsTableTableManager
    extends
        RootTableManager<
          _$LocalDataEventsDatabase,
          $LocalDataEventsTable,
          LocalDataEvent,
          $$LocalDataEventsTableFilterComposer,
          $$LocalDataEventsTableOrderingComposer,
          $$LocalDataEventsTableAnnotationComposer,
          $$LocalDataEventsTableCreateCompanionBuilder,
          $$LocalDataEventsTableUpdateCompanionBuilder,
          (
            LocalDataEvent,
            BaseReferences<
              _$LocalDataEventsDatabase,
              $LocalDataEventsTable,
              LocalDataEvent
            >,
          ),
          LocalDataEvent,
          PrefetchHooks Function()
        > {
  $$LocalDataEventsTableTableManager(
    _$LocalDataEventsDatabase db,
    $LocalDataEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LocalDataEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LocalDataEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LocalDataEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> target = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<int?> rowsAffected = const Value.absent(),
              }) => LocalDataEventsCompanion(
                id: id,
                occurredAt: occurredAt,
                kind: kind,
                target: target,
                reason: reason,
                userId: userId,
                rowsAffected: rowsAffected,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime occurredAt,
                required String kind,
                required String target,
                Value<String?> reason = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<int?> rowsAffected = const Value.absent(),
              }) => LocalDataEventsCompanion.insert(
                id: id,
                occurredAt: occurredAt,
                kind: kind,
                target: target,
                reason: reason,
                userId: userId,
                rowsAffected: rowsAffected,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LocalDataEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDataEventsDatabase,
      $LocalDataEventsTable,
      LocalDataEvent,
      $$LocalDataEventsTableFilterComposer,
      $$LocalDataEventsTableOrderingComposer,
      $$LocalDataEventsTableAnnotationComposer,
      $$LocalDataEventsTableCreateCompanionBuilder,
      $$LocalDataEventsTableUpdateCompanionBuilder,
      (
        LocalDataEvent,
        BaseReferences<
          _$LocalDataEventsDatabase,
          $LocalDataEventsTable,
          LocalDataEvent
        >,
      ),
      LocalDataEvent,
      PrefetchHooks Function()
    >;

class $LocalDataEventsDatabaseManager {
  final _$LocalDataEventsDatabase _db;
  $LocalDataEventsDatabaseManager(this._db);
  $$LocalDataEventsTableTableManager get localDataEvents =>
      $$LocalDataEventsTableTableManager(_db, _db.localDataEvents);
}
