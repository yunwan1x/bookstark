import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/html/remote_html_create_page.dart';
import 'html_note_page_fake_surface_test_support.dart';

void main() {
  for (final collection in [NoteCollection.note, NoteCollection.article]) {
    testWidgets(
      'remote ${collection.name} format cancellation and HTML draft perform no mutations',
      (tester) async {
        installFakeHtmlSessionChannel();
        final sourceSurface = FakeHtmlSurfaceControl();
        var mutations = 0;
        final client = BookstarkClient(
          'https://books.example',
          transport: MockClient((request) async {
            if (request.method != 'GET') mutations++;
            expect(request.method, 'GET');
            return http.Response(
              jsonEncode({
                'code': 0,
                'data': request.url.path == '/api/profile'
                    ? {'member_id': 3}
                    : [],
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        )..restoreSession({'token': 'session'});
        final values = <String, String>{};
        final vault = HtmlCreationVault(
          server: client.baseUri,
          memberId: 3,
          collection: collection.name,
          readValue: (k) async => values[k],
          writeValue: (k, v) async {
            values[k] = v;
          },
          deleteValue: (k) async {
            values.remove(k);
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: NotesPage(
              repository: RemoteNotesRepository(client, collection: collection),
              collection: collection,
              htmlCreationVault: vault,
              htmlSourceSurfaceBuilder: fakeHtmlSourceSurface(sourceSurface),
              htmlReadOnlySourceSurfaceBuilder: fakeReadOnlyHtmlCodeSurface(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final create = find.byTooltip(
          collection == NoteCollection.article ? '新建文章' : '新建笔记',
        );
        await tester.tap(create);
        await tester.pumpAndSettle();
        final markdownLabel = collection == NoteCollection.article
            ? 'Markdown 文章'
            : 'Markdown 笔记';
        final htmlLabel = collection == NoteCollection.article
            ? 'HTML 文章'
            : 'HTML 笔记';
        expect(find.text(markdownLabel), findsOneWidget);
        expect(find.text(htmlLabel), findsOneWidget);
        Navigator.of(tester.element(find.text(htmlLabel))).pop();
        await tester.pumpAndSettle();
        expect(values, isEmpty);
        expect(mutations, 0);
        await tester.tap(create);
        await tester.pumpAndSettle();
        await tester.tap(find.text(htmlLabel));
        await tester.pumpAndSettle();
        expect(find.byType(RemoteHtmlCreatePage), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('remote-html-create-title')),
          'Unsubmitted HTML',
        );
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('保留并离开'));
        await tester.pumpAndSettle();
        expect(values.length, 1);
        expect(mutations, 0);
        final record = await vault.read();
        expect(record!.pending, isFalse);
        expect(record.edit.title, 'Unsubmitted HTML');
        expect(sourceSurface.snapshotBegins, greaterThan(0));
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        client.close();
      },
    );
  }
}
