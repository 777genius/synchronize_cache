import 'dart:async';

import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/src/config.dart';
import 'package:offline_first_sync_drift/src/constants.dart';
import 'package:offline_first_sync_drift/src/cursor.dart';
import 'package:offline_first_sync_drift/src/exceptions.dart';
import 'package:offline_first_sync_drift/src/services/cursor_service.dart';
import 'package:offline_first_sync_drift/src/sync_events.dart';
import 'package:offline_first_sync_drift/src/syncable_table.dart';
import 'package:offline_first_sync_drift/src/transport_adapter.dart';

/// Сервис для получения изменений с сервера.
class PullService<DB extends GeneratedDatabase> {
  PullService({
    required DB db,
    required TransportAdapter transport,
    required Map<String, SyncableTable<dynamic>> tables,
    required CursorService cursorService,
    required SyncConfig config,
    required StreamController<SyncEvent> events,
  }) : _db = db,
       _transport = transport,
       _tables = tables,
       _cursorService = cursorService,
       _config = config,
       _events = events;

  final DB _db;
  final TransportAdapter _transport;
  final Map<String, SyncableTable<dynamic>> _tables;
  final CursorService _cursorService;
  final SyncConfig _config;
  final StreamController<SyncEvent> _events;

  /// Получить изменения для указанных типов.
  Future<int> pullKinds(Set<String> kinds) async {
    var total = 0;
    for (final kind in kinds) {
      if (_tables.containsKey(kind)) {
        total += await pullKind(kind);
      }
    }
    return total;
  }

  /// Получить изменения для типа.
  Future<int> pullKind(String kind) async {
    final tableConfig = _tables[kind];
    if (tableConfig == null) return 0;

    int done = 0;
    String? token;

    try {
      final cursor = await _cursorService.get(kind);
      var since =
          cursor?.ts ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      var afterId = cursor?.lastId;

      while (true) {
        final page = await _transport.pull(
          kind: kind,
          updatedSince: since,
          pageSize: _config.pageSize,
          pageToken: token,
          afterId: afterId,
          includeDeleted: true,
        );

        if (page.items.isEmpty) break;

        int upserts = 0;
        int deletes = 0;

        await _db.batch((batch) {
          for (final json in page.items) {
            final entity = tableConfig.fromJson(json);
            final deletedAt =
                json[SyncFields.deletedAt] ?? json[SyncFields.deletedAtSnake];

            if (deletedAt != null) {
              deletes++;
            } else {
              upserts++;
            }

            batch.insert(
              tableConfig.table,
              tableConfig.getInsertable(entity),
              mode: InsertMode.insertOrReplace,
            );
          }
        });

        _events.add(CacheUpdateEvent(kind, upserts: upserts, deletes: deletes));

        final last = page.items.last;
        final ts =
            last[SyncFields.updatedAt] ?? last[SyncFields.updatedAtSnake];
        final id =
            (last[SyncFields.id] ??
                    last[SyncFields.idUpper] ??
                    last[SyncFields.uuid])
                .toString();

        if (ts == null) {
          throw ParseException(
            'Transport returned item without updatedAt for kind=$kind',
          );
        }

        since = ts is DateTime ? ts : DateTime.parse(ts.toString()).toUtc();
        afterId = id;
        await _cursorService.set(kind, Cursor(ts: since, lastId: afterId));

        done += page.items.length;
        _events.add(SyncProgress(SyncPhase.pull, done, done));

        token = page.nextPageToken;
        if (token == null && page.items.length < _config.pageSize) {
          break;
        }
      }
    } on SyncException {
      rethrow;
    } catch (e, st) {
      throw SyncOperationException(
        'Pull failed for kind=$kind',
        phase: 'pull',
        cause: e,
        stackTrace: st,
      );
    }

    return done;
  }
}
