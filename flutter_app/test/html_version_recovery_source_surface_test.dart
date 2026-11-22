// Candidate test excerpts for test/html_version_view_test.dart and
// test/html_recovery_review_test.dart after the page builder seam is added.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/features/html/html_recovery_review.dart';
import 'package:bookstark_flutter/features/html/html_version_view.dart';

const fixture = '\ufeff<!doctype html>\r\n<p>版本只读 🧭</p>\n';

Widget fakeSource({
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required Future<void> Function(ComplexEditorTransport transport) onReady,
  required void Function(ComplexEditorState state) onState,
  required Future<void> Function(ComplexEditorTransport transport) beforeRetire,
  required VoidCallback onReloadRequested,
}) => Text('fake-html-source:${document.digest}:${document.source}');

void main() {
  testWidgets('version source toggles to immutable HTML source seam', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HtmlVersionViewPage(
          heading: '版本 3',
          title: '只读记录',
          source: fixture,
          labels: ['设计'],
          sourceSurfaceBuilder: fakeSource,
        ),
      ),
    );
    await tester.tap(find.text('源码'));
    await tester.pump();
    expect(find.textContaining('fake-html-source:'), findsOneWidget);
    expect(find.text('只读记录'), findsOneWidget);
    expect(find.text('设计'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.text('采用当前版本开始新编辑'), findsNothing);
  });

  testWidgets('recovery source preserves review and adoption controls', (
    tester,
  ) async {
    final note = HtmlNote(
      metadata: const HtmlNoteMetadata(
        id: 9,
        memberId: 4,
        collection: 'blog',
        title: '核对中的记录',
        version: 2,
        modifiedAt: 1735689600,
        protected: true,
      ),
      source: fixture,
      labels: const ['恢复'],
    );
    final record = HtmlRecoveryRecord.capture(
      note,
      HtmlNoteEdit(
        title: note.metadata.title,
        source: fixture,
        labels: note.labels,
      ),
      pending: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HtmlRecoveryReviewPage(
          note: note,
          record: record,
          sourceSurfaceBuilder: fakeSource,
        ),
      ),
    );
    await tester.tap(find.text('源码'));
    await tester.pump();
    expect(find.textContaining('fake-html-source:'), findsOneWidget);
    expect(find.text('采用当前版本开始新编辑'), findsOneWidget);
    await tester.tap(find.text('采用当前版本开始新编辑'));
    await tester.pumpAndSettle();
    expect(find.text('采用当前版本？'), findsOneWidget);
    await tester.tap(find.text('继续核对'));
    await tester.pumpAndSettle();
    expect(find.text('采用当前版本开始新编辑'), findsOneWidget);
  });
}
