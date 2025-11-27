# offline_first_sync_drift_rest

REST transport adapter for [offline_first_sync_drift](https://pub.dev/packages/offline_first_sync_drift).

## Installation

```yaml
dependencies:
  offline_first_sync_drift_rest: ^0.1.0
```

## Usage

### RestTransport

```dart
import 'package:offline_first_sync_drift_rest/offline_first_sync_drift_rest.dart';

final transport = RestTransport(
  base: Uri.parse('https://api.example.com'),
  token: () async => 'Bearer ${await getAccessToken()}',
  backoffMin: const Duration(seconds: 1),
  backoffMax: const Duration(minutes: 2),
  maxRetries: 5,
  pushConcurrency: 5, // Send 5 requests in parallel
);

final engine = SyncEngine(
  db: database,
  transport: transport,
  tables: [/* ... */],
);
```

> **Performance Tip**: Using `pushConcurrency: 5` speeds up synchronization **~5x** with high network latency. E2E tests show push batch time reduced from 600ms to 120ms (with 50ms latency per request).

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `base` | `Uri` | Base API URL |
| `token` | `Future<String> Function()` | Authorization token provider |
| `client` | `http.Client?` | HTTP client (optional) |
| `backoffMin` | `Duration` | Minimum retry delay (default: 1s) |
| `backoffMax` | `Duration` | Maximum retry delay (default: 2m) |
| `maxRetries` | `int` | Maximum retry attempts (default: 5) |
| `pushConcurrency` | `int` | Parallel push requests (default: 1) |

## REST API Contract

### Endpoints

| Method | URL | Description |
|--------|-----|-------------|
| `GET` | `/{kind}` | Pull with pagination |
| `GET` | `/{kind}/{id}` | Fetch single entity |
| `POST` | `/{kind}` | Create (server generates id) |
| `PUT` | `/{kind}/{id}` | Update |
| `DELETE` | `/{kind}/{id}` | Delete |
| `GET` | `/health` | Health check |

### Query Parameters (Pull)

```
GET /daily_feeling?updatedSince=2024-01-01T00:00:00Z&limit=100&includeDeleted=true
```

| Parameter | Description |
|-----------|-------------|
| `updatedSince` | ISO8601 timestamp |
| `limit` | Page size |
| `pageToken` | Next page token |
| `afterId` | ID for cursor pagination |
| `includeDeleted` | Include soft-deleted |

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

Client sends `_baseUpdatedAt` on update:

```json
PUT /daily_feeling/123
{
  "name": "Updated",
  "_baseUpdatedAt": "2024-01-01T12:00:00Z"
}
```

Server compares with current `updated_at`. On mismatch returns `409 Conflict`:

```json
{
  "error": "conflict",
  "current": {"id": "123", "name": "Server version", "updated_at": "..."},
  "serverTimestamp": "2024-01-01T12:30:00Z"
}
```

### Force Push Headers

| Header | Value | Description |
|--------|-------|-------------|
| `X-Force-Update` | `true` | Force update |
| `X-Force-Delete` | `true` | Force delete |
| `X-Idempotency-Key` | `{opId}` | Operation idempotency |

## E2E Testing

Package includes `TestServer` for e2e tests:

```dart
import 'package:offline_first_sync_drift_rest/test/e2e/helpers/test_server.dart';

late TestServer server;

setUp(() async {
  server = TestServer();
  await server.start();
});

tearDown(() async {
  await server.stop();
});

test('conflict resolution', () async {
  // Seed data
  server.seed('entity', {
    'id': 'e1',
    'name': 'Original',
    'updated_at': DateTime.utc(2024, 1, 1).toIso8601String(),
  });
  
  // Simulate concurrent modification
  server.update('entity', 'e1', {'name': 'Server Modified'});
  
  // Test...
  
  // Verify
  final data = server.get('entity', 'e1');
  expect(data?['name'], 'Expected Value');
});
```

### TestServer API

```dart
// Data
server.seed(kind, data);           // Add entity
server.update(kind, id, data);     // Update directly
server.get(kind, id);              // Get entity
server.getAll(kind);               // Get all by kind
server.clear();                    // Clear storage

// Error simulation
server.failNextRequests(count, statusCode: 500);  // N errors
server.delayNextRequests(Duration(ms: 100));      // Delay
server.returnInvalidJson(true);                   // Invalid JSON
server.returnIncompleteConflict(true);            // Incomplete conflict response
server.returnWrongEntity(true);                   // Wrong entity

// Settings
server.conflictCheckEnabled = true;  // Enable conflict checking

// Inspection
server.recordedRequests;  // List of all requests
server.requestCounts;     // Count by method
```

## Tests

```bash
# Run e2e tests
dart test test/e2e/conflict_e2e_test.dart

# With verbose output
dart test test/e2e/ --reporter expanded
```

### Test Coverage

- ConflictStrategy.serverWins
- ConflictStrategy.clientWins  
- ConflictStrategy.lastWriteWins
- ConflictStrategy.merge (+ deepMerge, preservingMerge)
- ConflictStrategy.autoPreserve
- ConflictStrategy.manual
- Delete conflicts
- Batch conflicts
- Table-specific configs
- Network errors & retries
- Invalid server responses

## Additional Information

- [GitHub Repository](https://github.com/cherrypick-agency/offline_first_sync_drift)
- [API Documentation](https://pub.dev/documentation/offline_first_sync_drift_rest/latest/)
- [Issue Tracker](https://github.com/cherrypick-agency/offline_first_sync_drift/issues)
