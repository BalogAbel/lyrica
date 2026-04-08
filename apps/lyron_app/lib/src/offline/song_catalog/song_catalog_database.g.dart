// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'song_catalog_database.dart';

// ignore_for_file: type=lint
class $CachedCatalogSnapshotsTable extends CachedCatalogSnapshots
    with TableInfo<$CachedCatalogSnapshotsTable, CachedCatalogSnapshot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCatalogSnapshotsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'cached_catalog_snapshots';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCatalogSnapshot> instance, {
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
  CachedCatalogSnapshot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCatalogSnapshot(
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
  $CachedCatalogSnapshotsTable createAlias(String alias) {
    return $CachedCatalogSnapshotsTable(attachedDatabase, alias);
  }
}

class CachedCatalogSnapshot extends DataClass
    implements Insertable<CachedCatalogSnapshot> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final DateTime refreshedAt;
  const CachedCatalogSnapshot({
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

  CachedCatalogSnapshotsCompanion toCompanion(bool nullToAbsent) {
    return CachedCatalogSnapshotsCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      refreshedAt: Value(refreshedAt),
    );
  }

  factory CachedCatalogSnapshot.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCatalogSnapshot(
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

  CachedCatalogSnapshot copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    DateTime? refreshedAt,
  }) => CachedCatalogSnapshot(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    refreshedAt: refreshedAt ?? this.refreshedAt,
  );
  CachedCatalogSnapshot copyWithCompanion(
    CachedCatalogSnapshotsCompanion data,
  ) {
    return CachedCatalogSnapshot(
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
    return (StringBuffer('CachedCatalogSnapshot(')
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
      (other is CachedCatalogSnapshot &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.refreshedAt == this.refreshedAt);
}

class CachedCatalogSnapshotsCompanion
    extends UpdateCompanion<CachedCatalogSnapshot> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<DateTime> refreshedAt;
  final Value<int> rowid;
  const CachedCatalogSnapshotsCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.refreshedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCatalogSnapshotsCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required DateTime refreshedAt,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       refreshedAt = Value(refreshedAt);
  static Insertable<CachedCatalogSnapshot> custom({
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

  CachedCatalogSnapshotsCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<DateTime>? refreshedAt,
    Value<int>? rowid,
  }) {
    return CachedCatalogSnapshotsCompanion(
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
    return (StringBuffer('CachedCatalogSnapshotsCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('refreshedAt: $refreshedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCatalogSummariesTable extends CachedCatalogSummaries
    with TableInfo<$CachedCatalogSummariesTable, CachedCatalogSummary> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCatalogSummariesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    organizationId,
    snapshotVersion,
    songId,
    slug,
    title,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_catalog_summaries';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCatalogSummary> instance, {
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
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, organizationId, songId};
  @override
  CachedCatalogSummary map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCatalogSummary(
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
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $CachedCatalogSummariesTable createAlias(String alias) {
    return $CachedCatalogSummariesTable(attachedDatabase, alias);
  }
}

class CachedCatalogSummary extends DataClass
    implements Insertable<CachedCatalogSummary> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final String songId;
  final String slug;
  final String title;
  final int version;
  const CachedCatalogSummary({
    required this.userId,
    required this.organizationId,
    required this.snapshotVersion,
    required this.songId,
    required this.slug,
    required this.title,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['snapshot_version'] = Variable<int>(snapshotVersion);
    map['song_id'] = Variable<String>(songId);
    map['slug'] = Variable<String>(slug);
    map['title'] = Variable<String>(title);
    map['version'] = Variable<int>(version);
    return map;
  }

  CachedCatalogSummariesCompanion toCompanion(bool nullToAbsent) {
    return CachedCatalogSummariesCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      songId: Value(songId),
      slug: Value(slug),
      title: Value(title),
      version: Value(version),
    );
  }

  factory CachedCatalogSummary.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCatalogSummary(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      snapshotVersion: serializer.fromJson<int>(json['snapshotVersion']),
      songId: serializer.fromJson<String>(json['songId']),
      slug: serializer.fromJson<String>(json['slug']),
      title: serializer.fromJson<String>(json['title']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'snapshotVersion': serializer.toJson<int>(snapshotVersion),
      'songId': serializer.toJson<String>(songId),
      'slug': serializer.toJson<String>(slug),
      'title': serializer.toJson<String>(title),
      'version': serializer.toJson<int>(version),
    };
  }

  CachedCatalogSummary copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    String? songId,
    String? slug,
    String? title,
    int? version,
  }) => CachedCatalogSummary(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    songId: songId ?? this.songId,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    version: version ?? this.version,
  );
  CachedCatalogSummary copyWithCompanion(CachedCatalogSummariesCompanion data) {
    return CachedCatalogSummary(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      snapshotVersion: data.snapshotVersion.present
          ? data.snapshotVersion.value
          : this.snapshotVersion,
      songId: data.songId.present ? data.songId.value : this.songId,
      slug: data.slug.present ? data.slug.value : this.slug,
      title: data.title.present ? data.title.value : this.title,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCatalogSummary(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('songId: $songId, ')
          ..write('slug: $slug, ')
          ..write('title: $title, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    organizationId,
    snapshotVersion,
    songId,
    slug,
    title,
    version,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCatalogSummary &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.songId == this.songId &&
          other.slug == this.slug &&
          other.title == this.title &&
          other.version == this.version);
}

class CachedCatalogSummariesCompanion
    extends UpdateCompanion<CachedCatalogSummary> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<String> songId;
  final Value<String> slug;
  final Value<String> title;
  final Value<int> version;
  final Value<int> rowid;
  const CachedCatalogSummariesCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.songId = const Value.absent(),
    this.slug = const Value.absent(),
    this.title = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCatalogSummariesCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required String songId,
    required String slug,
    required String title,
    required int version,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       songId = Value(songId),
       slug = Value(slug),
       title = Value(title),
       version = Value(version);
  static Insertable<CachedCatalogSummary> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<int>? snapshotVersion,
    Expression<String>? songId,
    Expression<String>? slug,
    Expression<String>? title,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (snapshotVersion != null) 'snapshot_version': snapshotVersion,
      if (songId != null) 'song_id': songId,
      if (slug != null) 'slug': slug,
      if (title != null) 'title': title,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCatalogSummariesCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<String>? songId,
    Value<String>? slug,
    Value<String>? title,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return CachedCatalogSummariesCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      songId: songId ?? this.songId,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      version: version ?? this.version,
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
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCatalogSummariesCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('songId: $songId, ')
          ..write('slug: $slug, ')
          ..write('title: $title, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCatalogSourcesTable extends CachedCatalogSources
    with TableInfo<$CachedCatalogSourcesTable, CachedCatalogSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCatalogSourcesTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
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
    songId,
    source,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_catalog_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCatalogSource> instance, {
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
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, organizationId, songId};
  @override
  CachedCatalogSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCatalogSource(
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
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
    );
  }

  @override
  $CachedCatalogSourcesTable createAlias(String alias) {
    return $CachedCatalogSourcesTable(attachedDatabase, alias);
  }
}

class CachedCatalogSource extends DataClass
    implements Insertable<CachedCatalogSource> {
  final String userId;
  final String organizationId;
  final int snapshotVersion;
  final String songId;
  final String source;
  const CachedCatalogSource({
    required this.userId,
    required this.organizationId,
    required this.snapshotVersion,
    required this.songId,
    required this.source,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['snapshot_version'] = Variable<int>(snapshotVersion);
    map['song_id'] = Variable<String>(songId);
    map['source'] = Variable<String>(source);
    return map;
  }

  CachedCatalogSourcesCompanion toCompanion(bool nullToAbsent) {
    return CachedCatalogSourcesCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      snapshotVersion: Value(snapshotVersion),
      songId: Value(songId),
      source: Value(source),
    );
  }

  factory CachedCatalogSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCatalogSource(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      snapshotVersion: serializer.fromJson<int>(json['snapshotVersion']),
      songId: serializer.fromJson<String>(json['songId']),
      source: serializer.fromJson<String>(json['source']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'snapshotVersion': serializer.toJson<int>(snapshotVersion),
      'songId': serializer.toJson<String>(songId),
      'source': serializer.toJson<String>(source),
    };
  }

  CachedCatalogSource copyWith({
    String? userId,
    String? organizationId,
    int? snapshotVersion,
    String? songId,
    String? source,
  }) => CachedCatalogSource(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    snapshotVersion: snapshotVersion ?? this.snapshotVersion,
    songId: songId ?? this.songId,
    source: source ?? this.source,
  );
  CachedCatalogSource copyWithCompanion(CachedCatalogSourcesCompanion data) {
    return CachedCatalogSource(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      snapshotVersion: data.snapshotVersion.present
          ? data.snapshotVersion.value
          : this.snapshotVersion,
      songId: data.songId.present ? data.songId.value : this.songId,
      source: data.source.present ? data.source.value : this.source,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCatalogSource(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('songId: $songId, ')
          ..write('source: $source')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(userId, organizationId, snapshotVersion, songId, source);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCatalogSource &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.snapshotVersion == this.snapshotVersion &&
          other.songId == this.songId &&
          other.source == this.source);
}

class CachedCatalogSourcesCompanion
    extends UpdateCompanion<CachedCatalogSource> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<int> snapshotVersion;
  final Value<String> songId;
  final Value<String> source;
  final Value<int> rowid;
  const CachedCatalogSourcesCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.snapshotVersion = const Value.absent(),
    this.songId = const Value.absent(),
    this.source = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCatalogSourcesCompanion.insert({
    required String userId,
    required String organizationId,
    required int snapshotVersion,
    required String songId,
    required String source,
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       snapshotVersion = Value(snapshotVersion),
       songId = Value(songId),
       source = Value(source);
  static Insertable<CachedCatalogSource> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<int>? snapshotVersion,
    Expression<String>? songId,
    Expression<String>? source,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (snapshotVersion != null) 'snapshot_version': snapshotVersion,
      if (songId != null) 'song_id': songId,
      if (source != null) 'source': source,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCatalogSourcesCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<int>? snapshotVersion,
    Value<String>? songId,
    Value<String>? source,
    Value<int>? rowid,
  }) {
    return CachedCatalogSourcesCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      snapshotVersion: snapshotVersion ?? this.snapshotVersion,
      songId: songId ?? this.songId,
      source: source ?? this.source,
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
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCatalogSourcesCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('snapshotVersion: $snapshotVersion, ')
          ..write('songId: $songId, ')
          ..write('source: $source, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CachedCatalogSongMutationsTable extends CachedCatalogSongMutations
    with
        TableInfo<$CachedCatalogSongMutationsTable, CachedCatalogSongMutation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CachedCatalogSongMutationsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<String> songId = GeneratedColumn<String>(
    'song_id',
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
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncStatusMeta = const VerificationMeta(
    'syncStatus',
  );
  @override
  late final GeneratedColumn<String> syncStatus = GeneratedColumn<String>(
    'sync_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseVersionMeta = const VerificationMeta(
    'baseVersion',
  );
  @override
  late final GeneratedColumn<int> baseVersion = GeneratedColumn<int>(
    'base_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncErrorContextMeta = const VerificationMeta(
    'syncErrorContext',
  );
  @override
  late final GeneratedColumn<String> syncErrorContext = GeneratedColumn<String>(
    'sync_error_context',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    organizationId,
    songId,
    slug,
    title,
    source,
    version,
    syncStatus,
    baseVersion,
    syncErrorContext,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cached_catalog_song_mutations';
  @override
  VerificationContext validateIntegrity(
    Insertable<CachedCatalogSongMutation> instance, {
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
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('slug')) {
      context.handle(
        _slugMeta,
        slug.isAcceptableOrUnknown(data['slug']!, _slugMeta),
      );
    } else if (isInserting) {
      context.missing(_slugMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    } else if (isInserting) {
      context.missing(_versionMeta);
    }
    if (data.containsKey('sync_status')) {
      context.handle(
        _syncStatusMeta,
        syncStatus.isAcceptableOrUnknown(data['sync_status']!, _syncStatusMeta),
      );
    } else if (isInserting) {
      context.missing(_syncStatusMeta);
    }
    if (data.containsKey('base_version')) {
      context.handle(
        _baseVersionMeta,
        baseVersion.isAcceptableOrUnknown(
          data['base_version']!,
          _baseVersionMeta,
        ),
      );
    }
    if (data.containsKey('sync_error_context')) {
      context.handle(
        _syncErrorContextMeta,
        syncErrorContext.isAcceptableOrUnknown(
          data['sync_error_context']!,
          _syncErrorContextMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId, organizationId, songId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {userId, organizationId, slug},
  ];
  @override
  CachedCatalogSongMutation map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CachedCatalogSongMutation(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      organizationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}organization_id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}song_id'],
      )!,
      slug: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slug'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
      syncStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_status'],
      )!,
      baseVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_version'],
      ),
      syncErrorContext: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_error_context'],
      ),
    );
  }

  @override
  $CachedCatalogSongMutationsTable createAlias(String alias) {
    return $CachedCatalogSongMutationsTable(attachedDatabase, alias);
  }
}

class CachedCatalogSongMutation extends DataClass
    implements Insertable<CachedCatalogSongMutation> {
  final String userId;
  final String organizationId;
  final String songId;
  final String slug;
  final String title;
  final String source;
  final int version;
  final String syncStatus;
  final int? baseVersion;
  final String? syncErrorContext;
  const CachedCatalogSongMutation({
    required this.userId,
    required this.organizationId,
    required this.songId,
    required this.slug,
    required this.title,
    required this.source,
    required this.version,
    required this.syncStatus,
    this.baseVersion,
    this.syncErrorContext,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['organization_id'] = Variable<String>(organizationId);
    map['song_id'] = Variable<String>(songId);
    map['slug'] = Variable<String>(slug);
    map['title'] = Variable<String>(title);
    map['source'] = Variable<String>(source);
    map['version'] = Variable<int>(version);
    map['sync_status'] = Variable<String>(syncStatus);
    if (!nullToAbsent || baseVersion != null) {
      map['base_version'] = Variable<int>(baseVersion);
    }
    if (!nullToAbsent || syncErrorContext != null) {
      map['sync_error_context'] = Variable<String>(syncErrorContext);
    }
    return map;
  }

  CachedCatalogSongMutationsCompanion toCompanion(bool nullToAbsent) {
    return CachedCatalogSongMutationsCompanion(
      userId: Value(userId),
      organizationId: Value(organizationId),
      songId: Value(songId),
      slug: Value(slug),
      title: Value(title),
      source: Value(source),
      version: Value(version),
      syncStatus: Value(syncStatus),
      baseVersion: baseVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(baseVersion),
      syncErrorContext: syncErrorContext == null && nullToAbsent
          ? const Value.absent()
          : Value(syncErrorContext),
    );
  }

  factory CachedCatalogSongMutation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CachedCatalogSongMutation(
      userId: serializer.fromJson<String>(json['userId']),
      organizationId: serializer.fromJson<String>(json['organizationId']),
      songId: serializer.fromJson<String>(json['songId']),
      slug: serializer.fromJson<String>(json['slug']),
      title: serializer.fromJson<String>(json['title']),
      source: serializer.fromJson<String>(json['source']),
      version: serializer.fromJson<int>(json['version']),
      syncStatus: serializer.fromJson<String>(json['syncStatus']),
      baseVersion: serializer.fromJson<int?>(json['baseVersion']),
      syncErrorContext: serializer.fromJson<String?>(json['syncErrorContext']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'organizationId': serializer.toJson<String>(organizationId),
      'songId': serializer.toJson<String>(songId),
      'slug': serializer.toJson<String>(slug),
      'title': serializer.toJson<String>(title),
      'source': serializer.toJson<String>(source),
      'version': serializer.toJson<int>(version),
      'syncStatus': serializer.toJson<String>(syncStatus),
      'baseVersion': serializer.toJson<int?>(baseVersion),
      'syncErrorContext': serializer.toJson<String?>(syncErrorContext),
    };
  }

  CachedCatalogSongMutation copyWith({
    String? userId,
    String? organizationId,
    String? songId,
    String? slug,
    String? title,
    String? source,
    int? version,
    String? syncStatus,
    Value<int?> baseVersion = const Value.absent(),
    Value<String?> syncErrorContext = const Value.absent(),
  }) => CachedCatalogSongMutation(
    userId: userId ?? this.userId,
    organizationId: organizationId ?? this.organizationId,
    songId: songId ?? this.songId,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    source: source ?? this.source,
    version: version ?? this.version,
    syncStatus: syncStatus ?? this.syncStatus,
    baseVersion: baseVersion.present ? baseVersion.value : this.baseVersion,
    syncErrorContext: syncErrorContext.present
        ? syncErrorContext.value
        : this.syncErrorContext,
  );
  CachedCatalogSongMutation copyWithCompanion(
    CachedCatalogSongMutationsCompanion data,
  ) {
    return CachedCatalogSongMutation(
      userId: data.userId.present ? data.userId.value : this.userId,
      organizationId: data.organizationId.present
          ? data.organizationId.value
          : this.organizationId,
      songId: data.songId.present ? data.songId.value : this.songId,
      slug: data.slug.present ? data.slug.value : this.slug,
      title: data.title.present ? data.title.value : this.title,
      source: data.source.present ? data.source.value : this.source,
      version: data.version.present ? data.version.value : this.version,
      syncStatus: data.syncStatus.present
          ? data.syncStatus.value
          : this.syncStatus,
      baseVersion: data.baseVersion.present
          ? data.baseVersion.value
          : this.baseVersion,
      syncErrorContext: data.syncErrorContext.present
          ? data.syncErrorContext.value
          : this.syncErrorContext,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CachedCatalogSongMutation(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('songId: $songId, ')
          ..write('slug: $slug, ')
          ..write('title: $title, ')
          ..write('source: $source, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('syncErrorContext: $syncErrorContext')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    organizationId,
    songId,
    slug,
    title,
    source,
    version,
    syncStatus,
    baseVersion,
    syncErrorContext,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CachedCatalogSongMutation &&
          other.userId == this.userId &&
          other.organizationId == this.organizationId &&
          other.songId == this.songId &&
          other.slug == this.slug &&
          other.title == this.title &&
          other.source == this.source &&
          other.version == this.version &&
          other.syncStatus == this.syncStatus &&
          other.baseVersion == this.baseVersion &&
          other.syncErrorContext == this.syncErrorContext);
}

class CachedCatalogSongMutationsCompanion
    extends UpdateCompanion<CachedCatalogSongMutation> {
  final Value<String> userId;
  final Value<String> organizationId;
  final Value<String> songId;
  final Value<String> slug;
  final Value<String> title;
  final Value<String> source;
  final Value<int> version;
  final Value<String> syncStatus;
  final Value<int?> baseVersion;
  final Value<String?> syncErrorContext;
  final Value<int> rowid;
  const CachedCatalogSongMutationsCompanion({
    this.userId = const Value.absent(),
    this.organizationId = const Value.absent(),
    this.songId = const Value.absent(),
    this.slug = const Value.absent(),
    this.title = const Value.absent(),
    this.source = const Value.absent(),
    this.version = const Value.absent(),
    this.syncStatus = const Value.absent(),
    this.baseVersion = const Value.absent(),
    this.syncErrorContext = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CachedCatalogSongMutationsCompanion.insert({
    required String userId,
    required String organizationId,
    required String songId,
    required String slug,
    required String title,
    required String source,
    required int version,
    required String syncStatus,
    this.baseVersion = const Value.absent(),
    this.syncErrorContext = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       organizationId = Value(organizationId),
       songId = Value(songId),
       slug = Value(slug),
       title = Value(title),
       source = Value(source),
       version = Value(version),
       syncStatus = Value(syncStatus);
  static Insertable<CachedCatalogSongMutation> custom({
    Expression<String>? userId,
    Expression<String>? organizationId,
    Expression<String>? songId,
    Expression<String>? slug,
    Expression<String>? title,
    Expression<String>? source,
    Expression<int>? version,
    Expression<String>? syncStatus,
    Expression<int>? baseVersion,
    Expression<String>? syncErrorContext,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (organizationId != null) 'organization_id': organizationId,
      if (songId != null) 'song_id': songId,
      if (slug != null) 'slug': slug,
      if (title != null) 'title': title,
      if (source != null) 'source': source,
      if (version != null) 'version': version,
      if (syncStatus != null) 'sync_status': syncStatus,
      if (baseVersion != null) 'base_version': baseVersion,
      if (syncErrorContext != null) 'sync_error_context': syncErrorContext,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CachedCatalogSongMutationsCompanion copyWith({
    Value<String>? userId,
    Value<String>? organizationId,
    Value<String>? songId,
    Value<String>? slug,
    Value<String>? title,
    Value<String>? source,
    Value<int>? version,
    Value<String>? syncStatus,
    Value<int?>? baseVersion,
    Value<String?>? syncErrorContext,
    Value<int>? rowid,
  }) {
    return CachedCatalogSongMutationsCompanion(
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      songId: songId ?? this.songId,
      slug: slug ?? this.slug,
      title: title ?? this.title,
      source: source ?? this.source,
      version: version ?? this.version,
      syncStatus: syncStatus ?? this.syncStatus,
      baseVersion: baseVersion ?? this.baseVersion,
      syncErrorContext: syncErrorContext ?? this.syncErrorContext,
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
    if (songId.present) {
      map['song_id'] = Variable<String>(songId.value);
    }
    if (slug.present) {
      map['slug'] = Variable<String>(slug.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (syncStatus.present) {
      map['sync_status'] = Variable<String>(syncStatus.value);
    }
    if (baseVersion.present) {
      map['base_version'] = Variable<int>(baseVersion.value);
    }
    if (syncErrorContext.present) {
      map['sync_error_context'] = Variable<String>(syncErrorContext.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CachedCatalogSongMutationsCompanion(')
          ..write('userId: $userId, ')
          ..write('organizationId: $organizationId, ')
          ..write('songId: $songId, ')
          ..write('slug: $slug, ')
          ..write('title: $title, ')
          ..write('source: $source, ')
          ..write('version: $version, ')
          ..write('syncStatus: $syncStatus, ')
          ..write('baseVersion: $baseVersion, ')
          ..write('syncErrorContext: $syncErrorContext, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$SongCatalogDatabase extends GeneratedDatabase {
  _$SongCatalogDatabase(QueryExecutor e) : super(e);
  $SongCatalogDatabaseManager get managers => $SongCatalogDatabaseManager(this);
  late final $CachedCatalogSnapshotsTable cachedCatalogSnapshots =
      $CachedCatalogSnapshotsTable(this);
  late final $CachedCatalogSummariesTable cachedCatalogSummaries =
      $CachedCatalogSummariesTable(this);
  late final $CachedCatalogSourcesTable cachedCatalogSources =
      $CachedCatalogSourcesTable(this);
  late final $CachedCatalogSongMutationsTable cachedCatalogSongMutations =
      $CachedCatalogSongMutationsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    cachedCatalogSnapshots,
    cachedCatalogSummaries,
    cachedCatalogSources,
    cachedCatalogSongMutations,
  ];
}

typedef $$CachedCatalogSnapshotsTableCreateCompanionBuilder =
    CachedCatalogSnapshotsCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required DateTime refreshedAt,
      Value<int> rowid,
    });
typedef $$CachedCatalogSnapshotsTableUpdateCompanionBuilder =
    CachedCatalogSnapshotsCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<DateTime> refreshedAt,
      Value<int> rowid,
    });

class $$CachedCatalogSnapshotsTableFilterComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSnapshotsTable> {
  $$CachedCatalogSnapshotsTableFilterComposer({
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

class $$CachedCatalogSnapshotsTableOrderingComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSnapshotsTable> {
  $$CachedCatalogSnapshotsTableOrderingComposer({
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

class $$CachedCatalogSnapshotsTableAnnotationComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSnapshotsTable> {
  $$CachedCatalogSnapshotsTableAnnotationComposer({
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

class $$CachedCatalogSnapshotsTableTableManager
    extends
        RootTableManager<
          _$SongCatalogDatabase,
          $CachedCatalogSnapshotsTable,
          CachedCatalogSnapshot,
          $$CachedCatalogSnapshotsTableFilterComposer,
          $$CachedCatalogSnapshotsTableOrderingComposer,
          $$CachedCatalogSnapshotsTableAnnotationComposer,
          $$CachedCatalogSnapshotsTableCreateCompanionBuilder,
          $$CachedCatalogSnapshotsTableUpdateCompanionBuilder,
          (
            CachedCatalogSnapshot,
            BaseReferences<
              _$SongCatalogDatabase,
              $CachedCatalogSnapshotsTable,
              CachedCatalogSnapshot
            >,
          ),
          CachedCatalogSnapshot,
          PrefetchHooks Function()
        > {
  $$CachedCatalogSnapshotsTableTableManager(
    _$SongCatalogDatabase db,
    $CachedCatalogSnapshotsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCatalogSnapshotsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedCatalogSnapshotsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedCatalogSnapshotsTableAnnotationComposer(
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
              }) => CachedCatalogSnapshotsCompanion(
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
              }) => CachedCatalogSnapshotsCompanion.insert(
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

typedef $$CachedCatalogSnapshotsTableProcessedTableManager =
    ProcessedTableManager<
      _$SongCatalogDatabase,
      $CachedCatalogSnapshotsTable,
      CachedCatalogSnapshot,
      $$CachedCatalogSnapshotsTableFilterComposer,
      $$CachedCatalogSnapshotsTableOrderingComposer,
      $$CachedCatalogSnapshotsTableAnnotationComposer,
      $$CachedCatalogSnapshotsTableCreateCompanionBuilder,
      $$CachedCatalogSnapshotsTableUpdateCompanionBuilder,
      (
        CachedCatalogSnapshot,
        BaseReferences<
          _$SongCatalogDatabase,
          $CachedCatalogSnapshotsTable,
          CachedCatalogSnapshot
        >,
      ),
      CachedCatalogSnapshot,
      PrefetchHooks Function()
    >;
typedef $$CachedCatalogSummariesTableCreateCompanionBuilder =
    CachedCatalogSummariesCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required String songId,
      required String slug,
      required String title,
      required int version,
      Value<int> rowid,
    });
typedef $$CachedCatalogSummariesTableUpdateCompanionBuilder =
    CachedCatalogSummariesCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<String> songId,
      Value<String> slug,
      Value<String> title,
      Value<int> version,
      Value<int> rowid,
    });

class $$CachedCatalogSummariesTableFilterComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSummariesTable> {
  $$CachedCatalogSummariesTableFilterComposer({
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

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCatalogSummariesTableOrderingComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSummariesTable> {
  $$CachedCatalogSummariesTableOrderingComposer({
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

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCatalogSummariesTableAnnotationComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSummariesTable> {
  $$CachedCatalogSummariesTableAnnotationComposer({
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

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);
}

class $$CachedCatalogSummariesTableTableManager
    extends
        RootTableManager<
          _$SongCatalogDatabase,
          $CachedCatalogSummariesTable,
          CachedCatalogSummary,
          $$CachedCatalogSummariesTableFilterComposer,
          $$CachedCatalogSummariesTableOrderingComposer,
          $$CachedCatalogSummariesTableAnnotationComposer,
          $$CachedCatalogSummariesTableCreateCompanionBuilder,
          $$CachedCatalogSummariesTableUpdateCompanionBuilder,
          (
            CachedCatalogSummary,
            BaseReferences<
              _$SongCatalogDatabase,
              $CachedCatalogSummariesTable,
              CachedCatalogSummary
            >,
          ),
          CachedCatalogSummary,
          PrefetchHooks Function()
        > {
  $$CachedCatalogSummariesTableTableManager(
    _$SongCatalogDatabase db,
    $CachedCatalogSummariesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCatalogSummariesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedCatalogSummariesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedCatalogSummariesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<int> snapshotVersion = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCatalogSummariesCompanion(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                songId: songId,
                slug: slug,
                title: title,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required int snapshotVersion,
                required String songId,
                required String slug,
                required String title,
                required int version,
                Value<int> rowid = const Value.absent(),
              }) => CachedCatalogSummariesCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                songId: songId,
                slug: slug,
                title: title,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCatalogSummariesTableProcessedTableManager =
    ProcessedTableManager<
      _$SongCatalogDatabase,
      $CachedCatalogSummariesTable,
      CachedCatalogSummary,
      $$CachedCatalogSummariesTableFilterComposer,
      $$CachedCatalogSummariesTableOrderingComposer,
      $$CachedCatalogSummariesTableAnnotationComposer,
      $$CachedCatalogSummariesTableCreateCompanionBuilder,
      $$CachedCatalogSummariesTableUpdateCompanionBuilder,
      (
        CachedCatalogSummary,
        BaseReferences<
          _$SongCatalogDatabase,
          $CachedCatalogSummariesTable,
          CachedCatalogSummary
        >,
      ),
      CachedCatalogSummary,
      PrefetchHooks Function()
    >;
typedef $$CachedCatalogSourcesTableCreateCompanionBuilder =
    CachedCatalogSourcesCompanion Function({
      required String userId,
      required String organizationId,
      required int snapshotVersion,
      required String songId,
      required String source,
      Value<int> rowid,
    });
typedef $$CachedCatalogSourcesTableUpdateCompanionBuilder =
    CachedCatalogSourcesCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<int> snapshotVersion,
      Value<String> songId,
      Value<String> source,
      Value<int> rowid,
    });

class $$CachedCatalogSourcesTableFilterComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSourcesTable> {
  $$CachedCatalogSourcesTableFilterComposer({
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

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCatalogSourcesTableOrderingComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSourcesTable> {
  $$CachedCatalogSourcesTableOrderingComposer({
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

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCatalogSourcesTableAnnotationComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSourcesTable> {
  $$CachedCatalogSourcesTableAnnotationComposer({
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

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);
}

class $$CachedCatalogSourcesTableTableManager
    extends
        RootTableManager<
          _$SongCatalogDatabase,
          $CachedCatalogSourcesTable,
          CachedCatalogSource,
          $$CachedCatalogSourcesTableFilterComposer,
          $$CachedCatalogSourcesTableOrderingComposer,
          $$CachedCatalogSourcesTableAnnotationComposer,
          $$CachedCatalogSourcesTableCreateCompanionBuilder,
          $$CachedCatalogSourcesTableUpdateCompanionBuilder,
          (
            CachedCatalogSource,
            BaseReferences<
              _$SongCatalogDatabase,
              $CachedCatalogSourcesTable,
              CachedCatalogSource
            >,
          ),
          CachedCatalogSource,
          PrefetchHooks Function()
        > {
  $$CachedCatalogSourcesTableTableManager(
    _$SongCatalogDatabase db,
    $CachedCatalogSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCatalogSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CachedCatalogSourcesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedCatalogSourcesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<int> snapshotVersion = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCatalogSourcesCompanion(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                songId: songId,
                source: source,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required int snapshotVersion,
                required String songId,
                required String source,
                Value<int> rowid = const Value.absent(),
              }) => CachedCatalogSourcesCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                snapshotVersion: snapshotVersion,
                songId: songId,
                source: source,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCatalogSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$SongCatalogDatabase,
      $CachedCatalogSourcesTable,
      CachedCatalogSource,
      $$CachedCatalogSourcesTableFilterComposer,
      $$CachedCatalogSourcesTableOrderingComposer,
      $$CachedCatalogSourcesTableAnnotationComposer,
      $$CachedCatalogSourcesTableCreateCompanionBuilder,
      $$CachedCatalogSourcesTableUpdateCompanionBuilder,
      (
        CachedCatalogSource,
        BaseReferences<
          _$SongCatalogDatabase,
          $CachedCatalogSourcesTable,
          CachedCatalogSource
        >,
      ),
      CachedCatalogSource,
      PrefetchHooks Function()
    >;
typedef $$CachedCatalogSongMutationsTableCreateCompanionBuilder =
    CachedCatalogSongMutationsCompanion Function({
      required String userId,
      required String organizationId,
      required String songId,
      required String slug,
      required String title,
      required String source,
      required int version,
      required String syncStatus,
      Value<int?> baseVersion,
      Value<String?> syncErrorContext,
      Value<int> rowid,
    });
typedef $$CachedCatalogSongMutationsTableUpdateCompanionBuilder =
    CachedCatalogSongMutationsCompanion Function({
      Value<String> userId,
      Value<String> organizationId,
      Value<String> songId,
      Value<String> slug,
      Value<String> title,
      Value<String> source,
      Value<int> version,
      Value<String> syncStatus,
      Value<int?> baseVersion,
      Value<String?> syncErrorContext,
      Value<int> rowid,
    });

class $$CachedCatalogSongMutationsTableFilterComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSongMutationsTable> {
  $$CachedCatalogSongMutationsTableFilterComposer({
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

  ColumnFilters<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncErrorContext => $composableBuilder(
    column: $table.syncErrorContext,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CachedCatalogSongMutationsTableOrderingComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSongMutationsTable> {
  $$CachedCatalogSongMutationsTableOrderingComposer({
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

  ColumnOrderings<String> get songId => $composableBuilder(
    column: $table.songId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get slug => $composableBuilder(
    column: $table.slug,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncErrorContext => $composableBuilder(
    column: $table.syncErrorContext,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CachedCatalogSongMutationsTableAnnotationComposer
    extends Composer<_$SongCatalogDatabase, $CachedCatalogSongMutationsTable> {
  $$CachedCatalogSongMutationsTableAnnotationComposer({
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

  GeneratedColumn<String> get songId =>
      $composableBuilder(column: $table.songId, builder: (column) => column);

  GeneratedColumn<String> get slug =>
      $composableBuilder(column: $table.slug, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  GeneratedColumn<String> get syncStatus => $composableBuilder(
    column: $table.syncStatus,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseVersion => $composableBuilder(
    column: $table.baseVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncErrorContext => $composableBuilder(
    column: $table.syncErrorContext,
    builder: (column) => column,
  );
}

class $$CachedCatalogSongMutationsTableTableManager
    extends
        RootTableManager<
          _$SongCatalogDatabase,
          $CachedCatalogSongMutationsTable,
          CachedCatalogSongMutation,
          $$CachedCatalogSongMutationsTableFilterComposer,
          $$CachedCatalogSongMutationsTableOrderingComposer,
          $$CachedCatalogSongMutationsTableAnnotationComposer,
          $$CachedCatalogSongMutationsTableCreateCompanionBuilder,
          $$CachedCatalogSongMutationsTableUpdateCompanionBuilder,
          (
            CachedCatalogSongMutation,
            BaseReferences<
              _$SongCatalogDatabase,
              $CachedCatalogSongMutationsTable,
              CachedCatalogSongMutation
            >,
          ),
          CachedCatalogSongMutation,
          PrefetchHooks Function()
        > {
  $$CachedCatalogSongMutationsTableTableManager(
    _$SongCatalogDatabase db,
    $CachedCatalogSongMutationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CachedCatalogSongMutationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$CachedCatalogSongMutationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$CachedCatalogSongMutationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> organizationId = const Value.absent(),
                Value<String> songId = const Value.absent(),
                Value<String> slug = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<String> syncStatus = const Value.absent(),
                Value<int?> baseVersion = const Value.absent(),
                Value<String?> syncErrorContext = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCatalogSongMutationsCompanion(
                userId: userId,
                organizationId: organizationId,
                songId: songId,
                slug: slug,
                title: title,
                source: source,
                version: version,
                syncStatus: syncStatus,
                baseVersion: baseVersion,
                syncErrorContext: syncErrorContext,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String organizationId,
                required String songId,
                required String slug,
                required String title,
                required String source,
                required int version,
                required String syncStatus,
                Value<int?> baseVersion = const Value.absent(),
                Value<String?> syncErrorContext = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CachedCatalogSongMutationsCompanion.insert(
                userId: userId,
                organizationId: organizationId,
                songId: songId,
                slug: slug,
                title: title,
                source: source,
                version: version,
                syncStatus: syncStatus,
                baseVersion: baseVersion,
                syncErrorContext: syncErrorContext,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CachedCatalogSongMutationsTableProcessedTableManager =
    ProcessedTableManager<
      _$SongCatalogDatabase,
      $CachedCatalogSongMutationsTable,
      CachedCatalogSongMutation,
      $$CachedCatalogSongMutationsTableFilterComposer,
      $$CachedCatalogSongMutationsTableOrderingComposer,
      $$CachedCatalogSongMutationsTableAnnotationComposer,
      $$CachedCatalogSongMutationsTableCreateCompanionBuilder,
      $$CachedCatalogSongMutationsTableUpdateCompanionBuilder,
      (
        CachedCatalogSongMutation,
        BaseReferences<
          _$SongCatalogDatabase,
          $CachedCatalogSongMutationsTable,
          CachedCatalogSongMutation
        >,
      ),
      CachedCatalogSongMutation,
      PrefetchHooks Function()
    >;

class $SongCatalogDatabaseManager {
  final _$SongCatalogDatabase _db;
  $SongCatalogDatabaseManager(this._db);
  $$CachedCatalogSnapshotsTableTableManager get cachedCatalogSnapshots =>
      $$CachedCatalogSnapshotsTableTableManager(
        _db,
        _db.cachedCatalogSnapshots,
      );
  $$CachedCatalogSummariesTableTableManager get cachedCatalogSummaries =>
      $$CachedCatalogSummariesTableTableManager(
        _db,
        _db.cachedCatalogSummaries,
      );
  $$CachedCatalogSourcesTableTableManager get cachedCatalogSources =>
      $$CachedCatalogSourcesTableTableManager(_db, _db.cachedCatalogSources);
  $$CachedCatalogSongMutationsTableTableManager
  get cachedCatalogSongMutations =>
      $$CachedCatalogSongMutationsTableTableManager(
        _db,
        _db.cachedCatalogSongMutations,
      );
}
