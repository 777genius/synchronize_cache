import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:synchronize_cache/synchronize_cache.dart';

part 'test_database.g.dart';

class TestEntity {
  TestEntity({
    required this.id,
    required this.updatedAt,
    this.deletedAt,
    this.deletedAtLocal,
    required this.name,
    this.mood,
    this.energy,
    this.notes,
    this.settings,
    this.tags,
  });

  final String id;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? deletedAtLocal;
  final String name;
  final int? mood;
  final int? energy;
  final String? notes;
  final String? settings;
  final String? tags;

  factory TestEntity.fromJson(Map<String, dynamic> json) => TestEntity(
        id: json['id'] as String,
        updatedAt: DateTime.parse(json['updated_at'] as String),
        deletedAt: json['deleted_at'] != null
            ? DateTime.parse(json['deleted_at'] as String)
            : null,
        name: json['name'] as String? ?? '',
        mood: json['mood'] as int?,
        energy: json['energy'] as int?,
        notes: json['notes'] as String?,
        settings: json['settings'] is String
            ? json['settings'] as String
            : json['settings'] != null
                ? jsonEncode(json['settings'])
                : null,
        tags: json['tags'] is String
            ? json['tags'] as String
            : json['tags'] != null
                ? jsonEncode(json['tags'])
                : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'name': name,
        'mood': mood,
        'energy': energy,
        'notes': notes,
        'settings': settings,
        'tags': tags,
      };

  Map<String, Object?>? get settingsMap =>
      settings != null ? jsonDecode(settings!) as Map<String, Object?> : null;

  List<Object?>? get tagsList =>
      tags != null ? jsonDecode(tags!) as List<Object?> : null;
}

@UseRowClass(TestEntity, generateInsertable: true)
class TestEntities extends Table with SyncColumns {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get mood => integer().nullable()();
  IntColumn get energy => integer().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get settings => text().nullable()();
  TextColumn get tags => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  include: {'package:synchronize_cache/src/sync_tables.drift'},
  tables: [TestEntities],
)
class TestDatabase extends _$TestDatabase with SyncDatabaseMixin {
  TestDatabase() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}

