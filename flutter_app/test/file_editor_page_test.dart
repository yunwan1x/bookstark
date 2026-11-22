import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/file_draft_vault.dart';
import 'package:bookstark_flutter/features/drive/file_editor_page.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import '../tool/fixtures/drive.dart';

void main() {
  testWidgets(
    'actual editor persists draft previews Markdown and saves real bytes',
    (tester) async {
      final repo = DriveFixture(seed: false);
      final file = repo.addFile('read.md', utf8.encode('old'), 'text/markdown');
      final storage = <String, String>{};
      final vault = FileDraftVault(
        namespace: 'fixture',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async => storage[key] = value,
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: FileEditorPage(repository: repo, file: file, vault: vault),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('file-content-input')),
        '# New\n\n**bold**',
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(storage, isNotEmpty);
      await tester.tap(find.text('预览'));
      await tester.pumpAndSettle();
      expect(find.byType(BookstarkMarkdown), findsOneWidget);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(utf8.decode(repo.data[file.path]!), '# New\n\n**bold**');
      expect(storage, isEmpty);
      expect(find.textContaining('未保存'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('unreadable draft never creates editable blank overwrite', (
    tester,
  ) async {
    final repo = DriveFixture(seed: false);
    final file = repo.addFile(
      'read.md',
      utf8.encode('original'),
      'text/markdown',
    );
    final vault = FileDraftVault(
      namespace: 'fixture',
      readValue: (key) async => throw StateError('secure storage unavailable'),
      writeValue: (key, value) async {},
      deleteValue: (key) async {},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: FileEditorPage(repository: repo, file: file, vault: vault),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('重新读取文件'), findsOneWidget);
    expect(repo.saves, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
