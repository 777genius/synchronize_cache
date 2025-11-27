import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';
import 'package:test/test.dart';

import 'helpers/test_server.dart';

part 'full_resync_e2e_test.g.dart';

class TestEntity {
  TestEntity({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.name,
    this.mood,
    this.energy,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final String name;
  final int? mood;
  final int? energy;

  factory TestEntity.fromJson(Map<String, dynamic> json) => TestEntity(
        id: json['id'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        name: json['name'] as String? ?? '',
        mood: json['mood'] as int?,
        energy: json['energy'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'name': name,
        'mood': mood,
        'energy': energy,
      };
}

@UseRowClass(TestEntity, generateInsertable: true)
class TestEntities extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get mood => integer().nullable()();
  IntColumn get energy => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  include: {'package:synchronize_cache/src/sync_tables.drift'},
  tables: [TestEntities],
)
class TestDatabase extends _$TestDatabase with SyncDatabaseMixin {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

void main() {
  late TestServer server;
  late TestDatabase db;
  late RestTransport transport;

  setUp(() async {
    server = TestServer();
    await server.start();
    server.clear();

    db = TestDatabase();

    transport = RestTransport(
      base: server.baseUrl,
      token: () async => 'Bearer test-token',
      backoffMin: const Duration(milliseconds: 10),
      backoffMax: const Duration(milliseconds: 100),
      maxRetries: 3,
    );
  });

  tearDown(() async {
    await db.close();
    await server.stop();
  });

  SyncEngine createEngine({
    SyncConfig? config,
  }) =>
      SyncEngine(
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
        config: config ?? const SyncConfig(),
      );

  group('Full Resync E2E', () {
    test('fullResync pulls all data from server', () async {
      server
        ..seed('test_entity', {
          'id': 'entity-1',
          'name': 'Server Entity 1',
          'mood': 5,
        })
        ..seed('test_entity', {
          'id': 'entity-2',
          'name': 'Server Entity 2',
          'energy': 10,
        });

      final engine = createEngine();

      await engine.fullResync();

      final items = await db.select(db.testEntities).get();
      expect(items.length, 2);

      final entity1 = items.firstWhere((e) => e.id == 'entity-1');
      expect(entity1.name, 'Server Entity 1');
      expect(entity1.mood, 5);

      final entity2 = items.firstWhere((e) => e.id == 'entity-2');
      expect(entity2.name, 'Server Entity 2');
      expect(entity2.energy, 10);

      engine.dispose();
    });

    test('fullResync pushes local changes before pulling', () async {
      server.seed('test_entity', {
        'id': 'existing-entity',
        'name': 'Original Name',
      });

      final engine = createEngine();

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'new-entity',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'new-entity',
          'name': 'Client Created Entity',
          'mood': 7,
        },
      ));

      await engine.fullResync();

      final serverEntity = server.get('test_entity', 'new-entity');
      expect(serverEntity != null, isTrue);
      expect(serverEntity!['name'], 'Client Created Entity');

      final localItems = await db.select(db.testEntities).get();
      expect(localItems.length, 2);

      engine.dispose();
    });

    test('fullResync resets cursors and refetches all data', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Initial',
        'updated_at': baseTime.toIso8601String(),
      });

      final engine = createEngine();

      await engine.sync();

      var cursor = await db.getCursor('test_entity');
      expect(cursor != null, isTrue);
      final firstSyncTs = cursor!.ts;

      await Future<void>.delayed(const Duration(milliseconds: 50));
      server.update('test_entity', 'entity-1', {'name': 'Updated'});

      await engine.fullResync();

      cursor = await db.getCursor('test_entity');
      expect(cursor != null, isTrue);
      expect(cursor!.ts.isAfter(firstSyncTs), isTrue);

      final items = await db.select(db.testEntities).get();
      expect(items.first.name, 'Updated');

      engine.dispose();
    });

    test('fullResync with clearData removes old local data', () async {
      server.seed('test_entity', {
        'id': 'server-entity',
        'name': 'Server Only',
      });

      final engine = createEngine();

      await db.into(db.testEntities).insert(TestEntitiesCompanion.insert(
            id: 'local-only-entity',
            name: 'Local Only',
            updatedAt: DateTime.now().toUtc(),
          ));

      var items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.id, 'local-only-entity');

      await engine.fullResync(clearData: true);

      items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.id, 'server-entity');
      expect(items.first.name, 'Server Only');

      engine.dispose();
    });

    test('automatic fullResync when interval exceeded', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Server Entity',
      });

      final engine = createEngine(
        config: const SyncConfig(
          fullResyncInterval: Duration(days: 7),
        ),
      );

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final fullResyncEvents = events.whereType<FullResyncStarted>().toList();
      expect(fullResyncEvents.length, 1);
      expect(fullResyncEvents.first.reason, FullResyncReason.scheduled);

      engine.dispose();
    });

    test('no automatic fullResync when interval not exceeded', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Server Entity',
      });

      final engine = createEngine(
        config: const SyncConfig(
          fullResyncInterval: Duration(days: 7),
        ),
      );

      await db.setCursor(CursorKinds.fullResync, Cursor(
        ts: DateTime.now().toUtc(),
        lastId: '',
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final fullResyncEvents = events.whereType<FullResyncStarted>().toList();
      expect(fullResyncEvents, isEmpty);

      engine.dispose();
    });

    test('fullResync saves lastFullResync timestamp', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Entity',
      });

      final engine = createEngine();

      final beforeSync = DateTime.now().toUtc();
      await engine.fullResync();
      final afterSync = DateTime.now().toUtc();

      final cursor = await db.getCursor(CursorKinds.fullResync);
      expect(cursor != null, isTrue);
      expect(
        cursor!.ts.isAfter(beforeSync.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        cursor.ts.isBefore(afterSync.add(const Duration(seconds: 1))),
        isTrue,
      );

      engine.dispose();
    });

    test('fullResync handles server with many items (pagination)', () async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        server.seed('test_entity', {
          'id': 'entity-$i',
          'name': 'Entity $i',
          'mood': i,
        });
      }

      final engine = createEngine(
        config: const SyncConfig(
          pageSize: 2,
        ),
      );

      final stats = await engine.fullResync();

      expect(stats.pulled, greaterThanOrEqualTo(4));

      final items = await db.select(db.testEntities).get();
      expect(items.length, greaterThanOrEqualTo(4));

      engine.dispose();
    });

    test('fullResync handles conflict during push phase', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server Modified'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'conflict-op',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client Modified',
          'mood': 10,
        },
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.fullResync();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(events.whereType<FullResyncStarted>().length, 1);
      expect(events.whereType<ConflictDetectedEvent>().length, 1);
      expect(events.whereType<ConflictResolvedEvent>().length, 1);

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Modified');
      expect(serverData['mood'], 10);

      engine.dispose();
    });

    test('fullResync emits correct events sequence', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Entity 1',
      });

      final engine = createEngine();

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-2', 'name': 'Entity 2'},
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.fullResync();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(events[0], isA<FullResyncStarted>());

      expect(events[1], isA<SyncStarted>());
      expect((events[1] as SyncStarted).phase, SyncPhase.push);

      final pullStartIndex = events.indexWhere(
        (e) => e is SyncStarted && e.phase == SyncPhase.pull,
      );
      expect(pullStartIndex, greaterThan(1));

      expect(events.last, isA<SyncCompleted>());

      engine.dispose();
    });

    test('fullResync returns accurate stats', () async {
      server
        ..seed('test_entity', {
          'id': 'entity-1',
          'name': 'Server 1',
        })
        ..seed('test_entity', {
          'id': 'entity-2',
          'name': 'Server 2',
        });

      final engine = createEngine();

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'new-entity',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'new-entity', 'name': 'New'},
      ));

      final stats = await engine.fullResync();

      expect(stats.pushed, 1);
      expect(stats.pulled, 3);

      engine.dispose();
    });

    test('second fullResync resets and pulls again', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Version 1',
      });

      final engine = createEngine();

      await engine.fullResync();

      var items = await db.select(db.testEntities).get();
      expect(items.first.name, 'Version 1');

      server.update('test_entity', 'entity-1', {'name': 'Version 2'});

      await engine.fullResync();

      items = await db.select(db.testEntities).get();
      expect(items.first.name, 'Version 2');

      engine.dispose();
    });

    test('fullResync recovers from network error', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Entity',
      });

      final engine = createEngine(
        config: const SyncConfig(
          maxPushRetries: 1,
        ),
      );

      server.failNextRequests(5, statusCode: 500);

      Object? error;
      try {
        await engine.fullResync();
      } catch (e) {
        error = e;
      }

      expect(error != null, isTrue, reason: 'Should fail after max retries');

      server.failNextRequests(0);

      final stats = await engine.fullResync();

      expect(stats.pulled, greaterThan(0));

      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Entity');

      engine.dispose();
    });
  });

  group('Full Resync with multiple clients', () {
    test('new client gets all data via fullResync', () async {
      server
        ..seed('test_entity', {'id': 'entity-1', 'name': 'Entity 1'})
        ..seed('test_entity', {'id': 'entity-2', 'name': 'Entity 2'})
        ..seed('test_entity', {'id': 'entity-3', 'name': 'Entity 3'});

      final engine1 = createEngine();
      await engine1.fullResync();
      engine1.dispose();

      await db.close();
      db = TestDatabase();

      final engine2 = SyncEngine(
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
      );

      await engine2.fullResync();

      final items = await db.select(db.testEntities).get();
      expect(items.length, 3);

      engine2.dispose();
    });

    test('fullResync syncs changes from other clients', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
      });

      final engine1 = createEngine();
      await engine1.fullResync();

      server.update('test_entity', 'entity-1', {'name': 'Updated by Client 2'});

      await engine1.fullResync();

      final items = await db.select(db.testEntities).get();
      expect(items.first.name, 'Updated by Client 2');

      engine1.dispose();
    });
  });
}

