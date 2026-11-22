import 'dart:convert';
import 'topic_creation_metadata.dart';
import 'topic_creation_attempt.dart';

class TopicCreationDirectoryEntry {
  const TopicCreationDirectoryEntry({
    required this.recordKey,
    required this.attemptKey,
    this.slotKey,
    this.kind,
    this.topicId,
    this.target,
    this.targetId,
    this.phase,
    this.actualId,
  });
  final String recordKey, attemptKey;
  final String? slotKey;
  final TopicCreationKind? kind;
  final TopicCreationPhase? phase;
  final int? topicId, targetId, actualId;
  final String? target;
}

/// Only keys and current-scope slot pointers are read. No readAll body/credentials.
class TopicCreationDirectory {
  TopicCreationDirectory({
    required this.scope,
    required this.metadata,
    required this.read,
    required this.isCurrent,
  });
  final String scope;
  final Future<Object?> Function() metadata;
  final Future<String?> Function(String) read;
  final bool Function() isCurrent;
  void guard() {
    if (!isCurrent()) throw StateError('Topic recovery scope retired');
  }

  Future<List<TopicCreationDirectoryEntry>> list() async {
    guard();
    final root = await metadata();
    guard();
    if (root is! Map ||
        root.length != 5 ||
        root['format'] != 1 ||
        root['overflow'] != false ||
        root['valuesIncluded'] != false ||
        root['secureKeys'] is! List ||
        root['htmlKeys'] is! List) {
      throw const FormatException(
        'Bounded keys-only recovery metadata required',
      );
    }
    final keys = root['secureKeys'] as List, html = root['htmlKeys'] as List;
    if (keys.length + html.length > 4096) {
      throw const FormatException('Recovery index exceeds bound');
    }
    var bytes = 0;
    final seen = <String>{};
    for (final key in [...keys, ...html]) {
      if (key is! String || key.length > 65536) {
        throw const FormatException('Invalid recovery metadata key');
      }
      bytes += utf8.encode(key).length;
      if (bytes > 1024 * 1024 || !seen.add(key)) {
        throw const FormatException('Ambiguous or oversized metadata');
      }
    }
    final records = <String, TopicCreationDirectoryEntry>{};
    final slots = <String>[];
    for (final value in keys) {
      final key = value as String;
      if (!key.startsWith(TopicCreationMetadata.recordPrefix) &&
          !key.startsWith(TopicCreationMetadata.slotPrefix)) {
        continue;
      }
      final parsed = TopicCreationMetadata.parse(key);
      if (parsed.scope != scope) continue;
      if (parsed.slot) {
        slots.add(key);
      } else {
        records[parsed.identity] = TopicCreationDirectoryEntry(
          recordKey: key,
          attemptKey: parsed.identity,
        );
      }
    }
    if (records.length > 16 || slots.length > 16) {
      throw const FormatException(
        'Too many retained topic creations; no records were omitted or changed',
      );
    }
    for (final slot in slots) {
      final key = await read(slot);
      guard();
      if (key == null || !RegExp(r'^[a-f0-9]{32}$').hasMatch(key)) {
        throw const FormatException('Retained topic slot unavailable');
      }
      final recordKey = '${TopicCreationMetadata.recordPrefix}$scope.$key';
      final prior = records[key];
      if (prior?.slotKey != null) {
        throw const FormatException('Two slots point to the same creation');
      }
      records[key] = TopicCreationDirectoryEntry(
        recordKey: recordKey,
        attemptKey: key,
        slotKey: slot,
      );
    }
    if (records.length > 16) {
      throw const FormatException('Too many topic recovery entries');
    }
    final result = <TopicCreationDirectoryEntry>[];
    var sourceBytes = 0;
    for (final entry in records.values) {
      final raw = await read(entry.recordKey);
      guard();
      if (raw == null) {
        result.add(entry);
        continue;
      }
      if (raw.length > 512 * 1024) {
        throw const FormatException('Retained record exceeds bound');
      }
      sourceBytes += utf8.encode(raw).length;
      if (sourceBytes > 8 * 1024 * 1024) {
        throw const FormatException('Recovery directory exceeds byte budget');
      }
      final a = TopicCreationAttempt.decode(raw);
      if (a.scope != scope || a.key != entry.attemptKey) {
        throw const FormatException('Recovery directory identity mismatch');
      }
      result.add(
        TopicCreationDirectoryEntry(
          recordKey: entry.recordKey,
          attemptKey: entry.attemptKey,
          slotKey: entry.slotKey,
          kind: a.kind,
          topicId: a.topicId,
          target: a.target,
          targetId: a.targetId,
          phase: a.phase,
          actualId: a.actualId,
        ),
      );
    }
    return List.unmodifiable(result);
  }
}
