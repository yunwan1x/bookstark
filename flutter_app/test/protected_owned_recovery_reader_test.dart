import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/protected_owned_recovery_reader.dart';

String hex(String c) => List.filled(64, c).join();
Map<String, Object?> response(String source, {String kind = 'markdown'}) {
  final bytes = utf8.encode(source);
  return {
    'code': 0,
    'data': <String, Object?>{
      'resource': 'owned-blog-recovery',
      'id': 91,
      'book_id': 0,
      'member_id': 7,
      'kind': kind,
      'title': 'Current version',
      'labels': ['unchanged'],
      'resource_fp': hex('a'),
      'source_base64': base64Encode(bytes),
      'bytes': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
      'blog_type': 'article',
      'protected': true,
    },
  };
}

void main() {
  test('readonly MD source preserves BOM/CRLF and no credential DTO', () async {
    const source = '\uFEFF# current source\r\n';
    final reader = ProtectedOwnedRecoveryReader(
      scope: hex('b'),
      memberId: 7,
      resourceId: 91,
      isCurrent: () => true,
      password: 'fixture-password',
      request: (password) async {
        expect(password, 'fixture-password');
        return response(source);
      },
    );
    addTearDown(reader.dispose);
    final actual = await reader.read();
    expect(actual.document.source, source);
    expect(actual.collection, 'owned-blog-recovery');
    expect(actual.title, isNot(contains('fixture-password')));
  });
  test(
    'strict owner/digest/unknown field and response budget are rejected',
    () async {
      for (final key in ['member_id', 'sha256', 'extra', 'bytes']) {
        final envelope = response('current');
        final data = envelope['data'] as Map<String, Object?>;
        switch (key) {
          case 'member_id':
            data[key] = 8;
            break;
          case 'sha256':
            data[key] = hex('c');
            break;
          case 'extra':
            data[key] = 'unexpected';
            break;
          case 'bytes':
            data[key] = 5 * 1024 * 1024 + 1;
            break;
        }
        final reader = ProtectedOwnedRecoveryReader(
          scope: hex('b'),
          memberId: 7,
          resourceId: 91,
          isCurrent: () => true,
          password: 'fixture',
          request: (_) async => envelope,
        );
        await expectLater(reader.read(), throwsFormatException);
        reader.dispose();
      }
    },
  );
  test(
    'retirement before late response blocks actual source publication',
    () async {
      final held = Completer<Map<String, Object?>>();
      bool current = true;
      final reader = ProtectedOwnedRecoveryReader(
        scope: hex('b'),
        memberId: 7,
        resourceId: 91,
        isCurrent: () => current,
        password: 'fixture',
        request: (_) => held.future,
      );
      final request = reader.read();
      final rejected = expectLater(request, throwsStateError);
      current = false;
      reader.dispose();
      held.complete(response('late source'));
      await rejected;
    },
  );
}
