import 'package:drift/drift.dart';

/// Конфигурация синхронизируемой таблицы.
/// Регистрируется в SyncEngine для автоматической синхронизации.
class SyncableTable<T> {
  const SyncableTable({
    required this.kind,
    required this.table,
    required this.fromJson,
    required this.toJson,
    this.toInsertable,
    this.getId,
    this.getUpdatedAt,
  });

  /// Имя сущности на сервере (например, 'daily_feeling').
  final String kind;

  /// Drift таблица.
  final TableInfo<Table, T> table;

  /// Фабрика для создания объекта из JSON сервера.
  final T Function(Map<String, dynamic> json) fromJson;

  /// Сериализация объекта в JSON для отправки на сервер.
  final Map<String, dynamic> Function(T entity) toJson;

  /// Конвертация entity в Insertable для записи в БД.
  /// Если используете @UseRowClass(T, generateInsertable: true),
  /// передайте: toInsertable: (e) => e.toInsertable()
  /// Если T implements Insertable<T>, можно не указывать.
  final Insertable<T> Function(T entity)? toInsertable;

  /// Получить ID сущности. По умолчанию ищет поле 'id'.
  final String Function(T entity)? getId;

  /// Получить updatedAt сущности. По умолчанию ищет поле 'updatedAt'.
  final DateTime Function(T entity)? getUpdatedAt;

  /// Получить Insertable из entity.
  Insertable<T> getInsertable(T entity) {
    if (toInsertable != null) {
      return toInsertable!(entity);
    }
    // Fallback: assume entity implements Insertable<T>
    return entity as Insertable<T>;
  }
}
