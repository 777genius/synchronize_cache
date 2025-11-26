import 'dart:async';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

import 'parallel_push_test.drift.dart';

class TestEntity {
  TestEntity({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.name,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final String name;

  factory TestEntity.fromJson(Map<String, dynamic> json) => TestEntity(
        id: json['id'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        name: json['name'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'name': name,
      };
}

@UseRowClass(TestEntity, generateInsertable: true)
class TestEntities extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  include: {'package:synchronize_cache/src/sync_tables.drift'},
  tables: [TestEntities],
)
class TestDatabase extends $TestDatabase with SyncDatabaseMixin {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

void main() {
  late TestServer server;
  late TestDatabase db;
  var dbClosed = false;

  Future<void> closeDb() async {
    if (dbClosed) return;
    dbClosed = true;
    await db.close();
  }

  setUp(() async {
    server = TestServer();
    await server.start();
    // Disable conflict checks to simplify push logic for this perf test
    server.conflictCheckEnabled = false;

    db = TestDatabase();
    dbClosed = false;
  });

  tearDown(() async {
    await closeDb();
    await server.stop();
  });

  SyncEngine createEngine(int concurrency) {
    final transport = RestTransport(
      base: server.baseUrl,
      token: () async => 'Bearer test-token',
      pushConcurrency: concurrency,
    );

    return SyncEngine(
      db: db,
      transport: transport,
      tables: [
        SyncableTable<TestEntity>(
          kind: 'test_entity',
          table: db.testEntities,
          fromJson: TestEntity.fromJson,
          toJson: (item) => item.toJson(),
          toInsertable: (item) => item.toInsertable(),
        ),
      ],
      config: const SyncConfig(
        pushImmediately: false, // We want to accumulate ops first
      ),
    );
  }

  test('parallel push is faster than sequential push with latency', () async {
    // Setup: Create 10 operations
    const opCount = 10;
    const requestDelay = Duration(milliseconds: 50);

    // Create ops in DB
    for (var i = 0; i < opCount; i++) {
      await db.enqueue(UpsertOp(
        opId: 'op-$i',
        kind: 'test_entity',
        id: 'entity-$i',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-$i', 'name': 'Item $i'},
      ));
    }

    // --- Run 1: Sequential (concurrency = 1) ---
    server.delayNextRequests(requestDelay, count: opCount);
    
    final engine1 = createEngine(1);
    final stopwatch1 = Stopwatch()..start();
    await engine1.sync(); // Will trigger push
    stopwatch1.stop();
    engine1.dispose();

    // Verify sequential timing: roughly opCount * delay
    // 10 * 50ms = 500ms minimum
    developer.log(
      'Sequential time: ${stopwatch1.elapsedMilliseconds}ms',
      name: 'ParallelPushTest',
    );
    expect(stopwatch1.elapsedMilliseconds, greaterThanOrEqualTo(opCount * requestDelay.inMilliseconds));

    // Reset server stats and DB outbox for next run
    server
      ..clear()
      ..conflictCheckEnabled = false;
    
    // Re-enqueue ops since they were acked
    for (var i = 0; i < opCount; i++) {
      await db.enqueue(UpsertOp(
        opId: 'op-$i',
        kind: 'test_entity',
        id: 'entity-$i',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-$i', 'name': 'Item $i'},
      ));
    }

    // --- Run 2: Parallel (concurrency = 5) ---
    // Should take roughly (opCount / 5) * delay
    // 2 batches * 50ms = 100ms minimum
    server.delayNextRequests(requestDelay, count: opCount);

    final engine2 = createEngine(5);
    final stopwatch2 = Stopwatch()..start();
    await engine2.sync();
    stopwatch2.stop();
    engine2.dispose();

    developer.log(
      'Parallel time: ${stopwatch2.elapsedMilliseconds}ms',
      name: 'ParallelPushTest',
    );
    
    // Check that parallel is significantly faster
    // Ideally it should be close to 1/5th of the time, but let's be conservative and say it should be at least 2x faster
    expect(stopwatch2.elapsedMilliseconds, lessThan(stopwatch1.elapsedMilliseconds * 0.6));
    
    // Verify all requests reached server
    expect(server.requestCounts['PUT'], opCount);
  });
}

