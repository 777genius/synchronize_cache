import 'package:synchronize_cache/src/cursor.dart';
import 'package:synchronize_cache/src/exceptions.dart';
import 'package:synchronize_cache/src/sync_database.dart';

/// Сервис для работы с курсорами синхронизации.
class CursorService {
  CursorService(this._db);

  final SyncDatabaseMixin _db;

  /// Получить курсор для типа сущности.
  Future<Cursor?> get(String kind) async {
    try {
      return await _db.getCursor(kind);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Сохранить курсор для типа сущности.
  Future<void> set(String kind, Cursor cursor) async {
    try {
      await _db.setCursor(kind, cursor);
    } catch (e, st) {
      throw DatabaseException.fromError(e, st);
    }
  }

  /// Сбросить курсор для типа сущности.
  Future<void> reset(String kind) async {
    await set(kind, Cursor(
      ts: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastId: '',
    ));
  }
}

