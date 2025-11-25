import 'package:drift/drift.dart';

/// Data class для записи в SyncCursors.
class SyncCursorsData extends DataClass implements Insertable<SyncCursorsData> {
  /// Тип сущности.
  final String kind;

  /// Timestamp последнего элемента (milliseconds UTC).
  final int ts;

  /// ID последнего элемента.
  final String lastId;

  const SyncCursorsData({
    required this.kind,
    required this.ts,
    required this.lastId,
  });

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return {
      'kind': Variable<String>(kind),
      'ts': Variable<int>(ts),
      'last_id': Variable<String>(lastId),
    };
  }

  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return {
      'kind': serializer.toJson<String>(kind),
      'ts': serializer.toJson<int>(ts),
      'lastId': serializer.toJson<String>(lastId),
    };
  }
}

/// Таблица курсоров для стабильной пагинации при pull.
/// Хранит позицию последней синхронизации по каждому kind.
@UseRowClass(SyncCursorsData)
class SyncCursors extends Table {
  /// Тип сущности.
  TextColumn get kind => text()();

  /// Timestamp последнего элемента (milliseconds UTC).
  IntColumn get ts => integer()();

  /// ID последнего элемента для разрешения коллизий при одинаковом ts.
  TextColumn get lastId => text()();

  @override
  Set<Column> get primaryKey => {kind};

  @override
  String get tableName => 'sync_cursors';
}

/// Companion class для вставки/обновления записей в SyncCursors.
class SyncCursorsCompanion extends UpdateCompanion<SyncCursorsData> {
  final Value<String> kind;
  final Value<int> ts;
  final Value<String> lastId;

  const SyncCursorsCompanion({
    this.kind = const Value.absent(),
    this.ts = const Value.absent(),
    this.lastId = const Value.absent(),
  });

  SyncCursorsCompanion.insert({
    required String kind,
    required int ts,
    required String lastId,
  })  : kind = Value(kind),
        ts = Value(ts),
        lastId = Value(lastId);

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    return {
      if (kind.present) 'kind': Variable<String>(kind.value),
      if (ts.present) 'ts': Variable<int>(ts.value),
      if (lastId.present) 'last_id': Variable<String>(lastId.value),
    };
  }
}
