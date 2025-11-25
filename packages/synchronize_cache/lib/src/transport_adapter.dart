import 'package:synchronize_cache/src/conflict_resolution.dart';
import 'package:synchronize_cache/src/op.dart';

/// Результат pull: список json-элементов и указатель следующей страницы.
class PullPage {
  PullPage({required this.items, this.nextPageToken});

  /// Элементы страницы в формате JSON.
  final List<Map<String, Object?>> items;

  /// Токен следующей страницы, null если это последняя страница.
  final String? nextPageToken;
}

/// Результат push для одной операции.
class OpPushResult {
  const OpPushResult({
    required this.opId,
    required this.result,
  });

  /// ID операции.
  final String opId;

  /// Результат push.
  final PushResult result;

  bool get isSuccess => result is PushSuccess;
  bool get isConflict => result is PushConflict;
  bool get isNotFound => result is PushNotFound;
  bool get isError => result is PushError;
}

/// Результат push для пакета операций.
class BatchPushResult {
  const BatchPushResult({
    required this.results,
  });

  final List<OpPushResult> results;

  /// Все операции успешны.
  bool get allSuccess => results.every((r) => r.isSuccess);

  /// Есть конфликты.
  bool get hasConflicts => results.any((r) => r.isConflict);

  /// Есть ошибки.
  bool get hasErrors => results.any((r) => r.isError);

  /// Получить конфликтные операции.
  Iterable<OpPushResult> get conflicts => results.where((r) => r.isConflict);

  /// Получить успешные операции.
  Iterable<OpPushResult> get successes => results.where((r) => r.isSuccess);

  /// Получить операции с ошибками.
  Iterable<OpPushResult> get errors => results.where((r) => r.isError);
}

/// Интерфейс транспорта для сети.
abstract interface class TransportAdapter {
  /// Получить страницу данных с сервера.
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  });

  /// Отправить операции на сервер.
  /// Возвращает результат для каждой операции включая конфликты.
  Future<BatchPushResult> push(List<Op> ops);

  /// Принудительно отправить операцию (игнорировать конфликт версий).
  /// Используется для стратегии clientWins.
  Future<PushResult> forcePush(Op op);

  /// Получить текущую версию сущности с сервера.
  Future<FetchResult> fetch({
    required String kind,
    required String id,
  });

  /// Проверить доступность сервера.
  Future<bool> health();
}

/// Результат получения одной сущности.
sealed class FetchResult {
  const FetchResult();
}

/// Сущность найдена.
class FetchSuccess extends FetchResult {
  const FetchSuccess({
    required this.data,
    this.version,
  });

  final Map<String, Object?> data;
  final String? version;
}

/// Сущность не найдена.
class FetchNotFound extends FetchResult {
  const FetchNotFound();
}

/// Ошибка получения.
class FetchError extends FetchResult {
  const FetchError(this.error, [this.stackTrace]);

  final Object error;
  final StackTrace? stackTrace;
}
