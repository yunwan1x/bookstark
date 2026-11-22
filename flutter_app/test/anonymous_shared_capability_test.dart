// Draft only: protocol/SQLite tests are not Android rendering acceptance.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/anonymous_shared_capability.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/shared_complex_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';

class _Bytes implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List bytes) async {
    values[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class _Server {
  String source = '\ufeff<p>before🙂</p>\r\n';
  int target = 41, puts = 0, gets = 0;
  String format = 'html';
  bool drop = false, retarget = false;
  Completer<void>? gate;
  String get csrf => List.filled(64, 'b').join();
  Map<String, Object?> get identity => {
    'share_id': 5,
    'target_id': target,
    'owner_member_id': 7,
    'book_id': 0,
    'share_type': 'blog',
    'format': format,
    'protected': false,
    'blog_type': 'note',
  };
  Map<String, Object?> get data => {
    'identity': identity,
    'title': 'Actual readonly title',
    'modify_time': '2026-11-11 10:20:30',
    'source_base64': base64Encode(utf8.encode(source)),
    'source_sha256': sha256.convert(utf8.encode(source)).toString(),
    'bytes': utf8.encode(source).length,
  };
  http.Response response(
    Object data, {
    int status = 200,
    Map<String, String> headers = const {},
  }) => http.Response(
    jsonEncode(data),
    status,
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );
  Future<http.Response> handle(http.Request request) async {
    expect(request.url.origin, 'https://share.test');
    expect(request.headers.containsKey('authorization'), isFalse);
    if (request.url.path == '/mount/api/csrf-token') {
      expect(request.headers.containsKey('cookie'), isFalse);
      return response(
        {'code': 0, 'csrf_token': csrf},
        headers: {
          'set-cookie':
              'csrf_token=$csrf; Path=/, token=never-copy-member-cookie; Path=/',
        },
      );
    }
    expect(request.url.queryParameters['token'], List.filled(64, 'a').join());
    if (request.method == 'GET') {
      gets++;
      expect(request.headers.containsKey('cookie'), isFalse);
      await gate?.future;
      return response({'code': 0, 'data': data});
    }
    expect(request.method, 'PUT');
    puts++;
    expect(request.headers['cookie'], 'csrf_token=$csrf');
    expect(request.headers['x-csrf-token'], csrf);
    final body = jsonDecode(request.body) as Map;
    if (retarget) target = 42;
    if (jsonEncode(body['expected_identity']) != jsonEncode(identity) ||
        body['expected_source_sha256'] != data['source_sha256']) {
      return response({'code': 409}, status: 409);
    }
    source = ComplexEditorDocument.fromBytes(
      ComplexEditorKind.parse(format),
      base64Decode(body['source_base64'] as String),
    ).source;
    if (drop) return response({'code': 503}, status: 503);
    return response({
      'code': 0,
      'data': {
        'source_sha256': data['source_sha256'],
        'modify_time': '2026-11-11 10:20:30',
      },
    });
  }

  AnonymousSharedCapability cap({
    bool Function()? current,
  }) => AnonymousSharedCapability(
    PublicEditLink.parse(
      Uri.parse('https://share.test/mount'),
      'https://share.test/mount/shares/owned-fixture?token=${List.filled(64, 'a').join()}',
    ),
    isCurrent: current ?? () => true,
    anonymousTestClient: () => MockClient(handle),
  );
}

void main() {
  test(
    'anonymous csrf-only CAS is single-use and preserves actual BOM bytes',
    () async {
      final server = _Server();
      final actual = server.cap();
      addTearDown(actual.close);
      final baseline = await actual.read();
      final doc = ComplexEditorDocument.parse(
        ComplexEditorKind.html,
        '\ufeff<p>after🙂</p>\r\n',
      );
      final prepared = await actual.prepare(baseline, doc);
      final receipt = await prepared.sendOnce();
      expect(receipt['source_sha256'], doc.digest);
      expect(server.source, doc.source);
      await expectLater(prepared.sendOnce(), throwsStateError);
      expect(server.puts, 1);
      prepared.retire();
    },
  );
  test(
    'same-body retarget conflicts rather than writing another resource',
    () async {
      final server = _Server();
      final actual = server.cap();
      addTearDown(actual.close);
      final base = await actual.read();
      server.retarget = true;
      final prepared = await actual.prepare(
        base,
        ComplexEditorDocument.parse(ComplexEditorKind.html, '<p>wrong</p>'),
      );
      await expectLater(
        prepared.sendOnce(),
        throwsA(
          isA<SharedCapabilityFailure>().having((e) => e.status, 'status', 409),
        ),
      );
      expect(server.source, base.document.source);
      expect(server.target, 42);
      expect(server.puts, 1);
    },
  );
  test(
    'applied lost reply retains durable unknown; fresh review never sends again',
    () async {
      final server = _Server();
      final actual = server.cap();
      final initial = await actual.read();
      final repository = SharedComplexStore(
        transport: actual,
        initial: initial,
        isCurrent: () => true,
      );
      final baseline = await repository.read(initial.identity.targetId),
          bytes = _Bytes();
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: 'shared-complex',
        kind: ComplexEditorKind.html,
        store: bytes,
      );
      final controller = LocalComplexEditorController(
        repository: repository,
        vault: vault,
        baseline: baseline,
      );
      addTearDown(controller.dispose);
      server.drop = true;
      await controller.save(
        ComplexNoteEdit(
          title: baseline.title,
          labels: [],
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.html,
            '<p>submitted</p>',
          ),
        ),
      );
      expect(controller.phase, ComplexSavePhase.unknown);
      expect(server.puts, 1);
      expect((await vault.read(baseline.id))!.pending, isTrue);
      await controller.observe();
      expect(server.puts, 1);
    },
  );
  test('reserved envelope never reaches engine or PUT', () async {
    final server = _Server()..source = '\ufeffENC:v999:malformed';
    final actual = server.cap();
    addTearDown(actual.close);
    await expectLater(
      actual.read(),
      throwsA(
        isA<SharedCapabilityFailure>().having((e) => e.status, 'status', 423),
      ),
    );
    expect(server.puts, 0);
  });
  test(
    'all7 source kinds are explicit and preserve exact source; unknown/oversize reject',
    () async {
      final examples = <String, String>{
        'markdown': '\ufeff# Markdown🙂\r\n',
        'html': '\ufeff<p>HTML🙂</p>\r\n',
        'spreadsheet': SpreadsheetDocument.empty(
          workbookId: 'w',
          sheetId: 's',
        ).source,
        'drawing': ' {"elements":[],"appState":{},"future":true} ',
        'mindmap':
            '{"nodeData":{"id":"root","topic":"Actual text","children":[]},"future":true}',
        'richdoc':
            '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[{"value":"text"}]},"future":true}',
        'presentation':
            '{"width":1000,"height":562.5,"slides":[{"id":"s","elements":[]}],"future":true}',
      };
      for (final entry in examples.entries) {
        final server = _Server()
          ..format = entry.key
          ..source = entry.value;
        final cap = server.cap();
        final actual = await cap.read();
        expect(actual.document.kind.name, entry.key);
        expect(actual.document.source, entry.value);
        expect(server.puts, 0);
        cap.close();
      }
      final unknown = _Server()..format = 'pdf';
      final cap = unknown.cap();
      await expectLater(cap.read(), throwsFormatException);
      cap.close();
      final tooLarge = _Server()
        ..format = 'markdown'
        ..source = List.filled(500 * 1024 + 1, 'x').join();
      final large = tooLarge.cap();
      await expectLater(large.read(), throwsFormatException);
      large.close();
    },
  );
  test('shared body-only store rejects metadata edit without PUT', () async {
    final server = _Server();
    final actual = server.cap();
    final initial = await actual.read();
    final store = SharedComplexStore(
      transport: actual,
      initial: initial,
      isCurrent: () => true,
    );
    addTearDown(store.dispose);
    final base = await store.read(initial.identity.targetId);
    await expectLater(
      store.save(
        base,
        ComplexNoteEdit(
          title: 'Changed owner title',
          labels: [],
          document: base.document,
        ),
      ),
      throwsStateError,
    );
    expect(server.puts, 0);
    expect(server.source, base.document.source);
  });
  test(
    'retirement cancels stalled read and cannot authorize a new mutation',
    () async {
      final server = _Server()..gate = Completer<void>();
      final actual = server.cap();
      final read = actual.read();
      await Future<void>.delayed(Duration.zero);
      actual.close();
      await expectLater(read, throwsA(isA<SharedCapabilityFailure>()));
      server.gate!.complete();
      expect(server.puts, 0);
      await expectLater(actual.read(), throwsA(isA<SharedCapabilityFailure>()));
    },
  );
}
