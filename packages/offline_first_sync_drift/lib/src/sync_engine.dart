import 'dart:async';

import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/services/conflict_service.dart';
import 'package:offline_first_sync_drift/src/services/cursor_service.dart';
import 'package:offline_first_sync_drift/src/services/outbox_service.dart';
import 'package:offline_first_sync_drift/src/services/pull_service.dart';
import 'package:offline_first_sync_drift/src/services/push_service.dart';
import 'package:offline_first_sync_drift/src/sync_database.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// Движок синхронизации: push → pull с пагинацией и conflict resolution.
class SyncEngine<DB extends GeneratedDatabase> {
  SyncEngine({
    required DB db,
    required TransportAdapter transport,
    required List<SyncableTable<dynamic>> tables,
    SyncConfig config = const SyncConfig(),
    Map<String, TableConflictConfig>? tableConflictConfigs,
  }) : _db = db,
       _transport = transport,
       _tables = {for (final t in tables) t.kind: t},
       _config = config,
       _tableConflictConfigs = tableConflictConfigs ?? {} {
    if (db is! SyncDatabaseMixin) {
      throw ArgumentError(
        'Database must implement SyncDatabaseMixin. '
        'Add "with SyncDatabaseMixin" to your database class.',
      );
    }

    _initServices();
  }

  final DB _db;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final SyncConfig _config;
  final Map<String, TableConflictConfig> _tableConflictConfigs;

  final _events = StreamController<SyncEvent>.broadcast();

  late final OutboxService _outboxService;
  late final CursorService _cursorService;
  late final ConflictService<DB> _conflictService;
  late final PushService _pushService;
  late final PullService<DB> _pullService;

  SyncDatabaseMixin get _syncDb => _db as SyncDatabaseMixin;

  void _initServices() {
    _outboxService = OutboxService(_syncDb);
    _cursorService = CursorService(_syncDb);
    _conflictService = ConflictService<DB>(
      db: _db,
      transport: _transport,
      tables: _tables,
      config: _config,
      tableConflictConfigs: _tableConflictConfigs,
      events: _events,
    );
    _pushService = PushService(
      outbox: _outboxService,
      transport: _transport,
      conflictService: _conflictService,
      config: _config,
      events: _events,
    );
    _pullService = PullService<DB>(
      db: _db,
      transport: _transport,
      tables: _tables,
      cursorService: _cursorService,
      config: _config,
      events: _events,
    );
  }

  /// Поток событий синхронизации.
  Stream<SyncEvent> get events => _events.stream;

  /// Сервис для работы с outbox.
  OutboxService get outbox => _outboxService;

  /// Сервис для работы с курсорами.
  CursorService get cursors => _cursorService;

  Timer? _autoTimer;
  bool _running = false;

  /// Запустить автоматическую синхронизацию.
  void startAuto({Duration interval = const Duration(minutes: 5)}) {
    stopAuto();
    _autoTimer = Timer.periodic(interval, (_) => sync());
  }

  /// Остановить автоматическую синхронизацию.
  void stopAuto() {
    _autoTimer?.cancel();
    _autoTimer = null;
  }

  /// Выполнить синхронизацию.
  /// [kinds] — если указано, синхронизировать только эти типы.
  Future<SyncStats> sync({Set<String>? kinds}) async {
    if (_running) return const SyncStats();
    _running = true;
    final started = DateTime.now();

    var stats = const SyncStats();

    try {
      final lastFullResync = await _cursorService.getLastFullResync();
      final needsFullResync =
          lastFullResync == null ||
          started.difference(lastFullResync) >= _config.fullResyncInterval;

      if (needsFullResync) {
        return _doFullResync(
          reason: FullResyncReason.scheduled,
          clearData: false,
          started: started,
        );
      }

      _events.add(SyncStarted(SyncPhase.push));
      final pushStats = await _pushService.pushAll();
      stats = stats.copyWith(
        pushed: pushStats.pushed,
        conflicts: pushStats.conflicts,
        conflictsResolved: pushStats.conflictsResolved,
        errors: pushStats.errors,
      );
      _events.add(SyncStarted(SyncPhase.pull));
      final targetKinds = kinds ?? _tables.keys.toSet();
      final pulled = await _pullService.pullKinds(targetKinds);
      stats = stats.copyWith(pulled: pulled);

      _events.add(
        SyncCompleted(
          DateTime.now().difference(started),
          DateTime.now(),
          stats: stats,
        ),
      );

      return stats;
    } on SyncException catch (e, st) {
      _events.add(SyncErrorEvent(SyncPhase.pull, e, st));
      rethrow;
    } catch (e, st) {
      final exception = SyncOperationException(
        'Sync failed',
        phase: 'sync',
        cause: e,
        stackTrace: st,
      );
      _events.add(SyncErrorEvent(SyncPhase.pull, exception, st));
      throw exception;
    } finally {
      _running = false;
    }
  }

  /// Выполнить полную ресинхронизацию.
  ///
  /// [clearData] — очистить локальные данные перед pull.
  /// По умолчанию false — данные остаются, курсоры сбрасываются,
  /// затем pull накатывает данные поверх (insertOrReplace).
  Future<SyncStats> fullResync({bool clearData = false}) async {
    if (_running) return const SyncStats();
    _running = true;
    final started = DateTime.now();

    try {
      return _doFullResync(
        reason: FullResyncReason.manual,
        clearData: clearData,
        started: started,
      );
    } finally {
      _running = false;
    }
  }

  Future<SyncStats> _doFullResync({
    required FullResyncReason reason,
    required bool clearData,
    required DateTime started,
  }) async {
    var stats = const SyncStats();

    try {
      _events
        ..add(FullResyncStarted(reason))
        ..add(SyncStarted(SyncPhase.push));
      final pushStats = await _pushService.pushAll();
      stats = stats.copyWith(
        pushed: pushStats.pushed,
        conflicts: pushStats.conflicts,
        conflictsResolved: pushStats.conflictsResolved,
        errors: pushStats.errors,
      );

      await _cursorService.resetAll(_tables.keys.toSet());

      if (clearData) {
        final tableNames =
            _tables.values.map((t) => t.table.actualTableName).toList();
        await _syncDb.clearSyncableTables(tableNames);
      }

      _events.add(SyncStarted(SyncPhase.pull));
      final pulled = await _pullService.pullKinds(_tables.keys.toSet());
      stats = stats.copyWith(pulled: pulled);

      await _cursorService.setLastFullResync(DateTime.now());

      _events.add(
        SyncCompleted(
          DateTime.now().difference(started),
          DateTime.now(),
          stats: stats,
        ),
      );

      return stats;
    } on SyncException catch (e, st) {
      _events.add(SyncErrorEvent(SyncPhase.pull, e, st));
      rethrow;
    } catch (e, st) {
      final exception = SyncOperationException(
        'Full resync failed',
        phase: 'fullResync',
        cause: e,
        stackTrace: st,
      );
      _events.add(SyncErrorEvent(SyncPhase.pull, exception, st));
      throw exception;
    }
  }

  /// Освободить ресурсы.
  void dispose() {
    stopAuto();
    _events.close();
  }
}
