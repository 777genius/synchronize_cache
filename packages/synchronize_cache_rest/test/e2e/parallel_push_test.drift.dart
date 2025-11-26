// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:synchronize_cache/src/tables/cursors.drift.dart' as i1;
import 'package:synchronize_cache/src/tables/outbox.drift.dart' as i2;
import 'parallel_push_test.drift.dart' as i3;
import 'parallel_push_test.dart' as i4;

typedef $$TestEntitiesTableCreateCompanionBuilder =
    i3.TestEntitiesCompanion Function({
      required DateTime updatedAt,
      i0.Value<DateTime?> deletedAt,
      i0.Value<DateTime?> deletedAtLocal,
      required String id,
      required String name,
      i0.Value<int> rowid,
    });
typedef $$TestEntitiesTableUpdateCompanionBuilder =
    i3.TestEntitiesCompanion Function({
      i0.Value<DateTime> updatedAt,
      i0.Value<DateTime?> deletedAt,
      i0.Value<DateTime?> deletedAtLocal,
      i0.Value<String> id,
      i0.Value<String> name,
      i0.Value<int> rowid,
    });

class $$TestEntitiesTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i3.$TestEntitiesTable> {
  $$TestEntitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<DateTime> get deletedAtLocal => $composableBuilder(
    column: $table.deletedAtLocal,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$TestEntitiesTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i3.$TestEntitiesTable> {
  $$TestEntitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
    column: $table.deletedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<DateTime> get deletedAtLocal => $composableBuilder(
    column: $table.deletedAtLocal,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$TestEntitiesTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i3.$TestEntitiesTable> {
  $$TestEntitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  i0.GeneratedColumn<DateTime> get deletedAtLocal => $composableBuilder(
    column: $table.deletedAtLocal,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  i0.GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);
}

class $$TestEntitiesTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i3.$TestEntitiesTable,
          i4.TestEntity,
          i3.$$TestEntitiesTableFilterComposer,
          i3.$$TestEntitiesTableOrderingComposer,
          i3.$$TestEntitiesTableAnnotationComposer,
          $$TestEntitiesTableCreateCompanionBuilder,
          $$TestEntitiesTableUpdateCompanionBuilder,
          (
            i4.TestEntity,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i3.$TestEntitiesTable,
              i4.TestEntity
            >,
          ),
          i4.TestEntity,
          i0.PrefetchHooks Function()
        > {
  $$TestEntitiesTableTableManager(
    i0.GeneratedDatabase db,
    i3.$TestEntitiesTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () =>
                  i3.$$TestEntitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () => i3.$$TestEntitiesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer:
              () => i3.$$TestEntitiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<DateTime> updatedAt = const i0.Value.absent(),
                i0.Value<DateTime?> deletedAt = const i0.Value.absent(),
                i0.Value<DateTime?> deletedAtLocal = const i0.Value.absent(),
                i0.Value<String> id = const i0.Value.absent(),
                i0.Value<String> name = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i3.TestEntitiesCompanion(
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                deletedAtLocal: deletedAtLocal,
                id: id,
                name: name,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required DateTime updatedAt,
                i0.Value<DateTime?> deletedAt = const i0.Value.absent(),
                i0.Value<DateTime?> deletedAtLocal = const i0.Value.absent(),
                required String id,
                required String name,
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i3.TestEntitiesCompanion.insert(
                updatedAt: updatedAt,
                deletedAt: deletedAt,
                deletedAtLocal: deletedAtLocal,
                id: id,
                name: name,
                rowid: rowid,
              ),
          withReferenceMapper:
              (p0) =>
                  p0
                      .map(
                        (e) => (
                          e.readTable(table),
                          i0.BaseReferences(db, table, e),
                        ),
                      )
                      .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$TestEntitiesTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i3.$TestEntitiesTable,
      i4.TestEntity,
      i3.$$TestEntitiesTableFilterComposer,
      i3.$$TestEntitiesTableOrderingComposer,
      i3.$$TestEntitiesTableAnnotationComposer,
      $$TestEntitiesTableCreateCompanionBuilder,
      $$TestEntitiesTableUpdateCompanionBuilder,
      (
        i4.TestEntity,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i3.$TestEntitiesTable,
          i4.TestEntity
        >,
      ),
      i4.TestEntity,
      i0.PrefetchHooks Function()
    >;

abstract class $TestDatabase extends i0.GeneratedDatabase {
  $TestDatabase(i0.QueryExecutor e) : super(e);
  $TestDatabaseManager get managers => $TestDatabaseManager(this);
  late final i1.$SyncCursorsTable syncCursors = i1.$SyncCursorsTable(this);
  late final i2.$SyncOutboxTable syncOutbox = i2.$SyncOutboxTable(this);
  late final i3.$TestEntitiesTable testEntities = i3.$TestEntitiesTable(this);
  @override
  Iterable<i0.TableInfo<i0.Table, Object?>> get allTables =>
      allSchemaEntities.whereType<i0.TableInfo<i0.Table, Object?>>();
  @override
  List<i0.DatabaseSchemaEntity> get allSchemaEntities => [
    syncCursors,
    syncOutbox,
    testEntities,
  ];
}

class $TestDatabaseManager {
  final $TestDatabase _db;
  $TestDatabaseManager(this._db);
  i1.$$SyncCursorsTableTableManager get syncCursors =>
      i1.$$SyncCursorsTableTableManager(_db, _db.syncCursors);
  i2.$$SyncOutboxTableTableManager get syncOutbox =>
      i2.$$SyncOutboxTableTableManager(_db, _db.syncOutbox);
  i3.$$TestEntitiesTableTableManager get testEntities =>
      i3.$$TestEntitiesTableTableManager(_db, _db.testEntities);
}

class $TestEntitiesTable extends i4.TestEntities
    with i0.TableInfo<$TestEntitiesTable, i4.TestEntity> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TestEntitiesTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _updatedAtMeta = const i0.VerificationMeta(
    'updatedAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> updatedAt =
      i0.GeneratedColumn<DateTime>(
        'updated_at',
        aliasedName,
        false,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const i0.VerificationMeta _deletedAtMeta = const i0.VerificationMeta(
    'deletedAt',
  );
  @override
  late final i0.GeneratedColumn<DateTime> deletedAt =
      i0.GeneratedColumn<DateTime>(
        'deleted_at',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _deletedAtLocalMeta =
      const i0.VerificationMeta('deletedAtLocal');
  @override
  late final i0.GeneratedColumn<DateTime> deletedAtLocal =
      i0.GeneratedColumn<DateTime>(
        'deleted_at_local',
        aliasedName,
        true,
        type: i0.DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const i0.VerificationMeta _idMeta = const i0.VerificationMeta('id');
  @override
  late final i0.GeneratedColumn<String> id = i0.GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _nameMeta = const i0.VerificationMeta(
    'name',
  );
  @override
  late final i0.GeneratedColumn<String> name = i0.GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [
    updatedAt,
    deletedAt,
    deletedAtLocal,
    id,
    name,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'test_entities';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i4.TestEntity> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('deleted_at')) {
      context.handle(
        _deletedAtMeta,
        deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta),
      );
    }
    if (data.containsKey('deleted_at_local')) {
      context.handle(
        _deletedAtLocalMeta,
        deletedAtLocal.isAcceptableOrUnknown(
          data['deleted_at_local']!,
          _deletedAtLocalMeta,
        ),
      );
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
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
  Set<i0.GeneratedColumn> get $primaryKey => {id};
  @override
  i4.TestEntity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i4.TestEntity(
      id:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}id'],
          )!,
      updatedAt:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.dateTime,
            data['${effectivePrefix}updated_at'],
          )!,
      deletedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at'],
      ),
      deletedAtLocal: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.dateTime,
        data['${effectivePrefix}deleted_at_local'],
      ),
      name:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}name'],
          )!,
    );
  }

  @override
  $TestEntitiesTable createAlias(String alias) {
    return $TestEntitiesTable(attachedDatabase, alias);
  }
}

class TestEntitiesCompanion extends i0.UpdateCompanion<i4.TestEntity> {
  final i0.Value<DateTime> updatedAt;
  final i0.Value<DateTime?> deletedAt;
  final i0.Value<DateTime?> deletedAtLocal;
  final i0.Value<String> id;
  final i0.Value<String> name;
  final i0.Value<int> rowid;
  const TestEntitiesCompanion({
    this.updatedAt = const i0.Value.absent(),
    this.deletedAt = const i0.Value.absent(),
    this.deletedAtLocal = const i0.Value.absent(),
    this.id = const i0.Value.absent(),
    this.name = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  TestEntitiesCompanion.insert({
    required DateTime updatedAt,
    this.deletedAt = const i0.Value.absent(),
    this.deletedAtLocal = const i0.Value.absent(),
    required String id,
    required String name,
    this.rowid = const i0.Value.absent(),
  }) : updatedAt = i0.Value(updatedAt),
       id = i0.Value(id),
       name = i0.Value(name);
  static i0.Insertable<i4.TestEntity> custom({
    i0.Expression<DateTime>? updatedAt,
    i0.Expression<DateTime>? deletedAt,
    i0.Expression<DateTime>? deletedAtLocal,
    i0.Expression<String>? id,
    i0.Expression<String>? name,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (deletedAtLocal != null) 'deleted_at_local': deletedAtLocal,
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i3.TestEntitiesCompanion copyWith({
    i0.Value<DateTime>? updatedAt,
    i0.Value<DateTime?>? deletedAt,
    i0.Value<DateTime?>? deletedAtLocal,
    i0.Value<String>? id,
    i0.Value<String>? name,
    i0.Value<int>? rowid,
  }) {
    return i3.TestEntitiesCompanion(
      updatedAt: updatedAt ?? this.updatedAt,
      deletedAt: deletedAt ?? this.deletedAt,
      deletedAtLocal: deletedAtLocal ?? this.deletedAtLocal,
      id: id ?? this.id,
      name: name ?? this.name,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (updatedAt.present) {
      map['updated_at'] = i0.Variable<DateTime>(updatedAt.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = i0.Variable<DateTime>(deletedAt.value);
    }
    if (deletedAtLocal.present) {
      map['deleted_at_local'] = i0.Variable<DateTime>(deletedAtLocal.value);
    }
    if (id.present) {
      map['id'] = i0.Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = i0.Variable<String>(name.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TestEntitiesCompanion(')
          ..write('updatedAt: $updatedAt, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('deletedAtLocal: $deletedAtLocal, ')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class _$TestEntityInsertable implements i0.Insertable<i4.TestEntity> {
  i4.TestEntity _object;
  _$TestEntityInsertable(this._object);
  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    return i3.TestEntitiesCompanion(
      updatedAt: i0.Value(_object.updatedAt),
      deletedAt: i0.Value(_object.deletedAt),
      deletedAtLocal: i0.Value(_object.deletedAtLocal),
      id: i0.Value(_object.id),
      name: i0.Value(_object.name),
    ).toColumns(false);
  }
}

extension TestEntityToInsertable on i4.TestEntity {
  _$TestEntityInsertable toInsertable() {
    return _$TestEntityInsertable(this);
  }
}
