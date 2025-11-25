/// Курсор для стабильной пагинации: (updatedAt, lastId).
class Cursor {
  const Cursor({required this.ts, required this.lastId});

  /// Timestamp последнего элемента.
  final DateTime ts;

  /// ID последнего элемента для разрешения коллизий.
  final String lastId;
}

