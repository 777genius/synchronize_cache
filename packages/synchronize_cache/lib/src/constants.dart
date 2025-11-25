/// Константы для синхронизации.

/// Типы операций в outbox.
abstract final class OpType {
  static const upsert = 'upsert';
  static const delete = 'delete';
}

/// Имена полей для сериализации/десериализации.
abstract final class SyncFields {
  // ID поля
  static const id = 'id';
  static const idUpper = 'ID';
  static const uuid = 'uuid';

  // Timestamp поля (camelCase)
  static const updatedAt = 'updatedAt';
  static const createdAt = 'createdAt';
  static const deletedAt = 'deletedAt';

  // Timestamp поля (snake_case)
  static const updatedAtSnake = 'updated_at';
  static const createdAtSnake = 'created_at';
  static const deletedAtSnake = 'deleted_at';

  /// Все ID поля для поиска.
  static const idFields = [id, idUpper, uuid];

  /// Все updatedAt поля для поиска.
  static const updatedAtFields = [updatedAt, updatedAtSnake];

  /// Все deletedAt поля для поиска.
  static const deletedAtFields = [deletedAt, deletedAtSnake];
}

/// Имена колонок в таблицах (snake_case для SQL).
abstract final class TableColumns {
  static const opId = 'op_id';
  static const kind = 'kind';
  static const entityId = 'entity_id';
  static const op = 'op';
  static const payload = 'payload';
  static const ts = 'ts';
  static const tryCount = 'try_count';
  static const baseUpdatedAt = 'base_updated_at';
  static const changedFields = 'changed_fields';
  static const lastId = 'last_id';
}

/// Имена таблиц.
abstract final class TableNames {
  static const syncOutbox = 'sync_outbox';
  static const syncCursors = 'sync_cursors';
}

