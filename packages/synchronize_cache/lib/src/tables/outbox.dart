import 'package:drift/drift.dart';
import 'package:synchronize_cache/src/tables/sync_data_classes.dart';

/// Таблица очереди операций для синхронизации.
/// Хранит локальные изменения до отправки на сервер.
@UseRowClass(SyncOutboxData)
class SyncOutbox extends Table {
  /// Уникальный идентификатор операции.
  TextColumn get opId => text()();

  /// Тип сущности (например, 'daily_feeling').
  TextColumn get kind => text()();

  /// ID сущности.
  TextColumn get entityId => text()();

  /// Тип операции: 'upsert' или 'delete'.
  TextColumn get op => text()();

  /// JSON payload для upsert операций.
  TextColumn get payload => text().nullable()();

  /// Timestamp операции (milliseconds UTC).
  IntColumn get ts => integer()();

  /// Количество попыток отправки.
  IntColumn get tryCount => integer().withDefault(const Constant(0))();

  /// Timestamp когда данные были получены с сервера (milliseconds UTC).
  IntColumn get baseUpdatedAt => integer().nullable()();

  /// JSON array с именами изменённых полей.
  TextColumn get changedFields => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};

  @override
  String get tableName => 'sync_outbox';
}
