import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/article_web_export.dart';

void main() {
  late Directory cache, folder;
  late Map<Object?, Object?> receipt;
  const id = '0123456789abcdef0123456789abcdef';
  const lease = 'owned-article-lease';
  final body = utf8.encode('\uFEFF你好😀\r\narticle\r\n');
  Future<void> metadata() async {
    await File(
      '${folder.path}/owned.json',
    ).writeAsString(jsonEncode({'format': 1, 'id': id, 'lease': lease}));
    await File('${folder.path}/ready.json').writeAsString(jsonEncode(receipt));
  }

  Future<ArticleWebExport> verify({bool Function()? current}) =>
      ArticleWebExport.verify(
        privateCache: cache,
        lease: lease,
        receipt: receipt,
        isCurrent: current ?? () => true,
      );
  setUp(() async {
    final parent = Platform.environment['BOOKSTARK_APK_TEST_ROOT'];
    if (parent == null) throw StateError('Owned test root is required');
    await Directory(parent).create(recursive: true);
    cache = await Directory(parent).createTemp('article-export-');
    folder = await Directory(
      '${cache.path}/article-web-downloads-v1/$id',
    ).create(recursive: true);
    receipt = {
      'format': 1,
      'id': id,
      'bytes': body.length,
      'sha256': sha256.convert(body).toString(),
      'name': '文章😀.html',
      'mime': 'text/html',
    };
    await File('${folder.path}/content.bin').writeAsBytes(body);
    await metadata();
  });
  tearDown(() async {
    await cache.delete(recursive: true);
  });
  test('verified export preserves exact BOM Unicode and CRLF bytes', () async {
    final result = await verify();
    expect(await result.file.readAsBytes(), body);
    expect(result.name, '文章😀.html');
    expect(result.bytes, body.length);
  });
  test('same length substitution fails independent SHA verification', () async {
    final changed = [...body];
    changed[changed.length - 1] ^= 1;
    await File('${folder.path}/content.bin').writeAsBytes(changed);
    await expectLater(
      verify(),
      throwsA(
        isA<ArticleExportFailure>().having(
          (e) => e.reason,
          'reason',
          ArticleExportReason.changed,
        ),
      ),
    );
  });
  test('old lease marker cannot approve another session export', () async {
    await File('${folder.path}/owned.json').writeAsString(
      jsonEncode({'format': 1, 'id': id, 'lease': 'another-lease'}),
    );
    await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
  });
  test('callback cannot change receipt filename after completion', () async {
    receipt['name'] = 'substituted.html';
    await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
  });
  test('content symlink is rejected even when target bytes match', () async {
    final outside = File('${cache.path}/outside.bin');
    await outside.writeAsBytes(body);
    await File('${folder.path}/content.bin').delete();
    await Link('${folder.path}/content.bin').create(outside.path);
    await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
  });
  test('job directory symlink is rejected', () async {
    final original = folder.path;
    final moved = await folder.rename('${cache.path}/moved-job');
    await Link(original).create(moved.path);
    await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
  });
  test(
    'revocation during streaming prevents handoff to file exporter',
    () async {
      var checks = 0;
      await expectLater(
        verify(current: () => ++checks < 2),
        throwsA(
          isA<ArticleExportFailure>().having(
            (e) => e.reason,
            'reason',
            ArticleExportReason.retired,
          ),
        ),
      );
    },
  );
  test(
    'oversized and path shaped receipts fail before filesystem reads',
    () async {
      receipt['bytes'] = ArticleWebExport.maxBytes + 1;
      await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
      receipt['bytes'] = body.length;
      receipt['id'] = '../escape';
      await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
    },
  );
  test('truncated native export cannot be offered for saving', () async {
    await File(
      '${folder.path}/content.bin',
    ).writeAsBytes(body.take(3).toList());
    await expectLater(verify(), throwsA(isA<ArticleExportFailure>()));
  });
  test(
    'trusted cache through an ancestor alias still verifies exact owned bytes',
    () async {
      final alias = Link(
        '${cache.parent.path}/${cache.uri.pathSegments.where((p) => p.isNotEmpty).last}-parent-alias',
      );
      await alias.create(cache.parent.path);
      try {
        final aliased = Directory(
          '${alias.path}/${cache.uri.pathSegments.where((p) => p.isNotEmpty).last}',
        );
        final result = await ArticleWebExport.verify(
          privateCache: aliased,
          lease: lease,
          receipt: receipt,
          isCurrent: () => true,
        );
        expect(await result.file.readAsBytes(), body);
        expect(result.sha256Hex, sha256.convert(body).toString());
      } finally {
        await alias.delete();
      }
    },
  );
}
