import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Тестовый HTTP сервер для e2e тестов конфликтов.
///
/// Эмулирует REST API с поддержкой:
/// - Хранение данных в памяти
/// - Детекция конфликтов по _baseUpdatedAt
/// - Force push через X-Force-Update header
/// - Пагинация при pull
/// - Batch API для пакетной обработки
class TestServer {
  TestServer({this.conflictCheckEnabled = true});

  HttpServer? _server;
  int? _port;

  /// Включена ли проверка конфликтов.
  bool conflictCheckEnabled;

  /// In-memory storage: kind -> id -> data.
  final Map<String, Map<String, Map<String, Object?>>> _storage = {};

  /// Версии сущностей (ETag).
  final Map<String, Map<String, int>> _versions = {};

  /// Счётчик запросов по типам.
  final Map<String, int> requestCounts = {};

  /// Последние запросы.
  final List<RecordedRequest> recordedRequests = [];

  /// Количество запросов которые нужно провалить.
  int _failNextRequests = 0;

  /// Код ошибки для провальных запросов.
  int _failStatusCode = 500;

  /// Задержка для следующих запросов.
  Duration? _nextDelay;

  /// Количество запросов с задержкой.
  int _delayedRequestsCount = 0;

  /// Флаг для возврата невалидного JSON.
  bool _returnInvalidJson = false;

  /// Флаг для возврата неполных данных в conflict response.
  bool _returnIncompleteConflict = false;

  /// Флаг для возврата неправильной сущности в conflict response.
  bool _returnWrongEntity = false;

  /// Порт сервера.
  int get port => _port ?? 0;

  /// Базовый URL сервера.
  Uri get baseUrl => Uri.parse('http://localhost:$port');

  /// Запустить сервер.
  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen(_handleRequest);
  }

  /// Остановить сервер.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }

  /// Очистить хранилище.
  void clear() {
    _storage.clear();
    _versions.clear();
    requestCounts.clear();
    recordedRequests.clear();
    _failNextRequests = 0;
    _nextDelay = null;
    _delayedRequestsCount = 0;
    _returnInvalidJson = false;
    _returnIncompleteConflict = false;
    _returnWrongEntity = false;
  }

  /// Сделать следующие N запросов неудачными с указанным кодом.
  void failNextRequests(int count, {int statusCode = 500}) {
    _failNextRequests = count;
    _failStatusCode = statusCode;
  }

  /// Добавить задержку к следующим N запросам.
  void delayNextRequests(Duration delay, {int count = 1}) {
    _nextDelay = delay;
    _delayedRequestsCount = count;
  }

  /// Возвращать невалидный JSON на следующие запросы.
  void returnInvalidJson(bool enabled) {
    _returnInvalidJson = enabled;
  }

  /// Возвращать неполные данные в conflict response.
  void returnIncompleteConflict(bool enabled) {
    _returnIncompleteConflict = enabled;
  }

  /// Возвращать неправильную сущность в conflict response.
  void returnWrongEntity(bool enabled) {
    _returnWrongEntity = enabled;
  }

  DateTime _now() {
    final now = DateTime.now().toUtc();
    return DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
      now.second,
    );
  }

  /// Добавить данные в хранилище (seed).
  void seed(String kind, Map<String, Object?> data) {
    final id = data['id'] as String;
    _storage.putIfAbsent(kind, () => {});
    _versions.putIfAbsent(kind, () => {});

    final now = _now();
    final seededData = Map<String, Object?>.from(data);
    seededData['updated_at'] ??= now.toIso8601String();
    seededData['created_at'] ??= now.toIso8601String();

    _storage[kind]![id] = seededData;
    _versions[kind]![id] = 1;
  }

  /// Получить данные из хранилища.
  Map<String, Object?>? get(String kind, String id) => _storage[kind]?[id];

  /// Получить все данные по kind.
  List<Map<String, Object?>> getAll(String kind) =>
      _storage[kind]?.values.toList() ?? [];

  /// Обновить данные напрямую (для симуляции конкурентных изменений).
  void update(String kind, String id, Map<String, Object?> data) {
    _storage.putIfAbsent(kind, () => {});
    _versions.putIfAbsent(kind, () => {});

    final existing = _storage[kind]![id];
    final now = _now();

    final updatedData = <String, Object?>{
      ...?existing,
      ...data,
    };

    if (!data.containsKey('updated_at')) {
      updatedData['updated_at'] = now.toIso8601String();
    }

    _storage[kind]![id] = updatedData;
    _versions[kind]![id] = (_versions[kind]![id] ?? 0) + 1;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final method = request.method;
    final path = request.uri.path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();

    requestCounts[method] = (requestCounts[method] ?? 0) + 1;

    try {
      final body = await _readBody(request);
      recordedRequests.add(RecordedRequest(
        method: method,
        path: path,
        headers: request.headers,
        body: body,
      ));

      if (_nextDelay != null && _delayedRequestsCount > 0) {
        await Future<void>.delayed(_nextDelay!);
        _delayedRequestsCount--;
        if (_delayedRequestsCount == 0) {
          _nextDelay = null;
        }
      }

      if (_failNextRequests > 0) {
        _failNextRequests--;
        _sendError(request, _failStatusCode, 'Simulated server error');
        return;
      }

      if (_returnInvalidJson) {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..write('{invalid json data');
        await request.response.close();
        return;
      }

      if (segments.isEmpty) {
        _sendError(request, 404, 'Not Found');
        return;
      }

      if (segments.first == 'health') {
        _sendJson(request, 200, {'status': 'ok'});
        return;
      }

      if (segments.first == 'batch' && method == 'POST') {
        await _handleBatch(request, body);
        return;
      }

      final kind = segments.first;

      switch (method) {
        case 'GET':
          if (segments.length == 1) {
            await _handlePull(request, kind);
          } else {
            await _handleFetch(request, kind, segments[1]);
          }
        case 'POST':
          await _handleCreate(request, kind, body);
        case 'PUT':
          if (segments.length < 2) {
            _sendError(request, 400, 'Missing entity ID');
            return;
          }
          await _handleUpdate(request, kind, segments[1], body);
        case 'DELETE':
          if (segments.length < 2) {
            _sendError(request, 400, 'Missing entity ID');
            return;
          }
          await _handleDelete(request, kind, segments[1]);
        default:
          _sendError(request, 405, 'Method Not Allowed');
      }
    } catch (e, st) {
      _sendError(request, 500, 'Internal Server Error: $e\n$st');
    }
  }

  Future<void> _handleBatch(
      HttpRequest request, Map<String, Object?>? body) async {
    if (body == null || !body.containsKey('ops')) {
      _sendError(request, 400, 'Missing ops in body');
      return;
    }

    final ops = (body['ops'] as List).cast<Map<String, Object?>>();
    final results = <Map<String, Object?>>[];

    for (final op in ops) {
      final opId = op['opId'] as String;
      final kind = op['kind'] as String;
      final id = op['id'] as String;
      final type = op['type'] as String;

      try {
        // Эмулируем результат отдельного запроса
        final result = await _processBatchOp(kind, id, type, op, request);
        results.add({'opId': opId, ...result});
      } catch (e) {
        results.add({
          'opId': opId,
          'statusCode': 500,
          'error': e.toString(),
        });
      }
    }

    _sendJson(request, 200, {'results': results});
  }

  Future<Map<String, Object?>> _processBatchOp(
    String kind,
    String id,
    String type,
    Map<String, Object?> op,
    HttpRequest originalRequest,
  ) async {
    final mockReq = _MockHttpRequest(originalRequest);

    if (type == 'upsert') {
      final payload = op['payload'] as Map<String, Object?>;
      // Добавляем baseUpdatedAt в payload если он есть в op,
      // так как логика update ожидает его там
      if (op.containsKey('baseUpdatedAt')) {
        payload['_baseUpdatedAt'] = op['baseUpdatedAt'];
      }

      if (id.isEmpty) {
        await _handleCreate(mockReq, kind, payload);
      } else {
        await _handleUpdate(mockReq, kind, id, payload);
      }
    } else if (type == 'delete') {
      final queryParams = <String, String>{};
      if (op.containsKey('baseUpdatedAt')) {
        queryParams['_baseUpdatedAt'] = op['baseUpdatedAt'] as String;
      }
      mockReq.overrideUri(Uri(queryParameters: queryParams));

      await _handleDelete(mockReq, kind, id);
    } else {
      return {'statusCode': 400, 'error': 'Unknown type'};
    }

    if (mockReq.responseCode >= 200 && mockReq.responseCode < 300) {
      final res = <String, Object?>{
        'statusCode': mockReq.responseCode,
      };
      if (mockReq.responseBody != null) {
        final data = jsonDecode(mockReq.responseBody!) as Map<String, Object?>;
        res['data'] = data;
        res['version'] = mockReq.responseHeaders['ETag'];
      }
      return res;
    } else if (mockReq.responseCode == 409) {
      // Конфликт
      final body = jsonDecode(mockReq.responseBody!);
      return {
        'statusCode': 409,
        'error': body,
      };
    } else {
      return {
        'statusCode': mockReq.responseCode,
        'error': mockReq.responseBody,
      };
    }
  }

  Future<Map<String, Object?>?> _readBody(HttpRequest request) async {
    if (request.contentLength == 0) return null;

    final content = await utf8.decoder.bind(request).join();
    if (content.isEmpty) return null;

    return jsonDecode(content) as Map<String, Object?>;
  }

  Future<void> _handlePull(HttpRequest request, String kind) async {
    final params = request.uri.queryParameters;
    final updatedSince = params['updatedSince'];
    final limit = int.tryParse(params['limit'] ?? '') ?? 100;
    final pageToken = params['pageToken'];
    final afterId = params['afterId'];
    final includeDeleted = params['includeDeleted'] != 'false';

    var items = getAll(kind);

    if (updatedSince != null) {
      final since = DateTime.parse(updatedSince);
      items = items.where((item) {
        final ts = item['updated_at'] as String?;
        if (ts == null) return true;
        final parsedTs = DateTime.parse(ts);
        return parsedTs.isAfter(since) || parsedTs.isAtSameMomentAs(since);
      }).toList();
    }

    if (!includeDeleted) {
      items = items.where((item) => item['deleted_at'] == null).toList();
    }

    items.sort((a, b) {
      final aTs = a['updated_at'] as String? ?? '';
      final bTs = b['updated_at'] as String? ?? '';
      final cmp = aTs.compareTo(bTs);
      if (cmp != 0) return cmp;
      return (a['id'] as String).compareTo(b['id'] as String);
    });

    var startIndex = 0;
    if (pageToken != null) {
      startIndex = int.tryParse(pageToken) ?? 0;
    } else if (afterId != null) {
      final idx = items.indexWhere((item) => item['id'] == afterId);
      if (idx >= 0) startIndex = idx + 1;
    }

    final endIndex = (startIndex + limit).clamp(0, items.length);
    final pageItems = items.sublist(startIndex, endIndex);

    String? nextPageToken;
    if (endIndex < items.length) {
      nextPageToken = endIndex.toString();
    }

    _sendJson(request, 200, {
      'items': pageItems,
      'nextPageToken': nextPageToken,
    });
  }

  Future<void> _handleFetch(
      HttpRequest request, String kind, String id) async {
    final data = get(kind, id);
    if (data == null) {
      _sendError(request, 404, 'Not Found');
      return;
    }

    final version = _versions[kind]?[id] ?? 1;
    request.response.headers.set('ETag', 'v$version');
    _sendJson(request, 200, data);
  }

  Future<void> _handleCreate(
    HttpRequest request,
    String kind,
    Map<String, Object?>? body,
  ) async {
    if (body == null) {
      _sendError(request, 400, 'Missing body');
      return;
    }

    _storage.putIfAbsent(kind, () => {});
    _versions.putIfAbsent(kind, () => {});

    final id = body['id'] as String? ?? _generateId();
    final now = _now();

    final data = <String, Object?>{
      ...body,
      'id': id,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };

    _storage[kind]![id] = data;
    _versions[kind]![id] = 1;

    request.response.headers.set('ETag', 'v1');
    _sendJson(request, 201, data);
  }

  Future<void> _handleUpdate(
    HttpRequest request,
    String kind,
    String id,
    Map<String, Object?>? body,
  ) async {
    if (body == null) {
      _sendError(request, 400, 'Missing body');
      return;
    }

    final existing = get(kind, id);
    final isForceUpdate = request.headers.value('X-Force-Update') == 'true';

    if (existing == null) {
      _storage.putIfAbsent(kind, () => {});
      _versions.putIfAbsent(kind, () => {});

      final now = _now();
      final data = <String, Object?>{
        ...body,
        'id': id,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      }..remove('_baseUpdatedAt');

      _storage[kind]![id] = data;
      _versions[kind]![id] = 1;

      request.response.headers.set('ETag', 'v1');
      _sendJson(request, 201, data);
      return;
    }

    if (conflictCheckEnabled && !isForceUpdate) {
      final baseUpdatedAt = body['_baseUpdatedAt'] as String?;
      final serverUpdatedAt = existing['updated_at'] as String?;

      if (baseUpdatedAt != null && serverUpdatedAt != null) {
        final baseTs = DateTime.parse(baseUpdatedAt);
        final serverTs = DateTime.parse(serverUpdatedAt);

        if (!baseTs.isAtSameMomentAs(serverTs)) {
          _sendConflict(request, existing);
          return;
        }
      }
    }

    final now = _now();
    final updatedBody = Map<String, Object?>.from(body)
      ..remove('_baseUpdatedAt');

    final data = <String, Object?>{
      ...existing,
      ...updatedBody,
      'updated_at': now.toIso8601String(),
    };

    _storage[kind]![id] = data;
    final version = (_versions[kind]![id] ?? 0) + 1;
    _versions[kind]![id] = version;

    request.response.headers.set('ETag', 'v$version');
    _sendJson(request, 200, data);
  }

  Future<void> _handleDelete(
    HttpRequest request,
    String kind,
    String id,
  ) async {
    final existing = get(kind, id);
    final isForceDelete = request.headers.value('X-Force-Delete') == 'true';

    if (existing == null) {
      _sendError(request, 404, 'Not Found');
      return;
    }

    if (conflictCheckEnabled && !isForceDelete) {
      final params = request.uri.queryParameters;
      final baseUpdatedAt = params['_baseUpdatedAt'];
      final serverUpdatedAt = existing['updated_at'] as String?;

      if (baseUpdatedAt != null && serverUpdatedAt != null) {
        final baseTs = DateTime.parse(baseUpdatedAt);
        final serverTs = DateTime.parse(serverUpdatedAt);

        if (!baseTs.isAtSameMomentAs(serverTs)) {
          _sendConflict(request, existing);
          return;
        }
      }
    }

    _storage[kind]!.remove(id);
    _versions[kind]!.remove(id);

    request.response.statusCode = 204;
    await request.response.close();
  }

  void _sendConflict(HttpRequest request, Map<String, Object?> serverData) {
    final serverTimestamp =
        serverData['updated_at'] ?? _now().toIso8601String();

    if (_returnIncompleteConflict) {
      _sendJson(request, 409, {
        'error': 'conflict',
        'message': 'Data has been modified on server',
      });
      return;
    }

    if (_returnWrongEntity) {
      _sendJson(request, 409, {
        'error': 'conflict',
        'message': 'Data has been modified on server',
        'current': {
          'id': 'wrong-entity-id',
          'name': 'Wrong Entity',
          'updated_at': serverTimestamp,
        },
        'serverTimestamp': serverTimestamp,
        'version': 'v1',
      });
      return;
    }

    _sendJson(request, 409, {
      'error': 'conflict',
      'message': 'Data has been modified on server',
      'current': serverData,
      'serverTimestamp': serverTimestamp,
      'version': 'v${_versions[serverData['kind'] as String? ?? '']?[serverData['id']] ?? 1}',
    });
  }

  void _sendJson(HttpRequest request, int status, Object data) {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(data))
      ..close();
  }

  void _sendError(HttpRequest request, int status, String message) {
    _sendJson(request, status, {'error': message});
  }

  String _generateId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);
}

/// Записанный запрос для проверки в тестах.
class RecordedRequest {
  RecordedRequest({
    required this.method,
    required this.path,
    required this.headers,
    this.body,
  });

  final String method;
  final String path;
  final HttpHeaders headers;
  final Map<String, Object?>? body;
}

class _MockHttpRequest implements HttpRequest {
  _MockHttpRequest(this._original);
  final HttpRequest _original;

  int responseCode = 200;
  String? responseBody;
  final Map<String, String> responseHeaders = {};
  Uri? _uriOverride;

  void overrideUri(Uri uri) => _uriOverride = uri;

  @override
  Uri get uri => _uriOverride ?? _original.uri;

  @override
  HttpHeaders get headers =>
      _MockHttpHeaders(_original.headers); // Use mock wrapper for headers

  @override
  HttpResponse get response => _MockHttpResponse(this);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpResponse implements HttpResponse {
  _MockHttpResponse(this._req);
  final _MockHttpRequest _req;

  @override
  set statusCode(int code) => _req.responseCode = code;

  @override
  HttpHeaders get headers =>
      _MockHttpHeaders(null, _req.responseHeaders); // Pass null as source, map as target

  @override
  void write(Object? obj) {
    _req.responseBody = obj?.toString();
  }

  @override
  Future<void> close() async {} // no-op

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  _MockHttpHeaders(this._headersSource, [this._headersMap]);

  // Источник заголовков (либо реальные HttpHeaders, либо мапа для ответа)
  final HttpHeaders? _headersSource;
  final Map<String, String>? _headersMap;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    if (_headersMap != null) {
      _headersMap[name] = value.toString();
    }
  }
  
  @override
  set contentType(ContentType? contentType) {} // ignore

  @override
  String? value(String name) {
    if (_headersSource != null) {
      return _headersSource.value(name);
    }
    return _headersMap?[name];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
