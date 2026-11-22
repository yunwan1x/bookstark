import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/anonymous_shared_capability.dart';
import 'package:bookstark_flutter/core/public_complex_source.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';

/// Synthetic server protocol, never an account transport. Real new endpoint
/// schema/identity/CSRF/CAS and rejection paths are exercised by repository tests.
class SharedCapabilityHttpFixture {
  SharedCapabilityHttpFixture({
    required this.server,
    required this.identify,
    this.tokenChar = 'b',
    this.source = '\ufeff# Editable body\r\n',
    this.title = 'Actual editing title',
  });
  final Uri server;
  final String identify, tokenChar;
  String source, title, collection = 'note', modified = '2026-11-05 12:00:00';
  int shareId = 8, targetId = 3, owner = 9, puts = 0;
  bool protected = false, loseReply = false, retargetOnPut = false;
  final requests = <String>[];
  String get token => List.filled(64, tokenChar).join();
  String get csrf => List.filled(64, 'a').join();
  String get prefix => server.path;
  Map<String, Object?> get identity => {
    'share_id': shareId,
    'target_id': targetId,
    'owner_member_id': owner,
    'book_id': 0,
    'share_type': 'blog',
    'format': 'markdown',
    'protected': protected,
    'blog_type': collection,
  };
  Map<String, Object?> get publicRow => {
    'share_type': 'blog',
    'share_id': shareId,
    'target_id': targetId,
    'share_identify': identify,
    'blog_type': collection,
    'has_password': protected,
    'doc_type': 'markdown',
    'title': title,
    'content': protected ? '' : source,
  };
  http.Response json(
    Object value, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => http.Response.bytes(
    utf8.encode(jsonEncode(value)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );
  http.Response data(Object value) => json({'code': 0, 'data': value});
  Future<http.Response> handle(http.Request request) async {
    requests.add('${request.method} ${request.url.path}');
    expect(request.followRedirects, isFalse);
    expect(request.headers['authorization'], isNull);
    final parts = request.url.pathSegments;
    if (parts.last == 'csrf-token') {
      expect(request.headers['cookie'], isNull);
      return json(
        {'code': 0, 'csrf_token': csrf},
        headers: {
          'set-cookie':
              'csrf_token=$csrf; Path=/, token=never-copy-account; Path=/',
        },
      );
    }
    expect(parts.contains('blogs') || parts.contains('docs'), isFalse);
    expect(parts.contains('shares'), isTrue);
    if (request.method == 'GET' && !parts.contains('edit')) {
      expect(request.headers['cookie'], isNull);
      return data(publicRow);
    }
    expect(request.url.queryParameters, {'token': token});
    if (request.method == 'GET' && parts.last == 'edit') {
      expect(
        protected,
        isTrue,
      ); // Legacy READ ONLY locked metadata, never legacy mutation.
      expect(request.headers['cookie'], isNull);
      return data({
        'editable': true,
        'share_type': 'blog',
        'blog_type': collection,
        'has_password': true,
        'title': title,
        'doc_type': 'markdown',
        'content': 'cipher-must-not-enter-editor',
        'modify_time': modified,
      });
    }
    if (parts.last == 'cas' && request.method == 'GET') {
      expect(request.headers['cookie'], isNull);
      if (protected) return json({'code': 423}, status: 423);
    } else {
      expect(request.headers['cookie'], 'csrf_token=$csrf');
      expect(request.headers['x-csrf-token'], csrf);
    }
    final input = request.body.isEmpty
        ? <String, Object?>{}
        : Map<String, Object?>.from(jsonDecode(request.body) as Map);
    if (parts.last == 'read') {
      expect(request.method, 'POST');
      expect(input, {'password': ' correct '});
    } else if (request.method == 'PUT') {
      expect(parts.last, 'cas');
      puts++;
      if (retargetOnPut) targetId++;
      expect(
        input.keys.toSet().difference({
          'source_base64',
          'expected_source_sha256',
          'expected_identity',
          'password',
        }),
        isEmpty,
      );
      if (jsonEncode(input['expected_identity']) != jsonEncode(identity) ||
          input['expected_source_sha256'] !=
              sha256.convert(utf8.encode(source)).toString()) {
        return json({'code': 409}, status: 409);
      }
      if (protected) expect(input['password'], ' correct ');
      // Match Go string(bytes): Dart's plain utf8.decode consumes a BOM.
      // Preserve every BOM and CRLF in actual fixture storage and receipt digest.
      source = ComplexEditorDocument.fromBytes(
        ComplexEditorKind.parse(identity['format'] as String),
        base64Decode(input['source_base64'] as String),
      ).source;
      modified = '2026-11-05 12:01:00';
      if (loseReply) return json({'code': 503}, status: 503);
      return data({
        'source_sha256': sha256.convert(utf8.encode(source)).toString(),
        'modify_time': modified,
      });
    }
    return data({
      'identity': identity,
      'title': title,
      'modify_time': modified,
      'source_base64': base64Encode(utf8.encode(source)),
      'source_sha256': sha256.convert(utf8.encode(source)).toString(),
      'bytes': utf8.encode(source).length,
    });
  }

  AnonymousSharedCapability capability(
    PublicEditLink link,
    bool Function() current,
  ) => AnonymousSharedCapability(
    link,
    isCurrent: current,
    anonymousTestClient: () => MockClient(handle),
  );
  AnonymousPublicComplexSource probe(bool Function() current) =>
      AnonymousPublicComplexSource(
        isCurrent: current,
        anonymousTestClient: MockClient(handle),
      );
}
