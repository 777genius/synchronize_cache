// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:synchronize_cache/src/tables/sync_data_classes.dart' as i1;
import 'package:synchronize_cache/src/tables/cursors.drift.dart' as i2;
import 'package:synchronize_cache/src/tables/cursors.dart' as i3;

typedef $$SyncCursorsTableCreateCompanionBuilder =
    i2.SyncCursorsCompanion Function({
      required String kind,
      required int ts,
      required String lastId,
      i0.Value<int> rowid,
    });
typedef $$SyncCursorsTableUpdateCompanionBuilder =
    i2.SyncCursorsCompanion Function({
      i0.Value<String> kind,
      i0.Value<int> ts,
      i0.Value<String> lastId,
      i0.Value<int> rowid,
    });

class $$SyncCursorsTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i2.$SyncCursorsTable> {
  $$SyncCursorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get lastId => $composableBuilder(
    column: $table.lastId,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$SyncCursorsTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i2.$SyncCursorsTable> {
  $$SyncCursorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get lastId => $composableBuilder(
    column: $table.lastId,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$SyncCursorsTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i2.$SyncCursorsTable> {
  $$SyncCursorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  i0.GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  i0.GeneratedColumn<String> get lastId =>
      $composableBuilder(column: $table.lastId, builder: (column) => column);
}

class $$SyncCursorsTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i2.$SyncCursorsTable,
          i1.SyncCursorData,
          i2.$$SyncCursorsTableFilterComposer,
          i2.$$SyncCursorsTableOrderingComposer,
          i2.$$SyncCursorsTableAnnotationComposer,
          $$SyncCursorsTableCreateCompanionBuilder,
          $$SyncCursorsTableUpdateCompanionBuilder,
          (
            i1.SyncCursorData,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i2.$SyncCursorsTable,
              i1.SyncCursorData
            >,
          ),
          i1.SyncCursorData,
          i0.PrefetchHooks Function()
        > {
  $$SyncCursorsTableTableManager(
    i0.GeneratedDatabase db,
    i2.$SyncCursorsTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => i2.$$SyncCursorsTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  i2.$$SyncCursorsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => i2.$$SyncCursorsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> kind = const i0.Value.absent(),
                i0.Value<int> ts = const i0.Value.absent(),
                i0.Value<String> lastId = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i2.SyncCursorsCompanion(
                kind: kind,
                ts: ts,
                lastId: lastId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required int ts,
                required String lastId,
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i2.SyncCursorsCompanion.insert(
                kind: kind,
                ts: ts,
                lastId: lastId,
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

typedef $$SyncCursorsTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i2.$SyncCursorsTable,
      i1.SyncCursorData,
      i2.$$SyncCursorsTableFilterComposer,
      i2.$$SyncCursorsTableOrderingComposer,
      i2.$$SyncCursorsTableAnnotationComposer,
      $$SyncCursorsTableCreateCompanionBuilder,
      $$SyncCursorsTableUpdateCompanionBuilder,
      (
        i1.SyncCursorData,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i2.$SyncCursorsTable,
          i1.SyncCursorData
        >,
      ),
      i1.SyncCursorData,
      i0.PrefetchHooks Function()
    >;

class $SyncCursorsTable extends i3.SyncCursors
    with i0.TableInfo<$SyncCursorsTable, i1.SyncCursorData> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncCursorsTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _kindMeta = const i0.VerificationMeta(
    'kind',
  );
  @override
  late final i0.GeneratedColumn<String> kind = i0.GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _tsMeta = const i0.VerificationMeta('ts');
  @override
  late final i0.GeneratedColumn<int> ts = i0.GeneratedColumn<int>(
    'ts',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _lastIdMeta = const i0.VerificationMeta(
    'lastId',
  );
  @override
  late final i0.GeneratedColumn<String> lastId = i0.GeneratedColumn<String>(
    'last_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<i0.GeneratedColumn> get $columns => [kind, ts, lastId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_cursors';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.SyncCursorData> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('last_id')) {
      context.handle(
        _lastIdMeta,
        lastId.isAcceptableOrUnknown(data['last_id']!, _lastIdMeta),
      );
    } else if (isInserting) {
      context.missing(_lastIdMeta);
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {kind};
  @override
  i1.SyncCursorData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.SyncCursorData(
      kind:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      ts:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}ts'],
          )!,
      lastId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}last_id'],
          )!,
    );
  }

  @override
  $SyncCursorsTable createAlias(String alias) {
    return $SyncCursorsTable(attachedDatabase, alias);
  }
}

class SyncCursorsCompanion extends i0.UpdateCompanion<i1.SyncCursorData> {
  final i0.Value<String> kind;
  final i0.Value<int> ts;
  final i0.Value<String> lastId;
  final i0.Value<int> rowid;
  const SyncCursorsCompanion({
    this.kind = const i0.Value.absent(),
    this.ts = const i0.Value.absent(),
    this.lastId = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  SyncCursorsCompanion.insert({
    required String kind,
    required int ts,
    required String lastId,
    this.rowid = const i0.Value.absent(),
  }) : kind = i0.Value(kind),
       ts = i0.Value(ts),
       lastId = i0.Value(lastId);
  static i0.Insertable<i1.SyncCursorData> custom({
    i0.Expression<String>? kind,
    i0.Expression<int>? ts,
    i0.Expression<String>? lastId,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (ts != null) 'ts': ts,
      if (lastId != null) 'last_id': lastId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i2.SyncCursorsCompanion copyWith({
    i0.Value<String>? kind,
    i0.Value<int>? ts,
    i0.Value<String>? lastId,
    i0.Value<int>? rowid,
  }) {
    return i2.SyncCursorsCompanion(
      kind: kind ?? this.kind,
      ts: ts ?? this.ts,
      lastId: lastId ?? this.lastId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (kind.present) {
      map['kind'] = i0.Variable<String>(kind.value);
    }
    if (ts.present) {
      map['ts'] = i0.Variable<int>(ts.value);
    }
    if (lastId.present) {
      map['last_id'] = i0.Variable<String>(lastId.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncCursorsCompanion(')
          ..write('kind: $kind, ')
          ..write('ts: $ts, ')
          ..write('lastId: $lastId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
