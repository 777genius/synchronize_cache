import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:test/test.dart' hide isNotNull, isNull;

part 'sync_engine_test.g.dart';

// Тестовая модель
class TestItem {
  TestItem({
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

  factory TestItem.fromJson(Map<String, dynamic> json) => TestItem(
        id: json['id'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        name: json['name'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'name': name,
      };
}

// Тестовая таблица
@UseRowClass(TestItem, generateInsertable: true)
class TestItems extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [TestItems, SyncOutbox, SyncCursors])
class TestDatabase extends _$TestDatabase with SyncDatabaseMixin {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

// Мок транспорта
class MockTransport implements TransportAdapter {
  final List<Map<String, dynamic>> pullResponses = [];
  final List<Op> pushedOps = [];
  bool healthStatus = true;
  int pullCallCount = 0;
  int pushCallCount = 0;

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    pullCallCount++;
    return PullPage(items: pullResponses);
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushCallCount++;
    pushedOps.addAll(ops);
    return BatchPushResult(
      results: ops
          .map((op) => OpPushResult(
                opId: op.opId,
                result: const PushSuccess(),
              ))
          .toList(),
    );
  }

  @override
  Future<PushResult> forcePush(Op op) async {
    pushedOps.add(op);
    return const PushSuccess();
  }

  @override
  Future<FetchResult> fetch({
    required String kind,
    required String id,
  }) async {
    return const FetchNotFound();
  }

  @override
  Future<bool> health() async => healthStatus;
}

void main() {
  late TestDatabase db;

  setUp(() async {
    db = TestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncEngine', () {
    test('sync calls pull for registered kinds', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await engine.sync();

      // Pull вызывается для каждого зарегистрированного kind
      expect(transport.pullCallCount, 1);

      engine.dispose();
    });

    test('sync pushes outbox operations', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await db.enqueue(UpsertOp(
        opId: 'test-op-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Test'},
      ));

      await engine.sync();

      expect(transport.pushedOps.length, 1);
      expect(transport.pushedOps.first.opId, 'test-op-1');

      engine.dispose();
    });

    test('sync pulls and inserts items', () async {
      final transport = MockTransport();
      transport.pullResponses.addAll([
        {
          'id': 'pulled-1',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
          'name': 'Pulled Item',
        },
      ]);

      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await engine.sync();

      final items = await db.select(db.testItems).get();
      expect(items.length, 1);
      expect(items.first.name, 'Pulled Item');

      engine.dispose();
    });

    test('sync emits SyncStarted events', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await sub.cancel();

      // Должно быть 2 SyncStarted: один для push, один для pull
      expect(events.whereType<SyncStarted>().length, 2);

      engine.dispose();
    });

    test('sync emits SyncCompleted event', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      await sub.cancel();

      expect(events.whereType<SyncCompleted>().length, 1);

      engine.dispose();
    });

    test('sync updates cursor after pull', () async {
      final transport = MockTransport();
      final now = DateTime.now().toUtc();
      transport.pullResponses.addAll([
        {
          'id': 'cursor-test-1',
          'updated_at': now.toIso8601String(),
          'name': 'Test',
        },
      ]);

      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await engine.sync();

      final cursor = await db.getCursor('test_item');
      expect(cursor != null, isTrue);
      expect(cursor!.lastId, 'cursor-test-1');

      engine.dispose();
    });

    test('sync clears outbox after successful push', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await db.enqueue(UpsertOp(
        opId: 'clear-test-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {},
      ));

      expect((await db.takeOutbox()).length, 1);

      await engine.sync();

      expect((await db.takeOutbox()).length, 0);

      engine.dispose();
    });

    test('sync can filter by kinds', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await engine.sync(kinds: {'other_kind'});

      // Should not pull test_item since we only asked for other_kind
      expect(transport.pullCallCount, 0);

      engine.dispose();
    });

    test('startAuto and stopAuto', () async {
      final transport = MockTransport();
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      engine.startAuto(interval: const Duration(milliseconds: 100));

      await Future<void>.delayed(const Duration(milliseconds: 250));

      engine.stopAuto();

      // Should have synced at least once
      expect(transport.pullCallCount, greaterThan(0));

      engine.dispose();
    });
  });

  group('Error handling', () {
    test('sync throws on transport failure', () async {
      final errorTransport = _FailingTransport();
      final engine = SyncEngine(
        db: db,
        transport: errorTransport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      await expectLater(
        engine.sync(),
        throwsA(isA<Exception>()),
      );

      engine.dispose();
    });

    test('sync emits error event before throwing', () async {
      final errorTransport = _FailingTransport();
      final engine = SyncEngine(
        db: db,
        transport: errorTransport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
      );

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      try {
        await engine.sync();
      } catch (_) {
        // Expected
      }

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(events.whereType<SyncErrorEvent>().length, greaterThan(0));

      engine.dispose();
    });
  });

  group('Retry logic', () {
    test('sync retries push on failure', () async {
      final transport = RetryTransport(failCount: 2);
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
        config: const SyncConfig(
          maxPushRetries: 3,
          backoffMin: Duration(milliseconds: 10), // Fast retry for test
          backoffMultiplier: 1.0,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Test'},
      ));

      await engine.sync();

      expect(transport.pushAttempts, 3); // 2 failures + 1 success

      // Verify outbox is empty
      expect((await db.takeOutbox()).length, 0);

      engine.dispose();
    });

    test('sync gives up after max retries', () async {
      final transport = RetryTransport(failCount: 5);
      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
        config: const SyncConfig(
          maxPushRetries: 3,
          backoffMin: Duration(milliseconds: 10),
          backoffMultiplier: 1.0,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Test'},
      ));

      await expectLater(engine.sync(), throwsA(isA<Exception>()));

      expect(transport.pushAttempts, 3); // Max retries reached

      // Verify outbox is NOT empty
      expect((await db.takeOutbox()).length, 1);

      engine.dispose();
    });
  });

  group('Outbox operations', () {
    test('enqueue UpsertOp', () async {
      await db.enqueue(UpsertOp(
        opId: 'upsert-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Test'},
      ));

      final ops = await db.takeOutbox();
      expect(ops.length, 1);
      expect(ops.first, isA<UpsertOp>());
    });

    test('enqueue DeleteOp', () async {
      await db.enqueue(DeleteOp(
        opId: 'delete-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
      ));

      final ops = await db.takeOutbox();
      expect(ops.length, 1);
      expect(ops.first, isA<DeleteOp>());
    });

    test('takeOutbox respects limit', () async {
      for (var i = 0; i < 10; i++) {
        await db.enqueue(UpsertOp(
          opId: 'limit-$i',
          kind: 'test_item',
          id: 'item-$i',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {},
        ));
      }

      final ops = await db.takeOutbox(limit: 3);
      expect(ops.length, 3);
    });

    test('ackOutbox removes operations', () async {
      await db.enqueue(UpsertOp(
        opId: 'ack-1',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {},
      ));
      await db.enqueue(UpsertOp(
        opId: 'ack-2',
        kind: 'test_item',
        id: 'item-2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {},
      ));

      await db.ackOutbox(['ack-1']);

      final ops = await db.takeOutbox();
      expect(ops.length, 1);
      expect(ops.first.opId, 'ack-2');
    });
  });

  group('Cursor operations', () {
    test('getCursor returns null for unknown kind', () async {
      final cursor = await db.getCursor('unknown');
      expect(cursor == null, isTrue);
    });

    test('setCursor and getCursor roundtrip', () async {
      final original = Cursor(
        ts: DateTime(2024, 1, 1, 12, 0, 0).toUtc(),
        lastId: 'last-id-123',
      );

      await db.setCursor('test_kind', original);
      final retrieved = await db.getCursor('test_kind');

      expect(retrieved != null, isTrue);
      expect(retrieved!.lastId, original.lastId);
      expect(retrieved.ts.year, 2024);
    });
  });

  group('ConflictUtils.preservingMerge', () {
    test('merges non-conflicting fields', () {
      final local = {'name': 'Local Name', 'mood': 5};
      final server = {'name': 'Server Name', 'energy': 7};

      final result = ConflictUtils.preservingMerge(local, server);

      expect(result.data['name'], 'Local Name');
      expect(result.data['energy'], 7);
      expect(result.data['mood'], 5);
      expect(result.localFields, contains('name'));
      expect(result.localFields, contains('mood'));
      expect(result.serverFields, contains('energy'));
    });

    test('keeps local changes when server has null', () {
      final local = {'notes': 'My notes'};
      final server = {'notes': null, 'mood': 5};

      final result = ConflictUtils.preservingMerge(local, server);

      expect(result.data['notes'], 'My notes');
      expect(result.data['mood'], 5);
    });

    test('keeps server value when local is null', () {
      final local = <String, Object?>{'notes': null};
      final server = {'notes': 'Server notes'};

      final result = ConflictUtils.preservingMerge(local, server);

      expect(result.data['notes'], 'Server notes');
    });

    test('unions lists correctly', () {
      final local = {
        'tags': ['a', 'b', 'c']
      };
      final server = {
        'tags': ['b', 'd']
      };

      final result = ConflictUtils.preservingMerge(local, server);
      final tags = result.data['tags'] as List;

      expect(tags, containsAll(['a', 'b', 'c', 'd']));
    });

    test('unions lists of objects by id', () {
      final local = {
        'items': [
          {'id': '1', 'name': 'Local 1'},
          {'id': '3', 'name': 'Local 3'},
        ]
      };
      final server = {
        'items': [
          {'id': '1', 'name': 'Server 1'},
          {'id': '2', 'name': 'Server 2'},
        ]
      };

      final result = ConflictUtils.preservingMerge(local, server);
      final items = result.data['items'] as List;

      expect(items.length, 3);
    });

    test('respects changedFields', () {
      final local = {'name': 'Local', 'mood': 10, 'notes': 'Local notes'};
      final server = {'name': 'Server', 'mood': 5, 'notes': 'Server notes'};

      final result = ConflictUtils.preservingMerge(
        local,
        server,
        changedFields: {'mood'},
      );

      expect(result.data['name'], 'Server');
      expect(result.data['mood'], 10);
      expect(result.data['notes'], 'Server notes');
    });

    test('does not lose server data', () {
      final local = {'mood': 5};
      final server = {'mood': 3, 'energy': 7, 'notes': 'Server notes'};

      final result = ConflictUtils.preservingMerge(local, server);

      expect(result.data['mood'], 5);
      expect(result.data['energy'], 7);
      expect(result.data['notes'], 'Server notes');
    });

    test('handles nested objects', () {
      final local = {
        'settings': {'theme': 'dark', 'fontSize': 14}
      };
      final server = {
        'settings': {'theme': 'light', 'language': 'en'}
      };

      final result = ConflictUtils.preservingMerge(local, server);
      final settings = result.data['settings'] as Map<String, Object?>;

      expect(settings['theme'], 'dark');
      expect(settings['fontSize'], 14);
      expect(settings['language'], 'en');
    });

    test('preserves system fields from server', () {
      final local = {
        'id': 'local-id',
        'updatedAt': '2024-01-01T00:00:00Z',
        'name': 'Local',
      };
      final server = {
        'id': 'server-id',
        'updatedAt': '2024-01-02T00:00:00Z',
        'name': 'Server',
      };

      final result = ConflictUtils.preservingMerge(local, server);

      expect(result.data['id'], 'server-id');
      expect(result.data['updatedAt'], '2024-01-02T00:00:00Z');
      expect(result.data['name'], 'Local');
    });
  });

  group('autoPreserve conflict strategy', () {
    test('autoPreserve merges and force-pushes', () async {
      final serverData = {
        'id': 'item-1',
        'name': 'Server Name',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'energy': 7,
      };

      final transport = ConflictingTransport(
        serverData: serverData,
        serverTimestamp: DateTime.now().toUtc(),
      );

      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'conflict-op',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Local Name', 'mood': 5},
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(transport.forcePushCalled, isTrue);
      expect(events.whereType<ConflictDetectedEvent>().length, 1);
      expect(events.whereType<DataMergedEvent>().length, 1);
      expect(events.whereType<ConflictResolvedEvent>().length, 1);

      engine.dispose();
    });

    test('autoPreserve emits DataMergedEvent with correct fields', () async {
      final serverData = {
        'id': 'item-1',
        'name': 'Server Name',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final transport = ConflictingTransport(
        serverData: serverData,
        serverTimestamp: DateTime.now().toUtc(),
      );

      final engine = SyncEngine(
        db: db,
        transport: transport,
        tables: [
          SyncableTable<TestItem>(
            kind: 'test_item',
            table: db.testItems,
            fromJson: TestItem.fromJson,
            toJson: (item) => item.toJson(),
            toInsertable: (item) => item.toInsertable(),
          ),
        ],
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'merge-test',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'mood': 5},
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final mergeEvent = events.whereType<DataMergedEvent>().first;
      expect(mergeEvent.kind, 'test_item');
      expect(mergeEvent.entityId, 'item-1');
      expect(mergeEvent.localFields, contains('mood'));

      engine.dispose();
    });
  });

  group('UpsertOp with baseUpdatedAt and changedFields', () {
    test('enqueue preserves baseUpdatedAt', () async {
      final baseTime = DateTime(2024, 1, 1, 12, 0, 0).toUtc();

      await db.enqueue(UpsertOp(
        opId: 'base-test',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Test'},
        baseUpdatedAt: baseTime,
      ));

      final ops = await db.takeOutbox();
      expect(ops.length, 1);

      final op = ops.first as UpsertOp;
      expect(op.baseUpdatedAt, baseTime);
      expect(op.isNewRecord, isFalse);
    });

    test('enqueue preserves changedFields', () async {
      await db.enqueue(UpsertOp(
        opId: 'changed-test',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'Test', 'mood': 5},
        changedFields: {'mood'},
      ));

      final ops = await db.takeOutbox();
      expect(ops.length, 1);

      final op = ops.first as UpsertOp;
      expect(op.changedFields, {'mood'});
    });

    test('isNewRecord returns true when baseUpdatedAt is null', () async {
      await db.enqueue(UpsertOp(
        opId: 'new-record',
        kind: 'test_item',
        id: 'item-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'item-1', 'name': 'New'},
      ));

      final ops = await db.takeOutbox();
      final op = ops.first as UpsertOp;
      expect(op.isNewRecord, isTrue);
    });
  });
}

class _FailingTransport implements TransportAdapter {
  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    throw Exception('Network error');
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    throw Exception('Network error');
  }

  @override
  Future<PushResult> forcePush(Op op) async {
    throw Exception('Network error');
  }

  @override
  Future<FetchResult> fetch({
    required String kind,
    required String id,
  }) async {
    throw Exception('Network error');
  }

  @override
  Future<bool> health() async => false;
}

class RetryTransport implements TransportAdapter {
  int pushAttempts = 0;
  final int failCount;

  RetryTransport({this.failCount = 2});

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushAttempts++;
    if (pushAttempts <= failCount) {
      throw Exception('Network error attempt $pushAttempts');
    }
    return BatchPushResult(
      results: ops
          .map((op) => OpPushResult(
                opId: op.opId,
                result: const PushSuccess(),
              ))
          .toList(),
    );
  }

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    return PullPage(items: []);
  }

  @override
  Future<PushResult> forcePush(Op op) async => const PushSuccess();

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}

class ConflictingTransport implements TransportAdapter {
  final Map<String, Object?> serverData;
  final DateTime serverTimestamp;
  int pushCallCount = 0;
  bool forcePushCalled = false;

  ConflictingTransport({
    required this.serverData,
    required this.serverTimestamp,
  });

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    pushCallCount++;
    return BatchPushResult(
      results: ops
          .map((op) => OpPushResult(
                opId: op.opId,
                result: PushConflict(
                  serverData: serverData,
                  serverTimestamp: serverTimestamp,
                ),
              ))
          .toList(),
    );
  }

  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    return PullPage(items: []);
  }

  @override
  Future<PushResult> forcePush(Op op) async {
    forcePushCalled = true;
    return const PushSuccess();
  }

  @override
  Future<FetchResult> fetch({required String kind, required String id}) async =>
      const FetchNotFound();

  @override
  Future<bool> health() async => true;
}
