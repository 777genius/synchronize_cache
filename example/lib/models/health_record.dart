import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:synchronize_cache/synchronize_cache.dart';

part 'health_record.g.dart';

/// Модель записи о здоровье.
@JsonSerializable(fieldRename: FieldRename.snake)
class HealthRecord {
  HealthRecord({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.type,
    required this.userId,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final String type;
  final int userId;

  factory HealthRecord.fromJson(Map<String, dynamic> json) =>
      _$HealthRecordFromJson(json);

  Map<String, dynamic> toJson() => _$HealthRecordToJson(this);
}

/// Таблица записей о здоровье.
@UseRowClass(HealthRecord, generateInsertable: true)
class HealthRecords extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get type => text()();
  IntColumn get userId => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
