import 'package:synchronize_cache/src/exceptions.dart';
import 'package:synchronize_cache/src/op.dart';
import 'package:synchronize_cache/src/sync_database.dart';

/// Сервис для работы с очередью исходящих операций (outbox).
class OutboxService {
  OutboxService(this._db);

  final SyncDatabaseMixin _db;

  /// Добавить операцию в очередь отправки.
  Future<void> enqueue(Op op) async {
    try {
      await _db.enqueue(op);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Получить операции из очереди для отправки.
  Future<List<Op>> take({int limit = 100}) async {
    try {
      return await _db.takeOutbox(limit: limit);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Подтвердить отправку операций (удалить из очереди).
  Future<void> ack(Iterable<String> opIds) async {
    if (opIds.isEmpty) return;
    try {
      await _db.ackOutbox(opIds);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Очистить операции старше threshold.
  Future<int> purgeOlderThan(DateTime threshold) async {
    try {
      return await _db.purgeOutboxOlderThan(threshold);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Проверить есть ли операции в очереди.
  Future<bool> hasOperations() async {
    final ops = await take(limit: 1);
    return ops.isNotEmpty;
  }
}

