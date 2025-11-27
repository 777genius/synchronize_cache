import 'package:drift/drift.dart';
import 'package:synchronize_cache/src/tables/sync_data_classes.dart';

/// Таблица курсоров для стабильной пагинации при pull.
/// Хранит позицию последней синхронизации по каждому kind.
@UseRowClass(SyncCursorData)
class SyncCursors extends Table {
  /// Тип сущности.
  TextColumn get kind => text()();

  /// Timestamp последнего элемента (milliseconds UTC).
  IntColumn get ts => integer()();

  /// ID последнего элемента для разрешения коллизий при одинаковом ts.
  TextColumn get lastId => text()();

  @override
  Set<Column> get primaryKey => {kind};

  @override
  String get tableName => 'sync_cursors';
}
