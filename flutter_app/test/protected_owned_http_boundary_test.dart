import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/protected_complex_memory_store.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';
import 'package:bookstark_flutter/core/remote_owned_complex_store.dart';

class Env {
  final values = <String, String>{};
  int puts = 0, version = 0;
  String source = '[]';
  bool drop = false, failDelete = false;
  Completer<void>? held, entered;
  String get fp =>
      sha256.convert(utf8.encode(jsonEncode([source, version]))).toString();
  Map<String, Object?> get data => {
    'resource': 'remote-note',
    'id': 91,
    'book_id': 0,
    'member_id': 7,
    'kind': 'drawing',
    'title': 'Owned',
    'labels': ['same'],
    'resource_fp': fp,
    'source_base64': base64Encode(utf8.encode(source)),
    'bytes': utf8.encode(source).length,
    'sha256': sha256.convert(utf8.encode(source)).toString(),
    'protected': true,
  };
  http.Response reply(Object body, {int status = 200}) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  late final client = BookstarkClient(
    'https://fixture.test/mount',
    transport: MockClient((request) async {
      expect(request.url.origin, 'https://fixture.test');
      expect(request.url.queryParameters, {'kind': 'drawing'});
      expect(request.headers['cookie'], contains('token=fixture'));
      expect(request.headers['x-csrf-token'], 'fixture-csrf');
      final body = jsonDecode(request.body) as Map;
      expect(body['password'], 'fixture-only');
      if (request.url.path.endsWith('/unlock')) {
        return reply({'code': 0, 'data': data});
      }
      expect(request.method, 'PUT');
      expect(request.url.path, '/mount/api/owned-complex/notes/91/protected');
      expect(body.keys.toSet(), {'password', 'expected_fp', 'source_base64'});
      expect(
        values,
        isNotEmpty,
      ); // Real transport reached only after durable claim.
      puts++;
      source = utf8.decode(base64Decode(body['source_base64'] as String));
      version++;
      if (drop) return reply({'code': 503}, status: 503);
      return reply({'code': 0, 'data': data});
    }),
  )..restoreSession({'token': 'fixture', 'csrf_token': 'fixture-csrf'});
  late final journal = ProtectedOwnedComplexJournal(
    scope: ProtectedOwnedComplexJournal.scopeFor(
      server: client.baseUri.toString(),
      memberId: 7,
      namespace: 'stable',
      resourceId: 91,
      kind: 'drawing',
    ),
    ownerTag: ProtectedOwnedComplexJournal.ownerTagFor(
      server: client.baseUri.toString(),
      memberId: 7,
      namespace: 'stable',
    ),
    isCurrent: () => true,
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      if (failDelete) throw StateError('IO');
      values.remove(key);
    },
    flush: () async {
      if (values.isNotEmpty && held != null) {
        if (!entered!.isCompleted) entered!.complete();
        await held!.future;
      }
    },
  );
  late final store = ProtectedOwnedComplexStore(
    client: client,
    memberId: 7,
    resourceId: 91,
    kind: ComplexEditorKind.drawing,
    recoveryNamespace: 'stable',
    isCurrent: () => true,
    password: 'fixture-only',
    journal: journal,
  );
  void close() {
    store.dispose();
    journal.retire();
    client.close();
  }
}

ComplexNoteEdit edit(ComplexNote baseline) => ComplexNoteEdit(
  title: baseline.title,
  labels: baseline.labels,
  document: ComplexEditorDocument.parse(
    ComplexEditorKind.drawing,
    '{"elements":[]}',
  ),
);
void main() {
  test(
    'durable claim blocks actual PUT until barrier then sends only once',
    () async {
      final e = Env();
      addTearDown(e.close);
      final baseline = await e.store.read(91);
      e.held = Completer<void>();
      e.entered = Completer<void>();
      final save = e.store.save(baseline, edit(baseline));
      await e.entered!.future;
      expect(e.puts, 0);
      expect(e.values.length, 1);
      e.held!.complete();
      await save;
      expect(e.puts, 1);
      await expectLater(
        e.store.save(baseline, edit(baseline)),
        throwsStateError,
      );
      expect(e.puts, 1);
    },
  );
  test('response loss remains unknown and repeat Save cannot resend', () async {
    final e = Env()..drop = true;
    addTearDown(e.close);
    final baseline = await e.store.read(91);
    await expectLater(
      e.store.save(baseline, edit(baseline)),
      throwsA(isA<ApiFailure>()),
    );
    expect((await e.journal.load())!.known, false);
    await expectLater(e.store.save(baseline, edit(baseline)), throwsStateError);
    expect(e.puts, 1);
  });
  test(
    'known receipt cleanup retries storage only, memory draft is not durable',
    () async {
      final e = Env()..failDelete = true;
      addTearDown(e.close);
      final baseline = await e.store.read(91);
      final memory = ProtectedComplexMemoryStore(e.journal);
      final controller = LocalComplexEditorController(
        repository: e.store,
        vault: ComplexRecoveryVault(
          scope: e.store.scope,
          collection: 'remote-note',
          kind: ComplexEditorKind.drawing,
          store: memory,
        ),
        baseline: baseline,
        ephemeralDrafts: true,
      );
      addTearDown(controller.dispose);
      await controller.save(edit(baseline));
      expect(controller.phase, ComplexSavePhase.committedCleanupFailed);
      expect(controller.draftDurable, false);
      expect(e.puts, 1);
      e.failDelete = false;
      await controller.retryCleanup();
      expect(controller.phase, ComplexSavePhase.ready);
      expect(e.puts, 1);
      expect(e.values, isEmpty);
    },
  );
}
