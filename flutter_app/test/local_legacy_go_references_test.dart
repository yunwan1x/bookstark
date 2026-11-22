import 'dart:convert';
import 'package:bookstark_flutter/core/local_legacy_go_issue.dart';
import 'package:bookstark_flutter/core/local_legacy_go_references.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Row = Map<String, Object?>;
Map<String, Object?> valid() =>
    jsonDecode(
          jsonEncode({
            'books.json': [
              {
                'identify': 'book',
                'documents': [
                  {'identify': 'parent', 'parent_identify': ''},
                  {'identify': 'child', 'parent_identify': 'parent'},
                ],
              },
            ],
            'blogs.json': [
              {'blog_identify': 'note', 'blog_type': 'note'},
            ],
            'bookmarks.json': [
              {'url': 'https://example.invalid/one'},
              {'url': 'https://example.invalid/one'},
            ],
            'tasks.json': [
              {'task_id': 9223372036854775807, 'parent_id': 0, 'topic_id': 4},
            ],
            'topics.json': [
              {
                'topic_id': 4,
                'summaries': [
                  {'summary_id': 5},
                ],
                'resources': [
                  {
                    'topic_resource_id': 6,
                    'resource_type': 'document',
                    'target_identify': 'book/child',
                  },
                  {
                    'topic_resource_id': 7,
                    'resource_type': 'task',
                    'target_identify': '9223372036854775807',
                  },
                ],
                'comments': [
                  {
                    'comment_id': 8,
                    'parent_comment_id': 0,
                    'target_type': 'summary',
                    'target_id': 5,
                  },
                  {
                    'comment_id': 9,
                    'parent_comment_id': 8,
                    'target_type': 'summary',
                    'target_id': 5,
                  },
                ],
              },
            ],
            'labels.json': {
              'labels': [
                {'label_name': '标签'},
              ],
              'relations': [
                {
                  'label_name': '标签',
                  'resource_type': 'blog',
                  'resource_identify': 'note',
                },
                {
                  'label_name': '标签',
                  'resource_type': 'document',
                  'resource_identify': 'book/child',
                },
              ],
            },
          }),
        )
        as Map<String, Object?>;

List<Row> rows(Map<String, Object?> data, String key) =>
    (data[key] as List).cast<Row>();
Row topic(Map<String, Object?> data) => rows(data, 'topics.json').single;
List<Row> nested(Row data, String key) => (data[key] as List).cast<Row>();

void main() {
  test(
    'valid composite references and max task ID; unreferenced duplicate URLs retained',
    () {
      expect(inspectLegacyGoReferences(valid()), isEmpty);
    },
  );

  test('all three hierarchy kinds reject cycles without recursive walking', () {
    for (final kind in ['document', 'task', 'comment']) {
      final data = valid();
      if (kind == 'document') {
        final docs = nested(rows(data, 'books.json').single, 'documents');
        docs.first['parent_identify'] = 'child';
      } else if (kind == 'task') {
        rows(data, 'tasks.json').single['parent_id'] = 9223372036854775807;
      } else {
        nested(topic(data), 'comments').first['parent_comment_id'] = 9;
      }
      expect(
        inspectLegacyGoReferences(data).map((issue) => issue.code),
        contains(LegacyGoIssueCode.cyclicHierarchy),
      );
    }
  });

  test(
    'missing parent, topic, label, resource and comment targets are explicit',
    () {
      final changes = <void Function(Map<String, Object?>)>[
        (data) => nested(
          rows(data, 'books.json').single,
          'documents',
        ).last['parent_identify'] = 'missing',
        (data) => rows(data, 'tasks.json').single['parent_id'] = 77,
        (data) => rows(data, 'tasks.json').single['topic_id'] = 77,
        (data) => nested(
          data['labels.json'] as Row,
          'relations',
        ).first['label_name'] = 'missing',
        (data) => nested(
          data['labels.json'] as Row,
          'relations',
        ).first['resource_identify'] = 'missing',
        (data) => nested(topic(data), 'resources').first['target_identify'] =
            'book/missing',
        (data) => nested(topic(data), 'comments').first['target_id'] = 77,
        (data) =>
            nested(topic(data), 'comments').last['parent_comment_id'] = 77,
      ];
      for (final change in changes) {
        final data = valid();
        change(data);
        expect(
          inspectLegacyGoReferences(data).map((issue) => issue.code),
          contains(LegacyGoIssueCode.unresolvedReference),
        );
      }
    },
  );

  test(
    'bookmark URL ambiguity cannot silently pick one of two source rows',
    () {
      final data = valid();
      nested(topic(data), 'resources').add({
        'topic_resource_id': 10,
        'resource_type': 'bookmark',
        'target_identify': 'https://example.invalid/one',
      });
      final issues = inspectLegacyGoReferences(data);
      expect(
        issues.map((issue) => issue.code),
        contains(LegacyGoIssueCode.ambiguousReference),
      );
      expect(
        issues.map((issue) => issue.location).join(),
        isNot(contains('example.invalid')),
      );
      expect(rows(data, 'bookmarks.json').length, 2);
    },
  );

  test('article reference cannot resolve to a note with the same identify', () {
    final data = valid();
    nested(
      topic(data),
      'resources',
    ).first.addAll({'resource_type': 'article', 'target_identify': 'note'});
    expect(
      inspectLegacyGoReferences(data).map((issue) => issue.code),
      contains(LegacyGoIssueCode.unresolvedReference),
    );
  });

  test('unsupported kinds and duplicate source IDs remain blocked', () {
    final data = valid();
    nested(topic(data), 'resources').first['resource_type'] = 'future';
    rows(
      data,
      'tasks.json',
    ).add({'task_id': 9223372036854775807, 'parent_id': 0});
    final codes = inspectLegacyGoReferences(data).map((issue) => issue.code);
    expect(
      codes,
      containsAll([
        LegacyGoIssueCode.unsupportedResourceKind,
        LegacyGoIssueCode.duplicateIdentity,
      ]),
    );
  });

  test('comments cannot attach to a parent under a different target', () {
    final data = valid();
    nested(
      topic(data),
      'comments',
    ).last.addAll({'target_type': 'resource', 'target_id': 6});
    expect(
      inspectLegacyGoReferences(data).map((issue) => issue.code),
      contains(LegacyGoIssueCode.unresolvedReference),
    );
  });

  test('100000-node chain is bounded and iterative', () {
    final data = valid();
    data['tasks.json'] = List<Row>.generate(
      100000,
      (i) => {'task_id': i + 1, 'parent_id': i, 'topic_id': 4},
    );
    // Keep the earlier task resource from introducing an unrelated missing ID.
    nested(topic(data), 'resources').last['target_identify'] = '100000';
    expect(inspectLegacyGoReferences(data), isEmpty);
    rows(data, 'tasks.json').first['parent_id'] = 100000;
    expect(
      inspectLegacyGoReferences(data).map((issue) => issue.code),
      contains(LegacyGoIssueCode.cyclicHierarchy),
    );
  });
}
