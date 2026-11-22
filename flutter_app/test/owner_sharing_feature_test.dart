import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/sharing/owner_sharing.dart';

http.Response reply(Map<String, Object?> data) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': data})),
  200,
  headers: {'content-type': 'application/json'},
);
void main() {
  testWidgets(
    'real owner notes menu reaches sharing and password repositories without publishing on open',
    (tester) async {
      var writes = 0;
      String? password;
      final requests = <String>[];
      final client = BookstarkClient(
        'https://example.test/base',
        transport: MockClient((r) async {
          requests.add('${r.method} ${r.url.path}');
          expect(r.followRedirects, isFalse);
          if (r.method != 'GET') {
            writes++;
          }
          if (r.url.path == '/base/api/blogs') {
            return reply({
              'data': [
                {
                  'blog_id': 7,
                  'blog_title': 'List preview title',
                  'content_preview': 'preview',
                },
              ],
              'total': 1,
            });
          }
          if (r.url.path == '/base/api/blogs/7') {
            if (r.method == 'PUT') {
              final body = jsonDecode(r.body) as Map;
              expect(body.keys, {'new_password'});
              password = body['new_password'] as String;
              return reply({});
            }
            return reply({
              'blog_id': 7,
              'blog_title': 'Actual owner title',
              'blog_type': 'note',
              'editor_type': 'markdown',
              'has_password': password != null,
              'blog_content': password == null ? 'actual body' : '',
            });
          }
          if (r.url.path == '/base/api/blogs/7/verify-password') {
            expect((jsonDecode(r.body) as Map)['password'], password);
            return reply({'blog_content': 'actual body'});
          }
          if (r.url.path == '/base/api/shares/status') {
            return reply({});
          }
          if (r.url.path == '/base/api/shares') {
            return reply({
              'share_identify': 'actual-owner-7',
              'edit_token': '',
            });
          }
          throw StateError('Unexpected owner feature endpoint');
        }),
      )..restoreSession({'csrf_token': 'csrf'});
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => NotesPage(
              repository: RemoteNotesRepository(client),
              onShareSettings: (note) => openOwnerSharing(
                context,
                client: client,
                kind: PublicShareKind.blog,
                id: note.id,
                title: note.title,
                onSpeak: (_, _, _) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('笔记操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('分享设置'));
      await tester.pumpAndSettle();
      expect(writes, 0);
      expect(find.text('Actual owner title'), findsOneWidget);
      expect(requests, contains('GET /base/api/shares/status'));
      await tester.ensureVisible(find.text('公开并获取链接'));
      await tester.tap(find.text('公开并获取链接'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('确认公开并获取'));
      await tester.tap(find.text('确认公开并获取'));
      await tester.pumpAndSettle();
      expect(writes, 1);
      expect(
        find.text('https://example.test/base/shares/actual-owner-7'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('管理内容密码'));
      await tester.tap(find.text('管理内容密码'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        ' native password ',
      );
      await tester.enterText(
        find.byType(TextFormField).at(1),
        ' native password ',
      );
      await tester.ensureVisible(find.text('设置密码'));
      await tester.tap(find.text('设置密码'));
      await tester.pumpAndSettle();
      expect(password, ' native password ');
      expect(writes, 3);
      expect(find.text('密码更改已核对。'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('当前正文设有密码。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    },
  );
}
