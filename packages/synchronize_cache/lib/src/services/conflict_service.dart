import 'dart:async';

import 'package:drift/drift.dart';
import 'package:synchronize_cache/src/config.dart';
import 'package:synchronize_cache/src/conflict_resolution.dart';
import 'package:synchronize_cache/src/op.dart';
import 'package:synchronize_cache/src/sync_events.dart';
import 'package:synchronize_cache/src/syncable_table.dart';
import 'package:synchronize_cache/src/transport_adapter.dart';

/// Результат разрешения конфликта.
class ConflictResolutionResult {
  const ConflictResolutionResult({
    required this.resolved,
    this.resultData,
  });

  /// Конфликт разрешён.
  final bool resolved;

  /// Данные после разрешения.
  final Map<String, Object?>? resultData;
}

/// Сервис для разрешения конфликтов синхронизации.
class ConflictService<DB extends GeneratedDatabase> {
  ConflictService({
    required DB db,
    required TransportAdapter transport,
    required Map<String, SyncableTable<dynamic>> tables,
    required SyncConfig config,
    required Map<String, TableConflictConfig> tableConflictConfigs,
    required StreamController<SyncEvent> events,
  })  : _db = db,
        _transport = transport,
        _tables = tables,
        _config = config,
        _tableConflictConfigs = tableConflictConfigs,
        _events = events;

  final DB _db;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final SyncConfig _config;
  final Map<String, TableConflictConfig> _tableConflictConfigs;
  final StreamController<SyncEvent> _events;

  /// Разрешить конфликт для операции.
  Future<ConflictResolutionResult> resolve(
    Op op,
    PushConflict serverConflict,
  ) async {
    final tableConfig = _tableConflictConfigs[op.kind];
    final strategy = tableConfig?.strategy ?? _config.conflictStrategy;

    final localData = op is UpsertOp ? op.payloadJson : <String, Object?>{};
    final changedFields = op is UpsertOp ? op.changedFields : null;

    final conflict = Conflict(
      kind: op.kind,
      entityId: op.id,
      opId: op.opId,
      localData: localData,
      serverData: serverConflict.serverData,
      localTimestamp: op.localTimestamp,
      serverTimestamp: serverConflict.serverTimestamp,
      serverVersion: serverConflict.serverVersion,
      changedFields: changedFields,
    );

    _events.add(ConflictDetectedEvent(conflict: conflict, strategy: strategy));

    final resolution = await _determineResolution(conflict, strategy, tableConfig);

    return _applyResolution(op, conflict, resolution);
  }

  Future<ConflictResolution> _determineResolution(
    Conflict conflict,
    ConflictStrategy strategy,
    TableConflictConfig? tableConfig,
  ) async {
    switch (strategy) {
      case ConflictStrategy.serverWins:
        return const AcceptServer();

      case ConflictStrategy.clientWins:
        return const AcceptClient();

      case ConflictStrategy.lastWriteWins:
        if (conflict.localTimestamp.isAfter(conflict.serverTimestamp)) {
          return const AcceptClient();
        }
        return const AcceptServer();

      case ConflictStrategy.merge:
        final mergeFunc = tableConfig?.mergeFunction ??
            _config.mergeFunction ??
            ConflictUtils.defaultMerge;
        final merged = mergeFunc(conflict.localData, conflict.serverData);
        return AcceptMerged(merged);

      case ConflictStrategy.manual:
        final resolver = tableConfig?.resolver ?? _config.conflictResolver;
        if (resolver == null) {
          _events.add(ConflictUnresolvedEvent(
            conflict: conflict,
            reason: 'No conflict resolver provided for manual strategy',
          ));
          return const DeferResolution();
        }
        return resolver(conflict);

      case ConflictStrategy.autoPreserve:
        final mergeResult = ConflictUtils.preservingMerge(
          conflict.localData,
          conflict.serverData,
          changedFields: conflict.changedFields,
        );

        _events.add(DataMergedEvent(
          kind: conflict.kind,
          entityId: conflict.entityId,
          localFields: mergeResult.localFields,
          serverFields: mergeResult.serverFields,
          mergedData: mergeResult.data,
        ));

        return AcceptMerged(
          mergeResult.data,
          mergeInfo: MergeInfo(
            localFields: mergeResult.localFields,
            serverFields: mergeResult.serverFields,
          ),
        );
    }
  }

  Future<ConflictResolutionResult> _applyResolution(
    Op op,
    Conflict conflict,
    ConflictResolution resolution,
  ) async {
    switch (resolution) {
      case AcceptServer():
        await _applyServerData(conflict);
        _events.add(ConflictResolvedEvent(
          conflict: conflict,
          resolution: resolution,
          resultData: conflict.serverData,
        ));
        return ConflictResolutionResult(
          resolved: true,
          resultData: conflict.serverData,
        );

      case AcceptClient():
        final success = await _forcePushOp(op);
        if (success) {
          _events.add(ConflictResolvedEvent(
            conflict: conflict,
            resolution: resolution,
            resultData: conflict.localData,
          ));
        }
        return ConflictResolutionResult(
          resolved: success,
          resultData: success ? conflict.localData : null,
        );

      case AcceptMerged(:final mergedData):
        final success = await _pushMergedData(op, mergedData);
        if (success) {
          _events.add(ConflictResolvedEvent(
            conflict: conflict,
            resolution: resolution,
            resultData: mergedData,
          ));
        }
        return ConflictResolutionResult(
          resolved: success,
          resultData: success ? mergedData : null,
        );

      case DeferResolution():
        _events.add(ConflictUnresolvedEvent(
          conflict: conflict,
          reason: 'Resolution deferred',
        ));
        return const ConflictResolutionResult(resolved: false);

      case DiscardOperation():
        _events.add(ConflictResolvedEvent(
          conflict: conflict,
          resolution: resolution,
        ));
        return const ConflictResolutionResult(resolved: true);
    }
  }

  Future<void> _applyServerData(Conflict conflict) async {
    final tableConfig = _tables[conflict.kind];
    if (tableConfig == null) return;

    final entity = tableConfig.fromJson(conflict.serverData);
    await _db.into(tableConfig.table).insertOnConflictUpdate(
          tableConfig.getInsertable(entity),
        );
  }

  Future<bool> _forcePushOp(Op op) async {
    var retries = 0;
    while (retries < _config.maxConflictRetries) {
      final result = await _transport.forcePush(op);

      if (result is PushSuccess) {
        return true;
      }

      if (result is PushConflict) {
        retries++;
        if (retries < _config.maxConflictRetries) {
          await Future<void>.delayed(_config.conflictRetryDelay);
        }
        continue;
      }

      return false;
    }
    return false;
  }

  Future<bool> _pushMergedData(Op op, Map<String, Object?> mergedData) async {
    if (op is! UpsertOp) return false;

    final mergedOp = UpsertOp(
      opId: op.opId,
      kind: op.kind,
      id: op.id,
      localTimestamp: DateTime.now().toUtc(),
      payloadJson: mergedData,
    );

    var retries = 0;
    while (retries < _config.maxConflictRetries) {
      final result = await _transport.forcePush(mergedOp);

      if (result is PushSuccess) {
        final tableConfig = _tables[op.kind];
        if (tableConfig != null) {
          final entity = tableConfig.fromJson(mergedData);
          await _db.into(tableConfig.table).insertOnConflictUpdate(
                tableConfig.getInsertable(entity),
              );
        }
        return true;
      }

      if (result is PushConflict) {
        retries++;
        if (retries < _config.maxConflictRetries) {
          await Future<void>.delayed(_config.conflictRetryDelay);
        }
        continue;
      }

      return false;
    }
    return false;
  }
}

