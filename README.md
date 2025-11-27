# Offline-first Cache Sync

[![CI](https://github.com/cherrypick-agency/synchronize_cache/actions/workflows/ci.yml/badge.svg)](https://github.com/cherrypick-agency/synchronize_cache/actions/workflows/ci.yml)
![coverage](https://img.shields.io/badge/coverage-52.8%25-yellow)

Dart/Flutter библиотека для offline-first работы с данными. Локальный кэш на Drift + синхронизация с сервером.

**Принцип:** читаем локально → пишем локально + в outbox → sync() отправляет и получает данные.

## Содержание

- [Offline-first Cache Sync](#offline-first-cache-sync)
  - [Содержание](#содержание)
  - [Быстрый старт](#быстрый-старт)
    - [1. Установка](#1-установка)
    - [2. Настройка базы данных](#2-настройка-базы-данных)
    - [3. Настройка SyncEngine](#3-настройка-syncengine)
    - [4. Модель данных](#4-модель-данных)
  - [Работа с данными](#работа-с-данными)
    - [Чтение](#чтение)
    - [Локальные изменения + outbox](#локальные-изменения--outbox)
    - [Синхронизация](#синхронизация)
  - [Разрешение конфликтов](#разрешение-конфликтов)
    - [Стратегии](#стратегии)
    - [autoPreserve](#autopreserve)
    - [Ручное разрешение](#ручное-разрешение)
    - [Кастомный merge](#кастомный-merge)
    - [Стратегия для отдельных таблиц](#стратегия-для-отдельных-таблиц)
  - [События и статистика](#события-и-статистика)
  - [Требования к серверу](#требования-к-серверу)
  - [CI/CD](#cicd)

---

## Быстрый старт

Минимальный чеклист: ставим пакеты, готовим Drift-базу с `include` для sync таблиц, затем регистрируем свои таблицы в `SyncEngine`.

### 1. Установка

```yaml
dependencies:
  offline_first_sync_drift: ^0.1.1
  offline_first_sync_drift_rest: ^0.1.1
  drift: ^2.0.0
  json_annotation: ^4.8.0

dev_dependencies:
  drift_dev: ^2.0.0
  build_runner: ^2.0.0
  json_serializable: ^6.7.0
```

**build.yaml** (требуется modular generation для межпакетного шаринга):

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

### 2. Настройка базы данных

1. Описываем свои доменные таблицы и добавляем `SyncColumns`, чтобы автоматом получить `updatedAt/deletedAt/deletedAtLocal`.
2. Подключаем sync таблицы через `include` — это автоматически добавит `sync_outbox` и `sync_cursors`.
3. Наследуем `SyncDatabaseMixin`, который даёт `enqueue()`, `takeOutbox()`, `setCursor()` и другие утилиты.

```dart
import 'package:drift/drift.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

import 'database.drift.dart';
import 'models/daily_feeling.dart'; // см. секцию "Модель данных"

@DriftDatabase(
  include: {'package:offline_first_sync_drift/src/sync_tables.drift'},
  tables: [DailyFeelings],
)
class AppDatabase extends $AppDatabase with SyncDatabaseMixin {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;
}
```

### 3. Настройка SyncEngine

SyncEngine связывает локальную БД и транспорт. В `tables` перечисляем каждую сущность: `kind` - имя на сервере, `table` - ссылка на Drift-таблицу, `fromJson`/`toJson` - преобразования между локальной моделью и API.

```dart
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';

final transport = RestTransport(
  base: Uri.parse('https://api.example.com'),
  token: () async => 'Bearer ${await getToken()}',
);

final engine = SyncEngine(
  db: db,
  transport: transport,
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

### 4. Модель данных

Для участия в синхронизации таблица должна:

- иметь строковый первичный ключ `id`;
- хранить `updatedAt` в UTC (сервер обновляет это поле сам);
- опционально иметь `deletedAt` для soft-delete и `deletedAtLocal` для локальных пометок;
- содержать любые ваши бизнес-поля.

Добавьте `SyncColumns`, и все обязательные системные поля появятся автоматически - вам останется описать только доменные колонки. Таблица при этом автоматически реализует `SynchronizableTable`, так что можно типобезопасно отличать её от обычных Drift таблиц:

```dart
import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

part 'daily_feeling.g.dart';

/// Модель данных (row class).
@JsonSerializable(fieldRename: FieldRename.snake)
class DailyFeeling {
  DailyFeeling({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.date,
    this.mood,
    this.energy,
    this.notes,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final DateTime date;
  final int? mood;
  final int? energy;
  final String? notes;

  factory DailyFeeling.fromJson(Map<String, dynamic> json) =>
      _$DailyFeelingFromJson(json);

  Map<String, dynamic> toJson() => _$DailyFeelingToJson(this);

  // toInsertable() генерируется автоматически благодаря generateInsertable: true
}

/// Drift-таблица со всеми sync-полями.
@UseRowClass(DailyFeeling, generateInsertable: true)
class DailyFeelings extends Table with SyncColumns {
  TextColumn get id => text()();
  IntColumn get mood => integer().nullable()();
  IntColumn get energy => integer().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get date => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

---

## Работа с данными

Читаем как обычный Drift-слой, а при изменениях придерживаемся паттерна «локально обновили → положили операцию в outbox».

### Чтение

Работаем с Drift как обычно: все данные уже в локальной БД, запросы мгновенные и офлайн-friendly.

```dart
final all = await db.select(db.dailyFeelings).get();

final today = await (db.select(db.dailyFeelings)
  ..where((t) => t.date.equals(DateTime.now())))
  .getSingleOrNull();

db.select(db.dailyFeelings).watch().listen((list) {
  setState(() => _feelings = list);
});
```

### Локальные изменения + outbox

Каждая операция состоит из двух шагов: сначала меняем локальную таблицу, потом ставим операцию в очередь через `db.enqueue(...)`. Для апдейтов обязательно отправляем `baseUpdatedAt` (когда запись пришла с сервера) и `changedFields` (какие поля правил пользователь).

```dart
Future<void> create(DailyFeeling feeling) async {
  await db.into(db.dailyFeelings).insert(feeling);
  
  await db.enqueue(UpsertOp(
    opId: uuid.v4(),
    kind: 'daily_feeling',
    id: feeling.id,
    localTimestamp: DateTime.now().toUtc(),
    payloadJson: feeling.toJson(),
  ));
}

Future<void> updateFeeling(DailyFeeling updated, Set<String> changedFields) async {
  await db.update(db.dailyFeelings).replace(updated);
  
  await db.enqueue(UpsertOp(
    opId: uuid.v4(),
    kind: 'daily_feeling',
    id: updated.id,
    localTimestamp: DateTime.now().toUtc(),
    payloadJson: updated.toJson(),
    baseUpdatedAt: updated.updatedAt,
    changedFields: changedFields,
  ));
}

Future<void> deleteFeeling(String id, DateTime? serverUpdatedAt) async {
  await (db.delete(db.dailyFeelings)..where((t) => t.id.equals(id))).go();
  
  await db.enqueue(DeleteOp(
    opId: uuid.v4(),
    kind: 'daily_feeling',
    id: id,
    localTimestamp: DateTime.now().toUtc(),
    baseUpdatedAt: serverUpdatedAt,
  ));
}
```

### Синхронизация

Вручную вызываем `sync()` когда нужно (pull/push/merge), либо включаем авто-таймер. Можно ограничивать список `kind`, если нужно обновить только часть данных.

```dart
// Вручную
final stats = await engine.sync();

// Автоматически каждые 5 минут
engine.startAuto(interval: Duration(minutes: 5));
engine.stopAuto();

// Для конкретных таблиц
await engine.sync(kinds: {'daily_feeling', 'health_record'});
```

---

## Разрешение конфликтов

Конфликт возникает когда данные изменились и на клиенте, и на сервере. Поведение задаём через `SyncConfig(conflictStrategy: ...)` глобально либо `tableConflictConfigs` для отдельных таблиц.

### Стратегии

| Стратегия | Описание |
|-----------|----------|
| `autoPreserve` | **(по умолчанию)** Умный merge - сохраняет все данные |
| `serverWins` | Серверная версия побеждает |
| `clientWins` | Клиентская версия побеждает (force push) |
| `lastWriteWins` | Побеждает более поздний timestamp |
| `merge` | Кастомная функция слияния |
| `manual` | Ручное разрешение через callback |

### autoPreserve

Стратегия по умолчанию - объединяет данные без потерь:

```dart
// Локально: {mood: 5, notes: "My notes"}
// На сервере: {mood: 3, energy: 7}
// Результат:  {mood: 5, energy: 7, notes: "My notes"}
```

Как работает:
1. Берёт серверные данные как базу
2. Применяет локальные изменения (только `changedFields` если указаны)
3. Списки объединяет без дубликатов
4. Вложенные объекты мержит рекурсивно
5. Системные поля (`id`, `updatedAt`, `createdAt`) берёт с сервера
6. Отправляет результат с `X-Force-Update: true`

### Ручное разрешение

```dart
final engine = SyncEngine(
  // ...
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.manual,
    conflictResolver: (conflict) async {
      // Показать диалог пользователю или решить программно
      final choice = await showConflictDialog(conflict);
      
      return switch (choice) {
        'server' => AcceptServer(),
        'client' => AcceptClient(),
        'merge'  => AcceptMerged({...}),
        'defer'  => DeferResolution(),
        _        => DiscardOperation(),
      };
    },
  ),
);
```

### Кастомный merge

```dart
final engine = SyncEngine(
  // ...
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.merge,
    mergeFunction: (local, server) {
      return {...server, ...local};
    },
  ),
);

// Встроенные утилиты
ConflictUtils.defaultMerge(local, server);
ConflictUtils.deepMerge(local, server);
ConflictUtils.preservingMerge(local, server, changedFields: {'mood'});
```

### Стратегия для отдельных таблиц

```dart
final engine = SyncEngine(
  // ...
  tableConflictConfigs: {
    'user_settings': TableConflictConfig(
      strategy: ConflictStrategy.clientWins,
    ),
  },
);
```

---

## События и статистика

SyncEngine шлёт поток событий, который удобно использовать для UI-индикаторов, логирования и метрик.

```dart
// Подписка на события
engine.events.listen((event) {
  switch (event) {
    case SyncStarted(:final phase):
      print('Начало: $phase');
    case SyncProgress(:final done, :final total):
      print('Прогресс: $done/$total');
    case SyncCompleted(:final stats):
      print('Готово: pushed=${stats.pushed}, pulled=${stats.pulled}');
    case ConflictDetectedEvent(:final conflict):
      print('Конфликт: ${conflict.entityId}');
    case SyncErrorEvent(:final error):
      print('Ошибка: $error');
  }
});

// Статистика после sync
final stats = await engine.sync();
print('Отправлено: ${stats.pushed}');
print('Получено: ${stats.pulled}');
print('Конфликтов: ${stats.conflicts}');
print('Разрешено: ${stats.conflictsResolved}');
print('Ошибок: ${stats.errors}');
```

---

## Требования к серверу

Сервер обязан поддерживать предсказуемый REST-контракт: идемпотентные PUT-запросы, стабильную пагинацию и проверку конфликтов по `updatedAt`. Полное руководство с примерами и чеклистом см. в [`docs/backend_guidelines.md`](docs/backend_guidelines.md).

Краткое напоминание:

- реализуйте CRUD-эндпоинты `/{kind}` с фильтрами `updatedSince`, `afterId`, `limit`, `includeDeleted`;
- держите `updatedAt` и (опционально) `deletedAt`, выставляя системные поля на сервере;
- при PUT проверяйте `_baseUpdatedAt`, возвращайте `409` с текущими данными и поддерживайте `X-Force-Update` + `X-Idempotency-Key`;
- отдавайте списки в формате `{ "items": [...], "nextPageToken": "..." }`, строя курсор по `(updatedAt, id)`;
- ориентируйтесь на e2e-пример в `packages/offline_first_sync_drift_rest/test/e2e`, если нужна референсная реализация.

---

## CI/CD

GitHub Actions пайплайн `.github/workflows/ci.yml` гоняет `dart analyze` и тесты для всех пакетов воркспейса (`packages/offline_first_sync_drift`, `packages/offline_first_sync_drift_rest`, `example`) на каждом push и pull request в ветки `main`/`master`. Локально можно повторить те же проверки командами:

```bash
dart pub get
dart analyze .
dart test packages/offline_first_sync_drift
dart test packages/offline_first_sync_drift_rest
dart test
```
