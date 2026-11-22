import 'dart:convert';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/drive/file_upload_page.dart';
import '../tool/fixtures/drive.dart';

XFile source(String name, String body) => XFile.fromData(
  utf8.encode(body),
  path: name,
  lastModified: DateTime.utc(2026),
);
Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });
  await tester.pump();
}

void main() {
  testWidgets(
    'picker selection does not upload and explicit skip protects existing file',
    (tester) async {
      final repo = DriveFixture(seed: false);
      repo.addFile('a.md', utf8.encode('original'), 'text/markdown');
      await tester.pumpWidget(
        MaterialApp(
          home: FileUploadPage(
            repository: repo,
            directory: '',
            pickFiles: () async => [source('a.md', 'replacement')],
          ),
        ),
      );
      await tester.tap(find.text('选择文件（可多选）'));
      await tester.pumpAndSettle();
      expect(repo.uploads, 0);
      await tester.tap(find.text('开始上传'));
      for (var i = 0; i < 15 && find.text('跳过').evaluate().isEmpty; i++) {
        await flush(tester);
      }
      expect(find.text('覆盖'), findsOneWidget);
      expect(repo.uploads, 0);
      await tester.tap(find.text('跳过'));
      await tester.pumpAndSettle();
      expect(find.textContaining('已跳过'), findsOneWidget);
      expect(utf8.decode(repo.data['a.md']!), 'original');
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'directory picker navigates actual folders before starting upload',
    (tester) async {
      final repo = DriveFixture(seed: false)..addDirectory('资料');
      await tester.pumpWidget(
        MaterialApp(
          home: FileUploadPage(
            repository: repo,
            directory: '',
            pickFiles: () async => [],
          ),
        ),
      );
      await tester.tap(find.text('全部文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('资料'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择此目录'));
      await tester.pumpAndSettle();
      expect(find.text('全部文件 / 资料'), findsOneWidget);
      expect(repo.uploads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
