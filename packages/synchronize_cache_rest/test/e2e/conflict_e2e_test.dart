import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';
import 'package:test/test.dart' hide isNotNull, isNull;

import 'helpers/test_server.dart';
import 'tables/local_sync_tables.dart';

part 'conflict_e2e_test.g.dart';

class TestEntity {
  TestEntity({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.name,
    this.mood,
    this.energy,
    this.notes,
    this.settings,
    this.tags,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final String name;
  final int? mood;
  final int? energy;
  final String? notes;
  final String? settings;
  final String? tags;

  factory TestEntity.fromJson(Map<String, dynamic> json) => TestEntity(
        id: json['id'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        name: json['name'] as String? ?? '',
        mood: json['mood'] as int?,
        energy: json['energy'] as int?,
        notes: json['notes'] as String?,
        settings: json['settings'] is String
            ? json['settings'] as String
            : json['settings'] != null
                ? jsonEncode(json['settings'])
                : null,
        tags: json['tags'] is String
            ? json['tags'] as String
            : json['tags'] != null
                ? jsonEncode(json['tags'])
                : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'name': name,
        'mood': mood,
        'energy': energy,
        'notes': notes,
        'settings': settings,
        'tags': tags,
      };

  Map<String, Object?>? get settingsMap =>
      settings != null ? jsonDecode(settings!) as Map<String, Object?> : null;

  List<Object?>? get tagsList =>
      tags != null ? jsonDecode(tags!) as List<Object?> : null;
}

@UseRowClass(TestEntity, generateInsertable: true)
class TestEntities extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get mood => integer().nullable()();
  IntColumn get energy => integer().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get settings => text().nullable()();
  TextColumn get tags => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [TestEntities, LocalSyncOutbox, LocalSyncCursors])
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
    Map<String, TableConflictConfig>? tableConflictConfigs,
  }) {
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
      config: config ?? const SyncConfig(),
      tableConflictConfigs: tableConflictConfigs ?? {},
    );
  }

  group('ConflictStrategy.serverWins', () {
    test('accepts server data on conflict', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'name': 'Server Updated',
        'energy': 8,
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client Updated',
          'mood': 10,
        },
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(
        events.whereType<ConflictDetectedEvent>().length,
        1,
        reason: 'Should detect conflict',
      );
      expect(
        events.whereType<ConflictResolvedEvent>().length,
        1,
        reason: 'Should resolve conflict',
      );

      final resolvedEvent = events.whereType<ConflictResolvedEvent>().first;
      expect(resolvedEvent.resolution, isA<AcceptServer>());

      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Server Updated');
      expect(items.first.energy, 8);

      engine.dispose();
    });

    test('clears outbox after accepting server data', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final outbox = await db.takeOutbox();
      expect(outbox, isEmpty, reason: 'Outbox should be cleared');

      engine.dispose();
    });
  });

  group('ConflictStrategy.clientWins', () {
    test('force pushes client data on conflict', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'name': 'Server Updated',
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client Wins',
          'mood': 10,
        },
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(events.whereType<ConflictDetectedEvent>().length, 1);
      expect(events.whereType<ConflictResolvedEvent>().length, 1);

      final resolvedEvent = events.whereType<ConflictResolvedEvent>().first;
      expect(resolvedEvent.resolution, isA<AcceptClient>());

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Wins');
      expect(serverData['mood'], 10);

      // Проверяем что локальная БД сохранила клиентские данные
      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Client Wins');
      expect(items.first.mood, 10);

      engine.dispose();
    });

    test('verifies force push header is sent', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final forceRequests = server.recordedRequests
          .where((r) => r.headers.value('X-Force-Update') == 'true')
          .toList();

      expect(forceRequests, isNotEmpty, reason: 'Should send force push');

      engine.dispose();
    });
  });

  group('ConflictStrategy.lastWriteWins', () {
    test('client wins when local timestamp is newer', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      final serverUpdateTime = DateTime.utc(2024, 1, 1, 12, 30, 0);
      server.update('test_entity', 'entity-1', {
        'name': 'Server',
        'updated_at': serverUpdateTime.toIso8601String(),
      });

      final localTimestamp = DateTime.utc(2024, 1, 1, 13, 0, 0);

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.lastWriteWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: localTimestamp,
        payloadJson: {'id': 'entity-1', 'name': 'Client Newer'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final resolvedEvent = events.whereType<ConflictResolvedEvent>().first;
      expect(resolvedEvent.resolution, isA<AcceptClient>());

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Newer');

      engine.dispose();
    });

    test('server wins when server timestamp is newer', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      final serverUpdateTime = DateTime.utc(2024, 1, 1, 14, 0, 0);
      server.update('test_entity', 'entity-1', {
        'name': 'Server Newer',
        'updated_at': serverUpdateTime.toIso8601String(),
      });

      final localTimestamp = DateTime.utc(2024, 1, 1, 13, 0, 0);

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.lastWriteWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: localTimestamp,
        payloadJson: {'id': 'entity-1', 'name': 'Client Older'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final resolvedEvent = events.whereType<ConflictResolvedEvent>().first;
      expect(resolvedEvent.resolution, isA<AcceptServer>());

      final items = await db.select(db.testEntities).get();
      expect(items.first.name, 'Server Newer');

      engine.dispose();
    });
  });

  group('ConflictStrategy.merge', () {
    test('merges non-conflicting fields', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'energy': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'energy': 10,
        'notes': 'Server notes',
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client Name',
          'mood': 8,
        },
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final resolvedEvent = events.whereType<ConflictResolvedEvent>().first;
      expect(resolvedEvent.resolution, isA<AcceptMerged>());

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Name');
      expect(serverData['mood'], 8);
      expect(serverData['energy'], 10);
      expect(serverData['notes'], 'Server notes');

      // Проверяем что локальная БД сохранила merged данные
      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Client Name');
      expect(items.first.mood, 8);
      expect(items.first.energy, 10);
      expect(items.first.notes, 'Server notes');

      engine.dispose();
    });

    test('uses custom merge function', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Server',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'mood': 10});

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (local, server) {
            return {
              ...server,
              'name': '${local['name']} + ${server['name']}',
            };
          },
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client + Server');

      engine.dispose();
    });
  });

  group('ConflictStrategy.autoPreserve', () {
    test('preserves all data without loss', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'energy': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'energy': 10,
        'notes': 'Server added notes',
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client Updated',
          'mood': 8,
        },
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(events.whereType<DataMergedEvent>().length, 1);

      final mergedEvent = events.whereType<DataMergedEvent>().first;
      expect(mergedEvent.localFields, isNotEmpty);
      expect(mergedEvent.serverFields, isNotEmpty);

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Updated');
      expect(serverData['mood'], 8);
      expect(serverData['energy'], 10);
      expect(serverData['notes'], 'Server added notes');

      // Проверяем что локальная БД сохранила preserved данные
      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Client Updated');
      expect(items.first.mood, 8);
      expect(items.first.energy, 10);
      expect(items.first.notes, 'Server added notes');

      engine.dispose();
    });

    test('respects changedFields', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'energy': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'name': 'Server Name',
        'energy': 10,
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client Name',
          'mood': 8,
          'energy': 3,
        },
        baseUpdatedAt: baseTime,
        changedFields: {'mood'},
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Server Name');
      expect(serverData['mood'], 8);
      expect(serverData['energy'], 10);

      // Проверяем что локальная БД учла changedFields:
      // - mood взят из клиента (был в changedFields)
      // - name и energy взяты с сервера (не были в changedFields)
      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Server Name');
      expect(items.first.mood, 8);
      expect(items.first.energy, 10);

      engine.dispose();
    });

    test('preserves server value when local is null', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'notes': 'Important notes',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'mood': 7});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Updated',
          'notes': null,
        },
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Updated');
      expect(serverData['notes'], 'Important notes');

      engine.dispose();
    });
  });

  group('ConflictStrategy.manual', () {
    test('calls resolver callback', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      var resolverCalled = false;
      Conflict? capturedConflict;

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (conflict) async {
            resolverCalled = true;
            capturedConflict = conflict;
            return const AcceptServer();
          },
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      expect(resolverCalled, isTrue);
      expect(capturedConflict != null, isTrue, reason: 'Conflict should be captured');
      expect(capturedConflict!.kind, 'test_entity');
      expect(capturedConflict!.entityId, 'entity-1');
      expect(capturedConflict!.localData['name'], 'Client');
      expect(capturedConflict!.serverData['name'], 'Server');

      engine.dispose();
    });

    test('accepts client via resolver', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (conflict) async => const AcceptClient(),
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Manual Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Manual Client');

      engine.dispose();
    });

    test('accepts merged data via resolver', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'energy': 10});

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (conflict) async {
            return AcceptMerged({
              ...conflict.serverData,
              'name': 'Manually Merged',
              'mood': 100,
            });
          },
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client', 'mood': 8},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Manually Merged');
      expect(serverData['mood'], 100);
      expect(serverData['energy'], 10);

      engine.dispose();
    });

    test('defers resolution', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (conflict) async => const DeferResolution(),
          skipConflictingOps: true,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      expect(events.whereType<ConflictUnresolvedEvent>().length, 1);

      final unresolvedEvent = events.whereType<ConflictUnresolvedEvent>().first;
      expect(unresolvedEvent.reason, contains('deferred'));

      engine.dispose();
    });

    test('discards operation', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (conflict) async => const DiscardOperation(),
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final outbox = await db.takeOutbox();
      expect(outbox, isEmpty, reason: 'Operation should be removed');

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Server', reason: 'Server unchanged');

      engine.dispose();
    });

    test('defers when no resolver provided', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          skipConflictingOps: true,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final unresolvedEvents = events.whereType<ConflictUnresolvedEvent>();
      expect(unresolvedEvents.length, greaterThanOrEqualTo(1));
      expect(
        unresolvedEvents.first.reason,
        contains('No conflict resolver'),
      );

      engine.dispose();
    });
  });

  group('Batch conflicts', () {
    test('handles multiple conflicts in single push', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      for (var i = 1; i <= 3; i++) {
        server.seed('test_entity', {
          'id': 'entity-$i',
          'name': 'Original $i',
          'updated_at': baseTime.toIso8601String(),
        });
      }

      await Future<void>.delayed(const Duration(milliseconds: 10));

      server.update('test_entity', 'entity-1', {'name': 'Server 1'});
      server.update('test_entity', 'entity-2', {'name': 'Server 2'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client 1'},
        baseUpdatedAt: baseTime,
      ));

      await db.enqueue(UpsertOp(
        opId: 'op-2',
        kind: 'test_entity',
        id: 'entity-2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-2', 'name': 'Client 2'},
        baseUpdatedAt: baseTime,
      ));

      await db.enqueue(UpsertOp(
        opId: 'op-3',
        kind: 'test_entity',
        id: 'entity-3',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-3', 'name': 'Client 3'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await sub.cancel();

      final conflictEvents = events.whereType<ConflictDetectedEvent>().toList();
      expect(conflictEvents.length, 2, reason: 'Should detect 2 conflicts');

      final resolvedEvents = events.whereType<ConflictResolvedEvent>().toList();
      expect(resolvedEvents.length, 2, reason: 'Should resolve 2 conflicts');

      final outbox = await db.takeOutbox();
      expect(outbox, isEmpty, reason: 'All operations should be processed');

      engine.dispose();
    });

    test('handles mixed success and conflicts', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client Conflict'},
        baseUpdatedAt: baseTime,
      ));

      await db.enqueue(UpsertOp(
        opId: 'op-2',
        kind: 'test_entity',
        id: 'entity-new',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-new', 'name': 'New Entity'},
      ));

      await engine.sync();

      final entity1 = server.get('test_entity', 'entity-1');
      expect(entity1?['name'], 'Client Conflict');

      final newEntity = server.get('test_entity', 'entity-new');
      expect(newEntity != null, isTrue, reason: 'New entity should exist');
      expect(newEntity?['name'], 'New Entity');

      engine.dispose();
    });
  });

  group('Conflict events', () {
    test('emits ConflictDetectedEvent with correct data', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'name': 'Server Name',
        'energy': 10,
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'conflict-op',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.utc(2024, 1, 2),
        payloadJson: {'id': 'entity-1', 'name': 'Client Name', 'mood': 8},
        baseUpdatedAt: baseTime,
        changedFields: {'name', 'mood'},
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final detectedEvent = events.whereType<ConflictDetectedEvent>().first;

      expect(detectedEvent.conflict.kind, 'test_entity');
      expect(detectedEvent.conflict.entityId, 'entity-1');
      expect(detectedEvent.conflict.opId, 'conflict-op');
      expect(detectedEvent.conflict.localData['name'], 'Client Name');
      expect(detectedEvent.conflict.serverData['name'], 'Server Name');
      expect(detectedEvent.conflict.changedFields, {'name', 'mood'});
      expect(detectedEvent.strategy, ConflictStrategy.serverWins);

      engine.dispose();
    });

    test('emits ConflictResolvedEvent with result data', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Server',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'energy': 10});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final resolvedEvent = events.whereType<ConflictResolvedEvent>().first;

      expect(resolvedEvent.conflict.entityId, 'entity-1');
      expect(resolvedEvent.resolution, isA<AcceptServer>());
      expect(resolvedEvent.resultData != null, isTrue);
      expect(resolvedEvent.resultData!['name'], 'Server');

      engine.dispose();
    });

    test('emits DataMergedEvent for autoPreserve', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'energy': 10});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.autoPreserve,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client', 'mood': 8},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final mergedEvent = events.whereType<DataMergedEvent>().first;

      expect(mergedEvent.kind, 'test_entity');
      expect(mergedEvent.entityId, 'entity-1');
      expect(mergedEvent.localFields, isNotEmpty);
      expect(mergedEvent.serverFields, isNotEmpty);
      expect(mergedEvent.mergedData['name'], 'Client');
      expect(mergedEvent.mergedData['mood'], 8);
      expect(mergedEvent.mergedData['energy'], 10);

      engine.dispose();
    });

    test('emits SyncStats with conflict counts', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final completedEvent = events.whereType<SyncCompleted>().firstOrNull;
      expect(completedEvent != null, isTrue);

      if (completedEvent?.stats != null) {
        expect(completedEvent!.stats!.conflicts, greaterThan(0));
        expect(completedEvent.stats!.conflictsResolved, greaterThan(0));
      }

      engine.dispose();
    });
  });

  group('Delete conflicts', () {
    test('handles delete conflict with serverWins', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await db.into(db.testEntities).insert(TestEntitiesCompanion.insert(
            id: 'entity-1',
            name: 'Original',
            updatedAt: baseTime,
          ));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Modified After Read'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(DeleteOp(
        opId: 'delete-op',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        baseUpdatedAt: baseTime,
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final conflictEvents = events.whereType<ConflictDetectedEvent>().toList();
      expect(conflictEvents.length, 1);

      final entity = server.get('test_entity', 'entity-1');
      expect(entity != null, isTrue, reason: 'Server entity should not be deleted');

      final localItems = await db.select(db.testEntities).get();
      expect(localItems.length, 1, reason: 'Local entity should remain (serverWins)');
      expect(localItems.first.name, 'Modified After Read');

      engine.dispose();
    });

    test('force deletes on clientWins', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await db.into(db.testEntities).insert(TestEntitiesCompanion.insert(
            id: 'entity-1',
            name: 'Original',
            updatedAt: baseTime,
          ));

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Modified'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
        ),
      );

      await db.enqueue(DeleteOp(
        opId: 'delete-op',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final forceRequests = server.recordedRequests
          .where((r) => r.headers.value('X-Force-Delete') == 'true')
          .toList();

      expect(forceRequests, isNotEmpty);

      final entity = server.get('test_entity', 'entity-1');
      expect(entity == null, isTrue, reason: 'Server entity should be deleted');

      engine.dispose();
    });

    test('delete conflict with lastWriteWins when client is newer', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);
      final serverUpdateTime = DateTime.utc(2024, 1, 1, 12, 30, 0);
      final clientDeleteTime = DateTime.utc(2024, 1, 1, 13, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await db.into(db.testEntities).insert(TestEntitiesCompanion.insert(
            id: 'entity-1',
            name: 'Original',
            updatedAt: baseTime,
          ));

      server.update('test_entity', 'entity-1', {
        'name': 'Server Modified',
        'updated_at': serverUpdateTime.toIso8601String(),
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.lastWriteWins,
        ),
      );

      await db.enqueue(DeleteOp(
        opId: 'delete-op',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: clientDeleteTime,
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final entity = server.get('test_entity', 'entity-1');
      expect(entity == null, isTrue, reason: 'Client delete wins (newer timestamp)');

      engine.dispose();
    });
  });

  group('Table-specific conflict config', () {
    test('uses table-specific strategy', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
        tableConflictConfigs: {
          'test_entity': const TableConflictConfig(
            strategy: ConflictStrategy.clientWins,
          ),
        },
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client Wins'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Wins');

      engine.dispose();
    });

    test('uses table-specific merge function', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Server',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'energy': 10});

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
        ),
        tableConflictConfigs: {
          'test_entity': TableConflictConfig(
            strategy: ConflictStrategy.merge,
            mergeFunction: (local, server) => {
              ...server,
              'name': 'Custom: ${local['name']}',
            },
          ),
        },
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Custom: Client');

      engine.dispose();
    });

    test('uses table-specific resolver', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server'});

      var tableResolverCalled = false;

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.manual,
          conflictResolver: (c) async {
            fail('Global resolver should not be called');
          },
        ),
        tableConflictConfigs: {
          'test_entity': TableConflictConfig(
            strategy: ConflictStrategy.manual,
            resolver: (conflict) async {
              tableResolverCalled = true;
              return const AcceptServer();
            },
          ),
        },
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      expect(tableResolverCalled, isTrue);

      engine.dispose();
    });
  });

  group('No conflict scenarios', () {
    test('successful push without conflict', () async {
      server.conflictCheckEnabled = false;

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
      });

      final engine = createEngine();

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Updated'},
      ));

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      await engine.sync();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final conflictEvents = events.whereType<ConflictDetectedEvent>().toList();
      expect(conflictEvents, isEmpty);

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Updated');

      engine.dispose();
    });

    test('create new entity', () async {
      final engine = createEngine();

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: '',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'name': 'Brand New'},
      ));

      await engine.sync();

      final entities = server.getAll('test_entity');
      expect(entities.length, 1);
      expect(entities.first['name'], 'Brand New');

      engine.dispose();
    });
  });

  group('Deep merge scenarios', () {
    test('merges nested objects correctly', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'settings': {'language': 'en'},
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'settings': {'language': 'ru', 'notifications': true},
      });

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: ConflictUtils.deepMerge,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Updated',
          'settings': {'theme': 'dark', 'language': 'en'},
        },
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Updated');

      final settings = serverData['settings'] as Map<String, Object?>;
      expect(settings['theme'], 'dark');
      expect(settings['language'], 'en');
      expect(settings['notifications'], true);

      engine.dispose();
    });

    test('merges lists using preservingMerge', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'tags': ['tag1', 'tag2'],
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'tags': ['tag2', 'tag3', 'tag4'],
      });

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (local, server) =>
              ConflictUtils.preservingMerge(local, server).data,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client',
          'tags': ['tag1', 'tag2', 'tag5'],
        },
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      final tags = serverData['tags'] as List<Object?>;

      expect(tags, containsAll(['tag1', 'tag2', 'tag5', 'tag3', 'tag4']));

      engine.dispose();
    });

    test('deep merges nested objects with preservingMerge', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'settings': {
          'ui': {'fontSize': 14},
          'features': ['feature1'],
        },
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'settings': {
          'ui': {'fontSize': 16, 'theme': 'light'},
          'features': ['feature1', 'feature2'],
        },
      });

      final engine = createEngine(
        config: SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
          mergeFunction: (local, server) =>
              ConflictUtils.preservingMerge(local, server).data,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {
          'id': 'entity-1',
          'name': 'Client',
          'settings': {
            'ui': {'fontSize': 14, 'darkMode': true},
            'features': ['feature1', 'feature3'],
          },
        },
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      final settings = serverData['settings'] as Map<String, Object?>;
      final ui = settings['ui'] as Map<String, Object?>;
      final features = settings['features'] as List<Object?>;

      expect(ui['fontSize'], 14);
      expect(ui['darkMode'], true);
      expect(ui['theme'], 'light');

      expect(features, containsAll(['feature1', 'feature3', 'feature2']));

      engine.dispose();
    });
  });

  group('Pull after conflict resolution', () {
    test('local db contains merged data after conflict resolution', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'mood': 5,
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {
        'energy': 10,
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.merge,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Merged Name', 'mood': 8},
        baseUpdatedAt: baseTime,
      ));

      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Merged Name');
      expect(serverData['mood'], 8);
      expect(serverData['energy'], 10);

      final items = await db.select(db.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Merged Name');
      expect(items.first.mood, 8);
      expect(items.first.energy, 10);

      engine.dispose();
    });

    test('new client can pull resolved data', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      await Future<void>.delayed(const Duration(milliseconds: 10));
      server.update('test_entity', 'entity-1', {'name': 'Server Version'});

      final engine1 = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client Version'},
        baseUpdatedAt: baseTime,
      ));

      await engine1.sync();
      engine1.dispose();

      final db2 = TestDatabase();
      addTearDown(() => db2.close());

      final engine2 = SyncEngine(
        db: db2,
        transport: RestTransport(
          base: server.baseUrl,
          token: () async => 'Bearer test-token',
        ),
        tables: [
          SyncableTable<TestEntity>(
            kind: 'test_entity',
            table: db2.testEntities,
            fromJson: TestEntity.fromJson,
            toJson: (e) => e.toJson(),
            toInsertable: (e) => e.toInsertable(),
          ),
        ],
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await engine2.sync();

      final items = await db2.select(db2.testEntities).get();
      expect(items.length, 1);
      expect(items.first.name, 'Server Version');

      engine2.dispose();
    });
  });

  group('Network errors during conflict resolution', () {
    test('eventually succeeds after transient server errors', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.clientWins,
          maxPushRetries: 5,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client Version'},
        baseUpdatedAt: baseTime,
      ));

      server.failNextRequests(2, statusCode: 500);

      try {
        await engine.sync();
      } catch (_) {}

      server.failNextRequests(0);
      await engine.sync();

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Version');

      engine.dispose();
    });

    test('server errors prevent pull from completing', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Server Data',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      server.failNextRequests(10, statusCode: 503);

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
          maxPushRetries: 2,
        ),
      );

      Object? caughtError;
      try {
        await engine.sync();
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNot(isNull));

      final items = await db.select(db.testEntities).get();
      expect(items, isEmpty);

      engine.dispose();
    });

    test('handles slow server response', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client Version'},
        baseUpdatedAt: baseTime,
      ));

      server.delayNextRequests(const Duration(milliseconds: 100));

      final stopwatch = Stopwatch()..start();
      await engine.sync();
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(100));

      final serverData = server.get('test_entity', 'entity-1')!;
      expect(serverData['name'], 'Client Version');

      engine.dispose();
    });
  });

  group('Error handling', () {
    test('handles invalid JSON in server response', () async {
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);

      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': baseTime.toIso8601String(),
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
          skipConflictingOps: true,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      server.returnInvalidJson(true);

      Object? caughtError;
      try {
        await engine.sync();
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNot(isNull));

      server.returnInvalidJson(false);
      engine.dispose();
    });

    test('handles missing current field in conflict response', () async {
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
          conflictStrategy: ConflictStrategy.serverWins,
          skipConflictingOps: true,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client'},
        baseUpdatedAt: baseTime,
      ));

      server.returnIncompleteConflict(true);

      Object? caughtError;
      try {
        await engine.sync();
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNot(isNull));

      server.returnIncompleteConflict(false);
      engine.dispose();
    });

    test('handles server returning wrong entity in conflict response', () async {
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
          conflictStrategy: ConflictStrategy.merge,
          skipConflictingOps: true,
        ),
      );

      await db.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: 'entity-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'entity-1', 'name': 'Client', 'mood': 10},
        baseUpdatedAt: baseTime,
      ));

      server.returnWrongEntity(true);

      final events = <SyncEvent>[];
      final sub = engine.events.listen(events.add);

      try {
        await engine.sync();
      } catch (_) {}

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await sub.cancel();

      final conflictEvents = events.whereType<ConflictDetectedEvent>().toList();
      expect(conflictEvents.length, 1);

      server.returnWrongEntity(false);
      engine.dispose();
    });

    test('handles network error during pull', () async {
      server.seed('test_entity', {
        'id': 'entity-1',
        'name': 'Original',
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      final engine = createEngine(
        config: const SyncConfig(
          conflictStrategy: ConflictStrategy.serverWins,
          maxPushRetries: 1,
          maxConflictRetries: 1,
        ),
      );

      server.failNextRequests(5, statusCode: 500);

      Object? caughtError;
      try {
        await engine.sync();
      } catch (e) {
        caughtError = e;
      }

      expect(caughtError, isNot(isNull));

      engine.dispose();
    });
  });
}

