import 'dart:io';

import 'package:example/database.dart';
import 'package:example/models/daily_feeling.dart';
import 'package:example/models/daily_feeling.drift.dart';
import 'package:example/models/health_record.dart';
import 'package:example/models/health_record.drift.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';

Future<void> main() async {
  // Open the database
  final db = await AppDatabase.open(filename: 'example.db');

  // Create REST transport
  final transport = RestTransport(
    base: Uri.parse('https://api.example.com'),
    token: () async => 'Bearer your-token-here',
  );

  // Register syncable tables
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

  // Subscribe to sync events
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
      case FullResyncStarted(reason: final r):
        stdout.writeln('Full resync started: $r');
    }
  });

  // Local operations demo
  stdout.writeln('=== Local operations demo ===');

  // Insert a record
  final feeling = DailyFeeling(
    id: 'test-feeling-1',
    updatedAt: DateTime.now().toUtc(),
    date: DateTime.now().toUtc(),
    feeling: 'good',
    healthRecordId: 1,
  );

  await db.into(db.dailyFeelings).insert(feeling.toInsertable());
  stdout.writeln('Record added: ${feeling.id}');

  // Add operation to outbox for sync
  await db.enqueue(UpsertOp(
    opId: 'op-${DateTime.now().millisecondsSinceEpoch}',
    kind: 'daily_feeling',
    id: feeling.id,
    localTimestamp: DateTime.now().toUtc(),
    payloadJson: feeling.toJson(),
  ));
  stdout.writeln('Operation added to outbox');

  // Read all records
  final feelings = await db.select(db.dailyFeelings).get();
  stdout.writeln('Total records: ${feelings.length}');

  // Check outbox
  final ops = await db.takeOutbox();
  stdout.writeln('Operations in outbox: ${ops.length}');

  // Clear outbox
  await db.ackOutbox(ops.map((o) => o.opId));
  stdout.writeln('Outbox cleared');

  // Run sync (commented out — no real server)
  // stdout.writeln('=== Start sync ===');
  // try {
  //   await engine.sync();
  // } catch (e) {
  //   stdout.writeln('Sync failed: $e');
  // }

  // Cleanup
  await subscription.cancel();
  engine.dispose();
  await db.close();

  stdout.writeln('Done!');
}
