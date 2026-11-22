import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';

Map<String, Object?> payload(PublicShareReference reference) => {
  'share_type': 'blog',
  'share_id': -17,
  'target_id': 17,
  'share_identify': reference.identify,
  'has_password': false,
  'title': 'Actual title',
  'author': 'Actual author',
  'doc_type': 'markdown',
  'content': '\ufeff# 正文\r\n保留内容',
  'description': 'Actual description',
  'labels': [' 保留,a&b%2F ', '中文'],
  'share_time': '2026-11-05T00:00:00Z',
};
void main() {
  final reference = PublicShareReference(
    Uri.parse('https://example.test/base/'),
    '原始%2F+📚',
  );
  test(
    'canonical public paths encode identifiers once and carry no editing or auth query',
    () {
      expect(
        Uri.parse(reference.detailPath).pathSegments.last,
        reference.identify,
      );
      expect(reference.canonicalUri.pathSegments, [
        'base',
        'shares',
        reference.identify,
      ]);
      expect(reference.canonicalUri.hasQuery, false);
      reference.validateRawPath(reference.rawPath);
      reference.validateRawPath('/base${reference.rawPath}');
      for (final id in [
        '',
        '.',
        '..',
        'a/b',
        'a\\b',
        'a\n',
        String.fromCharCode(0xd800),
      ]) {
        expect(
          () => PublicShareReference(reference.server, id),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'actual negative public blog IDs are distinct from private target IDs',
    () {
      final actual = PublicShareDetail.fromJson(reference, payload(reference));
      expect(actual.shareId, -17);
      expect(actual.targetId, 17);
      expect(actual.blogType, isNull);
      expect(actual.content, '\ufeff# 正文\r\n保留内容');
      expect(actual.content.codeUnitAt(0), 0xfeff);
      expect(actual.content.contains(String.fromCharCodes([13, 10])), true);
      expect(actual.labels, [' 保留,a&b%2F ', '中文']);
      expect(
        () => PublicShareDetail.fromJson(reference, {
          ...payload(reference),
          'share_id': -18,
        }),
        throwsFormatException,
      );
      expect(
        () => PublicShareDetail.fromJson(reference, {
          ...payload(reference),
          'share_type': 'book',
        }),
        throwsFormatException,
      );
      expect(
        () => PublicShareDetail.fromJson(reference, {
          ...payload(reference),
          'share_identify': 'different',
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'protected payloads discard body, labels, descriptions, URLs and trees before UI receives them',
    () {
      final locked = PublicShareDetail.fromJson(reference, {
        ...payload(reference),
        'has_password': true,
        'content': {'secret': true},
        'description': {'private': true},
        'labels': ['SECRET LABEL'],
        'doc_tree': [
          {'private': true},
        ],
        'content_url': 'https://evil.test/private',
      });
      expect(locked.locked, true);
      expect(locked.content, isEmpty);
      expect(locked.description, isEmpty);
      expect(locked.labels, isEmpty);
      expect(locked.nodes, isEmpty);
      expect(locked.rawAvailable, false);
      final unlocked = locked.unlockMarkdown('解锁正文');
      expect(unlocked.content, '解锁正文');
      expect(unlocked.protected, true);
      expect(unlocked.locked, false);
      expect(unlocked.labels, isEmpty);
      expect(locked.content, isEmpty);
    },
  );
  test(
    'raw content can only use the same canonical public context, including literal plus',
    () {
      for (final path in [
        'https://evil.test${reference.rawPath}',
        '/api/webdav/files/download?path=private',
        '${reference.rawPath}?token=secret',
        '//example.test${reference.rawPath}',
        '${reference.detailPath}/edit/content/raw',
      ]) {
        expect(
          () => PublicShareDetail.fromJson(reference, {
            ...payload(reference),
            'doc_type': 'html',
            'content': '',
            'content_url': path,
          }),
          throwsFormatException,
        );
      }
      final actual = PublicShareDetail.fromJson(reference, {
        ...payload(reference),
        'doc_type': 'html',
        'content': '',
        'content_url': '/base${reference.rawPath}',
      });
      expect(actual.rawAvailable, true);
      expect(actual.markdown, false);
    },
  );
  test(
    'shared book chapters retain actual identifiers and reject ambiguous or foreign parent membership',
    () {
      Map<String, Object?> node(
        int id,
        String identify, {
        int parent = 0,
        List<Object?> children = const [],
      }) => {
        'document_id': id,
        'document_name': 'Node $id',
        'identify': identify,
        'parent_id': parent,
        'doc_type': 'markdown',
        'children': children,
      };
      Map<String, Object?> book(Object? tree) => {
        ...payload(reference),
        'share_type': 'book',
        'share_id': 8,
        'doc_tree': tree,
        'doc_count': 6,
      };
      final actual = PublicShareDetail.fromJson(
        reference,
        book([
          node(1, 'parent', children: [node(2, 'literal%2F', parent: 1)]),
        ]),
      );
      expect(actual.nodes.single.children.single.identify, 'literal%2F');
      expect(actual.documentCount, 6);
      expect(
        () => actual.nodes.add(actual.nodes.single),
        throwsUnsupportedError,
      );
      for (final tree in [
        [node(1, 'a'), node(1, 'b')],
        [node(1, 'same'), node(2, 'same')],
        [
          node(1, 'root', children: [node(2, 'wrong', parent: 0)]),
        ],
      ]) {
        expect(
          () => PublicShareDetail.fromJson(reference, book(tree)),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'unknown formats are never inferred as Markdown, and malformed Unicode is not normalized silently',
    () {
      final unknown = PublicShareDetail.fromJson(reference, {
        ...payload(reference),
        'doc_type': 'drawing',
        'content': '{"type":"drawing"}',
      });
      expect(unknown.markdown, false);
      expect(unknown.format, 'drawing');
      final protected = PublicShareDetail.fromJson(reference, {
        ...payload(reference),
        'doc_type': 'html',
        'has_password': true,
      });
      expect(() => protected.unlockMarkdown('not Markdown'), throwsStateError);
      expect(
        () => PublicShareDetail.fromJson(reference, {
          ...payload(reference),
          'content': String.fromCharCode(0xd800),
        }),
        throwsFormatException,
      );
    },
  );
}
