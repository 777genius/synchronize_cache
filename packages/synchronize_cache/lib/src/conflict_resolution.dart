import 'package:synchronize_cache/src/constants.dart';

/// Стратегии и типы для разрешения конфликтов синхронизации.

/// Стратегия разрешения конфликтов.
enum ConflictStrategy {
  /// Серверная версия всегда побеждает.
  serverWins,

  /// Клиентская версия всегда побеждает (retry с force).
  clientWins,

  /// Побеждает версия с более поздним timestamp.
  lastWriteWins,

  /// Попытка слияния изменений.
  merge,

  /// Ручное разрешение через callback.
  manual,

  /// Автоматический умный merge без потери данных.
  autoPreserve,
}

/// Результат разрешения конфликта.
sealed class ConflictResolution {
  const ConflictResolution();
}

/// Принять серверную версию.
class AcceptServer extends ConflictResolution {
  const AcceptServer();
}

/// Принять клиентскую версию (повторить push с force).
class AcceptClient extends ConflictResolution {
  const AcceptClient();
}

/// Использовать объединённые данные.
class AcceptMerged extends ConflictResolution {
  const AcceptMerged(this.mergedData, {this.mergeInfo});

  final Map<String, Object?> mergedData;

  /// Информация о том, откуда взяты поля.
  final MergeInfo? mergeInfo;
}

/// Информация о слиянии данных.
class MergeInfo {
  const MergeInfo({
    required this.localFields,
    required this.serverFields,
  });

  /// Поля, взятые из локальных данных.
  final Set<String> localFields;

  /// Поля, взятые с сервера.
  final Set<String> serverFields;
}

/// Отложить разрешение (оставить в outbox).
class DeferResolution extends ConflictResolution {
  const DeferResolution();
}

/// Отменить операцию (удалить из outbox).
class DiscardOperation extends ConflictResolution {
  const DiscardOperation();
}

/// Информация о конфликте.
class Conflict {
  const Conflict({
    required this.kind,
    required this.entityId,
    required this.opId,
    required this.localData,
    required this.serverData,
    required this.localTimestamp,
    required this.serverTimestamp,
    this.serverVersion,
    this.changedFields,
  });

  /// Тип сущности.
  final String kind;

  /// ID сущности.
  final String entityId;

  /// ID операции.
  final String opId;

  /// Локальные данные клиента.
  final Map<String, Object?> localData;

  /// Данные с сервера.
  final Map<String, Object?> serverData;

  /// Локальный timestamp изменения.
  final DateTime localTimestamp;

  /// Серверный timestamp изменения.
  final DateTime serverTimestamp;

  /// Версия на сервере (ETag, version number).
  final String? serverVersion;

  /// Поля, изменённые клиентом.
  final Set<String>? changedFields;

  @override
  String toString() => 'Conflict(kind: $kind, id: $entityId, '
      'local: ${localTimestamp.toIso8601String()}, '
      'server: ${serverTimestamp.toIso8601String()})';
}

/// Callback для ручного разрешения конфликта.
typedef ConflictResolver = Future<ConflictResolution> Function(Conflict conflict);

/// Callback для слияния данных.
typedef MergeFunction = Map<String, Object?> Function(
  Map<String, Object?> local,
  Map<String, Object?> server,
);

/// Результат push операции.
sealed class PushResult {
  const PushResult();
}

/// Операция успешно отправлена.
class PushSuccess extends PushResult {
  const PushSuccess({this.serverData, this.serverVersion});

  /// Данные, возвращённые сервером (если есть).
  final Map<String, Object?>? serverData;

  /// Версия на сервере после операции.
  final String? serverVersion;
}

/// Конфликт при отправке.
class PushConflict extends PushResult {
  const PushConflict({
    required this.serverData,
    required this.serverTimestamp,
    this.serverVersion,
  });

  /// Текущие данные на сервере.
  final Map<String, Object?> serverData;

  /// Timestamp данных на сервере.
  final DateTime serverTimestamp;

  /// Версия на сервере.
  final String? serverVersion;
}

/// Сущность не найдена на сервере (для update/delete).
class PushNotFound extends PushResult {
  const PushNotFound();
}

/// Ошибка при отправке (не конфликт).
class PushError extends PushResult {
  const PushError(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}

/// Утилиты для работы с конфликтами.
abstract final class ConflictUtils {
  /// Системные поля которые не мержим.
  static const systemFields = {
    SyncFields.id,
    SyncFields.idUpper,
    SyncFields.uuid,
    SyncFields.updatedAt,
    SyncFields.updatedAtSnake,
    SyncFields.createdAt,
    SyncFields.createdAtSnake,
    SyncFields.deletedAt,
    SyncFields.deletedAtSnake,
  };

  /// Стандартное слияние: server-поля + изменённые client-поля.
  /// Сохраняет серверные значения для полей, которые клиент не менял.
  static Map<String, Object?> defaultMerge(
    Map<String, Object?> local,
    Map<String, Object?> server,
  ) {
    final merged = Map<String, Object?>.from(server);
    for (final entry in local.entries) {
      if (entry.value != null) {
        merged[entry.key] = entry.value;
      }
    }
    return merged;
  }

  /// Глубокое слияние для вложенных объектов.
  static Map<String, Object?> deepMerge(
    Map<String, Object?> local,
    Map<String, Object?> server,
  ) {
    final merged = <String, Object?>{};

    final allKeys = {...local.keys, ...server.keys};

    for (final key in allKeys) {
      final localValue = local[key];
      final serverValue = server[key];

      if (localValue is Map<String, Object?> &&
          serverValue is Map<String, Object?>) {
        merged[key] = deepMerge(localValue, serverValue);
      } else if (local.containsKey(key)) {
        merged[key] = localValue;
      } else {
        merged[key] = serverValue;
      }
    }

    return merged;
  }

  /// Умный merge который сохраняет ВСЕ данные без потерь.
  ///
  /// Логика:
  /// - Системные поля берутся с сервера
  /// - Если указаны [changedFields] — применяем только эти поля из локальных
  /// - Если локальное значение не null, а серверное null — берём локальное
  /// - Списки объединяются (union)
  /// - Вложенные объекты мержатся рекурсивно
  static PreservingMergeResult preservingMerge(
    Map<String, Object?> local,
    Map<String, Object?> server, {
    Set<String>? changedFields,
  }) {
    final result = Map<String, Object?>.from(server);
    final localFieldsUsed = <String>{};
    final serverFieldsUsed = <String>{};

    // Все поля с сервера по умолчанию
    for (final key in server.keys) {
      if (!systemFields.contains(key)) {
        serverFieldsUsed.add(key);
      }
    }

    for (final key in local.keys) {
      // Системные поля — всегда с сервера
      if (systemFields.contains(key)) continue;

      final localVal = local[key];
      final serverVal = server[key];

      // Если указаны changedFields — применяем только их
      if (changedFields != null && !changedFields.contains(key)) {
        continue;
      }

      // Оба null — пропускаем
      if (localVal == null && serverVal == null) continue;

      // Локальное есть, серверного нет — берём локальное
      if (localVal != null && serverVal == null) {
        result[key] = localVal;
        localFieldsUsed.add(key);
        serverFieldsUsed.remove(key);
        continue;
      }

      // Локальное null, серверное есть — оставляем серверное
      if (localVal == null && serverVal != null) {
        continue;
      }

      // Оба есть — умный merge по типу
      if (localVal is List && serverVal is List) {
        result[key] = _mergeLists(localVal, serverVal);
        localFieldsUsed.add(key);
        // Списки объединены, оба источника использованы
      } else if (localVal is Map<String, Object?> &&
          serverVal is Map<String, Object?>) {
        final nestedResult = preservingMerge(localVal, serverVal);
        result[key] = nestedResult.data;
        if (nestedResult.localFields.isNotEmpty) {
          localFieldsUsed.add(key);
        }
      } else {
        // Примитивы — берём локальное (пользователь изменил)
        result[key] = localVal;
        localFieldsUsed.add(key);
        serverFieldsUsed.remove(key);
      }
    }

    return PreservingMergeResult(
      data: result,
      localFields: localFieldsUsed,
      serverFields: serverFieldsUsed,
    );
  }

  /// Объединение списков.
  static List<Object?> _mergeLists(List<Object?> local, List<Object?> server) {
    final result = List<Object?>.from(server);

    for (final item in local) {
      if (item is Map && item.containsKey(SyncFields.id)) {
        final itemId = item[SyncFields.id];
        final exists = server.any((s) => s is Map && s[SyncFields.id] == itemId);
        if (!exists) {
          result.add(item);
        }
      } else {
        if (!server.contains(item)) {
          result.add(item);
        }
      }
    }

    return result;
  }

  /// Получить timestamp из JSON данных.
  static DateTime? extractTimestamp(Map<String, Object?> data) {
    final ts = data[SyncFields.updatedAt] ?? data[SyncFields.updatedAtSnake];
    if (ts == null) return null;
    if (ts is DateTime) return ts;
    return DateTime.tryParse(ts.toString())?.toUtc();
  }
}

/// Результат preservingMerge с информацией об источниках полей.
class PreservingMergeResult {
  const PreservingMergeResult({
    required this.data,
    required this.localFields,
    required this.serverFields,
  });

  /// Объединённые данные.
  final Map<String, Object?> data;

  /// Поля, взятые из локальных данных.
  final Set<String> localFields;

  /// Поля, взятые с сервера.
  final Set<String> serverFields;
}
