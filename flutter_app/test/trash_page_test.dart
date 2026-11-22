import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/trash/trash_page.dart';
import 'trash_controller_test.dart' as fixture;
import 'api_tokens_page_test.dart' show click;

Future<void> open(
  WidgetTester tester,
  fixture.Repo r, {
  bool english = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: TrashPage(repository: r, english: english),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'single restore confirmation cancellation has zero writes and success describes actual verified evidence',
    (tester) async {
      final r = fixture.Repo();
      await open(tester, r);
      await click(tester, find.text('还原').first);
      expect(find.text('还原这1项？'), findsOneWidget);
      expect(r.writes, 0);
      await click(tester, find.text('取消'));
      expect(r.writes, 0);
      await click(tester, find.text('还原').first);
      await click(tester, find.text('确认还原'));
      expect(r.writes, 1);
      expect(r.probes, 1);
      expect(find.textContaining('还原回执已收到，回收站记录已移出。'), findsOneWidget);
    },
  );
  testWidgets(
    'page selection delete lists exact projects and known partial failure remains selected',
    (tester) async {
      final r = fixture.Repo()..rejectId = 2;
      await open(tester, r);
      await click(tester, find.text('选择当前页'));
      await click(tester, find.text('永久删除所选'));
      expect(find.text('永久删除这3项？'), findsOneWidget);
      expect(r.writes, 0);
      expect(find.text('note1\n笔记与文章 · #1'), findsOneWidget);
      await click(tester, find.text('确认永久删除'));
      expect(r.writes, 3);
      expect(find.text('已选1项'), findsOneWidget);
      expect(find.textContaining('操作未完成，保留选择'), findsOneWidget);
    },
  );
  testWidgets(
    'unknown applied deletion blocks writes and only explicit read verifies absence',
    (tester) async {
      final r = fixture.Repo()..loseId = 1;
      await open(tester, r);
      await click(tester, find.text('永久删除').first);
      await click(tester, find.text('确认永久删除'));
      expect(r.writes, 1);
      expect(find.textContaining('结果未知，不会自动重发。'), findsOneWidget);
      await click(tester, find.text('只读核对未确认结果'));
      expect(r.writes, 1);
      expect(find.textContaining('记录已移出；上次操作回执仍未知。'), findsOneWidget);
    },
  );
  testWidgets(
    'English narrow200 percent confirmation and selected controls remain scrollable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final r = fixture.Repo();
      await open(tester, r, english: true);
      await click(tester, find.text('Select current page'));
      await click(tester, find.text('Delete selected permanently'));
      await click(tester, find.text('Cancel'));
      expect(r.writes, 0);
      await click(tester, find.text('Restore selected'));
      await click(tester, find.text('Confirm restoration'));
      expect(r.writes, 3);
      expect(tester.takeException(), isNull);
    },
  );
}
