import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

/// Provider function for authorization token.
typedef AuthTokenProvider = Future<String> Function();

/// REST implementation of [TransportAdapter] with full conflict resolution support.
///
/// Features:
/// - Automatic retry with exponential backoff
/// - Parallel push support via [pushConcurrency]
/// - Batch API support via [enableBatch]
/// - Conflict detection with `409 Conflict` response handling
/// - Force push headers (`X-Force-Update`, `X-Force-Delete`)
/// - Idempotency support via `X-Idempotency-Key` header
///
/// Example:
/// ```dart
/// final transport = RestTransport(
///   base: Uri.parse('https://api.example.com'),
///   token: () async => 'Bearer ${await getToken()}',
///   pushConcurrency: 5,
/// );
/// ```
class RestTransport implements TransportAdapter {
  /// Creates a new REST transport.
  ///
  /// [base] is the base URL for all API requests.
  /// [token] is a function that returns the authorization token.
  /// [client] is an optional HTTP client (defaults to a new client).
  /// [backoffMin] is the minimum retry delay (default: 1 second).
  /// [backoffMax] is the maximum retry delay (default: 2 minutes).
  /// [maxRetries] is the maximum number of retry attempts (default: 5).
  /// [pushConcurrency] is the number of parallel push requests (default: 1).
  /// [enableBatch] enables batch API mode (default: false).
  /// [batchSize] is the maximum operations per batch request (default: 100).
  /// [batchPath] is the batch endpoint path (default: 'batch').
  RestTransport({
    required this.base,
    required this.token,
    http.Client? client,
    this.backoffMin = const Duration(seconds: 1),
    this.backoffMax = const Duration(minutes: 2),
    this.maxRetries = 5,
    this.pushConcurrency = 1,
    this.enableBatch = false,
    this.batchSize = 100,
    this.batchPath = 'batch',
  }) : client = client ?? http.Client();

  /// Base URL for all API requests.
  final Uri base;

  /// Authorization token provider function.
  final AuthTokenProvider token;

  /// HTTP client used for requests.
  final http.Client client;

  /// Minimum delay between retry attempts.
  final Duration backoffMin;

  /// Maximum delay between retry attempts.
  final Duration backoffMax;

  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Number of concurrent push requests.
  ///
  /// If 1, requests are sent sequentially (default).
  /// If > 1, requests are sent in parallel batches.
  final int pushConcurrency;

  /// Enable batch API mode.
  final bool enableBatch;

  /// Maximum operations per batch request.
  final int batchSize;

  /// Batch endpoint path (relative to [base]).
  final String batchPath;

  Uri _url(String path, [Map<String, String>? q]) => Uri.parse(
    '${base.toString().replaceAll(RegExp(r"/+$"), '')}/$path',
  ).replace(queryParameters: q);

  Map<String, String> _headers(String auth, {String? version}) {
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': auth,
    };
    if (version != null) {
      headers['If-Match'] = version;
    }
    return headers;
  }

  /// Pulls entities from the server with pagination.
  ///
  /// Makes a GET request to `/{kind}` with query parameters:
  /// - `updatedSince`: ISO8601 timestamp
  /// - `limit`: page size
  /// - `pageToken`: next page token (if provided)
  /// - `afterId`: cursor ID (if provided)
  /// - `includeDeleted`: include soft-deleted entities
  @override
  Future<PullPage> pull({
    required String kind,
    required DateTime updatedSince,
    required int pageSize,
    String? pageToken,
    String? afterId,
    bool includeDeleted = true,
  }) async {
    final auth = await token();
    final params = <String, String>{
      'updatedSince': updatedSince.toUtc().toIso8601String(),
      'limit': '$pageSize',
      'includeDeleted': includeDeleted ? 'true' : 'false',
    };
    if (pageToken != null) params['pageToken'] = pageToken;
    if (afterId != null) params['afterId'] = afterId;

    final res = await _withRetry(
      () => client.get(_url(kind, params), headers: _headers(auth)),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, Object?>;
      final items =
          (body['items'] as List<dynamic>? ?? []).cast<Map<String, Object?>>();
      final next = body['nextPageToken'] as String?;
      return PullPage(items: items, nextPageToken: next);
    }
    throw TransportException.httpError(res.statusCode, res.body);
  }

  /// Pushes operations to the server.
  ///
  /// If [enableBatch] is true, uses batch API.
  /// If [pushConcurrency] > 1, sends requests in parallel.
  ///
  /// Returns [BatchPushResult] with results for each operation.
  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    if (ops.isEmpty) {
      return const BatchPushResult(results: []);
    }

    final auth = await token();

    if (enableBatch) {
      return _pushBatch(ops, auth);
    }

    final results = <OpPushResult>[];

    if (pushConcurrency > 1) {
      // Параллельная отправка батчами
      for (var i = 0; i < ops.length; i += pushConcurrency) {
        final end =
            (i + pushConcurrency < ops.length)
                ? i + pushConcurrency
                : ops.length;
        final chunk = ops.sublist(i, end);

        final chunkResults = await Future.wait(
          chunk.map((op) async {
            final result = await _pushSingleOp(op, auth);
            return OpPushResult(opId: op.opId, result: result);
          }),
        );
        results.addAll(chunkResults);
      }
    } else {
      // Последовательная отправка
      for (final op in ops) {
        final result = await _pushSingleOp(op, auth);
        results.add(OpPushResult(opId: op.opId, result: result));
      }
    }

    return BatchPushResult(results: results);
  }

  Future<BatchPushResult> _pushBatch(List<Op> ops, String auth) async {
    final results = <OpPushResult>[];

    // Разбиваем на чанки по batchSize
    final chunks = <List<Op>>[];
    for (var i = 0; i < ops.length; i += batchSize) {
      final end = (i + batchSize < ops.length) ? i + batchSize : ops.length;
      chunks.add(ops.sublist(i, end));
    }

    if (pushConcurrency > 1) {
      // Обрабатываем чанки параллельно
      for (var i = 0; i < chunks.length; i += pushConcurrency) {
        final end =
            (i + pushConcurrency < chunks.length)
                ? i + pushConcurrency
                : chunks.length;
        final batchGroup = chunks.sublist(i, end);

        final groupResults = await Future.wait(
          batchGroup.map((chunk) => _pushBatchChunk(chunk, auth)),
        );

        for (final batchRes in groupResults) {
          results.addAll(batchRes.results);
        }
      }
    } else {
      // Обрабатываем чанки последовательно
      for (final chunk in chunks) {
        final batchRes = await _pushBatchChunk(chunk, auth);
        results.addAll(batchRes.results);
      }
    }

    return BatchPushResult(results: results);
  }

  Future<BatchPushResult> _pushBatchChunk(List<Op> chunk, String auth) async {
    try {
      final payload = {
        'ops':
            chunk.map((op) {
              final map = <String, Object?>{
                'opId': op.opId,
                'kind': op.kind,
                'id': op.id,
                'type': op is UpsertOp ? 'upsert' : 'delete',
              };

              if (op is UpsertOp) {
                map['payload'] = op.payloadJson;
                if (op.baseUpdatedAt != null) {
                  map['baseUpdatedAt'] =
                      op.baseUpdatedAt!.toUtc().toIso8601String();
                }
              } else if (op is DeleteOp) {
                if (op.baseUpdatedAt != null) {
                  map['baseUpdatedAt'] =
                      op.baseUpdatedAt!.toUtc().toIso8601String();
                }
              }
              return map;
            }).toList(),
      };

      final res = await _withRetry(() async {
        final req =
            http.Request('POST', _url(batchPath))
              ..headers.addAll(_headers(auth))
              ..body = jsonEncode(payload);
        return http.Response.fromStream(await client.send(req));
      });

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final body = jsonDecode(res.body) as Map<String, Object?>;
        final resultsJson =
            (body['results'] as List?)?.cast<Map<String, Object?>>() ?? [];

        // Создаем карту результатов для быстрого поиска
        final resultsMap = <String, OpPushResult>{};
        for (final item in resultsJson) {
          final opRes = _parseBatchItem(item);
          resultsMap[opRes.opId] = opRes;
        }

        // Формируем итоговый список, сохраняя порядок ops в чанке
        final results =
            chunk.map((op) {
              if (resultsMap.containsKey(op.opId)) {
                return resultsMap[op.opId]!;
              }
              // Если сервер не вернул результат для операции
              return OpPushResult(
                opId: op.opId,
                result: PushError(
                  http.ClientException(
                    'No result for op ${op.opId} in batch response',
                  ),
                ),
              );
            }).toList();

        return BatchPushResult(results: results);
      }

      throw TransportException.httpError(res.statusCode, res.body);
    } on SyncException {
      rethrow;
    } catch (e, st) {
      throw NetworkException.fromError(e, st);
    }
  }

  OpPushResult _parseBatchItem(Map<String, Object?> item) {
    final opId = item['opId'] as String;
    final statusCode = item['statusCode'] as int? ?? 200;

    PushResult result;

    if (statusCode >= 200 && statusCode < 300) {
      result = PushSuccess(
        serverData: item['data'] as Map<String, Object?>?,
        serverVersion: item['version']?.toString(),
      );
    } else if (statusCode == 404) {
      result = const PushNotFound();
    } else if (statusCode == 409) {
      final conflictBody = (item['error'] as Map<String, Object?>?) ?? item;
      result = _parseConflictMap(conflictBody);
    } else {
      result = PushError(http.ClientException('Batch op failed: $statusCode'));
    }

    return OpPushResult(opId: opId, result: result);
  }

  Future<PushResult> _pushSingleOp(
    Op op,
    String auth, {
    bool force = false,
  }) async {
    try {
      if (op is UpsertOp) {
        return await _pushUpsert(op, auth, force: force);
      } else if (op is DeleteOp) {
        return await _pushDelete(op, auth, force: force);
      }
      return PushError(ArgumentError('Unknown operation type: $op'));
    } on SyncException catch (e, st) {
      return PushError(e, st);
    } catch (e, st) {
      return PushError(NetworkException.fromError(e, st), st);
    }
  }

  Future<PushResult> _pushUpsert(
    UpsertOp op,
    String auth, {
    bool force = false,
  }) async {
    final id = op.id;
    final method = id.isEmpty ? 'POST' : 'PUT';
    final path = id.isEmpty ? op.kind : '${op.kind}/$id';
    final uri = _url(path);

    final headers = _headers(auth);
    headers['X-Idempotency-Key'] = op.opId;
    if (force) {
      headers['X-Force-Update'] = 'true';
    }

    // Подготовка payload с _baseUpdatedAt для детекции конфликта
    final payload = Map<String, Object?>.from(op.payloadJson);
    if (op.baseUpdatedAt != null && !force) {
      payload['_baseUpdatedAt'] = op.baseUpdatedAt!.toUtc().toIso8601String();
    }

    final res = await _withRetry(() async {
      final req =
          http.Request(method, uri)
            ..headers.addAll(headers)
            ..body = jsonEncode(payload);
      return http.Response.fromStream(await client.send(req));
    });

    return _parseResponse(res, op.kind, op.id);
  }

  Future<PushResult> _pushDelete(
    DeleteOp op,
    String auth, {
    bool force = false,
  }) async {
    final uri = _url('${op.kind}/${op.id}');

    final headers = _headers(auth);
    headers['X-Idempotency-Key'] = op.opId;
    if (force) {
      headers['X-Force-Delete'] = 'true';
    }

    // Для delete тоже можно передать baseUpdatedAt
    Map<String, String>? queryParams;
    if (op.baseUpdatedAt != null && !force) {
      queryParams = {
        '_baseUpdatedAt': op.baseUpdatedAt!.toUtc().toIso8601String(),
      };
    }

    final deleteUri =
        queryParams != null ? uri.replace(queryParameters: queryParams) : uri;

    final res = await _withRetry(() async {
      final req = http.Request('DELETE', deleteUri)..headers.addAll(headers);
      return http.Response.fromStream(await client.send(req));
    });

    if (res.statusCode == 204 || res.statusCode == 200) {
      return const PushSuccess();
    }
    if (res.statusCode == 404) {
      return const PushNotFound();
    }
    if (res.statusCode == 409) {
      return _parseConflict(res);
    }
    return PushError(
      http.ClientException('Delete failed ${res.statusCode}', res.request?.url),
    );
  }

  PushResult _parseResponse(http.Response res, String kind, String id) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      Map<String, Object?>? serverData;
      String? serverVersion;

      if (res.body.isNotEmpty) {
        try {
          serverData = jsonDecode(res.body) as Map<String, Object?>?;
        } catch (_) {}
      }

      serverVersion = res.headers['etag'];

      return PushSuccess(serverData: serverData, serverVersion: serverVersion);
    }

    if (res.statusCode == 404) {
      return const PushNotFound();
    }

    if (res.statusCode == 409) {
      return _parseConflict(res);
    }

    return PushError(
      http.ClientException('Push failed ${res.statusCode}', res.request?.url),
    );
  }

  PushConflict _parseConflict(http.Response res) {
    if (res.body.isNotEmpty) {
      try {
        final body = jsonDecode(res.body) as Map<String, Object?>;
        return _parseConflictMap(body, res.headers['etag']);
      } catch (_) {}
    }

    return PushConflict(
      serverData: {},
      serverTimestamp: DateTime.now().toUtc(),
    );
  }

  PushConflict _parseConflictMap(
    Map<String, Object?> body, [
    String? headerEtag,
  ]) {
    Map<String, Object?> serverData = {};
    DateTime serverTimestamp = DateTime.now().toUtc();
    String? serverVersion;

    try {
      // Поддержка разных форматов ответа от сервера
      serverData =
          (body['current'] as Map<String, Object?>?) ??
          (body['serverData'] as Map<String, Object?>?) ??
          body;

      final ts =
          body['serverTimestamp'] ??
          serverData[SyncFields.updatedAt] ??
          serverData[SyncFields.updatedAtSnake];
      if (ts != null) {
        serverTimestamp =
            ts is DateTime ? ts : DateTime.parse(ts.toString()).toUtc();
      }

      serverVersion =
          body['version']?.toString() ??
          serverData['version']?.toString() ??
          headerEtag;
    } catch (_) {}

    return PushConflict(
      serverData: serverData,
      serverTimestamp: serverTimestamp,
      serverVersion: serverVersion,
    );
  }

  /// Forces push of an operation, bypassing conflict detection.
  ///
  /// Sends `X-Force-Update` or `X-Force-Delete` header.
  @override
  Future<PushResult> forcePush(Op op) async {
    final auth = await token();
    return _pushSingleOp(op, auth, force: true);
  }

  /// Fetches a single entity from the server.
  ///
  /// Makes a GET request to `/{kind}/{id}`.
  /// Returns [FetchSuccess], [FetchNotFound], or [FetchError].
  @override
  Future<FetchResult> fetch({required String kind, required String id}) async {
    try {
      final auth = await token();
      final uri = _url('$kind/$id');

      final res = await _withRetry(
        () => client.get(uri, headers: _headers(auth)),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, Object?>;
        final version = res.headers['etag'];
        return FetchSuccess(data: data, version: version);
      }

      if (res.statusCode == 404) {
        return const FetchNotFound();
      }

      return FetchError(TransportException.httpError(res.statusCode, res.body));
    } on SyncException catch (e, st) {
      return FetchError(e, st);
    } catch (e, st) {
      return FetchError(NetworkException.fromError(e, st), st);
    }
  }

  Future<http.Response> _withRetry(
    Future<http.Response> Function() send,
  ) async {
    var attempt = 0;
    var delay = backoffMin;

    while (true) {
      attempt++;
      try {
        final res = await send();
        if (_isRetryable(res.statusCode)) {
          if (attempt > maxRetries) return res;
          final ra = _retryAfter(res.headers['retry-after']);
          await Future<void>.delayed(ra ?? delay);
          delay = _nextBackoff(delay);
          continue;
        }
        return res;
      } catch (e, st) {
        if (attempt > maxRetries) {
          throw NetworkException(
            'Request failed after $attempt attempts',
            e,
            st,
          );
        }
        await Future<void>.delayed(delay);
        delay = _nextBackoff(delay);
      }
    }
  }

  bool _isRetryable(int code) => code == 429 || (code >= 500 && code < 600);

  Duration? _retryAfter(String? h) {
    if (h == null) return null;
    final s = int.tryParse(h);
    if (s != null) return _clamp(Duration(seconds: s), backoffMin, backoffMax);
    return null;
  }

  Duration _clamp(Duration value, Duration min, Duration max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  Duration _nextBackoff(Duration d) {
    final next = d * 2;
    return next > backoffMax ? backoffMax : next;
  }

  /// Checks server health.
  ///
  /// Makes a GET request to `/health`.
  /// Returns `true` if server responds with 2xx status.
  @override
  Future<bool> health() async {
    try {
      final auth = await token();
      final res = await client.get(_url('health'), headers: _headers(auth));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (_) {
      return false;
    }
  }
}
