// PREPARED ONLY; not formatted/analyzed/executed. HTTP/bytes fakes are not Native evidence.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;
import 'package:bookstark_flutter/core/remote_owned_complex_store.dart';
import 'package:bookstark_flutter/core/remote_owned_complex_session.dart';

class RecoveryBytes implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  @override
  Future<Uint8List?> read(String key) async => values[key];
  @override
  Future<void> write(String key, Uint8List value) async {
    values[key] = Uint8List.fromList(value);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class SourceServer {
  SourceServer({this.note = true});
  final bool note;
  String title = 'original', source = '\ufeff<p>exact 😀</p>\r\n';
  List<String> labels = ['one', 'legacy,value'];
  int puts = 0, gets = 0, version = 0;
  bool current = true,
      dropAfterApply = false,
      protected = false,
      renameBeforePut = false;
  Map<String, Object?>? lastBody, overrideData;
  Completer<void>? heldRead, enteredRead;
  String get fingerprint => sha256
      .convert(utf8.encode(jsonEncode([note, title, labels, source, version])))
      .toString();
  Map<String, Object?> get data => {
    'resource': note ? 'remote-note' : 'remote-book-document',
    'id': 41,
    'book_id': note ? 0 : 10,
    'member_id': 7,
    'kind': 'html',
    'title': title,
    'labels': labels,
    'resource_fp': fingerprint,
    'source_base64': base64Encode(utf8.encode(source)),
    'bytes': utf8.encode(source).length,
    'sha256': sha256.convert(utf8.encode(source)).toString(),
    ...?(overrideData),
  };
  http.Response response(Object payload, {int status = 200}) => http.Response(
    jsonEncode(payload),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  late final client = BookstarkClient(
    'https://example.test/mount',
    transport: MockClient((request) async {
      expect(request.url.origin, 'https://example.test');
      expect(
        request.url.path,
        note
            ? '/mount/api/owned-complex/notes/41'
            : '/mount/api/owned-complex/books/10/docs/41',
      );
      expect(request.url.queryParameters, {'kind': 'html'});
      expect(request.headers['cookie'], contains('token=synthetic'));
      if (request.method == 'GET') {
        gets++;
        if (enteredRead != null && !enteredRead!.isCompleted) {
          enteredRead!.complete();
        }
        await heldRead?.future;
        if (protected) return response({'code': 423}, status: 423);
        return response({'code': 0, 'data': data});
      }
      expect(request.method, 'PUT');
      expect(request.headers['x-csrf-token'], 'synthetic-csrf');
      puts++;
      lastBody = Map<String, Object?>.from(jsonDecode(request.body) as Map);
      if (renameBeforePut) {
        renameBeforePut = false;
        title = 'external rename';
        version++;
      }
      if (lastBody!['expected_fp'] != fingerprint) {
        return response({'code': 409}, status: 409);
      }
      source = utf8.decode(
        base64Decode(lastBody!['source_base64'] as String),
        allowMalformed: false,
      );
      // UTF8 decoder strips one BOM; restore exact wire text for the fake server.
      final raw = base64Decode(lastBody!['source_base64'] as String);
      if (raw.length >= 3 && raw[0] == 239 && raw[1] == 187 && raw[2] == 191) {
        source = '\ufeff$source';
      }
      if (lastBody!.containsKey('title')) {
        title = lastBody!['title'] as String;
        labels = (lastBody!['labels'] as List).cast<String>();
      }
      version++;
      if (dropAfterApply) return response({'code': 503}, status: 503);
      return response({'code': 0, 'data': data});
    }),
  )..restoreSession({'token': 'synthetic', 'csrf_token': 'synthetic-csrf'});
  RemoteOwnedComplexStore store() => RemoteOwnedComplexStore(
    client: client,
    memberId: 7,
    resourceId: 41,
    bookId: note ? 0 : 10,
    kind: ComplexEditorKind.html,
    note: note,
    recoveryNamespace: 'stable-account-namespace',
    isCurrent: () => current,
  );
  Future<RemoteOwnedComplexSession> session(RecoveryBytes bytes) =>
      RemoteOwnedComplexSession.inspect(
        client: client,
        memberId: 7,
        resourceId: 41,
        bookId: note ? 0 : 10,
        note: note,
        kind: ComplexEditorKind.html,
        recoveryNamespace: 'stable-account-namespace',
        isCurrent: () => current,
        recoveryStore: bytes,
      );
}

ComplexNoteEdit edited(
  ComplexNote baseline,
  String body, {
  String? title,
  List<String>? labels,
}) => ComplexNoteEdit(
  title: title ?? baseline.title,
  labels: labels ?? baseline.labels,
  document: ComplexEditorDocument.parse(baseline.document.kind, body),
);
void main() {
  test(
    'owned note source/title/ordered labels share one authenticated CAS request',
    () async {
      final server = SourceServer(), store = server.store();
      addTearDown(server.client.close);
      addTearDown(store.dispose);
      final baseline = await store.read(41);
      final saved = await store.save(
        baseline,
        edited(
          baseline,
          '\ufeff<p>changed</p>\r\n',
          title: 'new title',
          labels: ['new', 'comma,label'],
        ),
      );
      expect(saved.title, 'new title');
      expect(saved.labels, ['new', 'comma,label']);
      expect(saved.document.source, '\ufeff<p>changed</p>\r\n');
      expect(server.puts, 1);
      expect(server.lastBody!.keys.toSet(), {
        'expected_fp',
        'source_base64',
        'title',
        'labels',
      });
    },
  );
  test(
    'book document rejects metadata and never aliases a note route',
    () async {
      final server = SourceServer(note: false), store = server.store();
      addTearDown(server.client.close);
      addTearDown(store.dispose);
      final baseline = await store.read(41);
      await expectLater(
        store.save(
          baseline,
          edited(baseline, '<p>new</p>', title: 'illegal rename'),
        ),
        throwsStateError,
      );
      expect(server.puts, 0);
      await store.save(baseline, edited(baseline, '<p>body only</p>'));
      expect(server.lastBody!.keys.toSet(), {'expected_fp', 'source_base64'});
    },
  );
  test(
    'metadata drift becomes fresh conflict, user must review before explicit overwrite',
    () async {
      final server = SourceServer()..renameBeforePut = true,
          bytes = RecoveryBytes();
      addTearDown(server.client.close);
      final session = await server.session(bytes);
      final controller = await session.enter(RemoteComplexDraftChoice.restore);
      addTearDown(controller!.dispose);
      addTearDown(session.retire);
      await controller.save(
        edited(
          controller.baseline,
          '<p>draft</p>',
          title: 'user title',
          labels: ['explicit'],
        ),
      );
      expect(controller.phase, ComplexSavePhase.conflict);
      expect(server.title, 'external rename');
      expect(server.source, '\ufeff<p>exact 😀</p>\r\n');
      final reviewed = await controller.observe();
      await controller.adoptReviewed(reviewed, keepDraft: true);
      expect(controller.edit.title, 'user title');
      expect(controller.edit.labels, ['explicit']);
      await controller.save(controller.edit);
      expect(server.title, 'user title');
      expect(server.labels, ['explicit']);
      expect(server.puts, 2);
    },
  );
  test(
    'applied response loss survives cold pending and never automatically PUTs again',
    () async {
      final server = SourceServer()..dropAfterApply = true,
          bytes = RecoveryBytes();
      addTearDown(server.client.close);
      final session = await server.session(bytes);
      final first = await session.enter(RemoteComplexDraftChoice.restore);
      await first!.save(edited(first.baseline, '<p>actually applied</p>'));
      expect(first.phase, ComplexSavePhase.unknown);
      expect(server.puts, 1);
      first.dispose();
      session.retire();
      server.dropAfterApply = false;
      final cold = await server.session(bytes),
          controller = await cold.enter(RemoteComplexDraftChoice.restore);
      addTearDown(controller!.dispose);
      addTearDown(cold.retire);
      expect(controller.phase, ComplexSavePhase.unknown);
      expect(controller.editable, false);
      expect(server.puts, 1);
      final actual = await controller.observe();
      expect(actual.document.source, '<p>actually applied</p>');
      expect(server.puts, 1);
      expect(bytes.values, isNotEmpty);
    },
  );
  test(
    'protected and wrong actual resource IDs cannot become plain editors',
    () async {
      final server = SourceServer(), store = server.store();
      addTearDown(server.client.close);
      addTearDown(store.dispose);
      server.protected = true;
      await expectLater(store.read(41), throwsA(isA<NoteLocked>()));
      server.protected = false;
      for (final bad in [
        {'book_id': 10},
        {'member_id': 8},
        {'kind': 'drawing'},
        {'id': 42},
      ]) {
        server.overrideData = bad;
        await expectLater(store.read(41), throwsFormatException);
      }
      server.overrideData = null;
      server.source = '\ufeffENC:v9:opaque';
      await expectLater(store.read(41), throwsA(isA<NoteLocked>()));
      expect(server.puts, 0);
    },
  );
  test(
    'scope retirement rejects late body without touching a new recovery namespace',
    () async {
      final server = SourceServer(), store = server.store();
      addTearDown(server.client.close);
      server.enteredRead = Completer<void>();
      server.heldRead = Completer<void>();
      final reading = store.read(41);
      await server.enteredRead!.future;
      server.current = false;
      store.dispose();
      server.heldRead!.complete();
      await expectLater(reading, throwsA(anything));
      expect(server.puts, 0);
    },
  );
}
