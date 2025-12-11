// ignore_for_file: avoid_print

import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';

part 'example.g.dart';

// Model
class Todo {
  final String id;
  final String title;
  final bool completed;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;

  Todo({
    required this.id,
    required this.title,
    required this.completed,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
  });

  factory Todo.fromJson(Map<String, dynamic> json) => Todo(
        id: json['id'] as String,
        title: json['title'] as String,
        completed: json['completed'] as bool,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        deletedAtLocal: json['deleted_at_local'] != null
            ? DateTime.parse(json['deleted_at_local'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'completed': completed,
        'updated_at': updatedAt.toIso8601String(),
        if (deletedAt != null) 'deleted_at': deletedAt!.toIso8601String(),
        if (deletedAtLocal != null)
          'deleted_at_local': deletedAtLocal!.toIso8601String(),
      };

  TodosCompanion toInsertable() => TodosCompanion.insert(
        id: id,
        title: title,
        completed: completed,
        updatedAt: updatedAt,
        deletedAt: Value(deletedAt),
        deletedAtLocal: Value(deletedAtLocal),
      );
}

// Table with SyncColumns
@UseRowClass(Todo, generateInsertable: true)
class Todos extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get title => text()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// Database
@DriftDatabase(
  include: {'package:offline_first_sync_drift/src/sync_tables.drift'},
  tables: [Todos],
)
class AppDatabase extends _$AppDatabase with SyncDatabaseMixin {
  AppDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

Future<void> main() async {
  final db = AppDatabase();

  // Configure REST transport
  final transport = RestTransport(
    base: Uri.parse('https://api.example.com'),
    token: () async => 'Bearer your-token-here',
    backoffMin: const Duration(seconds: 1),
    backoffMax: const Duration(minutes: 2),
    maxRetries: 5,
    pushConcurrency: 5, // Parallel push for better performance
  );

  // Create SyncEngine with REST transport
  final engine = SyncEngine(
    db: db,
    transport: transport,
    tables: [
      SyncableTable<Todo>(
        kind: 'todo',
        table: db.todos,
        fromJson: Todo.fromJson,
        toJson: (t) => t.toJson(),
        toInsertable: (t) => t.toInsertable(),
      ),
    ],
    config: const SyncConfig(
      conflictStrategy: ConflictStrategy.autoPreserve,
    ),
  );

  // Listen to events
  final subscription = engine.events.listen((event) {
    switch (event) {
      case SyncStarted(:final phase):
        print('Sync started: $phase');
      case SyncCompleted(:final stats):
        print('Sync completed: pushed=${stats.pushed}, pulled=${stats.pulled}');
      case ConflictDetectedEvent(:final conflict, :final strategy):
        print('Conflict on ${conflict.entityId}, strategy: $strategy');
      case ConflictResolvedEvent(:final conflict, :final resolution):
        print('Conflict resolved: ${conflict.entityId} -> $resolution');
      case SyncErrorEvent(:final error):
        print('Error: $error');
      default:
        break;
    }
  });

  // Create a todo locally
  final todo = Todo(
    id: 'todo-1',
    title: 'Learn offline_first_sync_drift',
    completed: false,
    updatedAt: DateTime.now().toUtc(),
  );

  await db.into(db.todos).insert(todo.toInsertable());
  print('Created todo: ${todo.id}');

  // Add to outbox for sync
  await db.enqueue(UpsertOp(
    opId: 'op-1',
    kind: 'todo',
    id: todo.id,
    localTimestamp: DateTime.now().toUtc(),
    payloadJson: todo.toJson(),
  ));
  print('Added to outbox');

  // Sync (will fail without real server, but demonstrates usage)
  try {
    final stats = await engine.sync();
    print('Sync stats: pushed=${stats.pushed}, pulled=${stats.pulled}');
  } catch (e) {
    print('Sync failed (expected without server): $e');
  }

  // Cleanup
  await subscription.cancel();
  engine.dispose();
  await db.close();
}





