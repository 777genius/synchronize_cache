import 'package:offline_first_sync_drift/src/conflict_resolution.dart';

/// Конфигурация синхронизации.
class SyncConfig {
  const SyncConfig({
    this.pageSize = 500,
    this.backoffMin = const Duration(seconds: 1),
    this.backoffMax = const Duration(minutes: 2),
    this.backoffMultiplier = 2.0,
    this.maxPushRetries = 5,
    this.fullResyncInterval = const Duration(days: 7),
    this.pullOnStartup = false,
    this.pushImmediately = true,
    this.reconcileInterval,
    this.lazyReconcileOnMiss = false,
    this.conflictStrategy = ConflictStrategy.autoPreserve,
    this.conflictResolver,
    this.mergeFunction,
    this.maxConflictRetries = 3,
    this.conflictRetryDelay = const Duration(milliseconds: 500),
    this.skipConflictingOps = false,
  });

  /// Размер страницы при pull.
  final int pageSize;

  /// Минимальная задержка при retry.
  final Duration backoffMin;

  /// Максимальная задержка при retry.
  final Duration backoffMax;

  /// Множитель для exponential backoff.
  final double backoffMultiplier;

  /// Максимальное количество попыток отправки push.
  final int maxPushRetries;

  /// Интервал полной ресинхронизации.
  final Duration fullResyncInterval;

  /// Выполнять pull при старте.
  final bool pullOnStartup;

  /// Отправлять изменения сразу.
  final bool pushImmediately;

  /// Интервал сверки данных.
  final Duration? reconcileInterval;

  /// Ленивая сверка при промахе.
  final bool lazyReconcileOnMiss;

  /// Стратегия разрешения конфликтов по умолчанию.
  /// По умолчанию [ConflictStrategy.autoPreserve] — автоматическое слияние без потери данных.
  final ConflictStrategy conflictStrategy;

  /// Callback для ручного разрешения конфликтов.
  /// Используется когда [conflictStrategy] == [ConflictStrategy.manual].
  final ConflictResolver? conflictResolver;

  /// Функция слияния данных.
  /// Используется когда [conflictStrategy] == [ConflictStrategy.merge].
  /// Если не указана, используется [ConflictUtils.defaultMerge].
  final MergeFunction? mergeFunction;

  /// Максимальное количество попыток разрешения конфликта.
  final int maxConflictRetries;

  /// Задержка между попытками разрешения конфликта.
  final Duration conflictRetryDelay;

  /// Пропускать операции с неразрешёнными конфликтами.
  /// Если true, операция удаляется из outbox.
  /// Если false, операция остаётся в outbox для следующей синхронизации.
  final bool skipConflictingOps;

  /// Создать копию конфигурации с изменёнными параметрами.
  SyncConfig copyWith({
    int? pageSize,
    Duration? backoffMin,
    Duration? backoffMax,
    double? backoffMultiplier,
    int? maxPushRetries,
    Duration? fullResyncInterval,
    bool? pullOnStartup,
    bool? pushImmediately,
    Duration? reconcileInterval,
    bool? lazyReconcileOnMiss,
    ConflictStrategy? conflictStrategy,
    ConflictResolver? conflictResolver,
    MergeFunction? mergeFunction,
    int? maxConflictRetries,
    Duration? conflictRetryDelay,
    bool? skipConflictingOps,
  }) => SyncConfig(
    pageSize: pageSize ?? this.pageSize,
    backoffMin: backoffMin ?? this.backoffMin,
    backoffMax: backoffMax ?? this.backoffMax,
    backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
    maxPushRetries: maxPushRetries ?? this.maxPushRetries,
    fullResyncInterval: fullResyncInterval ?? this.fullResyncInterval,
    pullOnStartup: pullOnStartup ?? this.pullOnStartup,
    pushImmediately: pushImmediately ?? this.pushImmediately,
    reconcileInterval: reconcileInterval ?? this.reconcileInterval,
    lazyReconcileOnMiss: lazyReconcileOnMiss ?? this.lazyReconcileOnMiss,
    conflictStrategy: conflictStrategy ?? this.conflictStrategy,
    conflictResolver: conflictResolver ?? this.conflictResolver,
    mergeFunction: mergeFunction ?? this.mergeFunction,
    maxConflictRetries: maxConflictRetries ?? this.maxConflictRetries,
    conflictRetryDelay: conflictRetryDelay ?? this.conflictRetryDelay,
    skipConflictingOps: skipConflictingOps ?? this.skipConflictingOps,
  );
}

/// Конфигурация конфликтов для конкретной таблицы.
/// Позволяет переопределить стратегию для отдельных типов сущностей.
class TableConflictConfig {
  const TableConflictConfig({
    this.strategy,
    this.resolver,
    this.mergeFunction,
    this.timestampField = 'updatedAt',
  });

  /// Стратегия для этой таблицы. Если null, используется глобальная.
  final ConflictStrategy? strategy;

  /// Callback для этой таблицы. Если null, используется глобальный.
  final ConflictResolver? resolver;

  /// Функция слияния для этой таблицы.
  final MergeFunction? mergeFunction;

  /// Поле с timestamp для стратегии lastWriteWins.
  final String timestampField;
}
