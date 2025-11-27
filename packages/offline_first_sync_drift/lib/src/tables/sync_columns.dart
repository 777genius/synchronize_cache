import 'package:drift/drift.dart';

/// Маркерный интерфейс для синхронизируемых таблиц.
/// Позволяет типобезопасно определять, что таблица содержит
/// обязательные системные поля.
abstract interface class SynchronizableTable {
  DateTimeColumn get updatedAt;
  DateTimeColumn get deletedAt;
  DateTimeColumn get deletedAtLocal;
}

/// Mixin для таблиц с синхронизацией.
/// Добавляет стандартные поля updatedAt, deletedAt, deletedAtLocal.
mixin SyncColumns on Table implements SynchronizableTable {
  /// Время последнего обновления (UTC).
  @override
  DateTimeColumn get updatedAt => dateTime()();

  /// Время удаления на сервере (UTC), null если не удалено.
  @override
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Время локального удаления (UTC), для отложенной очистки.
  @override
  DateTimeColumn get deletedAtLocal => dateTime().nullable()();
}
