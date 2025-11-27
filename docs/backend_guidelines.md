# Руководство по серверной части для `offline_first_sync_drift`

## Содержание

- [Введение](#введение)
- [Упрощённый сценарий](#упрощённый-сценарий)
  - [REST-эндпоинты](#rest-эндпоинты)
  - [Поля моделей](#поля-моделей)
  - [POST: создание](#post-создание-записи)
  - [PUT: обновление](#put-обновление-upsert)
  - [DELETE: удаление](#delete-удаление)
  - [GET по ID](#get-по-id)
  - [Пагинация](#пагинация)
  - [Чеклист](#чеклист-упрощённый-сценарий)
- [Полный сценарий](#полный-сценарий-с-обработкой-конфликтов)
  - [PUT с конфликтами](#put-обновление-с-проверкой-конфликтов)
  - [DELETE с конфликтами](#delete-удаление-с-проверкой-конфликтов)
  - [Формат 409 Conflict](#формат-ответа-при-конфликте-409)
  - [Batch API](#batch-api-опционально)
  - [Чеклист](#чеклист-полный-сценарий)
- [Общие разделы](#общие-разделы)
  - [Системные поля](#системные-поля)
  - [Health endpoint](#health-endpoint-опционально)
  - [ETag](#etag-опционально)
  - [Rate Limiting](#rate-limiting-опционально)
- [FAQ](#faq)

---

## Введение

`offline_first_sync_drift` — клиентская библиотека для offline-first синхронизации. Этот документ описывает требования к REST API сервера.

### Два сценария использования

| Сценарий | Когда использовать | Сложность |
|----------|-------------------|-----------|
| **Упрощённый** | Один клиент, один аккаунт, бэкенд не модифицирует данные | Минимальная |
| **Полный** | Несколько клиентов/устройств, бэкенд может добавлять данные | Требует обработки конфликтов |

> Начните с упрощённого сценария. Если понадобится поддержка нескольких клиентов — добавьте обработку конфликтов.

---

# Упрощённый сценарий

**Используйте этот вариант если:**
- Одно приложение, один аккаунт
- Одно устройство (или устройства не работают одновременно)
- Бэкенд только хранит данные, не модифицирует их самостоятельно

В этом сценарии **конфликты невозможны**, поэтому проверка `_baseUpdatedAt` не нужна.

## REST-эндпоинты

| Метод | URL | Назначение |
|-------|-----|------------|
| `GET` | `/{kind}` | Список записей с фильтрацией и пагинацией |
| `GET` | `/{kind}/{id}` | Получение одной записи |
| `POST` | `/{kind}` | Создание новой записи |
| `PUT` | `/{kind}/{id}` | Обновление записи (upsert) |
| `DELETE` | `/{kind}/{id}` | Удаление записи |

`{kind}` — имя сущности. Можно реализовать как:
- Отдельные контроллеры: `/daily_feeling`, `/health_record`
- Или динамический параметр с whitelist разрешённых сущностей

## Поля моделей

| Поле | Тип | Описание |
|------|-----|----------|
| `id` | `string` | Уникальный идентификатор (UUID), **генерируется клиентом** |
| `updated_at` | `datetime` | Время последнего обновления (UTC), **задаётся сервером** |

> Клиент поддерживает `snake_case` (`updated_at`) и `camelCase` (`updatedAt`).

```json
{
  "id": "abc-123",
  "mood": 5,
  "energy": 7,
  "updated_at": "2025-01-15T10:30:00Z"
}
```

## POST: создание записи

Клиент **обычно генерирует `id` сам** и использует PUT. POST используется редко (когда id пустой).

Вернуть `201 Created` с созданной записью.

```javascript
async function handlePost(req, res) {
  const { kind } = req.params;
  
  // id приходит от клиента или генерируем на сервере
  const id = req.body.id || generateUUID();
  
  // Удаляем системные поля из данных
  const payload = stripSystemFields(req.body);
  const now = new Date().toISOString();

  await db(kind).insert({
    ...payload,
    id,
    updated_at: now,
  });

  const result = await db(kind).where({ id }).first();
  return res.status(201).json(result);
}
```

## PUT: обновление (upsert)

PUT работает как **upsert**: если записи нет — создаёт её.

Клиент может передавать `_baseUpdatedAt` в теле — **просто игнорируйте его** в упрощённом сценарии.

```javascript
async function handlePut(req, res) {
  const { kind, id } = req.params;  // id из URL
  const payload = stripSystemFields(req.body);
  const now = new Date().toISOString();

  const existing = await db(kind).where({ id }).first();

  if (!existing) {
    await db(kind).insert({ ...payload, id, updated_at: now });
    const result = await db(kind).where({ id }).first();
    return res.status(201).json(result);
  }

  await db(kind).where({ id }).update({ ...payload, updated_at: now });
  const result = await db(kind).where({ id }).first();
  return res.json(result);
}
```

## DELETE: удаление

Клиент может передавать `_baseUpdatedAt` как query-параметр — **просто игнорируйте его** в упрощённом сценарии.

```javascript
async function handleDelete(req, res) {
  const { kind, id } = req.params;

  const existing = await db(kind).where({ id }).first();
  if (!existing) {
    return res.status(404).json({ error: 'not_found' });
  }

  await db(kind).where({ id }).delete();
  return res.status(204).end();
}
```

## GET по ID

```javascript
async function handleGet(req, res) {
  const { kind, id } = req.params;

  const record = await db(kind).where({ id }).first();
  if (!record) {
    return res.status(404).json({ error: 'not_found' });
  }

  return res.json(record);
}
```

## Пагинация

### Запрос

```http
GET /daily_feeling?updatedSince=2025-01-01T00:00:00Z&limit=500&includeDeleted=true
```

| Параметр | Описание |
|----------|----------|
| `updatedSince` | Вернуть записи с `updated_at >= значение` |
| `limit` | Максимум записей (рекомендуется 500) |
| `pageToken` | Токен следующей страницы |
| `afterId` | Клиент может передавать — можно игнорировать если используете `pageToken` |
| `includeDeleted` | Включить soft-deleted записи (по умолчанию `true`) |

### Ответ

```json
{
  "items": [
    {"id": "abc-123", "mood": 5, "updated_at": "2025-01-15T10:00:00Z"},
    {"id": "def-456", "mood": 3, "updated_at": "2025-01-15T10:05:00Z"}
  ],
  "nextPageToken": "10"
}
```

`nextPageToken` — `null` если это последняя страница.

### Простая реализация с offset

```javascript
async function handleList(req, res) {
  const { kind } = req.params;
  const { updatedSince, pageToken } = req.query;
  const limit = parseInt(req.query.limit || '500', 10);
  const offset = parseInt(pageToken || '0', 10);
  // includeDeleted — для hard-delete можно игнорировать

  let query = db(kind).orderBy('updated_at', 'asc').orderBy('id', 'asc');
  
  if (updatedSince) {
    query = query.where('updated_at', '>=', updatedSince);
  }

  const items = await query.limit(limit).offset(offset);
  const nextPageToken = items.length === limit ? String(offset + limit) : null;

  return res.json({ items, nextPageToken });
}
```

## Чеклист (упрощённый сценарий)

- [ ] У каждой модели есть `updated_at`, задаваемый сервером
- [ ] `GET /{kind}` принимает `updatedSince`, `limit`, `pageToken`
- [ ] Сортировка по `(updated_at, id)` для стабильной пагинации
- [ ] Ответ `GET` возвращает `{ "items": [...], "nextPageToken": "..." }`
- [ ] `POST` возвращает `201` с созданной записью
- [ ] `PUT` работает как upsert
- [ ] `DELETE` возвращает `204`
- [ ] Все ответы `POST/PUT` включают `updated_at`

---

# Полный сценарий (с обработкой конфликтов)

**Используйте этот вариант если:**
- Несколько устройств могут работать одновременно
- Бэкенд может модифицировать данные (webhooks, cron jobs, админка)
- Нужна защита от потери данных при concurrent updates

## Что добавляется к упрощённому варианту

| Фича | Описание |
|------|----------|
| Проверка `_baseUpdatedAt` | Детекция конфликтов |
| `409 Conflict` ответ | Возврат актуального состояния при конфликте |
| `X-Force-Update/Delete` | Принудительное обновление после merge |
| `X-Idempotency-Key` | Защита от дублей при ретраях |

## PUT: обновление с проверкой конфликтов

### Заголовки запроса

| Заголовок | Описание |
|-----------|----------|
| `X-Idempotency-Key` | Уникальный ключ операции для безопасных ретраев |
| `X-Force-Update: true` | Пропустить проверку конфликта (после merge на клиенте) |

### Тело запроса

Клиент присылает `_baseUpdatedAt` — timestamp записи на момент получения с сервера:

```json
{
  "mood": 7,
  "energy": 8,
  "_baseUpdatedAt": "2025-01-15T10:30:00Z"
}
```

### Алгоритм обработки

1. Прочитать `X-Idempotency-Key`. Если операция уже выполнялась — вернуть сохранённый ответ.
2. Найти запись. Если не существует — создать (upsert), вернуть `201`.
3. Считать `_baseUpdatedAt` из тела.
4. Если `X-Force-Update != true` и `existing.updated_at != baseUpdatedAt` — вернуть `409 Conflict`.
5. Обновить запись, присвоив новый `updated_at`.
6. Вернуть `200` с обновлённой записью.
7. Закэшировать ответ по `X-Idempotency-Key` на 24 часа.

### Пример

```javascript
async function handlePut(req, res) {
  const { kind, id } = req.params;
  const idempotencyKey = req.header('x-idempotency-key');

  // Idempotency check
  if (idempotencyKey) {
    const cached = await cache.get(`idempotency:${idempotencyKey}`);
    if (cached) return res.json(cached);
  }

  const existing = await db(kind).where({ id }).first();
  const forceUpdate = req.header('x-force-update') === 'true';
  
  // Берём _baseUpdatedAt ДО удаления системных полей
  const baseUpdatedAt = req.body._baseUpdatedAt;
  const payload = stripSystemFields(req.body);
  const now = new Date().toISOString();

  // Upsert
  if (!existing) {
    await db(kind).insert({ ...payload, id, updated_at: now });
    const result = await db(kind).where({ id }).first();
    return res.status(201).json(result);
  }

  // Проверка конфликта
  if (!forceUpdate && baseUpdatedAt && existing.updated_at !== baseUpdatedAt) {
    return res.status(409).json({
      error: 'conflict',
      current: existing,
    });
  }

  await db(kind).where({ id }).update({ ...payload, updated_at: now });
  const result = await db(kind).where({ id }).first();

  if (idempotencyKey) {
    await cache.set(`idempotency:${idempotencyKey}`, result, 86400);
  }

  return res.json(result);
}
```

## DELETE: удаление с проверкой конфликтов

`_baseUpdatedAt` передаётся как **query-параметр**.

### Заголовки запроса

| Заголовок | Описание |
|-----------|----------|
| `X-Idempotency-Key` | Уникальный ключ операции |
| `X-Force-Delete: true` | Пропустить проверку конфликта |

### Пример запроса

```http
DELETE /daily_feeling/abc-123?_baseUpdatedAt=2025-01-15T10:30:00Z
X-Idempotency-Key: op-456
```

### Пример

```javascript
async function handleDelete(req, res) {
  const { kind, id } = req.params;
  const idempotencyKey = req.header('x-idempotency-key');

  if (idempotencyKey) {
    const cached = await cache.get(`idempotency:${idempotencyKey}`);
    if (cached) return res.status(204).end();
  }

  const existing = await db(kind).where({ id }).first();
  if (!existing) {
    return res.status(404).json({ error: 'not_found' });
  }

  const forceDelete = req.header('x-force-delete') === 'true';
  const baseUpdatedAt = req.query._baseUpdatedAt;

  // Проверка конфликта
  if (!forceDelete && baseUpdatedAt && existing.updated_at !== baseUpdatedAt) {
    return res.status(409).json({
      error: 'conflict',
      current: existing,
    });
  }

  await db(kind).where({ id }).delete();

  if (idempotencyKey) {
    await cache.set(`idempotency:${idempotencyKey}`, { deleted: true }, 86400);
  }

  return res.status(204).end();
}
```

## Формат ответа при конфликте (409)

```json
{
  "error": "conflict",
  "current": {
    "id": "abc-123",
    "mood": 6,
    "energy": 9,
    "updated_at": "2025-01-15T11:00:00Z"
  }
}
```

| Поле | Описание |
|------|----------|
| `error` | Код ошибки (`"conflict"`) |
| `current` | Актуальное состояние записи (должен содержать `updated_at`) |

Клиент использует `current` для merge и повторяет запрос с `X-Force-Update: true` (или `X-Force-Delete: true`).

## Batch API (опционально)

Для оптимизации можно реализовать пакетную обработку.

### Запрос

```http
POST /batch
Content-Type: application/json

{
  "ops": [
    {
      "opId": "op-001",
      "kind": "daily_feeling",
      "id": "abc-123",
      "type": "upsert",
      "payload": {"mood": 7, "energy": 8},
      "baseUpdatedAt": "2025-01-15T10:30:00Z"
    },
    {
      "opId": "op-002",
      "kind": "daily_feeling",
      "id": "def-456",
      "type": "delete",
      "baseUpdatedAt": "2025-01-15T10:00:00Z"
    }
  ]
}
```

### Ответ

```json
{
  "results": [
    {
      "opId": "op-001",
      "statusCode": 200,
      "data": {"id": "abc-123", "mood": 7, "updated_at": "2025-01-15T12:00:00Z"}
    },
    {
      "opId": "op-002",
      "statusCode": 409,
      "error": {
        "error": "conflict",
        "current": {"id": "def-456", "mood": 5, "updated_at": "2025-01-15T11:30:00Z"}
      }
    }
  ]
}
```

## Чеклист (полный сценарий)

Всё из упрощённого сценария, плюс:

- [ ] `PUT` проверяет `_baseUpdatedAt`, возвращает `409` с `current` при конфликте
- [ ] `DELETE` проверяет `_baseUpdatedAt` (query-параметр)
- [ ] Поддерживаются заголовки `X-Force-Update`, `X-Force-Delete`
- [ ] Поддерживается `X-Idempotency-Key` (24ч cache)

### Опционально

- [ ] `POST /batch` для пакетной обработки
- [ ] Сервер возвращает заголовок `ETag`
- [ ] Поддержка `deleted_at` для soft-delete

---

# Общие разделы

## Системные поля

При сохранении данных удаляйте системные поля из payload — они управляются сервером.

> **Важно:** Извлекайте нужные значения (например, `_baseUpdatedAt`) **до** вызова `stripSystemFields`.

```javascript
const SYSTEM_FIELDS = [
  'id', 'ID', 'uuid',
  'updatedAt', 'updated_at',
  'createdAt', 'created_at',
  'deletedAt', 'deleted_at',
  '_baseUpdatedAt',
];

function stripSystemFields(payload) {
  const result = { ...payload };
  for (const field of SYSTEM_FIELDS) {
    delete result[field];
  }
  return result;
}

// Пример использования:
const baseUpdatedAt = req.body._baseUpdatedAt;  // сначала извлекаем
const payload = stripSystemFields(req.body);     // потом очищаем
```

## Health endpoint (опционально)

Клиент может вызывать `GET /health` для проверки доступности сервера.

```javascript
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});
```

Верните `2xx` статус если сервер работает. Содержимое ответа не важно.

## ETag (опционально)

Сервер может возвращать заголовок `ETag`:

```http
HTTP/1.1 200 OK
ETag: "v2"
Content-Type: application/json

{"id": "abc-123", "mood": 7, ...}
```

## Rate Limiting (опционально)

При превышении лимита:

```http
HTTP/1.1 429 Too Many Requests
Retry-After: 60
```

Клиент автоматически ретраит через указанное количество секунд.

---

# FAQ

## Что такое `{kind}` в URL?

Это имя сущности/таблицы. Реализуйте как удобнее:

**Вариант 1:** Отдельные роуты
```javascript
router.get('/daily_feeling', handleList);
router.get('/health_record', handleList);
```

**Вариант 2:** Динамический параметр с whitelist
```javascript
const ALLOWED_KINDS = ['daily_feeling', 'health_record'];

router.get('/:kind', (req, res) => {
  if (!ALLOWED_KINDS.includes(req.params.kind)) {
    return res.status(404).json({ error: 'unknown_kind' });
  }
  return handleList(req, res);
});
```

## Откуда клиент берёт `_baseUpdatedAt`?

Когда клиент получает запись с сервера (через GET), он сохраняет `updated_at`. При следующем обновлении этой записи клиент отправляет сохранённый timestamp как `_baseUpdatedAt`.

Это позволяет серверу понять: "клиент редактировал версию от 10:30, а на сервере уже версия от 11:00 — конфликт!"

## Почему проверка `!=` а не `>`?

Используем **строгое равенство** (`!=`), а не "сервер новее" (`>`), потому что:

1. Любое изменение на сервере (даже более старое) означает что клиент работал с устаревшими данными
2. Это проще реализовать — не нужно парсить даты, достаточно сравнить строки
3. Защищает от edge cases с синхронизацией времени между серверами

## Что если `_baseUpdatedAt` не передан?

- **Новая запись** (PUT на несуществующий id): `_baseUpdatedAt` не нужен, это upsert
- **Существующая запись без `_baseUpdatedAt`**: считайте что клиент знает что делает — пропустите проверку конфликта (как при `X-Force-Update`)

```javascript
if (!forceUpdate && baseUpdatedAt && existing.updated_at !== baseUpdatedAt) {
  // Конфликт только если baseUpdatedAt передан И не совпадает
}
```

## Какой формат datetime использовать?

**ISO 8601 в UTC с суффиксом `Z`:**

```
2025-01-15T10:30:00Z
```

Клиент парсит и другие форматы (`+00:00`, миллисекунды), но `Z` — самый надёжный.

## Зачем `includeDeleted=true` по умолчанию?

Для синхронизации клиенту нужно знать какие записи были удалены (soft-delete), чтобы удалить их локально.

Если используете **hard-delete** — этот параметр можно игнорировать.

## Soft-delete vs hard-delete?

**Hard-delete** (упрощённый сценарий):
- Запись удаляется из БД
- Клиент не узнает об удалении до full resync
- Проще реализовать

**Soft-delete** (полный сценарий):
- Устанавливается `deleted_at`, запись остаётся в БД
- Клиент получает удалённые записи через `includeDeleted=true`
- Нужно для sync между устройствами

## Что хранить в idempotency cache?

Храните **полный response** (JSON body):

```javascript
// При успешном запросе
await cache.set(`idempotency:${key}`, result, 86400);

// При повторном запросе
const cached = await cache.get(`idempotency:${key}`);
if (cached) return res.json(cached);
```

Для DELETE можно хранить `{ deleted: true }` или просто факт выполнения.

## Как передавать авторизацию?

Документ не диктует способ авторизации. Используйте стандартный для вашего API:

```http
Authorization: Bearer <token>
```

Клиентская библиотека передаёт значение хедера через callback:
```dart
RestTransport(
  // Возвращает полное значение для Authorization header
  token: () async => 'Bearer ${await getToken()}',
)
```

## Что такое "merge на клиенте"?

Когда сервер возвращает `409 Conflict`, клиент:

1. Получает `current` (актуальное состояние с сервера)
2. Сравнивает с локальными изменениями
3. Объединяет данные (merge) по настроенной стратегии
4. Повторяет запрос с `X-Force-Update: true`

Стратегии merge настраиваются в клиентской библиотеке (serverWins, clientWins, lastWriteWins, custom).

## Кто генерирует `id`?

**Клиент генерирует UUID** перед отправкой. Это позволяет:
- Работать offline
- Создавать записи без round-trip к серверу

Сервер генерирует `id` только если клиент не передал его (редкий случай при POST).

---

## Дополнительные материалы

E2E-тесты в [`packages/offline_first_sync_drift_rest/test/e2e`](../packages/offline_first_sync_drift_rest/test/e2e) — референсная реализация сервера.
