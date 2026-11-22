import 'dart:convert';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'html_notes_repository_test.dart' show metadata, jsonResponse;

class Server {
  Server({bool protected = false}) {
    row['has_password'] = protected;
    client = BookstarkClient(
      'https://books.example',
      transport: MockClient(handle),
    )..restoreSession({'token': 'session'});
    repo = RemoteHtmlNotesRepository(client, memberId: 3);
  }
  late final BookstarkClient client;
  late final RemoteHtmlNotesRepository repo;
  final row = metadata();
  String source = '<p>Original</p>';
  List<String> labels = ['original'];
  int contentWrites = 0, labelWrites = 0;
  bool failLabels = false,
      loseContent = false,
      loseLabels = false,
      rejectContent = false;
  void Function()? afterContent;
  Future<void>? holdContent;
  final bodies = <Map>[];
  http.Response receipt([int status = 200]) => http.Response(
    jsonEncode({
      'code': status == 200 ? 0 : status,
      'message': status == 200 ? 'ok' : 'rejected',
    }),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    expect(request.followRedirects, isFalse);
    expect(request.headers['cookie'], contains('token=session'));
    if (path == '/api/profile') return jsonResponse({'member_id': 3});
    if (path == '/api/csrf-token') {
      return http.Response(
        '{}',
        200,
        headers: {'set-cookie': 'csrf_token=csrf; Path=/'},
      );
    }
    if (request.method == 'PUT') {
      expect(request.headers['x-csrf-token'], 'csrf');
    }
    if (path == '/api/blogs/7') {
      if (request.method == 'GET') return jsonResponse(row);
      expect(request.method, 'PUT');
      contentWrites++;
      if (rejectContent) return receipt(400);
      final body = jsonDecode(request.body) as Map;
      bodies.add(body);
      expect(
        body.keys.toSet(),
        row['has_password'] == true
            ? {'blog_title', 'blog_content', 'password'}
            : {'blog_title', 'blog_content'},
      );
      if (row['has_password'] == true) {
        expect(body['password'], ' raw password ');
      }
      row['blog_title'] = body['blog_title'];
      source = body['blog_content'] as String;
      row['version'] = (row['version'] as int) + 1;
      row['modify_at'] = (row['modify_at'] as int) + 1;
      afterContent?.call();
      await (holdContent ?? Future<void>.value());
      if (loseContent) throw http.ClientException('Injected lost receipt');
      return receipt();
    }
    if (path == '/api/labels/resource/blog/7') {
      if (request.method == 'GET') {
        return jsonResponse(labels.isEmpty ? null : labels);
      }
      labelWrites++;
      if (failLabels) return receipt(500);
      final value = (jsonDecode(request.body) as Map)['labels'] as String;
      labels = value.isEmpty ? [] : value.split(',');
      if (loseLabels) throw http.ClientException('Injected lost receipt');
      return jsonResponse(labels.isEmpty ? null : labels);
    }
    if (path.endsWith('/content/raw') ||
        path.endsWith('/verify-password/raw')) {
      if (row['has_password'] == true) {
        expect(request.method, 'POST');
        expect(jsonDecode(request.body), {'password': ' raw password '});
      }
      return http.Response.bytes(
        utf8.encode(source),
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    throw StateError('Unexpected fixture endpoint');
  }

  Future<HtmlNote> baseline() => repo.read(
    7,
    password: row['has_password'] == true ? ' raw password ' : null,
  );
  HtmlNoteEdit edit({List<String> labels = const []}) => HtmlNoteEdit(
    title: '  Updated HTML  ',
    source: '<script>window.x="你好";</script>',
    labels: labels,
  );
  void close() {
    repo.dispose();
    client.close();
  }
}

void main() {
  test(
    'unchanged literal comma label stays intact without label replacement or fabricated receipt',
    () async {
      final s = Server();
      s.labels = ['one,literal,label'];
      final before = await s.baseline();
      final result = await s.repo.save(before, s.edit(labels: before.labels));
      expect(result.note.labels, ['one,literal,label']);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      expect(result.attempt.labelsReceipt, false);
      expect(result.allReceiptsKnown, true);
      await expectLater(s.repo.finishLabels(result.attempt), throwsStateError);
      expect(s.labelWrites, 0);
      s.close();
    },
  );
  test('changed comma label is rejected before any content mutation', () async {
    final s = Server();
    await expectLater(
      s.repo.save(await s.baseline(), s.edit(labels: ['new,label'])),
      throwsFormatException,
    );
    expect(s.contentWrites, 0);
    expect(s.labelWrites, 0);
    s.close();
  });

  test(
    'actual separate content/label replacement, exact script and explicit empty labels read back',
    () async {
      final s = Server();
      final before = await s.baseline();
      final result = await s.repo.save(before, s.edit());
      expect(result.allReceiptsKnown, isTrue);
      expect(result.note.metadata.id, 7);
      expect(result.note.source, s.edit().source);
      expect(result.note.metadata.title, 'Updated HTML');
      expect(result.note.labels, isEmpty);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      s.close();
    },
  );
  test(
    'protected HTML keeps exact unlock password and does not change protection',
    () async {
      final s = Server(protected: true);
      final result = await s.repo.save(
        await s.baseline(),
        s.edit(labels: ['读书']),
      );
      expect(result.note.metadata.protected, isTrue);
      expect(result.note.unlockPassword, ' raw password ');
      expect(result.note.labels, ['读书']);
      s.close();
    },
  );
  test('concurrent baseline change prevents every mutation', () async {
    final s = Server();
    final before = await s.baseline();
    s.row['version'] = 10;
    await expectLater(
      s.repo.save(before, s.edit()),
      throwsA(isA<HtmlNoteConflict>()),
    );
    expect(s.contentWrites, 0);
    expect(s.labelWrites, 0);
    s.close();
  });
  test(
    'known content receipt plus failed labels resumes only labels',
    () async {
      final s = Server();
      final before = await s.baseline();
      s.failLabels = true;
      HtmlSaveIncomplete? pending;
      try {
        await s.repo.save(before, s.edit());
      } on HtmlSaveIncomplete catch (e) {
        pending = e;
      }
      expect(pending, isNotNull);
      expect(pending!.attempt.contentReceipt, isTrue);
      expect(pending.attempt.labelsReceipt, isFalse);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      s.failLabels = false;
      final done = await s.repo.finishLabels(pending.attempt);
      expect(done.allReceiptsKnown, isTrue);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 2);
      s.close();
    },
  );
  test(
    'applied content with lost receipt stays unknown until explicit read, then resumes labels without content resend',
    () async {
      final s = Server();
      final before = await s.baseline();
      s.loseContent = true;
      HtmlSaveIncomplete? pending;
      try {
        await s.repo.save(before, s.edit());
      } on HtmlSaveIncomplete catch (e) {
        pending = e;
      }
      expect(pending!.attempt.contentReceipt, isFalse);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 0);
      await expectLater(s.repo.finishLabels(pending.attempt), throwsStateError);
      final actual = await s.baseline();
      expect(pending.attempt.edit.sameContent(actual), isTrue);
      final done = await s.repo.finishLabels(pending.attempt.observedContent());
      expect(done.note.labels, isEmpty);
      expect(done.allReceiptsKnown, isFalse);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      s.close();
    },
  );
  test(
    'applied labels with lost receipt are observed without another replacement',
    () async {
      final s = Server();
      final before = await s.baseline();
      s.loseLabels = true;
      HtmlSaveIncomplete? pending;
      try {
        await s.repo.save(before, s.edit());
      } on HtmlSaveIncomplete catch (e) {
        pending = e;
      }
      expect(pending!.attempt.contentReceipt, isTrue);
      expect(pending.attempt.labelsReceipt, isFalse);
      final done = await s.repo.finishLabels(pending.attempt);
      expect(done.allReceiptsKnown, isFalse);
      expect(s.contentWrites, 1);
      expect(s.labelWrites, 1);
      s.close();
    },
  );
  test(
    'intervening external content or labels after content receipt are not overwritten',
    () async {
      for (final changeSource in [true, false]) {
        final s = Server();
        final before = await s.baseline();
        s.afterContent = () {
          if (changeSource) {
            s.source = '<p>External</p>';
          } else {
            s.labels = ['external'];
          }
        };
        HtmlSaveIncomplete? pending;
        try {
          await s.repo.save(before, s.edit());
        } on HtmlSaveIncomplete catch (e) {
          pending = e;
        }
        expect(pending!.attempt.contentReceipt, isTrue);
        expect(pending.observed, isNotNull);
        expect(s.labelWrites, 0);
        await expectLater(
          s.repo.finishLabels(pending.attempt),
          throwsA(isA<HtmlSaveIncomplete>()),
        );
        expect(s.labelWrites, 0);
        s.close();
      }
    },
  );
  test(
    'definite update rejection remains retryable with no label mutation',
    () async {
      final s = Server();
      final before = await s.baseline();
      s.rejectContent = true;
      await expectLater(
        s.repo.save(before, s.edit()),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 400)),
      );
      expect(s.source, before.source);
      expect(s.labelWrites, 0);
      s.rejectContent = false;
      expect((await s.repo.save(before, s.edit())).allReceiptsKnown, isTrue);
      s.close();
    },
  );
  test(
    'UTF8 byte bounds, malformed Unicode and unrepresentable labels fail before network',
    () async {
      final s = Server();
      final before = await s.baseline();
      for (final edit in [
        HtmlNoteEdit(title: '中' * 67, source: '', labels: []),
        HtmlNoteEdit(
          title: 'valid',
          source: 'x' * (5 * 1024 * 1024 + 1),
          labels: [],
        ),
        HtmlNoteEdit(
          title: 'valid',
          source: String.fromCharCode(0xd800),
          labels: [],
        ),
        HtmlNoteEdit(title: 'valid', source: '', labels: ['one,two']),
      ]) {
        await expectLater(s.repo.save(before, edit), throwsFormatException);
      }
      expect(s.contentWrites, 0);
      expect(s.labelWrites, 0);
      s.close();
    },
  );
}
