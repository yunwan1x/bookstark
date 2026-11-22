import 'dart:convert';
import 'books_repository.dart';
import 'secure_record_store.dart';

class BookDraftVault extends SecureRecordStore {
  BookDraftVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.book-draft.v1');
  Future<BookItem?> read(int? id) async {
    final value = await readRecord(id);
    if (value == null) return null;
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Book draft too large');
    }
    final row = jsonDecode(value) as Map;
    if (row['version'] != 1 ||
        row['id'] != id ||
        row['name'] is! String ||
        row['description'] is! String ||
        row['labels'] is! List) {
      throw const FormatException('Invalid book draft');
    }
    return BookItem(
      id: id,
      name: row['name'] as String,
      description: row['description'] as String,
      labels: (row['labels'] as List).cast<String>().toList(),
    );
  }

  Future<void> write(BookItem item) {
    final value = jsonEncode({
      'version': 1,
      'id': item.id,
      'name': item.name,
      'description': item.description,
      'labels': item.labels,
    });
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Book draft too large');
    }
    return writeRecord(item.id, value);
  }

  Future<void> remove(int? id) => removeRecord(id);
}
