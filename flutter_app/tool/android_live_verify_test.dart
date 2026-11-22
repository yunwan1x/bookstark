// Read-only proof of actual Android writes to the owned empty fixture.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/core/share_comments_repository.dart';

void main() {
  test('verify only the owned Android API fixture without any writes', () async {
    final path = Platform.environment['BOOKSTARK_ANDROID_FIXTURE_CONFIG'];
    if (path == null ||
        !path.startsWith(
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-live-fixture/',
        )) {
      throw StateError('Owned fixture configuration required');
    }
    final cfg = Map<String, Object?>.from(
      jsonDecode(await File(path).readAsString()) as Map,
    );
    final base = Uri.parse(cfg['local_base'] as String);
    if (cfg['fixture'] != true ||
        cfg['seeded'] != true ||
        base.host != '127.0.0.1' ||
        base.scheme != 'http') {
      throw StateError(
        'Read verification restricted to the owned loopback fixture',
      );
    }
    final client = BookstarkClient(base.toString())..language = 'zh';
    try {
      final repository = RemotePublicSharesRepository(client);
      PublicShareReference ref(String name) =>
          PublicShareReference(client.baseUri, cfg[name] as String);
      final article = await repository.load(ref('article_identify'));
      expect(article.content, '# Android native shared save proof');
      final locked = await repository.load(ref('protected_identify'));
      expect(locked.locked, isTrue);
      expect(locked.content, isEmpty);
      final protected = await repository.unlock(
        locked,
        cfg['share_password'] as String,
      );
      expect(protected.content, '# Android native protected save proof');
      final comments = await RemoteShareCommentsRepository(
        client,
      ).list(article, 1);
      final native = comments.items
          .where((item) => item.content == 'Android native comment proof')
          .toList();
      expect(native.length, 1);
      final book = await repository.load(ref('book_identify'));
      expect(book.targetId, cfg['book_id']);
      final proof = {
        'readOnlyVerification': true,
        'articleActualId': article.targetId,
        'articleBody': article.content,
        'protectedActualId': protected.targetId,
        'lockedBodyMasked': locked.content.isEmpty,
        'protectedBody': protected.content,
        'commentActualId': native.single.id,
        'commentCountWithProof': native.length,
        'bookActualId': book.targetId,
      };
      final output = File(
        '/vol1/1000/wy/bookstark/docs/flutter-rewrite/validation/2026-11-05-share-edit-android-api-proof.json',
      );
      await output.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(proof)}\n',
      );
    } finally {
      client.close();
    }
  });
}
