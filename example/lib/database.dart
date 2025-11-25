import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:example/models/daily_feeling.dart';
import 'package:example/models/health_record.dart';
import 'package:path/path.dart' as p;
import 'package:synchronize_cache/synchronize_cache.dart';

part 'database.g.dart';

/// Локальное определение таблицы SyncOutbox для Drift.
/// Использует типы из пакета synchronize_cache.
@UseRowClass(SyncOutboxData)
class SyncOutboxLocal extends Table {
  TextColumn get opId => text()();
  TextColumn get kind => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get ts => integer()();
  IntColumn get tryCount => integer().withDefault(const Constant(0))();
  IntColumn get baseUpdatedAt => integer().nullable()();
  TextColumn get changedFields => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};

  @override
  String get tableName => 'sync_outbox';
}

/// Локальное определение таблицы SyncCursors для Drift.
/// Использует типы из пакета synchronize_cache.
@UseRowClass(SyncCursorsData)
class SyncCursorsLocal extends Table {
  TextColumn get kind => text()();
  IntColumn get ts => integer()();
  TextColumn get lastId => text()();

  @override
  Set<Column> get primaryKey => {kind};

  @override
  String get tableName => 'sync_cursors';
}

/// База данных приложения с поддержкой синхронизации.
@DriftDatabase(tables: [
  HealthRecords,
  DailyFeelings,
  SyncOutboxLocal,
  SyncCursorsLocal,
])
class AppDatabase extends _$AppDatabase with SyncDatabaseMixin {
  AppDatabase(super.e);

  AppDatabase._(super.e);

  /// Открыть базу данных в файле.
  static Future<AppDatabase> open({String filename = 'app.db'}) async {
    final dir = Directory.current.path;
    final file = File(p.join(dir, filename));
    final executor = NativeDatabase(file);
    return AppDatabase._(executor);
  }

  /// Создать in-memory базу данных (для тестов).
  static AppDatabase inMemory() {
    return AppDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA journal_mode=WAL;');
          await customStatement('PRAGMA synchronous=NORMAL;');
        },
      );
}
