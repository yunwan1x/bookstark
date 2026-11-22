import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/file_draft_vault.dart';
import 'package:bookstark_flutter/features/drive/drive_page.dart';
import '../tool/fixtures/drive.dart';

FileDraftVault vault() => FileDraftVault(
  namespace: 'fixture',
  readValue: (_) async => null,
  writeValue: (_, _) async {},
  deleteValue: (_) async {},
);
void main() {
  testWidgets(
    'actual directory navigation and current folder search do not alter files',
    (tester) async {
      final repo = DriveFixture(seed: false)..addDirectory('资料');
      repo.addFile('资料/target.md', utf8.encode('actual'), 'text/markdown');
      repo.addFile('root.txt', utf8.encode('root'), 'text/plain');
      await tester.pumpWidget(
        MaterialApp(
          home: DrivePage(repository: repo, vault: vault()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('root.txt'), findsOneWidget);
      expect(find.text('target.md'), findsNothing);
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      expect(find.text('target.md'), findsOneWidget);
      expect(find.text('root.txt'), findsNothing);
      await tester.enterText(find.byType(TextField), 'nomatch');
      await tester.pumpAndSettle();
      expect(find.text('当前目录没有匹配文件'), findsOneWidget);
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('root.txt'), findsOneWidget);
      expect(repo.removals, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'delete menu cannot delete until explicit permanent confirmation',
    (tester) async {
      final repo = DriveFixture(seed: false);
      repo.addFile('target.txt', utf8.encode('actual'), 'text/plain');
      await tester.pumpWidget(
        MaterialApp(
          home: DrivePage(repository: repo, vault: vault()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('target.txt 操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('永久删除'));
      await tester.pumpAndSettle();
      expect(repo.removals, 0);
      expect(find.textContaining('不会进入回收站'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repo.nodes.containsKey('target.txt'), isTrue);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
