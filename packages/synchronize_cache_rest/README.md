# synchronize_cache_rest

REST транспорт для [synchronize_cache](../synchronize_cache).

## Установка

```yaml
dependencies:
  synchronize_cache_rest:
    path: ../synchronize_cache_rest
```

## Использование

### RestTransport

```dart
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';

final transport = RestTransport(
  base: Uri.parse('https://api.example.com'),
  token: () async => 'Bearer ${await getAccessToken()}',
  backoffMin: const Duration(seconds: 1),
  backoffMax: const Duration(minutes: 2),
  maxRetries: 5,
);

final engine = SyncEngine(
  db: database,
  transport: transport,
  tables: [/* ... */],
);
```

### Параметры

| Параметр | Тип | Описание |
|----------|-----|----------|
| `base` | `Uri` | Базовый URL API |
| `token` | `Future<String> Function()` | Провайдер токена авторизации |
| `client` | `http.Client?` | HTTP клиент (опционально) |
| `backoffMin` | `Duration` | Минимальная задержка retry (default: 1s) |
| `backoffMax` | `Duration` | Максимальная задержка retry (default: 2m) |
| `maxRetries` | `int` | Максимум попыток (default: 5) |

## REST API Contract

### Endpoints

| Метод | URL | Описание |
|-------|-----|----------|
| `GET` | `/{kind}` | Pull с пагинацией |
| `GET` | `/{kind}/{id}` | Fetch одной сущности |
| `POST` | `/{kind}` | Создание (id генерируется сервером) |
| `PUT` | `/{kind}/{id}` | Обновление |
| `DELETE` | `/{kind}/{id}` | Удаление |
| `GET` | `/health` | Health check |

### Query Parameters (Pull)

```
GET /daily_feeling?updatedSince=2024-01-01T00:00:00Z&limit=100&includeDeleted=true
```

| Параметр | Описание |
|----------|----------|
| `updatedSince` | ISO8601 timestamp |
| `limit` | Размер страницы |
| `pageToken` | Токен следующей страницы |
| `afterId` | ID для курсорной пагинации |
| `includeDeleted` | Включать soft-deleted |

### Response Format (Pull)

```json
{
  "items": [
    {"id": "123", "name": "...", "updated_at": "..."}
  ],
  "nextPageToken": "abc123"
}
```

### Conflict Detection

При обновлении клиент передаёт `_baseUpdatedAt`:

```json
PUT /daily_feeling/123
{
  "name": "Updated",
  "_baseUpdatedAt": "2024-01-01T12:00:00Z"
}
```

Сервер сравнивает с текущим `updated_at`. При несовпадении — `409 Conflict`:

```json
{
  "error": "conflict",
  "current": {"id": "123", "name": "Server version", "updated_at": "..."},
  "serverTimestamp": "2024-01-01T12:30:00Z"
}
```

### Force Push Headers

| Header | Значение | Описание |
|--------|----------|----------|
| `X-Force-Update` | `true` | Принудительное обновление |
| `X-Force-Delete` | `true` | Принудительное удаление |
| `X-Idempotency-Key` | `{opId}` | Идемпотентность операций |

## E2E Тестирование

Пакет включает `TestServer` для e2e тестов:

```dart
import 'package:synchronize_cache_rest/test/e2e/helpers/test_server.dart';

late TestServer server;

setUp(() async {
  server = TestServer();
  await server.start();
});

tearDown(() async {
  await server.stop();
});

test('conflict resolution', () async {
  // Seed данные
  server.seed('entity', {
    'id': 'e1',
    'name': 'Original',
    'updated_at': DateTime.utc(2024, 1, 1).toIso8601String(),
  });
  
  // Симуляция конкурентного изменения
  server.update('entity', 'e1', {'name': 'Server Modified'});
  
  // Тест...
  
  // Проверка
  final data = server.get('entity', 'e1');
  expect(data?['name'], 'Expected Value');
});
```

### TestServer API

```dart
// Данные
server.seed(kind, data);           // Добавить сущность
server.update(kind, id, data);     // Обновить напрямую
server.get(kind, id);              // Получить сущность
server.getAll(kind);               // Получить все по kind
server.clear();                    // Очистить хранилище

// Симуляция ошибок
server.failNextRequests(count, statusCode: 500);  // N ошибок
server.delayNextRequests(Duration(ms: 100));      // Задержка
server.returnInvalidJson(true);                   // Невалидный JSON
server.returnIncompleteConflict(true);            // Неполный conflict response
server.returnWrongEntity(true);                   // Неправильная сущность

// Настройки
server.conflictCheckEnabled = true;  // Включить проверку конфликтов

// Инспекция
server.recordedRequests;  // Список всех запросов
server.requestCounts;     // Счётчик по методам
```

## Тесты

```bash
# Запуск e2e тестов
dart test test/e2e/conflict_e2e_test.dart

# С подробным выводом
dart test test/e2e/ --reporter expanded
```

### Покрытие тестами

- ✅ ConflictStrategy.serverWins
- ✅ ConflictStrategy.clientWins  
- ✅ ConflictStrategy.lastWriteWins
- ✅ ConflictStrategy.merge (+ deepMerge, preservingMerge)
- ✅ ConflictStrategy.autoPreserve
- ✅ ConflictStrategy.manual
- ✅ Delete conflicts
- ✅ Batch conflicts
- ✅ Table-specific configs
- ✅ Network errors & retries
- ✅ Invalid server responses

