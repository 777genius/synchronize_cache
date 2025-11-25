# Offline-first Cache

Система для оффлайн работы с данными. Читаем локально, пишем локально + складываем операции в outbox, синхронизируемся с бэком когда надо.

## Что тут есть

- **synchronize_cache** — основная библиотека синхронизации: SyncEngine, Outbox, Cursors, Conflict Resolution
- **synchronize_cache_rest** — REST транспорт для API
- **example/** — рабочий пример использования

Принцип простой: читаем всегда локально, пишем локально + в очередь на отправку, sync() делает push (отправка) потом pull (загрузка).

## Как начать

```bash
cd cache_workspace
dart pub get
```

Базовая настройка:

```dart
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';

// База данных должна реализовать SyncDatabaseMixin
@DriftDatabase(tables: [MyEntities, SyncOutbox, SyncCursors])
class AppDatabase extends _$AppDatabase with SyncDatabaseMixin {
  // ...
}

// Транспорт для API
final transport = RestTransport(
  base: Uri.parse('https://api.example.com'),
  token: () async => 'Bearer токен_тут',
);

// Движок синхронизации
final engine = SyncEngine(
  db: db,
  transport: transport,
  tables: [
    SyncableTable<MyEntity>(
      kind: 'my_entity',
      table: db.myEntities,
      fromJson: MyEntity.fromJson,
      toJson: (e) => e.toJson(),
      toInsertable: (e) => e.toInsertable(),
    ),
  ],
);

// Синхронизируем
await engine.sync();
```

Работа с данными:

```dart
// Добавление в очередь на отправку
await db.enqueue(UpsertOp(
  opId: uuid.v4(),
  kind: 'my_entity',
  id: entity.id,
  localTimestamp: DateTime.now().toUtc(),
  payloadJson: entity.toJson(),
));
```

## Conflict Resolution

Система поддерживает несколько стратегий разрешения конфликтов. По умолчанию используется **autoPreserve** — автоматическое слияние без потери данных.

### Стратегии

- **autoPreserve** (по умолчанию) — умный merge: сохраняет все данные, объединяет списки, не теряет ни локальные ни серверные изменения
- **serverWins** — серверная версия всегда побеждает
- **clientWins** — клиентская версия всегда побеждает (forcePush)
- **lastWriteWins** — побеждает версия с более поздним timestamp
- **merge** — автоматическое слияние данных через кастомную функцию
- **manual** — ручное разрешение через callback

### autoPreserve — как это работает

При конфликте `autoPreserve`:

1. Берёт серверные данные как базу
2. Применяет локальные изменения поверх (только изменённые поля если указаны `changedFields`)
3. Для списков — объединяет (union) без дубликатов
4. Для вложенных объектов — рекурсивно мержит
5. Системные поля (`id`, `updatedAt`, `createdAt`) всегда берёт с сервера
6. Отправляет объединённые данные на сервер с force-update

```dart
// Пример
// Локальные данные: {mood: 5, notes: "My notes"}
// Серверные данные: {mood: 3, energy: 7}
// Результат merge:  {mood: 5, energy: 7, notes: "My notes"}
```

### Отслеживание изменённых полей

Для точного merge можно указать какие поля изменил пользователь:

```dart
await db.enqueue(UpsertOp(
  opId: uuid(),
  kind: 'daily_feeling',
  id: 'feeling-123',
  localTimestamp: DateTime.now().toUtc(),
  payloadJson: {'id': 'feeling-123', 'mood': 5, 'energy': 7},
  baseUpdatedAt: lastSyncTime,     // когда данные были получены с сервера
  changedFields: {'mood'},         // пользователь изменил только mood
));
```

Если `changedFields` указан — при merge применяются только эти поля из локальных данных.

### Настройка

```dart
final engine = SyncEngine(
  db: db,
  transport: transport,
  tables: [...],
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.autoPreserve, // по умолчанию
    maxConflictRetries: 3,
    conflictRetryDelay: Duration(milliseconds: 500),
    skipConflictingOps: false,
  ),
);
```

### Ручное разрешение

```dart
final engine = SyncEngine(
  db: db,
  transport: transport,
  tables: [...],
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.manual,
    conflictResolver: (conflict) async {
      // conflict содержит:
      // - kind, entityId, opId
      // - localData, serverData
      // - localTimestamp, serverTimestamp
      // - serverVersion
      // - changedFields (если были указаны)
      
      // Варианты разрешения:
      return AcceptServer();      // принять серверную версию
      return AcceptClient();      // принять клиентскую версию  
      return AcceptMerged({...}); // использовать объединённые данные
      return DeferResolution();   // отложить (оставить в outbox)
      return DiscardOperation();  // отменить операцию
    },
  ),
);
```

### Кастомное слияние данных

```dart
final engine = SyncEngine(
  db: db,
  transport: transport,
  tables: [...],
  config: SyncConfig(
    conflictStrategy: ConflictStrategy.merge,
    mergeFunction: (local, server) {
      // Кастомная логика слияния
      return {...server, ...local};
    },
  ),
);

// Встроенные утилиты:
ConflictUtils.defaultMerge(local, server);    // server + локальные изменения
ConflictUtils.deepMerge(local, server);       // глубокое слияние для вложенных объектов
ConflictUtils.preservingMerge(local, server); // умный merge с информацией об источниках
```

### Настройка для отдельных таблиц

```dart
final engine = SyncEngine(
  db: db,
  transport: transport,
  tables: [...],
  config: const SyncConfig(
    conflictStrategy: ConflictStrategy.autoPreserve, // глобальная стратегия
  ),
  tableConflictConfigs: {
    'important_data': const TableConflictConfig(
      strategy: ConflictStrategy.clientWins, // для этой таблицы
    ),
    'user_settings': TableConflictConfig(
      strategy: ConflictStrategy.merge,
      mergeFunction: customMergeSettings,
    ),
  },
);
```

### События конфликтов

```dart
engine.events.listen((event) {
  if (event is ConflictDetectedEvent) {
    print('Конфликт: ${event.conflict.kind}/${event.conflict.entityId}');
    print('Стратегия: ${event.strategy}');
  }
  
  if (event is DataMergedEvent) {
    print('Данные объединены: ${event.kind}/${event.entityId}');
    print('Локальные поля: ${event.localFields}');
    print('Серверные поля: ${event.serverFields}');
  }
  
  if (event is ConflictResolvedEvent) {
    print('Разрешён: ${event.resolution.runtimeType}');
    print('Результат: ${event.resultData}');
  }
  
  if (event is ConflictUnresolvedEvent) {
    print('Не разрешён: ${event.reason}');
  }
});
```

### Статистика синхронизации

```dart
final stats = await engine.sync();
print('Отправлено: ${stats.pushed}');
print('Получено: ${stats.pulled}');
print('Конфликтов: ${stats.conflicts}');
print('Разрешено: ${stats.conflictsResolved}');
print('Ошибок: ${stats.errors}');
```

## Минимум от бэка

В каждой сущности должно быть поле updatedAt в UTC. deletedAt если поддерживаете удаления.

### Эндпоинты

```
GET  /{kind}?updatedSince=...&limit=...&afterId=...&includeDeleted=true
POST /{kind}
PUT  /{kind}/{id}
DELETE /{kind}/{id}
```

### Формат запроса с детекцией конфликтов

Клиент отправляет `_baseUpdatedAt` — timestamp когда данные были получены с сервера:

```json
PUT /daily_feeling/abc-123
{
  "id": "abc-123",
  "mood": 5,
  "energy": 7,
  "_baseUpdatedAt": "2025-01-15T10:00:00Z"
}
```

### Логика сервера (PUT)

```python
@app.put("/{kind}/{id}")
def update(kind: str, id: str, data: dict):
    existing = db.get(kind, id)
    
    if not existing:
        return Response(404, {"error": "not_found"})
    
    # Проверка конфликта по _baseUpdatedAt
    base_updated = data.pop('_baseUpdatedAt', None)
    if base_updated:
        base_dt = parse_datetime(base_updated)
        if existing.updated_at > base_dt:
            # Конфликт! Клиент работал с устаревшими данными
            return Response(409, {
                "error": "conflict",
                "current": existing.to_dict()
            })
    
    # Нет конфликта — обновляем
    existing.update(data)
    existing.updated_at = utcnow()  # Серверное время!
    db.save(existing)
    
    return Response(200, existing.to_dict())
```

### Формат ответа 409 Conflict

```json
{
  "error": "conflict",
  "current": {
    "id": "abc-123",
    "mood": 4,
    "energy": 7,
    "notes": null,
    "updatedAt": "2025-01-15T11:30:00Z"
  }
}
```

### Force-update (после merge)

После merge клиент отправляет объединённые данные с заголовком `X-Force-Update: true`:

```
PUT /daily_feeling/abc-123
X-Force-Update: true
X-Idempotency-Key: op-uuid-123

{
  "id": "abc-123",
  "mood": 5,
  "energy": 7
}
```

Сервер должен принять данные без проверки `_baseUpdatedAt`.

### Идемпотентность

Сервер должен проверять заголовок `X-Idempotency-Key`:
- Если операция с таким ключом уже выполнена — вернуть тот же результат
- Хранить ключи 24 часа

### Загрузка данных (GET)

```
GET /health_record?updatedSince=2025-09-01T00:00:00Z&limit=500&includeDeleted=true&afterId=xyz
```

Сервер должен возвращать:
```json
{
  "items": [...],
  "nextPageToken": "следующая_страница"
}
```

Сортировка: `ORDER BY updatedAt ASC, id ASC`.

## Идеальный бэк

- POST /{kind}/bulk для массовой отправки
- ETag или Last-Modified для кэширования
- Поток томбстоунов для удалений
- Retry-After для rate limiting
- GET /health для проверки
- Gzip сжатие
- 409 Conflict с текущими данными при конфликте версий
- Идемпотентность через X-Idempotency-Key
- Force-update через X-Force-Update заголовок

## Стабильная пагинация

Чтобы не терять данные при загрузке, сервер должен фильтровать так:

```sql
WHERE (updatedAt > :ts) OR (updatedAt = :ts AND id > :id)
ORDER BY updatedAt ASC, id ASC
LIMIT :limit
```

## Логи и события

SyncEngine.events дает события: старт синка, прогресс, завершение, ошибки, конфликты, merge, обновления кэша.

## Flow синхронизации

```
1. Пользователь редактирует запись
   → Сохраняем: payload, baseUpdatedAt (когда получили), changedFields

2. sync() → push
   → Отправляем payload + _baseUpdatedAt
   
3. Сервер проверяет
   → if (db.updated_at > _baseUpdatedAt) return 409 + current data
   → else update + return 200

4. Клиент получает 409
   → preservingMerge(localData, serverData, changedFields)
   → Повторный push с merged данными (X-Force-Update: true)

5. Сервер принимает
   → Обновляет запись
   → Возвращает 200

6. Клиент сохраняет результат локально
   → Удаляет из outbox
```
