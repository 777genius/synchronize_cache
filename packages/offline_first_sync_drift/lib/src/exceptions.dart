// Кастомные исключения для синхронизации.

/// Базовое исключение синхронизации.
sealed class SyncException implements Exception {
  const SyncException(this.message, [this.cause, this.stackTrace]);

  /// Описание ошибки.
  final String message;

  /// Причина ошибки (оригинальное исключение).
  final Object? cause;

  /// Stack trace оригинальной ошибки.
  final StackTrace? stackTrace;

  @override
  String toString() =>
      cause == null
          ? '$runtimeType: $message'
          : '$runtimeType: $message\nCaused by: $cause';
}

/// Ошибка сети (недоступность сервера, таймаут).
class NetworkException extends SyncException {
  const NetworkException(super.message, [super.cause, super.stackTrace]);

  /// Создать из сетевой ошибки.
  factory NetworkException.fromError(Object error, [StackTrace? stackTrace]) =>
      NetworkException('Network request failed: $error', error, stackTrace);
}

/// Ошибка транспорта (неожиданный ответ сервера).
class TransportException extends SyncException {
  const TransportException(
    String message, {
    this.statusCode,
    this.responseBody,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(message, cause, stackTrace);

  /// HTTP статус код.
  final int? statusCode;

  /// Тело ответа.
  final String? responseBody;

  /// Создать для неуспешного HTTP ответа.
  factory TransportException.httpError(int statusCode, [String? body]) =>
      TransportException(
        'HTTP error $statusCode',
        statusCode: statusCode,
        responseBody: body,
      );

  @override
  String toString() =>
      statusCode == null
          ? 'TransportException: $message'
          : 'TransportException: $message (status: $statusCode)';
}

/// Ошибка базы данных.
class DatabaseException extends SyncException {
  const DatabaseException(super.message, [super.cause, super.stackTrace]);

  /// Создать из ошибки БД.
  factory DatabaseException.fromError(Object error, [StackTrace? stackTrace]) =>
      DatabaseException('Database operation failed: $error', error, stackTrace);
}

/// Неразрешённый конфликт данных.
class ConflictException extends SyncException {
  const ConflictException(
    String message, {
    required this.kind,
    required this.entityId,
    this.localData,
    this.serverData,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(message, cause, stackTrace);

  /// Тип сущности.
  final String kind;

  /// ID сущности.
  final String entityId;

  /// Локальные данные.
  final Map<String, Object?>? localData;

  /// Серверные данные.
  final Map<String, Object?>? serverData;

  @override
  String toString() => 'ConflictException: $message ($kind/$entityId)';
}

/// Ошибка синхронизации (общая).
class SyncOperationException extends SyncException {
  const SyncOperationException(
    String message, {
    this.phase,
    this.opId,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(message, cause, stackTrace);

  /// Фаза синхронизации (push/pull).
  final String? phase;

  /// ID операции.
  final String? opId;

  @override
  String toString() =>
      'SyncOperationException: $message'
      '${phase == null ? '' : ' (phase: $phase)'}'
      '${opId == null ? '' : ' (opId: $opId)'}';
}

/// Превышено максимальное количество попыток.
class MaxRetriesExceededException extends SyncException {
  const MaxRetriesExceededException(
    String message, {
    required this.attempts,
    required this.maxRetries,
    Object? cause,
    StackTrace? stackTrace,
  }) : super(message, cause, stackTrace);

  /// Количество выполненных попыток.
  final int attempts;

  /// Максимальное количество попыток.
  final int maxRetries;

  @override
  String toString() =>
      'MaxRetriesExceededException: $message (attempts: $attempts/$maxRetries)';
}

/// Ошибка парсинга данных.
class ParseException extends SyncException {
  const ParseException(super.message, [super.cause, super.stackTrace]);

  /// Создать из ошибки парсинга.
  factory ParseException.fromError(Object error, [StackTrace? stackTrace]) =>
      ParseException('Failed to parse data: $error', error, stackTrace);
}
