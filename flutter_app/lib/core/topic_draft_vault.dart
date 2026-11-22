import 'dart:convert';
import 'topics_repository.dart';
import 'secure_record_store.dart';

class TopicDraftVault extends SecureRecordStore {
  TopicDraftVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.topic-draft.v1');
  Future<TopicItem?> read(TopicItem original) async {
    final value = await readRecord(original.id);
    if (value == null) return null;
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Topic draft too large');
    }
    final row = jsonDecode(value) as Map;
    if (row['version'] != 1 ||
        row['id'] != original.id ||
        row['title'] is! String ||
        row['question'] is! String ||
        row['is_pinned'] is! bool) {
      throw const FormatException('Invalid topic draft');
    }
    return original.copyWith(
      title: row['title'] as String,
      question: row['question'] as String,
      isPinned: row['is_pinned'] as bool,
    );
  }

  Future<void> write(TopicItem item) {
    final value = jsonEncode({
      'version': 1,
      'id': item.id,
      'title': item.title,
      'question': item.question,
      'is_pinned': item.isPinned,
    });
    if (utf8.encode(value).length > 128 * 1024) {
      throw const FormatException('Topic draft too large');
    }
    return writeRecord(item.id, value);
  }

  Future<void> remove(int? id) => removeRecord(id);
}
