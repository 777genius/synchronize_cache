import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:synchronize_cache/synchronize_cache.dart';

typedef AuthTokenProvider = Future<String> Function();

/// REST реализация TransportAdapter с полной поддержкой conflict resolution.
class RestTransport implements TransportAdapter {
  RestTransport({
    required this.base,
    required this.token,
    http.Client? client,
    this.backoffMin = const Duration(seconds: 1),
    this.backoffMax = const Duration(minutes: 2),
    this.maxRetries = 5,
  }) : client = client ?? http.Client();

  /// Базовый URL API.
  final Uri base;

  /// Провайдер токена авторизации.
  final AuthTokenProvider token;

  /// HTTP клиент.
  final http.Client client;

  /// Минимальная задержка при retry.
  final Duration backoffMin;

  /// Максимальная задержка при retry.
  final Duration backoffMax;

  /// Максимальное количество попыток.
  final int maxRetries;

  Uri _url(String path, [Map<String, String>? q]) =>
      Uri.parse('${base.toString().replaceAll(RegExp(r"/+$"), '')}/$path')
          .replace(queryParameters: q);

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
        () => client.get(_url(kind, params), headers: _headers(auth)));

    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, Object?>;
      final items =
          (body['items'] as List<dynamic>? ?? []).cast<Map<String, Object?>>();
      final next = body['nextPageToken'] as String?;
      return PullPage(items: items, nextPageToken: next);
    }
    throw TransportException.httpError(res.statusCode, res.body);
  }

  @override
  Future<BatchPushResult> push(List<Op> ops) async {
    if (ops.isEmpty) {
      return const BatchPushResult(results: []);
    }

    final auth = await token();
    final results = <OpPushResult>[];

    for (final op in ops) {
      final result = await _pushSingleOp(op, auth);
      results.add(OpPushResult(opId: op.opId, result: result));
    }

    return BatchPushResult(results: results);
  }

  Future<PushResult> _pushSingleOp(Op op, String auth, {bool force = false}) async {
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

  Future<PushResult> _pushUpsert(UpsertOp op, String auth, {bool force = false}) async {
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
      final req = http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = jsonEncode(payload);
      return http.Response.fromStream(await client.send(req));
    });

    return _parseResponse(res, op.kind, op.id);
  }

  Future<PushResult> _pushDelete(DeleteOp op, String auth, {bool force = false}) async {
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

    final deleteUri = queryParams != null
        ? uri.replace(queryParameters: queryParams)
        : uri;

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
    Map<String, Object?> serverData = {};
    DateTime serverTimestamp = DateTime.now().toUtc();
    String? serverVersion;

    if (res.body.isNotEmpty) {
      try {
        final body = jsonDecode(res.body) as Map<String, Object?>;

        // Поддержка разных форматов ответа от сервера
        serverData = (body['current'] as Map<String, Object?>?) ??
            (body['serverData'] as Map<String, Object?>?) ??
            body;

        final ts = body['serverTimestamp'] ??
            serverData[SyncFields.updatedAt] ??
            serverData[SyncFields.updatedAtSnake];
        if (ts != null) {
          serverTimestamp =
              ts is DateTime ? ts : DateTime.parse(ts.toString()).toUtc();
        }

        serverVersion =
            body['version']?.toString() ?? res.headers['etag'];
      } catch (_) {}
    }

    return PushConflict(
      serverData: serverData,
      serverTimestamp: serverTimestamp,
      serverVersion: serverVersion,
    );
  }

  @override
  Future<PushResult> forcePush(Op op) async {
    final auth = await token();
    return _pushSingleOp(op, auth, force: true);
  }

  @override
  Future<FetchResult> fetch({
    required String kind,
    required String id,
  }) async {
    try {
      final auth = await token();
      final uri = _url('$kind/$id');

      final res = await _withRetry(
          () => client.get(uri, headers: _headers(auth)));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, Object?>;
        final version = res.headers['etag'];
        return FetchSuccess(data: data, version: version);
      }

      if (res.statusCode == 404) {
        return const FetchNotFound();
      }

      return FetchError(
        TransportException.httpError(res.statusCode, res.body),
      );
    } on SyncException catch (e, st) {
      return FetchError(e, st);
    } catch (e, st) {
      return FetchError(NetworkException.fromError(e, st), st);
    }
  }

  Future<http.Response> _withRetry(Future<http.Response> Function() send) async {
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
