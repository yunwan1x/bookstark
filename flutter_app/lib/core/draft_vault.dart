import 'dart:convert';
import 'notes_repository.dart';
import 'secure_record_store.dart';

/// Backed by platform secure storage in the app; no credentials are serialized.
class DraftVault extends SecureRecordStore {
  DraftVault({
    required super.namespace,
    super.maintenance,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.draft.v1');
  Future<Note?> read(int? id) async {
    final value = await readRecord(id);
    if (value == null) return null;
    final data = jsonDecode(value) as Map<String, dynamic>;
    if (data['version'] != 1 ||
        data['title'] is! String ||
        data['content'] is! String ||
        data['labels'] is! List) {
      throw const FormatException('Invalid note draft');
    }
    return Note(
      id: id,
      title: data['title'] as String,
      content: data['content'] as String,
      labels: (data['labels'] as List).cast<String>(),
    );
  }

  Future<void> write(Note note) {
    if (note.isProtected || note.unlockPassword != null) {
      return Future<void>.error(
        ArgumentError('Protected notes cannot be persisted as drafts'),
      );
    }
    final value = jsonEncode({
      'version': 1,
      'title': note.title,
      'content': note.content,
      'labels': note.labels,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    });
    return writeRecord(note.id, value);
  }

  Future<void> remove(int? id) => removeRecord(id);
}
