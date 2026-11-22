import 'dart:convert';
import 'bookmarks_repository.dart';
import 'secure_record_store.dart';

class BookmarkDraftVault extends SecureRecordStore {
  BookmarkDraftVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.bookmark-draft.v1');
  Future<BookmarkItem?> read(BookmarkItem original) async {
    final value = await readRecord(original.id);
    if (value == null) return null;
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Bookmark draft too large');
    }
    final row = jsonDecode(value) as Map;
    if (row['version'] != 1 ||
        row['id'] != original.id ||
        row['title'] is! String ||
        row['url'] is! String ||
        row['description'] is! String ||
        row['labels'] is! List ||
        row['is_public'] is! bool) {
      throw const FormatException('Invalid bookmark draft');
    }
    return original.copyWith(
      title: row['title'] as String,
      url: row['url'] as String,
      description: row['description'] as String,
      labels: (row['labels'] as List).cast<String>(),
      isPublic: row['is_public'] as bool,
      favicon: row['favicon'] as String? ?? '',
    );
  }

  Future<void> write(BookmarkItem item) {
    final value = jsonEncode({
      'version': 1,
      'id': item.id,
      'title': item.title,
      'url': item.url,
      'description': item.description,
      'labels': item.labels,
      'is_public': item.isPublic,
      'favicon': item.favicon,
    });
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Bookmark draft too large');
    }
    return writeRecord(item.id, value);
  }

  Future<void> remove(int? id) => removeRecord(id);
}
