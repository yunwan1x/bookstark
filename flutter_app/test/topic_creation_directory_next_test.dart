import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/topic_creation_attempt.dart';
import 'package:bookstark_flutter/core/topic_creation_directory.dart';
import 'package:bookstark_flutter/core/topic_creation_metadata.dart';
import 'package:bookstark_flutter/core/topic_creation_slot.dart';

void main() {
  test(
    'cold directory reads only own scoped bodies/slots and retains exact source',
    () async {
      final scope = 'a' * 64,
          other = 'b' * 64,
          reads = <String>[],
          values = <String, String>{};
      final own = TopicCreationAttempt(
        scope: scope,
        key: 'c' * 32,
        kind: TopicCreationKind.comment,
        topicId: 9,
        target: 'summary',
        targetId: 3,
        body: {
          'content': '\ufeffExact\r\n😀',
          'target_type': 'summary',
          'target_id': 3,
          'parent_comment_id': 0,
        },
        phase: TopicCreationPhase.unknown,
      );
      final foreign = TopicCreationAttempt(
        scope: other,
        key: 'd' * 32,
        kind: TopicCreationKind.topic,
        topicId: 0,
        target: '',
        targetId: 0,
        body: {
          'title': 'Other account',
          'question': 'Private',
          'is_pinned': false,
        },
      );
      final record = '${TopicCreationMetadata.recordPrefix}$scope.${own.key}';
      final foreignRecord =
          '${TopicCreationMetadata.recordPrefix}$other.${foreign.key}';
      final slot = TopicCreationSlot(
        scope: scope,
        kind: own.kind,
        topicId: 9,
        target: 'summary',
        targetId: 3,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      values[record] = own.encode();
      values[foreignRecord] = foreign.encode();
      values[slot.metadataKey] = own.key;
      final directory = TopicCreationDirectory(
        scope: scope,
        metadata: () async => {
          'format': 1,
          'secureKeys': [record, foreignRecord, slot.metadataKey],
          'htmlKeys': <String>[],
          'overflow': false,
          'valuesIncluded': false,
        },
        read: (k) async {
          reads.add(k);
          return values[k];
        },
        isCurrent: () => true,
      );
      final before = Map<String, String>.of(values);
      final rows = await directory.list();
      expect(rows, hasLength(1));
      expect(rows.single.phase, TopicCreationPhase.unknown);
      expect(rows.single.topicId, 9);
      expect(rows.single.targetId, 3);
      expect(reads, contains(record));
      expect(reads, contains(slot.metadataKey));
      expect(reads, isNot(contains(foreignRecord)));
      expect(values, before);
      expect(
        TopicCreationAttempt.decode(values[record]!).body['content'],
        '\ufeffExact\r\n😀',
      );
    },
  );
  test(
    'overflow or corrupt metadata never becomes empty or changes records',
    () async {
      final values = <String, String>{}, scope = 'e' * 64;
      var overflow = true;
      final d = TopicCreationDirectory(
        scope: scope,
        metadata: () async => {
          'format': 1,
          'secureKeys': ['${TopicCreationMetadata.recordPrefix}bad'],
          'htmlKeys': <String>[],
          'overflow': overflow,
          'valuesIncluded': false,
        },
        read: (k) async {
          throw StateError('No body should be read');
        },
        isCurrent: () => true,
      );
      await expectLater(d.list(), throwsFormatException);
      overflow = false;
      await expectLater(d.list(), throwsFormatException);
      expect(values, isEmpty);
    },
  );
  test(
    'retained allocation without a record is never marked newly allocated',
    () async {
      final values = <String, String>{}, scope = 'f' * 64;
      TopicCreationSlot slot() => TopicCreationSlot(
        scope: scope,
        kind: TopicCreationKind.topic,
        topicId: 0,
        target: '',
        targetId: 0,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final first = await slot().open(), cold = await slot().open();
      expect(first.created, isTrue);
      expect(cold.created, isFalse);
      expect(cold.key, first.key);
      await slot().clear(first.key);
      final next = await slot().open();
      expect(next.created, isTrue);
      expect(next.key, isNot(first.key));
    },
  );
}
