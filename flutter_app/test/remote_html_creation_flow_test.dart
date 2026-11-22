import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_controller.dart';
import 'package:bookstark_flutter/features/html/remote_html_create_page.dart';
import 'html_note_page_fake_surface_test_support.dart';
import 'package:bookstark_flutter/features/html/html_version_view.dart';
import 'remote_html_creation_controller_test.dart' show CreationServer;

class EmptyCreationLabels implements LabelsRepository {
  @override
  Future<List<String>> search(String keyword, {int page = 1}) async => [];
}

void main() {
  late CreationServer server;
  late HtmlCreationVault vault;
  late Map<String, String> values;
  late RemoteHtmlCreationController c;
  late FakeHtmlSurfaceControl sourceSurface;
  int? openedId;
  setUp(() {
    installFakeHtmlSessionChannel();
    sourceSurface = FakeHtmlSurfaceControl();
    server = CreationServer();
    values = {};
    openedId = null;
    vault = HtmlCreationVault(
      server: Uri.parse('https://books.example'),
      memberId: 3,
      collection: 'note',
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
    );
    c = RemoteHtmlCreationController(
      RemoteHtmlCreationRepository(
        server.client,
        memberId: 3,
        collection: 'note',
      ),
      vault,
      record: HtmlCreationRecord(
        key: '0123456789abcdef0123456789abcdef',
        memberId: 3,
        collection: 'note',
        edit: HtmlNoteEdit(
          title: server.row['blog_title'] as String,
          source: server.source,
          labels: server.labels,
        ),
        pending: true,
        createdId: 7,
      ),
    );
  });
  tearDown(() {
    server.repo.dispose();
    server.client.close();
  });
  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                openedId = await Navigator.of(context).push<int>(
                  MaterialPageRoute(
                    builder: (_) => RemoteHtmlCreatePage(
                      controller: c,
                      labels: EmptyCreationLabels(),
                      serverLabel: 'https://books.example',
                      readOnlySourceSurfaceBuilder:
                          fakeReadOnlyHtmlCodeSurface(),
                      sourceSurfaceBuilder: fakeHtmlSourceSurface(
                        sourceSurface,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open creation'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open creation'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'restored known ID is read-only and full review is required before adoption',
    (tester) async {
      await vault.write(c.record as HtmlCreationRecord);
      await mount(tester);
      expect(find.text('保存'), findsNothing);
      await tap(tester, '只读核对服务器新建结果');
      expect(c.phase, RemoteHtmlCreationPhase.review);
      expect(server.posts, 0);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, '采用已核对笔记并继续'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.text(server.row['blog_title'] as String).last,
      );
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.byType(HtmlVersionViewPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, '采用已核对笔记并继续');
      expect(openedId, 7);
      expect(server.posts, 0);
      expect(values, isEmpty);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'pending leave preserves recovery and never offers discard or another Save',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('放弃草稿'), findsNothing);
      expect(find.text('保存'), findsNothing);
      await tap(tester, '保留并离开');
      expect(values.length, 1);
      expect(server.posts, 0);
      expect(openedId, isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'protected candidate opens unlock only after hash-only recovery is durable',
    (tester) async {
      server.row['has_password'] = true;
      await mount(tester);
      await tap(tester, '只读核对服务器新建结果');
      expect(find.text('解锁笔记'), findsOneWidget);
      expect(values.values.single, isNot(contains(server.source)));
      expect(server.rawReads, 0);
      await tester.enterText(
        find.byKey(const Key('note-password')),
        ' raw password ',
      );
      await tap(tester, '解锁');
      expect(c.phase, RemoteHtmlCreationPhase.review);
      expect(server.posts, 0);
      expect(values.values.single, isNot(contains('raw password')));
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
