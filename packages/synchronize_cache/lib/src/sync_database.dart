import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:synchronize_cache/src/constants.dart';
import 'package:synchronize_cache/src/cursor.dart';
import 'package:synchronize_cache/src/op.dart';
import 'package:synchronize_cache/src/tables/cursors.drift.dart';
import 'package:synchronize_cache/src/tables/outbox.drift.dart';
import 'package:synchronize_cache/src/tables/sync_data_classes.dart';

/// Mixin для базы данных с поддержкой синхронизации.
///
/// Для использования:
/// 1. Добавьте в @DriftDatabase:
///    `include: {'package:synchronize_cache/src/sync_tables.drift'}`
/// 2. Добавьте "with SyncDatabaseMixin" к вашему классу базы данных
///
/// Drift автоматически подключит sync_outbox и sync_cursors таблицы.
mixin SyncDatabaseMixin on GeneratedDatabase {
  TableInfo<Table, SyncOutboxData>? _outboxTable;
  TableInfo<Table, SyncCursorData>? _cursorsTable;

  /// Получить таблицу outbox.
  TableInfo<Table, SyncOutboxData> get _outbox =>
      _outboxTable ??= allTables.whereType<TableInfo<Table, SyncOutboxData>>().firstWhere(
            (t) => t.actualTableName == 'sync_outbox',
            orElse: () => throw StateError(
              'SyncOutbox table not found. Make sure to add:\n'
              "include: {'package:synchronize_cache/src/sync_tables.drift'}\n"
              'to your @DriftDatabase annotation.',
            ),
          );

  /// Получить таблицу cursors.
  TableInfo<Table, SyncCursorData> get _cursors =>
      _cursorsTable ??= allTables.whereType<TableInfo<Table, SyncCursorData>>().firstWhere(
            (t) => t.actualTableName == 'sync_cursors',
            orElse: () => throw StateError(
              'SyncCursors table not found. Make sure to add:\n'
              "include: {'package:synchronize_cache/src/sync_tables.drift'}\n"
              'to your @DriftDatabase annotation.',
            ),
          );

  /// Добавить операцию в очередь отправки.
  Future<void> enqueue(Op op) async {
    final ts = op.localTimestamp.toUtc().millisecondsSinceEpoch;

    if (op is UpsertOp) {
      final baseTs = op.baseUpdatedAt?.toUtc().millisecondsSinceEpoch;
      final changedFieldsJson = op.changedFields != null
          ? jsonEncode(op.changedFields!.toList())
          : null;

      await into(_outbox).insertOnConflictUpdate(
        SyncOutboxCompanion.insert(
          opId: op.opId,
          kind: op.kind,
          entityId: op.id,
          op: OpType.upsert,
          ts: ts,
          payload: Value(jsonEncode(op.payloadJson)),
          tryCount: const Value(0),
          baseUpdatedAt: Value(baseTs),
          changedFields: Value(changedFieldsJson),
        ),
      );
    } else if (op is DeleteOp) {
      final baseTs = op.baseUpdatedAt?.toUtc().millisecondsSinceEpoch;

      await into(_outbox).insertOnConflictUpdate(
        SyncOutboxCompanion.insert(
          opId: op.opId,
          kind: op.kind,
          entityId: op.id,
          op: OpType.delete,
          ts: ts,
          tryCount: const Value(0),
          baseUpdatedAt: Value(baseTs),
        ),
      );
    }
  }

  /// Получить операции из очереди для отправки.
  Future<List<Op>> takeOutbox({int limit = 100}) async {
    final rows = await customSelect(
      'SELECT * FROM ${TableNames.syncOutbox} ORDER BY ${TableColumns.ts} LIMIT ?',
      variables: [Variable.withInt(limit)],
      readsFrom: {_outbox},
    ).get();

    return rows.map((row) {
      final opId = row.read<String>(TableColumns.opId);
      final kind = row.read<String>(TableColumns.kind);
      final entityId = row.read<String>(TableColumns.entityId);
      final opType = row.read<String>(TableColumns.op);
      final tsMillis = row.read<int>(TableColumns.ts);
      final baseUpdatedAtMillis = row.readNullable<int>(TableColumns.baseUpdatedAt);

      final ts = DateTime.fromMillisecondsSinceEpoch(tsMillis, isUtc: true);
      final baseUpdatedAt = baseUpdatedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(baseUpdatedAtMillis, isUtc: true)
          : null;

      if (opType == OpType.delete) {
        return DeleteOp(
          opId: opId,
          kind: kind,
          id: entityId,
          localTimestamp: ts,
          baseUpdatedAt: baseUpdatedAt,
        );
      }

      final payloadStr = row.readNullable<String>(TableColumns.payload);
      final payload = payloadStr == null
          ? <String, Object?>{}
          : (jsonDecode(payloadStr) as Map<String, Object?>);

      final changedFieldsStr = row.readNullable<String>(TableColumns.changedFields);
      Set<String>? changedFields;
      if (changedFieldsStr != null) {
        final list = jsonDecode(changedFieldsStr) as List<dynamic>;
        changedFields = list.cast<String>().toSet();
      }

      return UpsertOp(
        opId: opId,
        kind: kind,
        id: entityId,
        localTimestamp: ts,
        payloadJson: payload,
        baseUpdatedAt: baseUpdatedAt,
        changedFields: changedFields,
      );
    }).toList();
  }

  /// Подтвердить отправку операций (удалить из очереди).
  Future<void> ackOutbox(Iterable<String> opIds) async {
    if (opIds.isEmpty) return;
    final ids = opIds.toList();
    final placeholders = List.filled(ids.length, '?').join(', ');

    await customStatement(
      'DELETE FROM ${TableNames.syncOutbox} WHERE ${TableColumns.opId} IN ($placeholders)',
      ids,
    );
  }

  /// Получить курсор для типа сущности.
  Future<Cursor?> getCursor(String kind) async {
    final rows = await customSelect(
      'SELECT ${TableColumns.ts}, ${TableColumns.lastId} '
      'FROM ${TableNames.syncCursors} WHERE ${TableColumns.kind} = ?',
      variables: [Variable.withString(kind)],
      readsFrom: {_cursors},
    ).get();

    if (rows.isEmpty) return null;

    final row = rows.first;
    return Cursor(
      ts: DateTime.fromMillisecondsSinceEpoch(row.read<int>(TableColumns.ts), isUtc: true),
      lastId: row.read<String>(TableColumns.lastId),
    );
  }

  /// Сохранить курсор для типа сущности.
  Future<void> setCursor(String kind, Cursor cursor) async {
    await into(_cursors).insertOnConflictUpdate(
      SyncCursorsCompanion.insert(
        kind: kind,
        ts: cursor.ts.toUtc().millisecondsSinceEpoch,
        lastId: cursor.lastId,
      ),
    );
  }

  /// Очистить операции старше threshold.
  Future<int> purgeOutboxOlderThan(DateTime threshold) async {
    final th = threshold.toUtc().millisecondsSinceEpoch;
    return customUpdate(
      'DELETE FROM ${TableNames.syncOutbox} WHERE ${TableColumns.ts} <= ?',
      variables: [Variable.withInt(th)],
      updateKind: UpdateKind.delete,
    );
  }

  /// Сбросить все курсоры для указанных типов.
  Future<void> resetAllCursors(Set<String> kinds) async {
    if (kinds.isEmpty) return;

    final placeholders = List.filled(kinds.length, '?').join(', ');
    await customStatement(
      'DELETE FROM ${TableNames.syncCursors} WHERE ${TableColumns.kind} IN ($placeholders)',
      kinds.toList(),
    );
  }

  /// Очистить данные синхронизируемых таблиц.
  /// [tableNames] — имена таблиц для очистки.
  Future<void> clearSyncableTables(List<String> tableNames) async {
    for (final tableName in tableNames) {
      await customStatement('DELETE FROM "$tableName"');
    }
  }
}
