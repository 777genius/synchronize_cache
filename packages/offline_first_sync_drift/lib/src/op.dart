/// Outbox операции: upsert/delete с idempotency через opId.
sealed class Op {
  Op({
    required this.opId,
    required this.kind,
    required this.id,
    required this.localTimestamp,
  });

  /// UUID операции для идемпотентности.
  final String opId;

  /// Тип сущности.
  final String kind;

  /// ID сущности.
  final String id;

  /// Локальное время создания операции.
  final DateTime localTimestamp;
}

/// Операция создания/обновления сущности.
class UpsertOp extends Op {
  UpsertOp({
    required super.opId,
    required super.kind,
    required super.id,
    required super.localTimestamp,
    required this.payloadJson,
    this.baseUpdatedAt,
    this.changedFields,
  });

  /// JSON payload для отправки на сервер.
  final Map<String, Object?> payloadJson;

  /// Timestamp когда данные были получены с сервера.
  /// Используется для детекции конфликтов.
  /// null означает новую запись.
  final DateTime? baseUpdatedAt;

  /// Список полей, которые были изменены пользователем.
  /// null означает что все поля считаются изменёнными.
  final Set<String>? changedFields;

  /// Является ли запись новой (не существовала на сервере).
  bool get isNewRecord => baseUpdatedAt == null;

  /// Создать копию с изменёнными параметрами.
  UpsertOp copyWith({
    String? opId,
    String? kind,
    String? id,
    DateTime? localTimestamp,
    Map<String, Object?>? payloadJson,
    DateTime? baseUpdatedAt,
    Set<String>? changedFields,
  }) => UpsertOp(
    opId: opId ?? this.opId,
    kind: kind ?? this.kind,
    id: id ?? this.id,
    localTimestamp: localTimestamp ?? this.localTimestamp,
    payloadJson: payloadJson ?? this.payloadJson,
    baseUpdatedAt: baseUpdatedAt ?? this.baseUpdatedAt,
    changedFields: changedFields ?? this.changedFields,
  );
}

/// Операция удаления сущности.
class DeleteOp extends Op {
  DeleteOp({
    required super.opId,
    required super.kind,
    required super.id,
    required super.localTimestamp,
    this.baseUpdatedAt,
  });

  /// Timestamp когда данные были получены с сервера.
  final DateTime? baseUpdatedAt;
}
