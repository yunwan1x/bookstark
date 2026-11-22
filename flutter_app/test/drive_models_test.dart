import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/drive_models.dart';

DriveNode node() => const DriveNode(
  id: 7,
  name: '阅读清单.md',
  path: '阅读资料/阅读清单.md',
  directory: false,
  size: 0,
  etag: 'real-hash',
  mime: 'text/markdown',
  modified: '',
);
void main() {
  test(
    'relative DAV paths preserve literal percent-encoded names and Unicode without URL interpretation',
    () {
      expect(drivePath('/阅读资料/a%2Fb.md/'), '阅读资料/a%2Fb.md');
      expect(driveChild('阅读资料', '100%_?.md'), '阅读资料/100%_?.md');
      expect(
        Uri(queryParameters: {'path': driveChild('阅读资料', 'a%2Fb.md')}).query,
        contains('a%252Fb.md'),
      );
      expect(driveParent('阅读资料/子目录/a.md'), '阅读资料/子目录');
      expect(driveParent('a.md'), '');
      expect(drivePath('/'), '');
      for (final path in [
        '../a',
        'a/../b',
        'a/./b',
        'a//b',
        '//host/a',
        r'a\b',
        'a\nfile',
      ]) {
        expect(() => drivePath(path), throwsFormatException);
      }
      for (final name in ['', '.', '..', 'a/b', r'a\b', 'a\u0000']) {
        expect(() => driveName(name), throwsFormatException);
      }
    },
  );
  test(
    'node path and filename must agree and the real node ID remains independent of name',
    () {
      final row = <String, Object?>{
        'id': 7,
        'name': 'a.md',
        'path': '目录/a.md',
        'type': 'file',
        'etag': 'sha',
        'size': 12,
        'mime_type': 'text/markdown',
        'mod_time': '2026-11-04T10:20:00+08:00',
        'create_time': '2026-11-03T10:20:00+08:00',
        'mode': '0644',
        'is_public': false,
      };
      final item = DriveNode.fromJson(row);
      expect(item.id, 7);
      expect(item.storedSize, isNull);
      expect(item.isPublic, isFalse);
      expect(
        () => DriveNode.fromJson({...row, 'path': '目录/b.md'}),
        throwsFormatException,
      );
      expect(
        () => DriveNode.fromJson({...row, 'type': 'symlink'}),
        throwsFormatException,
      );
    },
  );
  test(
    'quota fraction follows unique compressed stored bytes rather than logical file lengths',
    () {
      final usage = DriveUsage.fromJson({
        'file_count': 4,
        'directory_count': 2,
        'logical_bytes': 1000,
        'stored_bytes': 100,
        'deduplicated_bytes': 500,
        'compression_saved_bytes': 400,
        'quota_bytes': 200,
      });
      expect(usage.fraction, 0.5);
      expect(usage.logicalBytes, 1000);
      final unlimited = DriveUsage.fromJson({
        'file_count': 0,
        'directory_count': 0,
        'logical_bytes': 0,
        'stored_bytes': 0,
        'deduplicated_bytes': 0,
        'compression_saved_bytes': 0,
        'quota_bytes': 0,
      });
      expect(unlimited.unlimited, isTrue);
      expect(unlimited.fraction, isNull);
    },
  );
  test(
    'strict UTF8 text retains BOM and CRLF, and empty edits remain a real empty file',
    () {
      final bytes = Uint8List.fromList([
        239,
        187,
        191,
        ...utf8.encode('# 阅读\r\n\r\n下一步\r\n'),
      ]);
      final doc = DriveText.decode(node(), bytes);
      expect(doc.hasBom, isTrue);
      expect(doc.content, '# 阅读\r\n\r\n下一步\r\n');
      expect(doc.encode(doc.content), bytes);
      expect(doc.hash.length, 64);
      final empty = DriveText.decode(node(), Uint8List(0));
      expect(empty.encode(''), isEmpty);
      expect(empty.hasBom, isFalse);
    },
  );
  test(
    'binary controls and malformed UTF8 are rejected rather than silently replaced',
    () {
      expect(
        () => DriveText.decode(node(), Uint8List.fromList([255, 254, 0, 65])),
        throwsFormatException,
      );
      expect(
        () => DriveText.decode(node(), Uint8List.fromList([65, 0, 66])),
        throwsFormatException,
      );
      expect(
        DriveText.decode(node(), Uint8List.fromList([65, 9, 66, 10])).content,
        'A\tB\n',
      );
    },
  );
}
