import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_notes_repository.dart';
import 'package:bookstark_flutter/features/public_notes/public_notes_page.dart';
import 'public_notes_repository_test.dart' as fixture;

class Repo implements PublicNotesRepository {
  final pages = <int>[];
  bool fail = false;
  Completer<PublicNotesPageData>? pending;
  bool aborted = false;
  @override
  Future<PublicNotesPageData> load(
    int page, {
    Future<void>? abortTrigger,
  }) async {
    pages.add(page);
    abortTrigger?.then((_) {
      aborted = true;
    });
    if (pending != null) {
      return pending!.future;
    }
    if (fail) {
      throw StateError('private error details');
    }
    return parsePublicNotes(
      fixture.source(
        page == 1
            ? [
                fixture.note(),
                fixture.note(id: 8, identify: 'locked', locked: true)
                  ..['labels'] = ['Secret locked tag'],
              ]
            : [],
      ),
      server: fixture.server,
      page: page,
    );
  }
}

Future<void> click(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'local page label selection retains actual identity and locked metadata never appears',
    (tester) async {
      final repo = Repo();
      PublicNotePreview? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: PublicNotesPage(
            repository: repo,
            onOpen: (item) async {
              opened = item;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Secret locked tag'), findsNothing);
      expect(find.text('正文需密码'), findsOneWidget);
      await click(tester, find.widgetWithText(ChoiceChip, '阅读'));
      expect(find.text('正文需密码'), findsNothing);
      await click(tester, find.text('打开完整笔记'));
      expect(opened!.id, 7);
      expect(opened!.reference.identify, 'literal%2F+');
      expect(repo.pages, [1]);
    },
  );
  testWidgets(
    'explicit next reaches real empty page then previous returns; errors clear old previews and only retry reads',
    (tester) async {
      final repo = Repo();
      await tester.pumpWidget(
        MaterialApp(
          home: PublicNotesPage(repository: repo, onOpen: (_) async {}),
        ),
      );
      await tester.pumpAndSettle();
      await click(tester, find.text('下一页'));
      expect(find.text('这一页暂无公开笔记。'), findsOneWidget);
      await click(tester, find.text('上一页'));
      expect(find.text('Actual preview'), findsOneWidget);
      repo.fail = true;
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(find.text('Actual preview'), findsNothing);
      expect(find.textContaining('private error'), findsNothing);
      repo.fail = false;
      await click(tester, find.text('重试'));
      expect(find.text('Actual preview'), findsOneWidget);
      expect(repo.pages, [1, 2, 1, 1, 1]);
    },
  );
  testWidgets('leaving cancels pending read and ignores late response', (
    tester,
  ) async {
    final repo = Repo()..pending = Completer<PublicNotesPageData>();
    await tester.pumpWidget(
      MaterialApp(
        home: PublicNotesPage(repository: repo, onOpen: (_) async {}),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(repo.aborted, isTrue);
    repo.pending!.complete(PublicNotesPageData(1, []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'English 320dp 200 percent page cards filters and pagination scroll without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: PublicNotesPage(
            repository: Repo(),
            english: true,
            onOpen: (_) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await click(tester, find.text('Next'));
      expect(find.text('No public notes on this page.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
