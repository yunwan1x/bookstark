// Explicit disposable Go fixture only; never normal unit-test discovery.
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

class PublicHtmlObservedTransport extends http.BaseClient {
  final inner = http.Client();
  int requests = 0;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    stdout.writeln(
      'HTTP ${++requests} ${request.method} ${request.url.pathSegments.take(2).join('/')} status=${response.statusCode} media=${response.headers['content-type']?.split(';').first}',
    );
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'actual anonymous Go HTML shares preserve exact raw data, unlock and chapter membership',
    () async {
      final path = Platform.environment['BOOKSTARK_ANDROID_FIXTURE_CONFIG'];
      if (path == null ||
          !path.startsWith(
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-live-fixture/',
          )) {
        throw StateError('Explicit disposable fixture required');
      }
      final config = jsonDecode(await File(path).readAsString()) as Map;
      final base = Uri.parse(config['local_base'] as String);
      if (config['fixture'] != true ||
          base.host != '127.0.0.1' ||
          base.scheme != 'http') {
        throw StateError('Owned loopback Go fixture required');
      }
      final owner = BookstarkClient(
            base.toString(),
            transport: PublicHtmlObservedTransport(),
          ),
          public = BookstarkClient(
            base.toString(),
            transport: PublicHtmlObservedTransport(),
          );
      final repo = RemotePublicSharesRepository(public);
      final books = RemoteBooksRepository(owner);
      final notes = <int>[], bookIds = <int>[];
      try {
        await owner.login(
          config['account'] as String,
          config['password'] as String,
        );
        const header = '\ufeff<!doctype html>\r\n<html><body><pre>中文';
        const tail =
            '</pre><script>window.fixture=true;</script></body></html>\r\n';
        final large =
            header +
            'x' * (5 * 1024 * 1024 - utf8.encode(header + tail).length) +
            tail;
        check(
          utf8.encode(large).length == 5 * 1024 * 1024,
          'Exact five MiB test boundary',
        );
        for (final protected in [false, true]) {
          final source = protected
              ? '\ufeff<h1>密码 HTML</h1>\r\n<script>let test=1;</script>\r\n'
              : large;
          final row = await owner.post('/api/blogs', {
            'blog_title': 'Public HTML contract $protected',
            'blog_type': 'note',
            'editor_type': 'html',
            'blog_content': source,
            'visibility': 0,
            if (protected) 'new_password': ' public html password ',
          });
          final id = row['blog_id'] as int;
          notes.add(id);
          final share = await owner.post('/api/shares', {
            'share_type': 'blog',
            'target_id': id,
          });
          final ref = PublicShareReference(
            public.baseUri,
            share['share_identify'] as String,
          );
          final detail = await repo.load(ref);
          check(detail.html && detail.targetId == id, 'Actual HTML identity');
          if (protected) {
            check(
              detail.locked && detail.content.isEmpty && detail.labels.isEmpty,
              'Protected HTML metadata stays masked',
            );
            var rejected = false;
            try {
              await repo.unlock(detail, 'wrong');
            } on ApiFailure {
              rejected = true;
            }
            check(
              rejected && detail.locked && detail.content.isEmpty,
              'Wrong password cannot reveal or mutate detail',
            );
            final unlocked = await repo.unlock(
              detail,
              ' public html password ',
            );
            check(
              unlocked.unlocked && unlocked.content == source,
              'Actual raw password unlock retains spaces, BOM and CRLF',
            );
            check(
              (await repo.load(ref)).locked,
              'Refresh relocks HTML without persisting password',
            );
          } else {
            check(
              detail.content == source,
              'Actual Go compressed five MiB source retained with BOM/Unicode/CRLF',
            );
            check(
              await owner.blogHtmlSource(id) == source,
              'Owner HTML raw source also preserves BOM',
            );
          }
          await owner.mutate('DELETE', '/api/shares/blog/$id', {});
          var revoked = false;
          try {
            await repo.load(ref);
          } on ApiFailure catch (error) {
            revoked = error.status == 404;
          }
          check(
            revoked,
            'Revoked HTML share fails instead of retaining old content',
          );
        }
        for (final name in [
          'Public HTML chapter contract',
          'Foreign HTML chapter contract',
        ]) {
          bookIds.add(await books.save(BookItem(name: name)));
        }
        final doc = await owner.post('/api/books/${bookIds.first}/docs', {
          'document_name': 'Actual HTML chapter',
          'parent_id': 0,
          'doc_type': 'html',
        });
        final id = doc['document_id'] as int;
        const source =
            '\ufeff<h1>HTML chapter</h1>\r\n<script>let chapter=1;</script>';
        await owner.mutate('PUT', '/api/docs/$id', {'markdown': source});
        final shared = await owner.post('/api/shares', {
          'share_type': 'book',
          'target_id': bookIds.first,
        });
        final bookRef = PublicShareReference(
          public.baseUri,
          shared['share_identify'] as String,
        );
        final book = await repo.load(bookRef);
        final identify = doc['identify'] as String;
        final chapter = await repo.chapter(book, identify);
        check(
          chapter.node.id == id &&
              chapter.format == 'html' &&
              chapter.content == source,
          'Actual public HTML chapter raw endpoint',
        );
        final foreign =
            (await owner.post('/api/books/${bookIds.last}/docs', {
                  'document_name': 'Foreign HTML',
                  'parent_id': 0,
                  'doc_type': 'html',
                }))['identify']
                as String;
        var denied = false;
        try {
          await public.publicShareHtmlSource(bookRef, chapterIdentify: foreign);
        } on ApiFailure catch (error) {
          denied = error.status == 403;
        }
        check(denied, 'Backend independently refuses cross-book raw HTML');
        check(
          public.exportSession()['token'] == null,
          'Public requests never logged into owner account',
        );
        stdout.writeln(
          'PASS actual Go anonymous HTML: compressed5MiB, BOM/Unicode/CRLF, password spaces, wrong password, refresh relock, revoke, public chapter and cross-book403',
        );
      } finally {
        for (final id in notes) {
          await owner.mutate('DELETE', '/api/blogs/$id', {});
        }
        for (final id in bookIds) {
          await books.remove(id);
        }
        public.close();
        owner.close();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
