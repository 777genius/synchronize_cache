import 'package:drift/drift.dart';

/// Mixin для таблиц с синхронизацией.
/// Добавляет стандартные поля updatedAt, deletedAt, deletedAtLocal.
mixin SyncColumns on Table {
  /// Время последнего обновления (UTC).
  DateTimeColumn get updatedAt => dateTime()();

  /// Время удаления на сервере (UTC), null если не удалено.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Время локального удаления (UTC), для отложенной очистки.
  DateTimeColumn get deletedAtLocal => dateTime().nullable()();
}

