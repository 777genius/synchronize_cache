// dart format width=80
// ignore_for_file: type=lint
import 'package:drift/drift.dart' as i0;
import 'package:offline_first_sync_drift/src/tables/sync_data_classes.dart'
    as i1;
import 'package:offline_first_sync_drift/src/tables/outbox.drift.dart' as i2;
import 'package:offline_first_sync_drift/src/tables/outbox.dart' as i3;
import 'package:drift/src/runtime/query_builder/query_builder.dart' as i4;

typedef $$SyncOutboxTableCreateCompanionBuilder =
    i2.SyncOutboxCompanion Function({
      required String opId,
      required String kind,
      required String entityId,
      required String op,
      i0.Value<String?> payload,
      required int ts,
      i0.Value<int> tryCount,
      i0.Value<int?> baseUpdatedAt,
      i0.Value<String?> changedFields,
      i0.Value<int> rowid,
    });
typedef $$SyncOutboxTableUpdateCompanionBuilder =
    i2.SyncOutboxCompanion Function({
      i0.Value<String> opId,
      i0.Value<String> kind,
      i0.Value<String> entityId,
      i0.Value<String> op,
      i0.Value<String?> payload,
      i0.Value<int> ts,
      i0.Value<int> tryCount,
      i0.Value<int?> baseUpdatedAt,
      i0.Value<String?> changedFields,
      i0.Value<int> rowid,
    });

class $$SyncOutboxTableFilterComposer
    extends i0.Composer<i0.GeneratedDatabase, i2.$SyncOutboxTable> {
  $$SyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnFilters<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get tryCount => $composableBuilder(
    column: $table.tryCount,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<int> get baseUpdatedAt => $composableBuilder(
    column: $table.baseUpdatedAt,
    builder: (column) => i0.ColumnFilters(column),
  );

  i0.ColumnFilters<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => i0.ColumnFilters(column),
  );
}

class $$SyncOutboxTableOrderingComposer
    extends i0.Composer<i0.GeneratedDatabase, i2.$SyncOutboxTable> {
  $$SyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.ColumnOrderings<String> get opId => $composableBuilder(
    column: $table.opId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get entityId => $composableBuilder(
    column: $table.entityId,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get ts => $composableBuilder(
    column: $table.ts,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get tryCount => $composableBuilder(
    column: $table.tryCount,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<int> get baseUpdatedAt => $composableBuilder(
    column: $table.baseUpdatedAt,
    builder: (column) => i0.ColumnOrderings(column),
  );

  i0.ColumnOrderings<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => i0.ColumnOrderings(column),
  );
}

class $$SyncOutboxTableAnnotationComposer
    extends i0.Composer<i0.GeneratedDatabase, i2.$SyncOutboxTable> {
  $$SyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  i0.GeneratedColumn<String> get opId =>
      $composableBuilder(column: $table.opId, builder: (column) => column);

  i0.GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  i0.GeneratedColumn<String> get entityId =>
      $composableBuilder(column: $table.entityId, builder: (column) => column);

  i0.GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  i0.GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  i0.GeneratedColumn<int> get ts =>
      $composableBuilder(column: $table.ts, builder: (column) => column);

  i0.GeneratedColumn<int> get tryCount =>
      $composableBuilder(column: $table.tryCount, builder: (column) => column);

  i0.GeneratedColumn<int> get baseUpdatedAt => $composableBuilder(
    column: $table.baseUpdatedAt,
    builder: (column) => column,
  );

  i0.GeneratedColumn<String> get changedFields => $composableBuilder(
    column: $table.changedFields,
    builder: (column) => column,
  );
}

class $$SyncOutboxTableTableManager
    extends
        i0.RootTableManager<
          i0.GeneratedDatabase,
          i2.$SyncOutboxTable,
          i1.SyncOutboxData,
          i2.$$SyncOutboxTableFilterComposer,
          i2.$$SyncOutboxTableOrderingComposer,
          i2.$$SyncOutboxTableAnnotationComposer,
          $$SyncOutboxTableCreateCompanionBuilder,
          $$SyncOutboxTableUpdateCompanionBuilder,
          (
            i1.SyncOutboxData,
            i0.BaseReferences<
              i0.GeneratedDatabase,
              i2.$SyncOutboxTable,
              i1.SyncOutboxData
            >,
          ),
          i1.SyncOutboxData,
          i0.PrefetchHooks Function()
        > {
  $$SyncOutboxTableTableManager(
    i0.GeneratedDatabase db,
    i2.$SyncOutboxTable table,
  ) : super(
        i0.TableManagerState(
          db: db,
          table: table,
          createFilteringComposer:
              () => i2.$$SyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer:
              () =>
                  i2.$$SyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer:
              () => i2.$$SyncOutboxTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                i0.Value<String> opId = const i0.Value.absent(),
                i0.Value<String> kind = const i0.Value.absent(),
                i0.Value<String> entityId = const i0.Value.absent(),
                i0.Value<String> op = const i0.Value.absent(),
                i0.Value<String?> payload = const i0.Value.absent(),
                i0.Value<int> ts = const i0.Value.absent(),
                i0.Value<int> tryCount = const i0.Value.absent(),
                i0.Value<int?> baseUpdatedAt = const i0.Value.absent(),
                i0.Value<String?> changedFields = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i2.SyncOutboxCompanion(
                opId: opId,
                kind: kind,
                entityId: entityId,
                op: op,
                payload: payload,
                ts: ts,
                tryCount: tryCount,
                baseUpdatedAt: baseUpdatedAt,
                changedFields: changedFields,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String opId,
                required String kind,
                required String entityId,
                required String op,
                i0.Value<String?> payload = const i0.Value.absent(),
                required int ts,
                i0.Value<int> tryCount = const i0.Value.absent(),
                i0.Value<int?> baseUpdatedAt = const i0.Value.absent(),
                i0.Value<String?> changedFields = const i0.Value.absent(),
                i0.Value<int> rowid = const i0.Value.absent(),
              }) => i2.SyncOutboxCompanion.insert(
                opId: opId,
                kind: kind,
                entityId: entityId,
                op: op,
                payload: payload,
                ts: ts,
                tryCount: tryCount,
                baseUpdatedAt: baseUpdatedAt,
                changedFields: changedFields,
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

typedef $$SyncOutboxTableProcessedTableManager =
    i0.ProcessedTableManager<
      i0.GeneratedDatabase,
      i2.$SyncOutboxTable,
      i1.SyncOutboxData,
      i2.$$SyncOutboxTableFilterComposer,
      i2.$$SyncOutboxTableOrderingComposer,
      i2.$$SyncOutboxTableAnnotationComposer,
      $$SyncOutboxTableCreateCompanionBuilder,
      $$SyncOutboxTableUpdateCompanionBuilder,
      (
        i1.SyncOutboxData,
        i0.BaseReferences<
          i0.GeneratedDatabase,
          i2.$SyncOutboxTable,
          i1.SyncOutboxData
        >,
      ),
      i1.SyncOutboxData,
      i0.PrefetchHooks Function()
    >;

class $SyncOutboxTable extends i3.SyncOutbox
    with i0.TableInfo<$SyncOutboxTable, i1.SyncOutboxData> {
  @override
  final i0.GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const i0.VerificationMeta _opIdMeta = const i0.VerificationMeta(
    'opId',
  );
  @override
  late final i0.GeneratedColumn<String> opId = i0.GeneratedColumn<String>(
    'op_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
  static const i0.VerificationMeta _entityIdMeta = const i0.VerificationMeta(
    'entityId',
  );
  @override
  late final i0.GeneratedColumn<String> entityId = i0.GeneratedColumn<String>(
    'entity_id',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _opMeta = const i0.VerificationMeta('op');
  @override
  late final i0.GeneratedColumn<String> op = i0.GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const i0.VerificationMeta _payloadMeta = const i0.VerificationMeta(
    'payload',
  );
  @override
  late final i0.GeneratedColumn<String> payload = i0.GeneratedColumn<String>(
    'payload',
    aliasedName,
    true,
    type: i0.DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const i0.VerificationMeta _tryCountMeta = const i0.VerificationMeta(
    'tryCount',
  );
  @override
  late final i0.GeneratedColumn<int> tryCount = i0.GeneratedColumn<int>(
    'try_count',
    aliasedName,
    false,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const i4.Constant(0),
  );
  static const i0.VerificationMeta _baseUpdatedAtMeta =
      const i0.VerificationMeta('baseUpdatedAt');
  @override
  late final i0.GeneratedColumn<int> baseUpdatedAt = i0.GeneratedColumn<int>(
    'base_updated_at',
    aliasedName,
    true,
    type: i0.DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const i0.VerificationMeta _changedFieldsMeta =
      const i0.VerificationMeta('changedFields');
  @override
  late final i0.GeneratedColumn<String> changedFields =
      i0.GeneratedColumn<String>(
        'changed_fields',
        aliasedName,
        true,
        type: i0.DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<i0.GeneratedColumn> get $columns => [
    opId,
    kind,
    entityId,
    op,
    payload,
    ts,
    tryCount,
    baseUpdatedAt,
    changedFields,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_outbox';
  @override
  i0.VerificationContext validateIntegrity(
    i0.Insertable<i1.SyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = i0.VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('op_id')) {
      context.handle(
        _opIdMeta,
        opId.isAcceptableOrUnknown(data['op_id']!, _opIdMeta),
      );
    } else if (isInserting) {
      context.missing(_opIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('entity_id')) {
      context.handle(
        _entityIdMeta,
        entityId.isAcceptableOrUnknown(data['entity_id']!, _entityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_entityIdMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    }
    if (data.containsKey('ts')) {
      context.handle(_tsMeta, ts.isAcceptableOrUnknown(data['ts']!, _tsMeta));
    } else if (isInserting) {
      context.missing(_tsMeta);
    }
    if (data.containsKey('try_count')) {
      context.handle(
        _tryCountMeta,
        tryCount.isAcceptableOrUnknown(data['try_count']!, _tryCountMeta),
      );
    }
    if (data.containsKey('base_updated_at')) {
      context.handle(
        _baseUpdatedAtMeta,
        baseUpdatedAt.isAcceptableOrUnknown(
          data['base_updated_at']!,
          _baseUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('changed_fields')) {
      context.handle(
        _changedFieldsMeta,
        changedFields.isAcceptableOrUnknown(
          data['changed_fields']!,
          _changedFieldsMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<i0.GeneratedColumn> get $primaryKey => {opId};
  @override
  i1.SyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return i1.SyncOutboxData(
      opId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}op_id'],
          )!,
      kind:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}kind'],
          )!,
      entityId:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}entity_id'],
          )!,
      op:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.string,
            data['${effectivePrefix}op'],
          )!,
      payload: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}payload'],
      ),
      ts:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}ts'],
          )!,
      tryCount:
          attachedDatabase.typeMapping.read(
            i0.DriftSqlType.int,
            data['${effectivePrefix}try_count'],
          )!,
      baseUpdatedAt: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.int,
        data['${effectivePrefix}base_updated_at'],
      ),
      changedFields: attachedDatabase.typeMapping.read(
        i0.DriftSqlType.string,
        data['${effectivePrefix}changed_fields'],
      ),
    );
  }

  @override
  $SyncOutboxTable createAlias(String alias) {
    return $SyncOutboxTable(attachedDatabase, alias);
  }
}

class SyncOutboxCompanion extends i0.UpdateCompanion<i1.SyncOutboxData> {
  final i0.Value<String> opId;
  final i0.Value<String> kind;
  final i0.Value<String> entityId;
  final i0.Value<String> op;
  final i0.Value<String?> payload;
  final i0.Value<int> ts;
  final i0.Value<int> tryCount;
  final i0.Value<int?> baseUpdatedAt;
  final i0.Value<String?> changedFields;
  final i0.Value<int> rowid;
  const SyncOutboxCompanion({
    this.opId = const i0.Value.absent(),
    this.kind = const i0.Value.absent(),
    this.entityId = const i0.Value.absent(),
    this.op = const i0.Value.absent(),
    this.payload = const i0.Value.absent(),
    this.ts = const i0.Value.absent(),
    this.tryCount = const i0.Value.absent(),
    this.baseUpdatedAt = const i0.Value.absent(),
    this.changedFields = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  });
  SyncOutboxCompanion.insert({
    required String opId,
    required String kind,
    required String entityId,
    required String op,
    this.payload = const i0.Value.absent(),
    required int ts,
    this.tryCount = const i0.Value.absent(),
    this.baseUpdatedAt = const i0.Value.absent(),
    this.changedFields = const i0.Value.absent(),
    this.rowid = const i0.Value.absent(),
  }) : opId = i0.Value(opId),
       kind = i0.Value(kind),
       entityId = i0.Value(entityId),
       op = i0.Value(op),
       ts = i0.Value(ts);
  static i0.Insertable<i1.SyncOutboxData> custom({
    i0.Expression<String>? opId,
    i0.Expression<String>? kind,
    i0.Expression<String>? entityId,
    i0.Expression<String>? op,
    i0.Expression<String>? payload,
    i0.Expression<int>? ts,
    i0.Expression<int>? tryCount,
    i0.Expression<int>? baseUpdatedAt,
    i0.Expression<String>? changedFields,
    i0.Expression<int>? rowid,
  }) {
    return i0.RawValuesInsertable({
      if (opId != null) 'op_id': opId,
      if (kind != null) 'kind': kind,
      if (entityId != null) 'entity_id': entityId,
      if (op != null) 'op': op,
      if (payload != null) 'payload': payload,
      if (ts != null) 'ts': ts,
      if (tryCount != null) 'try_count': tryCount,
      if (baseUpdatedAt != null) 'base_updated_at': baseUpdatedAt,
      if (changedFields != null) 'changed_fields': changedFields,
      if (rowid != null) 'rowid': rowid,
    });
  }

  i2.SyncOutboxCompanion copyWith({
    i0.Value<String>? opId,
    i0.Value<String>? kind,
    i0.Value<String>? entityId,
    i0.Value<String>? op,
    i0.Value<String?>? payload,
    i0.Value<int>? ts,
    i0.Value<int>? tryCount,
    i0.Value<int?>? baseUpdatedAt,
    i0.Value<String?>? changedFields,
    i0.Value<int>? rowid,
  }) {
    return i2.SyncOutboxCompanion(
      opId: opId ?? this.opId,
      kind: kind ?? this.kind,
      entityId: entityId ?? this.entityId,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      ts: ts ?? this.ts,
      tryCount: tryCount ?? this.tryCount,
      baseUpdatedAt: baseUpdatedAt ?? this.baseUpdatedAt,
      changedFields: changedFields ?? this.changedFields,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, i0.Expression> toColumns(bool nullToAbsent) {
    final map = <String, i0.Expression>{};
    if (opId.present) {
      map['op_id'] = i0.Variable<String>(opId.value);
    }
    if (kind.present) {
      map['kind'] = i0.Variable<String>(kind.value);
    }
    if (entityId.present) {
      map['entity_id'] = i0.Variable<String>(entityId.value);
    }
    if (op.present) {
      map['op'] = i0.Variable<String>(op.value);
    }
    if (payload.present) {
      map['payload'] = i0.Variable<String>(payload.value);
    }
    if (ts.present) {
      map['ts'] = i0.Variable<int>(ts.value);
    }
    if (tryCount.present) {
      map['try_count'] = i0.Variable<int>(tryCount.value);
    }
    if (baseUpdatedAt.present) {
      map['base_updated_at'] = i0.Variable<int>(baseUpdatedAt.value);
    }
    if (changedFields.present) {
      map['changed_fields'] = i0.Variable<String>(changedFields.value);
    }
    if (rowid.present) {
      map['rowid'] = i0.Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncOutboxCompanion(')
          ..write('opId: $opId, ')
          ..write('kind: $kind, ')
          ..write('entityId: $entityId, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('ts: $ts, ')
          ..write('tryCount: $tryCount, ')
          ..write('baseUpdatedAt: $baseUpdatedAt, ')
          ..write('changedFields: $changedFields, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}
