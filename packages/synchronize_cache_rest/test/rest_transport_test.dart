import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:synchronize_cache/synchronize_cache.dart';
import 'package:synchronize_cache_rest/synchronize_cache_rest.dart';
import 'package:test/test.dart';

void main() {
  late RestTransport transport;
  late List<http.Request> capturedRequests;

  RestTransport createTransport(
    MockClient client, {
    int pushConcurrency = 1,
    bool enableBatch = false,
    int batchSize = 100,
  }) =>
      RestTransport(
        base: Uri.parse('https://api.example.com'),
        token: () async => 'Bearer test-token',
        client: client,
        backoffMin: const Duration(milliseconds: 10),
        backoffMax: const Duration(milliseconds: 100),
        maxRetries: 3,
        pushConcurrency: pushConcurrency,
        enableBatch: enableBatch,
        batchSize: batchSize,
      );

  group('Pull operations', () {
    test('pull returns items successfully', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/test_entity');
        expect(request.url.queryParameters['updatedSince'], isNotEmpty);
        expect(request.url.queryParameters['limit'], '100');
        expect(request.headers['Authorization'], 'Bearer test-token');

        return http.Response(
          jsonEncode({
            'items': [
              {'id': '1', 'name': 'Test 1', 'updated_at': '2024-01-01T00:00:00Z'},
              {'id': '2', 'name': 'Test 2', 'updated_at': '2024-01-02T00:00:00Z'},
            ],
            'nextPageToken': 'token123',
          }),
          200,
        );
      });

      transport = createTransport(client);

      final result = await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
      );

      expect(result.items.length, 2);
      expect(result.items[0]['id'], '1');
      expect(result.items[1]['id'], '2');
      expect(result.nextPageToken, 'token123');
    });

    test('pull includes pageToken when provided', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['pageToken'], 'next-page');

        return http.Response(
          jsonEncode({'items': <Map<String, Object?>>[], 'nextPageToken': null}),
          200,
        );
      });

      transport = createTransport(client);

      await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
        pageToken: 'next-page',
      );
    });

    test('pull includes afterId when provided', () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['afterId'], 'last-id-123');

        return http.Response(
          jsonEncode({'items': <Map<String, Object?>>[]}),
          200,
        );
      });

      transport = createTransport(client);

      await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
        afterId: 'last-id-123',
      );
    });

    test('pull throws on error response', () async {
      final client = MockClient((request) async =>
          http.Response('Internal Server Error', 500));

      transport = createTransport(client);

      await expectLater(
        transport.pull(
          kind: 'test_entity',
          updatedSince: DateTime(2024, 1, 1).toUtc(),
          pageSize: 100,
        ),
        throwsA(isA<TransportException>()),
      );
    });

    test('pull handles empty response', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({'items': <Map<String, Object?>>[]}),
            200,
          ));

      transport = createTransport(client);

      final result = await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
      );

      expect(result.items, isEmpty);
      expect(result.nextPageToken, isNull);
    });
  });

  group('Push operations', () {
    test('push upsert operation successfully', () async {
      capturedRequests = [];
      final client = MockClient((request) async {
        capturedRequests.add(request);
        expect(request.method, 'PUT');
        expect(request.url.path, '/test_entity/entity-1');
        expect(request.headers['X-Idempotency-Key'], 'op-1');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['name'], 'Test');

        return http.Response(
          jsonEncode({'id': 'entity-1', 'name': 'Test', 'updated_at': '2024-01-01T00:00:00Z'}),
          200,
          headers: {'etag': 'v1'},
        );
      });

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'id': 'entity-1', 'name': 'Test'},
        ),
      ]);

      expect(result.results.length, 1);
      expect(result.results[0].isSuccess, isTrue);
      final success = result.results[0].result as PushSuccess;
      expect(success.serverVersion, 'v1');
    });

    test('push new entity uses POST', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/test_entity');

        return http.Response(
          jsonEncode({'id': 'new-id', 'name': 'New'}),
          201,
        );
      });

      transport = createTransport(client);

      await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: '',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'New'},
        ),
      ]);
    });

    test('push includes baseUpdatedAt for conflict detection', () async {
      final baseTime = DateTime(2024, 1, 1, 12, 0, 0).toUtc();
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['_baseUpdatedAt'], baseTime.toIso8601String());

        return http.Response(jsonEncode({}), 200);
      });

      transport = createTransport(client);

      await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test'},
          baseUpdatedAt: baseTime,
        ),
      ]);
    });

    test('push delete operation successfully', () async {
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/test_entity/entity-1');
        expect(request.headers['X-Idempotency-Key'], 'op-1');

        return http.Response('', 204);
      });

      transport = createTransport(client);

      final result = await transport.push([
        DeleteOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          ),
      ]);

      expect(result.results.length, 1);
      expect(result.results[0].isSuccess, isTrue);
    });

    test('push returns empty result for empty ops list', () async {
      final client = MockClient((request) async {
        fail('Should not make any requests');
      });

      transport = createTransport(client);

      final result = await transport.push([]);

      expect(result.results, isEmpty);
    });

    test('push batch operations', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        return http.Response(jsonEncode({}), 200);
      });

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test 1'},
        ),
        UpsertOp(
          opId: 'op-2',
          kind: 'test_entity',
          id: 'entity-2',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test 2'},
        ),
      ]);

      expect(requestCount, 2);
      expect(result.results.length, 2);
      expect(result.allSuccess, isTrue);
    });
  });

  group('Parallel Push', () {
    test('executes requests in parallel when concurrency > 1', () async {
      // We want to verify that 3 requests are pending at the same time
      final pendingRequests = <Completer<void>>[];

      final client = MockClient((request) async {
        final completer = Completer<void>();
        pendingRequests.add(completer);
        await completer.future;
        return http.Response(jsonEncode({}), 200);
      });

      transport = createTransport(client, pushConcurrency: 3);

      final ops = List.generate(
        3,
        (i) => UpsertOp(
          opId: 'op-$i',
          kind: 'test_entity',
          id: 'entity-$i',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Item $i'},
        ),
      );

      // Start push - this Future will not complete until we release the completers
      final pushFuture = transport.push(ops);

      // Wait for microtasks to propagate
      await Future<void>.delayed(Duration.zero);

      // Verify that we have 3 pending requests
      expect(pendingRequests.length, 3, reason: 'All 3 requests should be fired in parallel');

      // Release all requests
      for (final c in pendingRequests) {
        c.complete();
      }

      await pushFuture;
    });

    test('respects concurrency limit (batches)', () async {
      final pendingRequests = <Completer<void>>[];

      final client = MockClient((request) async {
        final completer = Completer<void>();
        pendingRequests.add(completer);
        await completer.future;
        return http.Response(jsonEncode({}), 200);
      });

      // Limit concurrency to 2
      transport = createTransport(client, pushConcurrency: 2);

      // Create 4 operations
      final ops = List.generate(
        4,
        (i) => UpsertOp(
          opId: 'op-$i',
          kind: 'test_entity',
          id: 'entity-$i',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Item $i'},
        ),
      );

      final pushFuture = transport.push(ops);

      await Future<void>.delayed(Duration.zero);

      // Should have first batch of 2 pending
      expect(pendingRequests.length, 2, reason: 'First batch of 2 should be active');

      // Release first batch
      pendingRequests[0].complete();
      pendingRequests[1].complete();

      // Wait for next batch to start
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // Should have 4 total requests (2 completed, 2 new pending)
      expect(pendingRequests.length, 4, reason: 'Second batch should have started');

      // Release remaining
      pendingRequests[2].complete();
      pendingRequests[3].complete();

      await pushFuture;
    });

    test('executes sequentially when concurrency is 1', () async {
      int activeRequests = 0;
      int maxActiveRequests = 0;

      final client = MockClient((request) async {
        activeRequests++;
        if (activeRequests > maxActiveRequests) maxActiveRequests = activeRequests;
        
        // Simulate some work
        await Future<void>.delayed(const Duration(milliseconds: 10));
        
        activeRequests--;
        return http.Response(jsonEncode({}), 200);
      });

      transport = createTransport(client, pushConcurrency: 1);

      final ops = List.generate(3, (i) => UpsertOp(
        opId: 'op-$i',
        kind: 'test_entity',
        id: 'entity-$i',
        localTimestamp: DateTime.now().toUtc(),
        payloadJson: {'name': 'Item $i'},
      ));

      await transport.push(ops);

      expect(maxActiveRequests, 1, reason: 'Should never have more than 1 active request');
    });
  });

  group('Conflict handling (409)', () {
    test('push returns PushConflict on 409', () async {
      final serverTimestamp = DateTime(2024, 1, 15, 12, 0, 0).toUtc();
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'error': 'conflict',
              'current': {
                'id': 'entity-1',
                'name': 'Server Name',
                'updatedAt': serverTimestamp.toIso8601String(),
              },
            }),
            409,
          ));

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Local Name'},
        ),
      ]);

      expect(result.results.length, 1);
      expect(result.results[0].isConflict, isTrue);

      final conflict = result.results[0].result as PushConflict;
      expect(conflict.serverData['name'], 'Server Name');
    });

    test('push handles conflict with serverData format', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'serverData': {
                'id': 'entity-1',
                'name': 'Server Name',
                'updated_at': '2024-01-15T12:00:00Z',
              },
              'serverTimestamp': '2024-01-15T12:00:00Z',
              'version': 'v2',
            }),
            409,
          ));

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Local Name'},
        ),
      ]);

      expect(result.hasConflicts, isTrue);
      final conflict = result.results[0].result as PushConflict;
      expect(conflict.serverVersion, 'v2');
    });

    test('delete returns PushConflict on 409', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'current': {'id': 'entity-1', 'name': 'Modified'},
            }),
            409,
          ));

      transport = createTransport(client);

      final result = await transport.push([
        DeleteOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
        ),
      ]);

      expect(result.results[0].isConflict, isTrue);
    });
  });

  group('Not found handling (404)', () {
    test('push returns PushNotFound on 404', () async {
      final client = MockClient((request) async => http.Response('Not Found', 404));

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'nonexistent',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test'},
        ),
      ]);

      expect(result.results[0].isNotFound, isTrue);
    });

    test('delete returns PushNotFound on 404', () async {
      final client = MockClient((request) async => http.Response('Not Found', 404));

      transport = createTransport(client);

      final result = await transport.push([
        DeleteOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'nonexistent',
          localTimestamp: DateTime.now().toUtc(),
        ),
      ]);

      expect(result.results[0].isNotFound, isTrue);
    });
  });

  group('Force push', () {
    test('forcePush sends X-Force-Update header', () async {
      final client = MockClient((request) async {
        expect(request.headers['X-Force-Update'], 'true');

        return http.Response(
          jsonEncode({'id': 'entity-1', 'name': 'Forced'}),
          200,
        );
      });

      transport = createTransport(client);

      final result = await transport.forcePush(
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Forced'},
        ),
      );

      expect(result, isA<PushSuccess>());
    });

    test('forcePush delete sends X-Force-Delete header', () async {
      final client = MockClient((request) async {
        expect(request.headers['X-Force-Delete'], 'true');

        return http.Response('', 204);
      });

      transport = createTransport(client);

      final result = await transport.forcePush(
        DeleteOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
        ),
      );

      expect(result, isA<PushSuccess>());
    });

    test('forcePush does not include _baseUpdatedAt', () async {
      final client = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('_baseUpdatedAt'), isFalse);

        return http.Response(jsonEncode({}), 200);
      });

      transport = createTransport(client);

      await transport.forcePush(
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test'},
          baseUpdatedAt: DateTime.now().toUtc(),
        ),
      );
    });
  });

  group('Fetch operations', () {
    test('fetch returns FetchSuccess on 200', () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/test_entity/entity-1');

        return http.Response(
          jsonEncode({
            'id': 'entity-1',
            'name': 'Fetched',
            'updated_at': '2024-01-01T00:00:00Z',
          }),
          200,
          headers: {'etag': 'v1'},
        );
      });

      transport = createTransport(client);

      final result = await transport.fetch(kind: 'test_entity', id: 'entity-1');

      expect(result, isA<FetchSuccess>());
      final success = result as FetchSuccess;
      expect(success.data['name'], 'Fetched');
      expect(success.version, 'v1');
    });

    test('fetch returns FetchNotFound on 404', () async {
      final client = MockClient((request) async => http.Response('Not Found', 404));

      transport = createTransport(client);

      final result = await transport.fetch(kind: 'test_entity', id: 'nonexistent');

      expect(result, isA<FetchNotFound>());
    });

    test('fetch returns FetchError on other errors', () async {
      final client = MockClient((request) async =>
          http.Response('Internal Server Error', 500));

      transport = createTransport(client);

      final result = await transport.fetch(kind: 'test_entity', id: 'entity-1');

      expect(result, isA<FetchError>());
    });

    test('fetch returns FetchError on network failure', () async {
      final client = MockClient((request) async {
        throw Exception('Network error');
      });

      transport = createTransport(client);

      final result = await transport.fetch(kind: 'test_entity', id: 'entity-1');

      expect(result, isA<FetchError>());
    });
  });

  group('Retry logic', () {
    test('retries on 5xx errors', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts < 3) {
          return http.Response('Server Error', 500);
        }
        return http.Response(jsonEncode({'items': <Map<String, Object?>>[]}), 200);
      });

      transport = createTransport(client);

      final result = await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
      );

      expect(attempts, 3);
      expect(result.items, isEmpty);
    });

    test('retries on 429 rate limit', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts < 2) {
          return http.Response('Too Many Requests', 429);
        }
        return http.Response(jsonEncode({'items': <Map<String, Object?>>[]}), 200);
      });

      transport = createTransport(client);

      final result = await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
      );

      expect(attempts, 2);
      expect(result.items, isEmpty);
    });

    test('respects Retry-After header', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts == 1) {
          return http.Response(
            'Too Many Requests',
            429,
            headers: {'retry-after': '1'},
          );
        }
        return http.Response(jsonEncode({'items': <Map<String, Object?>>[]}), 200);
      });

      transport = createTransport(client);

      final stopwatch = Stopwatch()..start();
      await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
      );
      stopwatch.stop();

      expect(attempts, 2);
      // Should wait at least backoffMin (10ms) due to clamping
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(10));
    });

    test('gives up after max retries', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Server Error', 500);
      });

      transport = createTransport(client);

      await expectLater(
        transport.pull(
          kind: 'test_entity',
          updatedSince: DateTime(2024, 1, 1).toUtc(),
          pageSize: 100,
        ),
        throwsA(isA<TransportException>()),
      );

      expect(attempts, 4); // 1 initial + 3 retries
    });

    test('retries on network errors', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        if (attempts < 3) {
          throw Exception('Network error');
        }
        return http.Response(jsonEncode({'items': <Map<String, Object?>>[]}), 200);
      });

      transport = createTransport(client);

      final result = await transport.pull(
        kind: 'test_entity',
        updatedSince: DateTime(2024, 1, 1).toUtc(),
        pageSize: 100,
      );

      expect(attempts, 3);
      expect(result.items, isEmpty);
    });

    test('does not retry on 4xx errors (except 429)', () async {
      var attempts = 0;
      final client = MockClient((request) async {
        attempts++;
        return http.Response('Bad Request', 400);
      });

      transport = createTransport(client);

      await expectLater(
        transport.pull(
          kind: 'test_entity',
          updatedSince: DateTime(2024, 1, 1).toUtc(),
          pageSize: 100,
        ),
        throwsA(isA<TransportException>()),
      );

      expect(attempts, 1); // No retries
    });
  });

  group('Health check', () {
    test('health returns true on success', () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/health');
        return http.Response('OK', 200);
      });

      transport = createTransport(client);

      final result = await transport.health();

      expect(result, isTrue);
    });

    test('health returns false on error', () async {
      final client = MockClient((request) async =>
          http.Response('Service Unavailable', 503));

      transport = createTransport(client);

      final result = await transport.health();

      expect(result, isFalse);
    });

    test('health returns false on network failure', () async {
      final client = MockClient((request) async {
        throw Exception('Network error');
      });

      transport = createTransport(client);

      final result = await transport.health();

      expect(result, isFalse);
    });
  });

  group('Error handling', () {
    test('push returns PushError on unexpected errors', () async {
      final client = MockClient((request) async {
        throw Exception('Unexpected error');
      });

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test'},
        ),
      ]);

      expect(result.results[0].isError, isTrue);
      expect(result.hasErrors, isTrue);
    });

    test('push handles mixed results', () async {
      var callCount = 0;
      final client = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          return http.Response(jsonEncode({}), 200);
        } else {
          return http.Response(
            jsonEncode({'current': {'id': 'entity-2'}}),
            409,
          );
        }
      });

      transport = createTransport(client);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test_entity',
          id: 'entity-1',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test 1'},
        ),
        UpsertOp(
          opId: 'op-2',
          kind: 'test_entity',
          id: 'entity-2',
          localTimestamp: DateTime.now().toUtc(),
          payloadJson: {'name': 'Test 2'},
        ),
      ]);

      expect(result.allSuccess, isFalse);
      expect(result.hasConflicts, isTrue);
      expect(result.successes.length, 1);
      expect(result.conflicts.length, 1);
    });
  });

  group('Batch Push', () {
    test('sends batch request with correct payload', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/batch');
        expect(request.headers['Authorization'], 'Bearer test-token');

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ops = body['ops'] as List;

        expect(ops.length, 2);

        expect(ops[0]['opId'], 'op-1');
        expect(ops[0]['type'], 'upsert');
        expect(ops[0]['payload']['name'], 'Test 1');

        expect(ops[1]['opId'], 'op-2');
        expect(ops[1]['type'], 'delete');

        return http.Response(
          jsonEncode({
            'results': [
              {'opId': 'op-1', 'statusCode': 200, 'version': 'v1'},
              {'opId': 'op-2', 'statusCode': 204},
            ]
          }),
          200,
        );
      });

      transport = createTransport(client, enableBatch: true);

      final result = await transport.push([
        UpsertOp(
          opId: 'op-1',
          kind: 'test',
          id: '1',
          localTimestamp: DateTime.now(),
          payloadJson: {'name': 'Test 1'},
        ),
        DeleteOp(
          opId: 'op-2',
          kind: 'test',
          id: '2',
          localTimestamp: DateTime.now(),
        ),
      ]);

      expect(result.allSuccess, isTrue);
      expect((result.results[0].result as PushSuccess).serverVersion, 'v1');
    });

    test('handles mixed results in batch', () async {
      final client = MockClient((request) async => http.Response(
            jsonEncode({
              'results': [
                {'opId': 'op-1', 'statusCode': 200},
                {
                  'opId': 'op-2',
                  'statusCode': 409,
                  'error': {
                    'current': {'id': '2', 'version': 'v2'}
                  }
                },
                {'opId': 'op-3', 'statusCode': 404},
                {'opId': 'op-4', 'statusCode': 500},
              ]
            }),
            200,
          ));

      transport = createTransport(client, enableBatch: true);

      final result = await transport.push([
        UpsertOp(
            opId: 'op-1',
            kind: 'test',
            id: '1',
            localTimestamp: DateTime.now(),
            payloadJson: {}),
        UpsertOp(
            opId: 'op-2',
            kind: 'test',
            id: '2',
            localTimestamp: DateTime.now(),
            payloadJson: {}),
        DeleteOp(
            opId: 'op-3',
            kind: 'test',
            id: '3',
            localTimestamp: DateTime.now()),
        DeleteOp(
            opId: 'op-4',
            kind: 'test',
            id: '4',
            localTimestamp: DateTime.now()),
      ]);

      expect(result.results[0].isSuccess, isTrue);
      expect(result.results[1].isConflict, isTrue);
      expect((result.results[1].result as PushConflict).serverVersion, 'v2');
      expect(result.results[2].isNotFound, isTrue);
      expect(result.results[3].isError, isTrue);
    });

    test('chunks large batch requests', () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ops = body['ops'] as List;
        final results = ops
            .map((op) => {'opId': op['opId'], 'statusCode': 200})
            .toList();
        return http.Response(jsonEncode({'results': results}), 200);
      });

      transport = createTransport(client, enableBatch: true, batchSize: 2);

      await transport.push(List.generate(
          5,
          (i) => UpsertOp(
              opId: '$i',
              kind: 'test',
              id: '$i',
              localTimestamp: DateTime.now(),
              payloadJson: {})));

      expect(requestCount, 3); // 2 + 2 + 1
    });

    test('sends batches in parallel', () async {
      final pending = <Completer<void>>[];
      final client = MockClient((request) async {
        final c = Completer<void>();
        pending.add(c);
        await c.future;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final ops = body['ops'] as List;
        final results = ops
            .map((op) => {'opId': op['opId'], 'statusCode': 200})
            .toList();
        return http.Response(jsonEncode({'results': results}), 200);
      });

      // batchSize=1, concurrency=2 -> should produce 2 parallel requests
      transport = createTransport(client,
          enableBatch: true, batchSize: 1, pushConcurrency: 2);

      final future = transport.push([
        UpsertOp(
            opId: '1',
            kind: 'test',
            id: '1',
            localTimestamp: DateTime.now(),
            payloadJson: {}),
        UpsertOp(
            opId: '2',
            kind: 'test',
            id: '2',
            localTimestamp: DateTime.now(),
            payloadJson: {}),
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(pending.length, 2);

      for (final c in pending) {
        c.complete();
      }
      await future;
    });
  });
}
