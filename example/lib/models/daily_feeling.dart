import 'package:drift/drift.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:synchronize_cache/synchronize_cache.dart';

part 'daily_feeling.g.dart';

/// Модель ежедневного самочувствия.
@JsonSerializable(fieldRename: FieldRename.snake)
class DailyFeeling {
  DailyFeeling({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.date,
    required this.feeling,
    this.comment,
    required this.healthRecordId,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final DateTime date;
  final String feeling;
  final String? comment;
  final int healthRecordId;

  factory DailyFeeling.fromJson(Map<String, dynamic> json) =>
      _$DailyFeelingFromJson(json);

  Map<String, dynamic> toJson() => _$DailyFeelingToJson(this);
}

/// Таблица ежедневного самочувствия.
@UseRowClass(DailyFeeling, generateInsertable: true)
class DailyFeelings extends Table with SyncColumns {
  TextColumn get id => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get feeling => text()();
  TextColumn get comment => text().nullable()();
  IntColumn get healthRecordId => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
