import 'package:drift/drift.dart';

/// Data class для записи в SyncOutbox.
class SyncOutboxData extends DataClass implements Insertable<SyncOutboxData> {
  /// Уникальный идентификатор операции.
  final String opId;

  /// Тип сущности.
  final String kind;

  /// ID сущности.
  final String entityId;

  /// Тип операции: 'upsert' или 'delete'.
  final String op;

  /// JSON payload для upsert операций.
  final String? payload;

  /// Timestamp операции (milliseconds UTC).
  final int ts;

  /// Количество попыток отправки.
  final int tryCount;

  /// Timestamp когда данные были получены с сервера (milliseconds UTC).
  /// null для новых записей.
  final int? baseUpdatedAt;

  /// JSON array с именами изменённых полей.
  /// null означает все поля изменены.
  final String? changedFields;

  const SyncOutboxData({
    required this.opId,
    required this.kind,
    required this.entityId,
    required this.op,
    this.payload,
    required this.ts,
    required this.tryCount,
    this.baseUpdatedAt,
    this.changedFields,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return {
      'op_id': Variable<String>(opId),
      'kind': Variable<String>(kind),
      'entity_id': Variable<String>(entityId),
      'op': Variable<String>(op),
      if (!nullToAbsent || payload != null)
        'payload': Variable<String>(payload),
      'ts': Variable<int>(ts),
      'try_count': Variable<int>(tryCount),
      if (!nullToAbsent || baseUpdatedAt != null)
        'base_updated_at': Variable<int>(baseUpdatedAt),
      if (!nullToAbsent || changedFields != null)
        'changed_fields': Variable<String>(changedFields),
    };
  }

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return {
      'opId': serializer.toJson<String>(opId),
      'kind': serializer.toJson<String>(kind),
      'entityId': serializer.toJson<String>(entityId),
      'op': serializer.toJson<String>(op),
      'payload': serializer.toJson<String?>(payload),
      'ts': serializer.toJson<int>(ts),
      'tryCount': serializer.toJson<int>(tryCount),
      'baseUpdatedAt': serializer.toJson<int?>(baseUpdatedAt),
      'changedFields': serializer.toJson<String?>(changedFields),
    };
  }
}

/// Таблица очереди операций для синхронизации.
/// Хранит локальные изменения до отправки на сервер.
@UseRowClass(SyncOutboxData)
class SyncOutbox extends Table {
  /// Уникальный идентификатор операции.
  TextColumn get opId => text()();

  /// Тип сущности (например, 'daily_feeling').
  TextColumn get kind => text()();

  /// ID сущности.
  TextColumn get entityId => text()();

  /// Тип операции: 'upsert' или 'delete'.
  TextColumn get op => text()();

  /// JSON payload для upsert операций.
  TextColumn get payload => text().nullable()();

  /// Timestamp операции (milliseconds UTC).
  IntColumn get ts => integer()();

  /// Количество попыток отправки.
  IntColumn get tryCount => integer().withDefault(const Constant(0))();

  /// Timestamp когда данные были получены с сервера (milliseconds UTC).
  IntColumn get baseUpdatedAt => integer().nullable()();

  /// JSON array с именами изменённых полей.
  TextColumn get changedFields => text().nullable()();

  @override
  Set<Column> get primaryKey => {opId};

  @override
  String get tableName => 'sync_outbox';
}

/// Companion class для вставки/обновления записей в SyncOutbox.
class SyncOutboxCompanion extends UpdateCompanion<SyncOutboxData> {
  final Value<String> opId;
  final Value<String> kind;
  final Value<String> entityId;
  final Value<String> op;
  final Value<String?> payload;
  final Value<int> ts;
  final Value<int> tryCount;
  final Value<int?> baseUpdatedAt;
  final Value<String?> changedFields;

  const SyncOutboxCompanion({
    this.opId = const Value.absent(),
    this.kind = const Value.absent(),
    this.entityId = const Value.absent(),
    this.op = const Value.absent(),
    this.payload = const Value.absent(),
    this.ts = const Value.absent(),
    this.tryCount = const Value.absent(),
    this.baseUpdatedAt = const Value.absent(),
    this.changedFields = const Value.absent(),
  });

  SyncOutboxCompanion.insert({
    required String opId,
    required String kind,
    required String entityId,
    required String op,
    this.payload = const Value.absent(),
    required int ts,
    this.tryCount = const Value.absent(),
    this.baseUpdatedAt = const Value.absent(),
    this.changedFields = const Value.absent(),
  })  : opId = Value(opId),
        kind = Value(kind),
        entityId = Value(entityId),
        op = Value(op),
        ts = Value(ts);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return {
      if (opId.present) 'op_id': Variable<String>(opId.value),
      if (kind.present) 'kind': Variable<String>(kind.value),
      if (entityId.present) 'entity_id': Variable<String>(entityId.value),
      if (op.present) 'op': Variable<String>(op.value),
      if (payload.present) 'payload': Variable<String>(payload.value),
      if (ts.present) 'ts': Variable<int>(ts.value),
      if (tryCount.present) 'try_count': Variable<int>(tryCount.value),
      if (baseUpdatedAt.present)
        'base_updated_at': Variable<int>(baseUpdatedAt.value),
      if (changedFields.present)
        'changed_fields': Variable<String>(changedFields.value),
    };
  }
}
