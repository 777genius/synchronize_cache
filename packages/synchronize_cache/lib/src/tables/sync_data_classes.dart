class SyncOutboxData {
  final String opId;
  final String kind;
  final String entityId;
  final String op;
  final String? payload;
  final int ts;
  final int tryCount;
  final int? baseUpdatedAt;
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
}

class SyncCursorData {
  final String kind;
  final int ts;
  final String lastId;

  const SyncCursorData({
    required this.kind,
    required this.ts,
    required this.lastId,
  });
}

