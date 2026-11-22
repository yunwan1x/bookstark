import 'dart:convert';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_protected_creation_record.dart';
import 'package:bookstark_flutter/core/remote_html_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'html_notes_save_test.dart' show Server;

class CreationServer extends Server {
  int posts = 0, rawReads = 0;
  bool dropPost = false, ignoreLabels = false;
  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path == '/api/blogs' && request.method == 'POST') {
      posts++;
      final body = jsonDecode(request.body) as Map;
      row['blog_title'] = body['blog_title'];
      source = body['blog_content'] as String;
      labels = ignoreLabels ? [] : (body['labels'] as String).split(',');
      if (dropPost) throw http.ClientException('Applied POST receipt lost');
      return http.Response(
        jsonEncode({'code': 0, 'data': row}),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    if (request.url.path.endsWith('/raw')) rawReads++;
    return super.handle(request);
  }
}

void main() {
  final edit = HtmlNoteEdit(
    title: 'New HTML',
    source: '<p>exact原文</p>\r\n',
    labels: ['first'],
  );
  late CreationServer server;
  late Map<String, String> storage;
  late HtmlCreationVault vault;
  late RemoteHtmlCreationController c;
  var failKnown = false, failDelete = false, failAny = false;
  RemoteHtmlCreationController make({Object? record}) =>
      RemoteHtmlCreationController(
        RemoteHtmlCreationRepository(
          server.client,
          memberId: 3,
          collection: 'note',
        ),
        vault,
        record: record,
      );
  setUp(() {
    server = CreationServer();
    storage = {};
    failKnown = false;
    failDelete = false;
    failAny = false;
    vault = HtmlCreationVault(
      server: Uri.parse('https://books.example'),
      memberId: 3,
      collection: 'note',
      readValue: (k) async => storage[k],
      writeValue: (k, v) async {
        final decoded = jsonDecode(v) as Map;
        if (failAny || failKnown && decoded['created_id'] != null) {
          throw StateError('Storage barrier failed');
        }
        if (storage.isEmpty &&
            decoded['pending'] == true &&
            decoded['created_id'] == null) {
          expect(server.posts, 0);
        }
        storage[k] = v;
      },
      deleteValue: (k) async {
        if (failDelete) throw StateError('Delete barrier failed');
        storage.remove(k);
      },
    );
    c = make();
    c.edit(edit);
  });
  tearDown(() {
    c.dispose();
    server.client.close();
    server.repo.dispose();
  });
  test(
    'pending barrier precedes POST and exact independent read completes creation',
    () async {
      await c.save();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
      expect(c.created!.source, edit.source);
      expect(c.receiptKnown, isTrue);
      expect(storage, isEmpty);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 0);
    },
  );
  test('failed pending barrier permits no POST', () async {
    failAny = true;
    await c.save();
    expect(c.phase, RemoteHtmlCreationPhase.editing);
    expect(server.posts, 0);
    expect(c.recoveryFailure, isNotNull);
  });
  test(
    'lost applied POST survives restoration and adoption does not replay or fabricate receipt',
    () async {
      server.dropPost = true;
      await c.save();
      expect(c.phase, RemoteHtmlCreationPhase.unknown);
      expect(server.posts, 1);
      final restored = await vault.readRecovery();
      c.dispose();
      c = make(record: restored);
      await c.inspect(7);
      expect(c.phase, RemoteHtmlCreationPhase.review);
      expect(c.receiptKnown, isFalse);
      await expectLater(c.adopt(), throwsStateError);
      c.markReviewed(c.observed!);
      await c.adopt();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 0);
    },
  );
  test(
    'known receipt storage failure retains ID and resolves only by reads',
    () async {
      failKnown = true;
      await c.save();
      expect(c.phase, RemoteHtmlCreationPhase.unknown);
      expect(c.receiptId, 7);
      expect(server.rawReads, 0);
      expect(server.posts, 1);
      failKnown = false;
      await c.inspect(7);
      c.markReviewed(c.observed!);
      await c.adopt();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
    },
  );
  test(
    'ignored server label bind is visible and never silently repaired',
    () async {
      server.ignoreLabels = true;
      await c.save();
      expect(c.phase, RemoteHtmlCreationPhase.review);
      expect(c.observed!.labels, isEmpty);
      expect(c.receiptId, 7);
      expect(server.labelWrites, 0);
      c.markReviewed(c.observed!);
      await c.adopt();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
    },
  );
  test(
    'changed candidate after complete review requires another review without overwriting',
    () async {
      server.dropPost = true;
      await c.save();
      await c.inspect(7);
      c.markReviewed(c.observed!);
      server.source = '<p>external edit</p>';
      server.row['version'] = 22;
      await c.adopt();
      expect(c.phase, RemoteHtmlCreationPhase.review);
      expect(c.reviewed, isFalse);
      expect(c.observed!.source, server.source);
      expect(server.posts, 1);
      expect(server.contentWrites, 0);
    },
  );
  test(
    'protected candidate seals journal before raw read and never stores password',
    () async {
      server.dropPost = true;
      await c.save();
      server.row['has_password'] = true;
      await c.inspect(7);
      expect(c.failure, isA<HtmlNoteLocked>());
      expect(server.rawReads, 0);
      expect(c.record, isA<HtmlProtectedCreationRecord>());
      expect(c.draft, isNull);
      expect(storage.values.single, isNot(contains(edit.source)));
      await c.inspect(7, password: ' raw password ');
      expect(c.phase, RemoteHtmlCreationPhase.review);
      expect(storage.values.single, isNot(contains('raw password')));
      c.markReviewed(c.observed!);
      await c.adopt();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
    },
  );
  test('known completion cleanup retries storage only', () async {
    failDelete = true;
    await c.save();
    expect(c.phase, RemoteHtmlCreationPhase.cleanup);
    final reads = server.rawReads;
    failDelete = false;
    await c.retryCleanup();
    expect(c.phase, RemoteHtmlCreationPhase.finished);
    expect(server.posts, 1);
    expect(server.rawReads, reads);
    expect(storage, isEmpty);
  });
  test(
    'session replacement refuses late candidate reads and journal writes',
    () async {
      server.dropPost = true;
      await c.save();
      final before = Map.of(storage);
      server.client.restoreSession({'token': 'another'});
      await c.inspect(7);
      expect(c.failure, isStateError);
      expect(server.rawReads, 0);
      expect(storage, before);
    },
  );
}
