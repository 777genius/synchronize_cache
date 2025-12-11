import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:offline_first_sync_drift/offline_first_sync_drift.dart';

part 'health_record.g.dart';

/// Health record model.
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

/// Health records table.
@UseRowClass(HealthRecord, generateInsertable: true)
class HealthRecords extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get type => text()();
  IntColumn get userId => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
