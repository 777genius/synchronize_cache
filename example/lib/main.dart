import 'dart:io';

import 'package:example/database.dart';
import 'package:example/models/daily_feeling.dart';
import 'package:example/models/health_record.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';

Future<void> main() async {
  // Открываем базу данных
  final db = await AppDatabase.open(filename: 'example.db');

  // Создаём REST транспорт
  final transport = RestTransport(
    base: Uri.parse('https://api.example.com'),
    token: () async => 'Bearer your-token-here',
  );

  // Регистрируем синхронизируемые таблицы
  final engine = SyncEngine(
    db: db,
    transport: transport,
    tables: [
      SyncableTable<HealthRecord>(
        kind: 'health_record',
        table: db.healthRecords,
        fromJson: HealthRecord.fromJson,
        toJson: (hr) => hr.toJson(),
        toInsertable: (hr) => hr.toInsertable(),
      ),
      SyncableTable<DailyFeeling>(
        kind: 'daily_feeling',
        table: db.dailyFeelings,
        fromJson: DailyFeeling.fromJson,
        toJson: (df) => df.toJson(),
        toInsertable: (df) => df.toInsertable(),
      ),
    ],
  );

  // Подписываемся на события синхронизации
  final subscription = engine.events.listen((event) {
    switch (event) {
      case SyncStarted(phase: final phase):
        stdout.writeln('Sync started: $phase');
      case SyncProgress(phase: final phase, done: final done, total: final total):
        stdout.writeln('Sync progress: $phase - $done/$total');
      case SyncCompleted(took: final took):
        stdout.writeln('Sync completed in ${took.inMilliseconds}ms');
      case SyncErrorEvent(phase: final phase, error: final error):
        stdout.writeln('Sync error in $phase: $error');
      case CacheUpdateEvent(kind: final kind, upserts: final upserts, deletes: final deletes):
        stdout.writeln('Cache updated: $kind - $upserts upserts, $deletes deletes');
      case ConflictDetectedEvent(conflict: final c, strategy: final s):
        stdout.writeln('Conflict detected: ${c.kind}/${c.entityId}, strategy: $s');
      case ConflictResolvedEvent(conflict: final c, resolution: final r):
        stdout.writeln('Conflict resolved: ${c.kind}/${c.entityId}, resolution: $r');
      case ConflictUnresolvedEvent(conflict: final c, reason: final r):
        stdout.writeln('Conflict unresolved: ${c.kind}/${c.entityId}, reason: $r');
      case DataMergedEvent(kind: final k, entityId: final id, localFields: final lf, serverFields: final sf):
        stdout.writeln('Data merged: $k/$id - local: ${lf.length}, server: ${sf.length}');
      case OperationPushedEvent(kind: final k, entityId: final id):
        stdout.writeln('Operation pushed: $k/$id');
      case OperationFailedEvent(kind: final k, entityId: final id, error: final e):
        stdout.writeln('Operation failed: $k/$id - $e');
      // ignore_for_file: deprecated_member_use
      case ConflictEvent():
        stdout.writeln('Conflict detected (deprecated)');
    }
  });

  // Демонстрация локальных операций
  stdout.writeln('=== Демонстрация локальных операций ===');

  // Добавляем запись
  final feeling = DailyFeeling(
    id: 'test-feeling-1',
    updatedAt: DateTime.now().toUtc(),
    date: DateTime.now().toUtc(),
    feeling: 'good',
    healthRecordId: 1,
  );

  await db.into(db.dailyFeelings).insert(feeling.toInsertable());
  stdout.writeln('Добавлена запись: ${feeling.id}');

  // Добавляем операцию в outbox для синхронизации
  await db.enqueue(UpsertOp(
    opId: 'op-${DateTime.now().millisecondsSinceEpoch}',
    kind: 'daily_feeling',
    id: feeling.id,
    localTimestamp: DateTime.now().toUtc(),
    payloadJson: feeling.toJson(),
  ));
  stdout.writeln('Операция добавлена в outbox');

  // Читаем все записи
  final feelings = await db.select(db.dailyFeelings).get();
  stdout.writeln('Всего записей: ${feelings.length}');

  // Проверяем outbox
  final ops = await db.takeOutbox();
  stdout.writeln('Операций в outbox: ${ops.length}');

  // Очищаем outbox
  await db.ackOutbox(ops.map((o) => o.opId));
  stdout.writeln('Outbox очищен');

  // Запускаем синхронизацию (закомментировано - нет реального сервера)
  // stdout.writeln('=== Запуск синхронизации ===');
  // try {
  //   await engine.sync();
  // } catch (e) {
  //   stdout.writeln('Sync failed: $e');
  // }

  // Очистка
  await subscription.cancel();
  engine.dispose();
  await db.close();

  stdout.writeln('Done!');
}
