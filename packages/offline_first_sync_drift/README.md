# offline_first_sync_drift

Offline-first synchronization library for Dart/Flutter applications built on top of [Drift](https://pub.dev/packages/drift). Provides local caching with background sync to remote servers, conflict resolution, and full resync capabilities.

## Features

- 🔄 **Offline-first architecture** - Read/write locally, sync in background
- 💾 **Drift integration** - Works seamlessly with Drift ORM
- ⚔️ **Conflict resolution** - Multiple strategies including smart merge
- 📦 **Outbox pattern** - Reliable operation queuing
- 📊 **Events stream** - Monitor sync progress in real-time
- 🔁 **Full resync** - Periodic or manual data refresh

## Installation

```yaml
dependencies:
  offline_first_sync_drift: ^0.1.0
  drift: ^2.26.0

dev_dependencies:
  drift_dev: ^2.26.0
  build_runner: ^2.4.0
```

Add `build.yaml` for modular generation:

```yaml
targets:
  $default:
    builders:
      drift_dev:
        enabled: false
      drift_dev:analyzer:
        enabled: true
        options: &options
          store_date_time_values_as_text: true
      drift_dev:modular:
        enabled: true
        options: *options
```

## Quick Start

### 1. Define your table with sync columns

```dart
import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

@UseRowClass(DailyFeeling, generateInsertable: true)
class DailyFeelings extends Table with SyncColumns {
  TextColumn get id => text()();
  IntColumn get mood => integer().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get date => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

### 2. Configure your database

```dart
@DriftDatabase(
  include: {'package:offline_first_sync_drift/src/sync_tables.drift'},
  tables: [DailyFeelings],
)
class AppDatabase extends _$AppDatabase with SyncDatabaseMixin {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
```

### 3. Create SyncEngine

```dart
final engine = SyncEngine(
  db: db,
  transport: yourTransport,  // See offline_first_sync_drift_rest
  tables: [
    SyncableTable<DailyFeeling>(
      kind: 'daily_feeling',
      table: db.dailyFeelings,
      fromJson: DailyFeeling.fromJson,
      toJson: (e) => e.toJson(),
      toInsertable: (e) => e.toInsertable(),
    ),
  ],
);
```

### 4. Local operations + outbox

```dart
// Create
await db.into(db.dailyFeelings).insert(feeling.toInsertable());
await db.enqueue(UpsertOp(
  opId: uuid.v4(),
  kind: 'daily_feeling',
  id: feeling.id,
  localTimestamp: DateTime.now().toUtc(),
  payloadJson: feeling.toJson(),
));

// Sync
final stats = await engine.sync();
print('Pushed: ${stats.pushed}, Pulled: ${stats.pulled}');
```

## Conflict Resolution

| Strategy | Description |
|----------|-------------|
| `autoPreserve` | **(default)** Smart merge - preserves all data |
| `serverWins` | Server version wins |
| `clientWins` | Client version wins (force push) |
| `lastWriteWins` | Latest timestamp wins |
| `merge` | Custom merge function |
| `manual` | Manual resolution via callback |

```dart
final engine = SyncEngine(
  // ...
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.autoPreserve,
  ),
);
```

## Events

```dart
engine.events.listen((event) {
  switch (event) {
    case SyncStarted(:final phase):
      print('Started: $phase');
    case SyncCompleted(:final stats):
      print('Done: pushed=${stats.pushed}, pulled=${stats.pulled}');
    case ConflictDetectedEvent(:final conflict):
      print('Conflict: ${conflict.entityId}');
    case SyncErrorEvent(:final error):
      print('Error: $error');
  }
});
```

## Transports

This package defines the `TransportAdapter` interface. Use one of the implementations:

- [`offline_first_sync_drift_rest`](https://pub.dev/packages/offline_first_sync_drift_rest) - REST API transport

## Additional Information

- [GitHub Repository](https://github.com/cherrypick-agency/offline_first_sync_drift)
- [API Documentation](https://pub.dev/documentation/offline_first_sync_drift/latest/)
- [Issue Tracker](https://github.com/cherrypick-agency/offline_first_sync_drift/issues)
