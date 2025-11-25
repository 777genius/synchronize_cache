import 'dart:async';
import 'dart:math' as math;

import 'package:synchronize_cache/src/config.dart';
import 'package:synchronize_cache/src/conflict_resolution.dart';
import 'package:synchronize_cache/src/constants.dart';
import 'package:synchronize_cache/src/exceptions.dart';
import 'package:synchronize_cache/src/op.dart';
import 'package:synchronize_cache/src/services/conflict_service.dart';
import 'package:synchronize_cache/src/services/outbox_service.dart';
import 'package:synchronize_cache/src/sync_events.dart';
import 'package:synchronize_cache/src/transport_adapter.dart';

/// Статистика push операций.
class PushStats {
  const PushStats({
    this.pushed = 0,
    this.conflicts = 0,
    this.conflictsResolved = 0,
    this.errors = 0,
  });

  final int pushed;
  final int conflicts;
  final int conflictsResolved;
  final int errors;

  PushStats copyWith({
    int? pushed,
    int? conflicts,
    int? conflictsResolved,
    int? errors,
  }) {
    return PushStats(
      pushed: pushed ?? this.pushed,
      conflicts: conflicts ?? this.conflicts,
      conflictsResolved: conflictsResolved ?? this.conflictsResolved,
      errors: errors ?? this.errors,
    );
  }
}

/// Сервис для отправки локальных изменений на сервер.
class PushService {
  PushService({
    required OutboxService outbox,
    required TransportAdapter transport,
    required ConflictService<dynamic> conflictService,
    required SyncConfig config,
    required StreamController<SyncEvent> events,
  })  : _outbox = outbox,
        _transport = transport,
        _conflictService = conflictService,
        _config = config,
        _events = events;

  final OutboxService _outbox;
  final TransportAdapter _transport;
  final ConflictService<dynamic> _conflictService;
  final SyncConfig _config;
  final StreamController<SyncEvent> _events;

  /// Отправить все операции из outbox.
  Future<PushStats> pushAll() async {
    var pushed = 0;
    var conflicts = 0;
    var conflictsResolved = 0;
    var errors = 0;

    try {
      while (true) {
        final ops = await _outbox.take(limit: _config.pageSize);
        if (ops.isEmpty) break;

        final result = await _pushBatch(ops);

        final successOpIds = <String>[];
        final conflictOps = <Op, PushConflict>{};

        for (final opResult in result.results) {
          final op = ops.firstWhere((o) => o.opId == opResult.opId);

          switch (opResult.result) {
            case PushSuccess():
              successOpIds.add(opResult.opId);
              pushed++;
              _events.add(OperationPushedEvent(
                opId: op.opId,
                kind: op.kind,
                entityId: op.id,
                operationType: op is UpsertOp ? OpType.upsert : OpType.delete,
              ));

            case PushConflict conflict:
              conflicts++;
              conflictOps[op] = conflict;

            case PushNotFound():
              successOpIds.add(opResult.opId);

            case PushError error:
              errors++;
              _events.add(OperationFailedEvent(
                opId: op.opId,
                kind: op.kind,
                entityId: op.id,
                error: error.error,
                willRetry: !_config.skipConflictingOps,
              ));
          }
        }

        await _outbox.ack(successOpIds);

        for (final entry in conflictOps.entries) {
          final result = await _conflictService.resolve(entry.key, entry.value);
          if (result.resolved) {
            conflictsResolved++;
            successOpIds.add(entry.key.opId);
          } else if (_config.skipConflictingOps) {
            successOpIds.add(entry.key.opId);
          }
        }

        if (conflictOps.isNotEmpty) {
          await _outbox.ack(
            conflictOps.keys
                .where((op) =>
                    successOpIds.contains(op.opId) ||
                    _config.skipConflictingOps)
                .map((op) => op.opId),
          );
        }
      }
    } on SyncException {
      rethrow;
    } catch (e, st) {
      throw SyncOperationException(
        'Push failed',
        phase: 'push',
        cause: e,
        stackTrace: st,
      );
    }

    return PushStats(
      pushed: pushed,
      conflicts: conflicts,
      conflictsResolved: conflictsResolved,
      errors: errors,
    );
  }

  Future<BatchPushResult> _pushBatch(List<Op> ops) async {
    int attempt = 0;
    while (true) {
      try {
        attempt++;
        return await _transport.push(ops);
      } catch (e, st) {
        if (attempt >= _config.maxPushRetries) {
          throw MaxRetriesExceededException(
            'Push failed after $attempt attempts',
            attempts: attempt,
            maxRetries: _config.maxPushRetries,
            cause: e,
            stackTrace: st,
          );
        }
        final backoff =
            _config.backoffMin * math.pow(_config.backoffMultiplier, attempt - 1);
        final delay =
            backoff > _config.backoffMax ? _config.backoffMax : backoff;

        await Future<void>.delayed(delay);
      }
    }
  }
}

