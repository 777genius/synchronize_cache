import 'package:example/database.dart';
import 'package:example/models/daily_feeling.dart';
import 'package:example/models/health_record.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:test/test.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('Database CRUD', () {
    test('insert and read HealthRecord', () async {
      final record = HealthRecord(
        id: 'hr-1',
        updatedAt: DateTime.now().toUtc(),
        type: 'diabetes',
        userId: 42,
      );

      await db.into(db.healthRecords).insert(record.toInsertable());

      final records = await db.select(db.healthRecords).get();
      expect(records.length, 1);
      expect(records.first.id, 'hr-1');
      expect(records.first.type, 'diabetes');
      expect(records.first.userId, 42);
    });

    test('insert and read DailyFeeling', () async {
      final feeling = DailyFeeling(
        id: 'df-1',
        updatedAt: DateTime.now().toUtc(),
        date: DateTime(2024, 1, 15).toUtc(),
        feeling: 'good',
        comment: 'Feeling great today!',
        healthRecordId: 1,
      );

      await db.into(db.dailyFeelings).insert(feeling.toInsertable());

      final feelings = await db.select(db.dailyFeelings).get();
      expect(feelings.length, 1);
      expect(feelings.first.id, 'df-1');
      expect(feelings.first.feeling, 'good');
      expect(feelings.first.comment, 'Feeling great today!');
    });

    test('update record', () async {
      final feeling = DailyFeeling(
        id: 'df-update',
        updatedAt: DateTime.now().toUtc(),
        date: DateTime.now().toUtc(),
        feeling: 'bad',
        healthRecordId: 1,
      );

      await db.into(db.dailyFeelings).insert(feeling.toInsertable());

      final updated = DailyFeeling(
        id: 'df-update',
        updatedAt: DateTime.now().toUtc(),
        date: DateTime.now().toUtc(),
        feeling: 'good',
        healthRecordId: 1,
      );

      await db.into(db.dailyFeelings).insertOnConflictUpdate(updated.toInsertable());

      final result = await (db.select(db.dailyFeelings)
            ..where((t) => t.id.equals('df-update')))
          .getSingle();

      expect(result.feeling, 'good');
    });

    test('delete record', () async {
      final feeling = DailyFeeling(
        id: 'df-delete',
        updatedAt: DateTime.now().toUtc(),
        date: DateTime.now().toUtc(),
        feeling: 'neutral',
        healthRecordId: 1,
      );

      await db.into(db.dailyFeelings).insert(feeling.toInsertable());
      expect((await db.select(db.dailyFeelings).get()).length, 1);

      await (db.delete(db.dailyFeelings)..where((t) => t.id.equals('df-delete'))).go();
      expect((await db.select(db.dailyFeelings).get()).length, 0);
    });
  });

  group('SyncDatabaseMixin', () {
    test('enqueue UpsertOp', () async {
      final op = UpsertOp(
        opId: 'op-1',
        kind: 'daily_feeling',
        id: 'df-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'id': 'df-1', 'feeling': 'good'},
      );

      await db.enqueue(op);

      final ops = await db.takeOutbox();
      expect(ops.length, 1);
      expect(ops.first.opId, 'op-1');
      expect(ops.first, isA<UpsertOp>());
      expect((ops.first as UpsertOp).payloadJson['feeling'], 'good');
    });

    test('enqueue DeleteOp', () async {
      final op = DeleteOp(
        opId: 'op-delete-1',
        kind: 'daily_feeling',
        id: 'df-1',
        localTimestamp: DateTime.now().toUtc(),
      );

      await db.enqueue(op);

      final ops = await db.takeOutbox();
      expect(ops.length, 1);
      expect(ops.first, isA<DeleteOp>());
    });

    test('ackOutbox removes operations', () async {
      await db.enqueue(UpsertOp(
        opId: 'op-ack-1',
        kind: 'test',
        id: 'id-1',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {},
      ));
      await db.enqueue(UpsertOp(
        opId: 'op-ack-2',
        kind: 'test',
        id: 'id-2',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {},
      ));

      expect((await db.takeOutbox()).length, 2);

      await db.ackOutbox(['op-ack-1']);

      final remaining = await db.takeOutbox();
      expect(remaining.length, 1);
      expect(remaining.first.opId, 'op-ack-2');
    });

    test('cursor operations', () async {
      final cursor = Cursor(ts: DateTime.utc(2024, 6, 15, 12, 0), lastId: 'last-1');

      await db.setCursor('daily_feeling', cursor);

      final retrieved = await db.getCursor('daily_feeling');
      expect(retrieved, isNotNull);
      expect(retrieved!.lastId, 'last-1');
      expect(retrieved.ts.year, 2024);
      expect(retrieved.ts.month, 6);
    });

    test('getCursor returns null for unknown kind', () async {
      final cursor = await db.getCursor('unknown_kind');
      expect(cursor, isNull);
    });

    test('takeOutbox respects limit', () async {
      for (var i = 0; i < 10; i++) {
        await db.enqueue(UpsertOp(
          opId: 'op-limit-$i',
          kind: 'test',
          id: 'id-$i',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {},
        ));
      }

      final ops = await db.takeOutbox(limit: 3);
      expect(ops.length, 3);
    });
  });

  group('JSON Serialization', () {
    test('DailyFeeling fromJson/toJson', () {
      final json = {
        'id': 'json-1',
        'updated_at': '2024-01-15T10:30:00.000Z',
        'date': '2024-01-15T00:00:00.000Z',
        'feeling': 'excellent',
        'comment': 'Great day!',
        'health_record_id': 5,
      };

      final feeling = DailyFeeling.fromJson(json);
      expect(feeling.id, 'json-1');
      expect(feeling.feeling, 'excellent');
      expect(feeling.healthRecordId, 5);

      final backToJson = feeling.toJson();
      expect(backToJson['id'], 'json-1');
      expect(backToJson['feeling'], 'excellent');
    });

    test('HealthRecord fromJson/toJson', () {
      final json = {
        'id': 'hr-json-1',
        'updated_at': '2024-01-15T10:30:00.000Z',
        'type': 'blood_pressure',
        'user_id': 100,
      };

      final record = HealthRecord.fromJson(json);
      expect(record.id, 'hr-json-1');
      expect(record.type, 'blood_pressure');
      expect(record.userId, 100);
    });
  });
}

