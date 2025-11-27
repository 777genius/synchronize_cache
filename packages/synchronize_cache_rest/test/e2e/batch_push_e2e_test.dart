import 'dart:async';

import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';
import 'package:test/test.dart';

import 'helpers/test_database.dart';
import 'helpers/test_server.dart';

void main() {
  late TestServer server;
  late SyncEngine syncEngine;
  late RestTransport transport;
  late TestDatabase database;

  // Создаем StreamController для событий, чтобы не потерять их
  final eventController = StreamController<SyncEvent>.broadcast();

  setUp(() async {
    server = TestServer();
    await server.start();

    database = TestDatabase();

    transport = RestTransport(
      base: server.baseUrl,
      token: () async => 'test-token',
      enableBatch: true, // Включаем Batch API
      batchSize: 2, // Маленький размер пакета для проверки чанкинга
    );

    syncEngine = SyncEngine(
      db: database,
      transport: transport,
      config: const SyncConfig(
        pageSize: 10,
      ),
      tables: [
        SyncableTable<TestEntity>(
          kind: 'test_entity', // Используем test_entity как в базе
          table: database.testEntities,
          fromJson: TestEntity.fromJson,
          toJson: (item) => item.toJson(),
          toInsertable: (item) => item.toInsertable(),
        ),
      ],
    );
    
    // Подписываемся на события (в новом API это делается через геттер)
    // syncEngine.events.listen(eventController.add); // Если нужно
  });

  tearDown(() async {
    syncEngine.dispose();
    await eventController.close();
    await database.close();
    await server.stop();
  });

  group('E2E Batch Push', () {
    test('successfully pushes multiple items in batch', () async {
      // Create 3 items locally
      await database.enqueue(UpsertOp(
        opId: 'op-1',
        kind: 'test_entity',
        id: '1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': '1', 'name': 'Item 1'},
      ));
      await database.enqueue(UpsertOp(
        opId: 'op-2',
        kind: 'test_entity',
        id: '2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': '2', 'name': 'Item 2'},
      ));
      await database.enqueue(UpsertOp(
        opId: 'op-3',
        kind: 'test_entity',
        id: '3',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': '3', 'name': 'Item 3'},
      ));

      // Sync (push + pull)
      final stats = await syncEngine.sync();

      expect(stats.pushed, 3);
      expect(stats.errors, 0);
      expect(stats.conflicts, 0);

      // Verify on server
      final item1 = server.get('test_entity', '1');
      final item2 = server.get('test_entity', '2');
      final item3 = server.get('test_entity', '3');

      expect(item1?['name'], 'Item 1');
      expect(item2?['name'], 'Item 2');
      expect(item3?['name'], 'Item 3');

      // Verify it was a batch request
      final batchRequests = server.recordedRequests
          .where((r) => r.path.contains('/batch') && r.method == 'POST');
      expect(batchRequests, isNotEmpty);
    });

    test('successfully deletes multiple items in batch', () async {
      server
        ..seed('test_entity', {'id': '1', 'name': 'Item 1'})
        ..seed('test_entity', {'id': '2', 'name': 'Item 2'});

      // Sync to get base state
      await syncEngine.sync();

      // Get items to have correct baseUpdatedAt
      final items = await database.select(database.testEntities).get();
      final item1 = items.firstWhere((i) => i.id == '1');
      final item2 = items.firstWhere((i) => i.id == '2');

      // Delete locally
      await database.enqueue(DeleteOp(
        opId: 'del-1',
        kind: 'test_entity',
        id: '1',
        localTimestamp: DateTime.now().toUtc(),
        baseUpdatedAt: item1.updatedAt,
      ));
      await database.enqueue(DeleteOp(
        opId: 'del-2',
        kind: 'test_entity',
        id: '2',
        localTimestamp: DateTime.now().toUtc(),
        baseUpdatedAt: item2.updatedAt,
      ));

      // Sync
      final stats = await syncEngine.sync();

      expect(stats.pushed, 2);

      // Verify on server
      expect(server.get('test_entity', '1'), isNull);
      expect(server.get('test_entity', '2'), isNull);
    });

    test('handles mixed operations (upsert + delete)', () async {
      server.seed('test_entity', {'id': '1', 'name': 'To Delete'});
      await syncEngine.sync();

      final items = await database.select(database.testEntities).get();
      final item1 = items.firstWhere((i) => i.id == '1');

      await database.enqueue(DeleteOp(
        opId: 'del-1',
        kind: 'test_entity',
        id: '1',
        localTimestamp: DateTime.now().toUtc(),
        baseUpdatedAt: item1.updatedAt,
      ));
      
      await database.enqueue(UpsertOp(
        opId: 'up-2',
        kind: 'test_entity',
        id: '2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': '2', 'name': 'New Item'},
      ));

      final stats = await syncEngine.sync();

      expect(stats.pushed, 2);

      expect(server.get('test_entity', '1'), isNull);
      expect(server.get('test_entity', '2'), isNotNull);
    });

    test('handles partial conflicts in batch', () async {
      // 1. Seed item on server and sync it
      final baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);
      server.seed('test_entity', {'id': '1', 'name': 'Original', 'updated_at': baseTime.toIso8601String()});
      
      await syncEngine.sync(); // Получаем данные и обновляем baseUpdatedAt в БД

      // 2. Simulate conflict: update item on server directly
      server.update('test_entity', '1', {'name': 'Server Update'});

      // 3. Update item locally (conflict)
      await database.enqueue(UpsertOp(
        opId: 'up-1',
        kind: 'test_entity',
        id: '1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': '1', 'name': 'Local Update'},
        baseUpdatedAt: baseTime,
      ));

      // 4. Create new item locally (success)
      await database.enqueue(UpsertOp(
        opId: 'up-2',
        kind: 'test_entity',
        id: '2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': '2', 'name': 'New Item'},
      ));

      // 5. Push
      // По умолчанию conflictStrategy = ConflictStrategy.autoPreserve
      final stats = await syncEngine.sync();

      expect(stats.conflicts, 1);
      expect(stats.pushed, 1); // Только Item 2 успешно отправлен без конфликта (Item 1 зарезолвлен)
      
      // Item 2 should be on server
      expect(server.get('test_entity', '2')?['name'], 'New Item');
      
      // Item 1: autoPreserve сольет данные. Так как server изменил name, а local изменил name, 
      // то server wins (обычно) или оба сохраняются если разные поля.
      // Тут одно поле 'name'.
      
      // Проверим что батч запрос был и сервер вернул смешанный ответ
      // Это уже проверено статистикой
    });

    test('chunks requests larger than batchSize', () async {
      // batchSize is 2 (configured in setUp)
      
      // Create 3 items
      for (var i = 1; i <= 3; i++) {
        await database.enqueue(UpsertOp(
          opId: 'op-$i',
          kind: 'test_entity',
          id: '$i',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'id': '$i', 'name': 'Item $i'},
        ));
      }

      await syncEngine.sync();

      // Should have at least 2 batch requests (2 items + 1 item)
      final batchRequests = server.recordedRequests
          .where((r) => r.path.contains('/batch') && r.method == 'POST');
      
      expect(batchRequests.length, greaterThanOrEqualTo(2));
    });
  });
}
