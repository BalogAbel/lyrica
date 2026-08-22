// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'last_known_identity_database.dart';

// ignore_for_file: type=lint
class $LastKnownIdentityRowsTable extends LastKnownIdentityRows
    with TableInfo<$LastKnownIdentityRowsTable, LastKnownIdentityRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LastKnownIdentityRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _rowIdMeta = const VerificationMeta('rowId');
  @override
  late final GeneratedColumn<int> rowId = GeneratedColumn<int>(
    'row_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _membershipRevokedAtMeta =
      const VerificationMeta('membershipRevokedAt');
  @override
  late final GeneratedColumn<DateTime> membershipRevokedAt =
      GeneratedColumn<DateTime>(
        'membership_revoked_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    rowId,
    userId,
    email,
    organizationId,
    updatedAt,
    membershipRevokedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'last_known_identity_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<LastKnownIdentityRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('row_id')) {
      context.handle(
        _rowIdMeta,
        rowId.isAcceptableOrUnknown(data['row_id']!, _rowIdMeta),
      );
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('organization_id')) {
      context.handle(
        _organizationIdMeta,
        organizationId.isAcceptableOrUnknown(
          data['organization_id']!,
          _organizationIdMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('membership_revoked_at')) {
      context.handle(
        _membershipRevokedAtMeta,
        membershipRevokedAt.isAcceptableOrUnknown(
          data['membership_revoked_at']!,
          _membershipRevokedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {rowId};
  @override
  LastKnownIdentityRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LastKnownIdentityRow(
      rowId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      ),
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      ),
      membershipRevokedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}membership_revoked_at'],
      ),
    );
  }

  @override
  $LastKnownIdentityRowsTable createAlias(String alias) {
    return $LastKnownIdentityRowsTable(attachedDatabase, alias);
  }
}

class LastKnownIdentityRow extends DataClass
    implements Insertable<LastKnownIdentityRow> {
  final int rowId;
  final String userId;
  final String email;
  final String? organizationId;
  final DateTime? updatedAt;
  final DateTime? membershipRevokedAt;
  const LastKnownIdentityRow({
    required this.rowId,
    required this.userId,
    required this.email,
    this.organizationId,
    this.updatedAt,
    this.membershipRevokedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['row_id'] = Variable<int>(rowId);
    map['user_id'] = Variable<String>(userId);
    map['email'] = Variable<String>(email);
    if (!nullToAbsent || organizationId != null) {
      map['organization_id'] = Variable<String>(organizationId);
    }
    if (!nullToAbsent || updatedAt != null) {
      map['updated_at'] = Variable<DateTime>(updatedAt);
    }
    if (!nullToAbsent || membershipRevokedAt != null) {
      map['membership_revoked_at'] = Variable<DateTime>(membershipRevokedAt);
    }
    return map;
  }

  LastKnownIdentityRowsCompanion toCompanion(bool nullToAbsent) {
    return LastKnownIdentityRowsCompanion(
      rowId: Value(rowId),
      userId: Value(userId),
      email: Value(email),
      organizationId: organizationId == null && nullToAbsent
          ? const Value.absent()
          : Value(organizationId),
      updatedAt: updatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(updatedAt),
      membershipRevokedAt: membershipRevokedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(membershipRevokedAt),
    );
  }

  factory LastKnownIdentityRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LastKnownIdentityRow(
      rowId: serializer.fromJson<int>(json['rowId']),
      userId: serializer.fromJson<String>(json['userId']),
      email: serializer.fromJson<String>(json['email']),
      organizationId: serializer.fromJson<String?>(json['organizationId']),
      updatedAt: serializer.fromJson<DateTime?>(json['updatedAt']),
      membershipRevokedAt: serializer.fromJson<DateTime?>(
        json['membershipRevokedAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'rowId': serializer.toJson<int>(rowId),
      'userId': serializer.toJson<String>(userId),
      'email': serializer.toJson<String>(email),
      'organizationId': serializer.toJson<String?>(organizationId),
      'updatedAt': serializer.toJson<DateTime?>(updatedAt),
      'membershipRevokedAt': serializer.toJson<DateTime?>(membershipRevokedAt),
    };
  }

  LastKnownIdentityRow copyWith({
    int? rowId,
    String? userId,
    String? email,
    Value<String?> organizationId = const Value.absent(),
    Value<DateTime?> updatedAt = const Value.absent(),
    Value<DateTime?> membershipRevokedAt = const Value.absent(),
  }) => LastKnownIdentityRow(
    rowId: rowId ?? this.rowId,
    userId: userId ?? this.userId,
    email: email ?? this.email,
    organizationId: organizationId.present
        ? organizationId.value
        : this.organizationId,
    updatedAt: updatedAt.present ? updatedAt.value : this.updatedAt,
    membershipRevokedAt: membershipRevokedAt.present
        ? membershipRevokedAt.value
        : this.membershipRevokedAt,
  );
  LastKnownIdentityRow copyWithCompanion(LastKnownIdentityRowsCompanion data) {
    return LastKnownIdentityRow(
      rowId: data.rowId.present ? data.rowId.value : this.rowId,
      userId: data.userId.present ? data.userId.value : this.userId,
      email: data.email.present ? data.email.value : this.email,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      membershipRevokedAt: data.membershipRevokedAt.present
          ? data.membershipRevokedAt.value
          : this.membershipRevokedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LastKnownIdentityRow(')
          ..write('rowId: $rowId, ')
          ..write('userId: $userId, ')
          ..write('email: $email, ')
          ..write('organizationId: $organizationId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('membershipRevokedAt: $membershipRevokedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    rowId,
    userId,
    email,
    organizationId,
    updatedAt,
    membershipRevokedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LastKnownIdentityRow &&
          other.rowId == this.rowId &&
          other.userId == this.userId &&
          other.email == this.email &&
          other.organizationId == this.organizationId &&
          other.updatedAt == this.updatedAt &&
          other.membershipRevokedAt == this.membershipRevokedAt);
}

class LastKnownIdentityRowsCompanion
    extends UpdateCompanion<LastKnownIdentityRow> {
  final Value<int> rowId;
  final Value<String> userId;
  final Value<String> email;
  final Value<String?> organizationId;
  final Value<DateTime?> updatedAt;
  final Value<DateTime?> membershipRevokedAt;
  const LastKnownIdentityRowsCompanion({
    this.rowId = const Value.absent(),
    this.userId = const Value.absent(),
    this.email = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.membershipRevokedAt = const Value.absent(),
  });
  LastKnownIdentityRowsCompanion.insert({
    this.rowId = const Value.absent(),
    required String userId,
    required String email,
    this.organizationId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.membershipRevokedAt = const Value.absent(),
  }) : userId = Value(userId),
       email = Value(email);
  static Insertable<LastKnownIdentityRow> custom({
    Expression<int>? rowId,
    Expression<String>? userId,
    Expression<String>? email,
    Expression<String>? organizationId,
    Expression<DateTime>? updatedAt,
    Expression<DateTime>? membershipRevokedAt,
  }) {
    return RawValuesInsertable({
      if (rowId != null) 'row_id': rowId,
      if (userId != null) 'user_id': userId,
      if (email != null) 'email': email,
      if (organizationId != null) 'organization_id': organizationId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (membershipRevokedAt != null)
        'membership_revoked_at': membershipRevokedAt,
    });
  }

  LastKnownIdentityRowsCompanion copyWith({
    Value<int>? rowId,
    Value<String>? userId,
    Value<String>? email,
    Value<String?>? organizationId,
    Value<DateTime?>? updatedAt,
    Value<DateTime?>? membershipRevokedAt,
  }) {
    return LastKnownIdentityRowsCompanion(
      rowId: rowId ?? this.rowId,
      userId: userId ?? this.userId,
      email: email ?? this.email,
      organizationId: organizationId ?? this.organizationId,
      updatedAt: updatedAt ?? this.updatedAt,
      membershipRevokedAt: membershipRevokedAt ?? this.membershipRevokedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (rowId.present) {
      map['row_id'] = Variable<int>(rowId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (organizationId.present) {
      map['organization_id'] = Variable<String>(organizationId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (membershipRevokedAt.present) {
      map['membership_revoked_at'] = Variable<DateTime>(
        membershipRevokedAt.value,
      );
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LastKnownIdentityRowsCompanion(')
          ..write('rowId: $rowId, ')
          ..write('userId: $userId, ')
          ..write('email: $email, ')
          ..write('organizationId: $organizationId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('membershipRevokedAt: $membershipRevokedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$LastKnownIdentityDatabase extends GeneratedDatabase {
  _$LastKnownIdentityDatabase(QueryExecutor e) : super(e);
  $LastKnownIdentityDatabaseManager get managers =>
      $LastKnownIdentityDatabaseManager(this);
  late final $LastKnownIdentityRowsTable lastKnownIdentityRows =
      $LastKnownIdentityRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [lastKnownIdentityRows];
}

typedef $$LastKnownIdentityRowsTableCreateCompanionBuilder =
    LastKnownIdentityRowsCompanion Function({
      Value<int> rowId,
      required String userId,
      required String email,
      Value<String?> organizationId,
      Value<DateTime?> updatedAt,
      Value<DateTime?> membershipRevokedAt,
    });
typedef $$LastKnownIdentityRowsTableUpdateCompanionBuilder =
    LastKnownIdentityRowsCompanion Function({
      Value<int> rowId,
      Value<String> userId,
      Value<String> email,
      Value<String?> organizationId,
      Value<DateTime?> updatedAt,
      Value<DateTime?> membershipRevokedAt,
    });

class $$LastKnownIdentityRowsTableFilterComposer
    extends Composer<_$LastKnownIdentityDatabase, $LastKnownIdentityRowsTable> {
  $$LastKnownIdentityRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get membershipRevokedAt => $composableBuilder(
    column: $table.membershipRevokedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LastKnownIdentityRowsTableOrderingComposer
    extends Composer<_$LastKnownIdentityDatabase, $LastKnownIdentityRowsTable> {
  $$LastKnownIdentityRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get rowId => $composableBuilder(
    column: $table.rowId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get membershipRevokedAt => $composableBuilder(
    column: $table.membershipRevokedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LastKnownIdentityRowsTableAnnotationComposer
    extends Composer<_$LastKnownIdentityDatabase, $LastKnownIdentityRowsTable> {
  $$LastKnownIdentityRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get rowId =>
      $composableBuilder(column: $table.rowId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get organizationId => $composableBuilder(
    column: $table.organizationId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get membershipRevokedAt => $composableBuilder(
    column: $table.membershipRevokedAt,
    builder: (column) => column,
  );
}

class $$LastKnownIdentityRowsTableTableManager
    extends
        RootTableManager<
          _$LastKnownIdentityDatabase,
          $LastKnownIdentityRowsTable,
          LastKnownIdentityRow,
          $$LastKnownIdentityRowsTableFilterComposer,
          $$LastKnownIdentityRowsTableOrderingComposer,
          $$LastKnownIdentityRowsTableAnnotationComposer,
          $$LastKnownIdentityRowsTableCreateCompanionBuilder,
          $$LastKnownIdentityRowsTableUpdateCompanionBuilder,
          (
            LastKnownIdentityRow,
            BaseReferences<
              _$LastKnownIdentityDatabase,
              $LastKnownIdentityRowsTable,
              LastKnownIdentityRow
            >,
          ),
          LastKnownIdentityRow,
          PrefetchHooks Function()
        > {
  $$LastKnownIdentityRowsTableTableManager(
    _$LastKnownIdentityDatabase db,
    $LastKnownIdentityRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LastKnownIdentityRowsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LastKnownIdentityRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LastKnownIdentityRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String?> organizationId = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> membershipRevokedAt = const Value.absent(),
              }) => LastKnownIdentityRowsCompanion(
                rowId: rowId,
                userId: userId,
                email: email,
                organizationId: organizationId,
                updatedAt: updatedAt,
                membershipRevokedAt: membershipRevokedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> rowId = const Value.absent(),
                required String userId,
                required String email,
                Value<String?> organizationId = const Value.absent(),
                Value<DateTime?> updatedAt = const Value.absent(),
                Value<DateTime?> membershipRevokedAt = const Value.absent(),
              }) => LastKnownIdentityRowsCompanion.insert(
                rowId: rowId,
                userId: userId,
                email: email,
                organizationId: organizationId,
                updatedAt: updatedAt,
                membershipRevokedAt: membershipRevokedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LastKnownIdentityRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$LastKnownIdentityDatabase,
      $LastKnownIdentityRowsTable,
      LastKnownIdentityRow,
      $$LastKnownIdentityRowsTableFilterComposer,
      $$LastKnownIdentityRowsTableOrderingComposer,
      $$LastKnownIdentityRowsTableAnnotationComposer,
      $$LastKnownIdentityRowsTableCreateCompanionBuilder,
      $$LastKnownIdentityRowsTableUpdateCompanionBuilder,
      (
        LastKnownIdentityRow,
        BaseReferences<
          _$LastKnownIdentityDatabase,
          $LastKnownIdentityRowsTable,
          LastKnownIdentityRow
        >,
      ),
      LastKnownIdentityRow,
      PrefetchHooks Function()
    >;

class $LastKnownIdentityDatabaseManager {
  final _$LastKnownIdentityDatabase _db;
  $LastKnownIdentityDatabaseManager(this._db);
  $$LastKnownIdentityRowsTableTableManager get lastKnownIdentityRows =>
      $$LastKnownIdentityRowsTableTableManager(_db, _db.lastKnownIdentityRows);
}
