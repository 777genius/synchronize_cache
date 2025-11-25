import 'package:drift/drift.dart';
import 'package:synchronize_cache/synchronize_cache.dart';

@UseRowClass(SyncOutboxData)
class LocalSyncOutbox extends Table {
  TextColumn get opId => text()();
  TextColumn get kind => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get ts => integer()();
  IntColumn get tryCount => integer().withDefault(const Constant(0))();
  IntColumn get baseUpdatedAt => integer().nullable()();
  TextColumn get changedFields => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};

  @override
  String get tableName => 'sync_outbox';
}

@UseRowClass(SyncCursorsData)
class LocalSyncCursors extends Table {
  TextColumn get kind => text()();
  IntColumn get ts => integer()();
  TextColumn get lastId => text()();

  @override
  Set<Column> get primaryKey => {kind};

  @override
  String get tableName => 'sync_cursors';
}
