import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';

class LostHtmlPutReceipt extends http.BaseClient {
  LostHtmlPutReceipt(this.path);
  final String path;
  final transport = http.Client();
  int contentWrites = 0;
  bool dropped = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final target = request.method == 'PUT' && request.url.path == path;
    if (target) contentWrites++;
    final response = await transport.send(request);
    if (target && !dropped) {
      dropped = true;
      await readBoundedResponse(response, maxBytes: 128 * 1024);
      throw TimeoutException('Owned fixture discarded applied HTML receipt');
    }
    return response;
  }

  @override
  void close() => transport.close();
}

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runHtmlSourceContract(BookstarkClient client) async {
  final ids = <int>[];
  final profile = await client.profileSettingsJson();
  final repository = RemoteHtmlNotesRepository(
    client,
    memberId: profile['member_id'] as int,
  );
  final prefix =
      'html-source-contract-${DateTime.now().microsecondsSinceEpoch}';
  const small =
      '<!doctype html>\n<meta charset="utf-8"><h1>你好</h1><script>window.test = "保留";</script>\n';
  // Exercise the real server compression and actual Dart IO decompression,
  // including a source larger than the former Markdown 500KB limit.
  final large = '<!doctype html><pre>${'中文 & < >\n' * 70000}</pre>';
  try {
    for (final protected in [false, true]) {
      final source = protected ? small : large;
      final created = await client.post('/api/blogs', {
        'blog_title': '$prefix-$protected',
        'blog_type': 'note',
        'editor_type': 'html',
        'blog_content': source,
        'visibility': 0,
        if (protected) 'labels': 'html-contract',
        if (protected) 'new_password': ' html-source-password ',
      });
      final id = created['blog_id'] as int;
      ids.add(id);
      final metadata = await client.get('/api/blogs/$id');
      check(
        metadata['editor_type'] == 'html' && metadata['blog_content'] == '',
        'HTML metadata is not the source',
      );
      if (protected) {
        try {
          await client.blogHtmlSource(id);
          throw StateError('Protected raw content was unexpectedly public');
        } on ApiFailure catch (error) {
          check(error.status == 403, 'Protected raw endpoint returns 403');
        }
      }
      final password = protected ? ' html-source-password ' : null;
      check(
        await client.blogHtmlSource(id, password: password) == source,
        'Real raw HTML source matches exact Unicode and markup',
      );
      final baseline = await repository.read(id, password: password);
      check(
        baseline.source == source &&
            baseline.metadata.id == id &&
            baseline.metadata.protected == protected,
        'Actual typed HTML repository preserves complete protected/normal baseline',
      );
      check(
        baseline.labels.length == (protected ? 1 : 0),
        'Actual Go null and nonempty resource labels',
      );
      const changed =
          '<html><body><button onclick="this.textContent=42">Run</button></body></html>';
      final saved = await repository.save(
        baseline,
        HtmlNoteEdit(
          title: '$prefix-$protected',
          source: changed,
          labels: protected ? [] : ['html-saved'],
        ),
      );
      check(
        saved.allReceiptsKnown &&
            saved.note.source == changed &&
            saved.note.labels.length == (protected ? 0 : 1),
        'Actual HTML save receipts and independent source/labels readback',
      );
      var expected = changed;
      if (!protected) {
        final dropped = LostHtmlPutReceipt(
          '${client.baseUri.path}/api/blogs/$id',
        );
        final interrupted = BookstarkClient(
          client.baseUri.toString(),
          transport: dropped,
        )..restoreSession(client.exportSession());
        final recovery = RemoteHtmlNotesRepository(
          interrupted,
          memberId: profile['member_id'] as int,
        );
        try {
          final edit = HtmlNoteEdit(
            title: '$prefix-$protected',
            source: '$changed<!-- lost receipt -->',
            labels: ['html-observed'],
          );
          HtmlSaveIncomplete? pending;
          try {
            await recovery.save(saved.note, edit);
          } on HtmlSaveIncomplete catch (error) {
            pending = error;
          }
          check(
            pending != null &&
                !pending.attempt.contentReceipt &&
                dropped.contentWrites == 1,
            'Actual applied lost receipt remains unknown without resend',
          );
          final observed = await recovery.read(id);
          check(
            edit.sameContent(observed) &&
                observed.labels.single == 'html-saved',
            'Explicit actual readonly verification sees applied content and old labels',
          );
          final finished = await recovery.finishLabels(
            pending!.attempt.observedContent(),
          );
          check(
            !finished.allReceiptsKnown &&
                finished.note.labels.single == 'html-observed' &&
                dropped.contentWrites == 1,
            'Explicit label-only recovery never replays content or fabricates receipt',
          );
          expected = edit.source;
        } finally {
          recovery.dispose();
          interrupted.close();
        }
      }
      check(
        await client.blogHtmlSource(id, password: password) == expected,
        'Actual HTML edit roundtrip retains exact source',
      );
      final after = await client.get('/api/blogs/$id');
      check(
        after['editor_type'] == 'html' && after['has_password'] == protected,
        'Editing preserves HTML format and protection',
      );
      if (protected) {
        final empty = await repository.save(
          await repository.read(id, password: password),
          HtmlNoteEdit(title: '$prefix-$protected', source: '', labels: []),
        );
        check(
          empty.allReceiptsKnown &&
              empty.note.source.isEmpty &&
              empty.note.metadata.protected,
          'Actual protected HTML can save an intentionally empty source without losing protection',
        );
      }
    }
  } finally {
    repository.dispose();
    for (final id in ids) {
      await client.mutate('DELETE', '/api/blogs/$id', {});
    }
  }
  stdout.writeln(
    'PASS real Go HTML raw source: compressed Unicode >500KB, exact script/markup, protected CSRF unlock with password spaces, actual typed owner/version/labels baseline, receipt-aware separate content/labels save, applied lost receipt with explicit label-only recovery, protected empty source, edit readback and format/protection preserved; disposable fixture only',
  );
}

Future<void> main(List<String> args) async {
  if (args.length != 1 ||
      !args.single.startsWith(
        '/vol1/1000/wy/photos-apk-test/bookstark-flutter/',
      )) {
    throw StateError('Owned disposable fixture configuration required');
  }
  final config = jsonDecode(await File(args.single).readAsString()) as Map;
  final server = config['local_base'] as String;
  if (config['fixture'] != true || !server.startsWith('http://127.0.0.1:')) {
    throw StateError('Owned loopback fixture required');
  }
  final client = BookstarkClient(server);
  try {
    await client.login(
      config['account'] as String,
      config['password'] as String,
    );
    await runHtmlSourceContract(client);
  } finally {
    client.close();
  }
}
