import 'dart:convert';
import 'task_draft_vault.dart';

String taskCreationDraftNamespace(String root, int topic, String? requested) {
  final value = requested ?? root;
  if (value == root) return value;
  Object? decoded;
  try {
    decoded = jsonDecode(value);
  } catch (_) {
    throw const FormatException(
      'Task draft namespace is not in this owner scope',
    );
  }
  if (decoded is! List ||
      decoded.length != 3 ||
      decoded[0] != root ||
      decoded[1] != 'topic-tasks' ||
      decoded[2] is! int ||
      (decoded[2] as int) <= 0 ||
      decoded[2] != topic ||
      jsonEncode(decoded) != value) {
    throw const FormatException(
      'Task draft namespace is not in this topic scope',
    );
  }
  return value;
}

TaskDraftVault taskCreationBoundVault(
  String namespace, {
  required Future<String?> Function(String) read,
  required Future<void> Function(String, String) write,
  required Future<void> Function(String) remove,
}) => TaskDraftVault(
  namespace: namespace,
  readValue: read,
  writeValue: write,
  deleteValue: remove,
);
