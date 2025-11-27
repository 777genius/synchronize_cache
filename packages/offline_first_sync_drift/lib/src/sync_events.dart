import 'package:offline_first_sync_drift/src/conflict_resolution.dart';

/// События синхронизации для логирования, UI и метрик.

sealed class SyncEvent {}

/// Фаза синхронизации.
enum SyncPhase { push, pull }

/// Причина запуска full resync.
enum FullResyncReason {
  /// Запущено по расписанию (fullResyncInterval).
  scheduled,

  /// Запущено вручную.
  manual,
}

/// Начало полной ресинхронизации.
class FullResyncStarted implements SyncEvent {
  FullResyncStarted(this.reason);
  final FullResyncReason reason;

  @override
  String toString() => 'FullResyncStarted($reason)';
}

/// Начало синхронизации.
class SyncStarted implements SyncEvent {
  SyncStarted(this.phase);
  final SyncPhase phase;

  @override
  String toString() => 'SyncStarted($phase)';
}

/// Прогресс синхронизации.
class SyncProgress implements SyncEvent {
  SyncProgress(this.phase, this.done, this.total);
  final SyncPhase phase;
  final int done;
  final int total;

  double get progress => total > 0 ? done / total : 0;

  @override
  String toString() => 'SyncProgress($phase, $done/$total)';
}

/// Завершение синхронизации.
class SyncCompleted implements SyncEvent {
  SyncCompleted(this.took, this.at, {this.stats});
  final Duration took;
  final DateTime at;
  final SyncStats? stats;

  @override
  String toString() => 'SyncCompleted(took: ${took.inMilliseconds}ms)';
}

/// Статистика синхронизации.
class SyncStats {
  const SyncStats({
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.conflictsResolved = 0,
    this.errors = 0,
  });

  final int pushed;
  final int pulled;
  final int conflicts;
  final int conflictsResolved;
  final int errors;

  SyncStats copyWith({
    int? pushed,
    int? pulled,
    int? conflicts,
    int? conflictsResolved,
    int? errors,
  }) => SyncStats(
    pushed: pushed ?? this.pushed,
    pulled: pulled ?? this.pulled,
    conflicts: conflicts ?? this.conflicts,
    conflictsResolved: conflictsResolved ?? this.conflictsResolved,
    errors: errors ?? this.errors,
  );

  @override
  String toString() =>
      'SyncStats(pushed: $pushed, pulled: $pulled, '
      'conflicts: $conflicts, resolved: $conflictsResolved, errors: $errors)';
}

/// Ошибка синхронизации.
class SyncErrorEvent implements SyncEvent {
  SyncErrorEvent(this.phase, this.error, [this.stackTrace]);
  final SyncPhase phase;
  final Object error;
  final StackTrace? stackTrace;

  @override
  String toString() => 'SyncError($phase): $error';
}

/// Обнаружен конфликт данных.
class ConflictDetectedEvent implements SyncEvent {
  ConflictDetectedEvent({required this.conflict, required this.strategy});

  /// Информация о конфликте.
  final Conflict conflict;

  /// Стратегия, которая будет применена.
  final ConflictStrategy strategy;

  @override
  String toString() =>
      'ConflictDetected(${conflict.kind}/${conflict.entityId}, '
      'strategy: $strategy)';
}

/// Конфликт разрешён.
class ConflictResolvedEvent implements SyncEvent {
  ConflictResolvedEvent({
    required this.conflict,
    required this.resolution,
    this.resultData,
  });

  /// Информация о конфликте.
  final Conflict conflict;

  /// Как был разрешён конфликт.
  final ConflictResolution resolution;

  /// Итоговые данные после разрешения.
  final Map<String, Object?>? resultData;

  @override
  String toString() =>
      'ConflictResolved(${conflict.kind}/${conflict.entityId}, '
      '${resolution.runtimeType})';
}

/// Конфликт не удалось разрешить автоматически.
class ConflictUnresolvedEvent implements SyncEvent {
  ConflictUnresolvedEvent({required this.conflict, required this.reason});

  /// Информация о конфликте.
  final Conflict conflict;

  /// Причина, почему не удалось разрешить.
  final String reason;

  @override
  String toString() =>
      'ConflictUnresolved(${conflict.kind}/${conflict.entityId}, '
      'reason: $reason)';
}

/// Данные были объединены при разрешении конфликта.
class DataMergedEvent implements SyncEvent {
  DataMergedEvent({
    required this.kind,
    required this.entityId,
    required this.localFields,
    required this.serverFields,
    required this.mergedData,
  });

  /// Тип сущности.
  final String kind;

  /// ID сущности.
  final String entityId;

  /// Поля, взятые из локальных данных.
  final Set<String> localFields;

  /// Поля, взятые с сервера.
  final Set<String> serverFields;

  /// Объединённые данные.
  final Map<String, Object?> mergedData;

  @override
  String toString() =>
      'DataMerged($kind/$entityId, '
      'local: ${localFields.length} fields, server: ${serverFields.length} fields)';
}

/// Обновление кэша.
class CacheUpdateEvent implements SyncEvent {
  CacheUpdateEvent(this.kind, {this.upserts = 0, this.deletes = 0});
  final String kind;
  final int upserts;
  final int deletes;

  @override
  String toString() =>
      'CacheUpdate($kind, upserts: $upserts, deletes: $deletes)';
}

/// Операция успешно отправлена.
class OperationPushedEvent implements SyncEvent {
  OperationPushedEvent({
    required this.opId,
    required this.kind,
    required this.entityId,
    required this.operationType,
  });

  final String opId;
  final String kind;
  final String entityId;
  final String operationType;

  @override
  String toString() => 'OperationPushed($operationType $kind/$entityId)';
}

/// Операция не удалась.
class OperationFailedEvent implements SyncEvent {
  OperationFailedEvent({
    required this.opId,
    required this.kind,
    required this.entityId,
    required this.error,
    this.willRetry = false,
  });

  final String opId;
  final String kind;
  final String entityId;
  final Object error;
  final bool willRetry;

  @override
  String toString() => 'OperationFailed($kind/$entityId, retry: $willRetry)';
}
