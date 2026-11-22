import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'tasks_repository.dart';

enum LocalAssistantDraftKind { note, task }

bool _validText(String value) {
  var decoded = utf8.decode(utf8.encode(value));
  if (value.startsWith('\ufeff')) decoded = '\ufeff$decoded';
  return decoded == value;
}

/// Typed model proposals are data. They carry no resource ID, SQL, editor type,
/// path or authorization to save. The editor's final input is hashed separately.
final class LocalAssistantDraftPayload {
  LocalAssistantDraftPayload._({
    required this.kind,
    required this.content,
    this.title = '',
    this.dueDate = '',
  });
  factory LocalAssistantDraftPayload.note({
    required String title,
    required String content,
  }) {
    final name = title.trim();
    if (name.isEmpty ||
        utf8.encode(name).length > 200 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
        !_validText(name) ||
        content.trim().isEmpty ||
        utf8.encode(content).length > 24000 ||
        !_validText(content)) {
      throw const FormatException('Invalid assistant note proposal');
    }
    return LocalAssistantDraftPayload._(
      kind: LocalAssistantDraftKind.note,
      title: name,
      content: content,
    );
  }
  factory LocalAssistantDraftPayload.task({
    required String content,
    String dueDate = '',
  }) {
    final text = content.trim();
    if (text.isEmpty ||
        text.runes.length > 1000 ||
        utf8.encode(text).length > 4000 ||
        !_validText(text) ||
        (dueDate.isNotEmpty && !validTaskDate(dueDate))) {
      throw const FormatException('Invalid assistant task proposal');
    }
    return LocalAssistantDraftPayload._(
      kind: LocalAssistantDraftKind.task,
      content: text,
      dueDate: dueDate,
    );
  }
  factory LocalAssistantDraftPayload.fromJson(Object? raw) {
    if (raw is! Map || raw['content'] is! String) {
      throw const FormatException('Invalid assistant proposal');
    }
    if (raw['kind'] == 'note' &&
        raw['title'] is String &&
        raw.keys.every((key) => {'kind', 'title', 'content'}.contains(key))) {
      return LocalAssistantDraftPayload.note(
        title: raw['title'] as String,
        content: raw['content'] as String,
      );
    }
    if (raw['kind'] == 'task' &&
        (raw['due_date'] == null || raw['due_date'] is String) &&
        raw.keys.every(
          (key) => {'kind', 'content', 'due_date'}.contains(key),
        )) {
      return LocalAssistantDraftPayload.task(
        content: raw['content'] as String,
        dueDate: raw['due_date'] as String? ?? '',
      );
    }
    throw const FormatException('Unsupported assistant proposal fields');
  }
  final LocalAssistantDraftKind kind;
  final String title, content, dueDate;
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    if (kind == LocalAssistantDraftKind.note) 'title': title,
    'content': content,
    if (kind == LocalAssistantDraftKind.task) 'due_date': dueDate,
  };
  String get digest =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();
}
