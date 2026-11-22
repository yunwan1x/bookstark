import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_controller.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';
import 'package:bookstark_flutter/core/remote_markdown_editor_bridge.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_editor_page.dart';
import 'package:bookstark_flutter/features/notes/remote_markdown_creation_review_page.dart';
import 'remote_markdown_creation_controller_next_test.dart' as fixture;

class ExistingRepository extends NotesRepository {
  ExistingRepository(this.f);
  final fixture.Fixture f;
  int saves = 0;
  @override
  Future<Note> read(int id) async => Note(
    id: id,
    title: f.transport.current.input.title,
    content: f.transport.current.input.content,
    labels: f.transport.current.input.labels,
  );
  @override
  Future<int> save(Note note) async {
    saves++;
    if (note.id == null) throw StateError('Legacy create forbidden');
    return note.id!;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<void> remove(int id) async => throw StateError('No deletion');
}

Widget page(
  fixture.Fixture f,
  RemoteMarkdownCreationController c,
  ExistingRepository repo,
) => MaterialApp(
  home: RemoteMarkdownCreationEditorPage(
    controller: c,
    repository: repo,
    isCurrent: () => f.current,
    english: true,
  ),
);
Future<void> edit(WidgetTester tester, String title, String content) async {
  await tester.enterText(find.byType(TextField).at(0), title);
  await tester.enterText(find.byType(TextField).at(1), content);
}

void observed(fixture.Fixture f, MarkdownCreationInput input) {
  f.transport.current = MarkdownCreationObserved(
    scope: f.scope,
    id: 318,
    version: 1,
    modifiedAt: 101,
    input: input,
    editorType: 'markdown',
    isProtected: false,
  );
}

void main() {
  testWidgets(
    'real Use saved content then edit and Save uses one guarded POST',
    (tester) async {
      final f = fixture.Fixture();
      final c = await f.open();
      addTearDown(c.retire);
      final repo = ExistingRepository(f);
      await tester.pumpWidget(page(f, c, repo));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use saved content'));
      await tester.pumpAndSettle();
      final input = MarkdownCreationInput(
        title: 'New title',
        content: 'New body',
        labels: [],
      );
      observed(f, input);
      await edit(tester, input.title, input.content);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(f.transport.posts, 1);
      expect(repo.saves, 0);
      expect(c.phase, MarkdownCreationPhase.finished);
      expect(await f.vault.read(), isNull);
      expect(find.text('Saved'), findsOneWidget);
    },
  );
  testWidgets('real Discard wins over the queued 600ms autosave and dispose', (
    tester,
  ) async {
    final f = fixture.Fixture();
    final c = await f.open();
    addTearDown(c.retire);
    final repo = ExistingRepository(f);
    await tester.pumpWidget(page(f, c, repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore draft'));
    await tester.pumpAndSettle();
    await edit(tester, 'Discard me', 'Body');
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 700));
    expect(await f.vault.read(), isNull);
    expect(f.transport.posts, 0);
    expect(c.record.input.title, isEmpty);
  });
  testWidgets(
    'unknown transition real old editor dispose cannot replace pending record',
    (tester) async {
      final f = fixture.Fixture()..transport.drop = true;
      final c = await f.open();
      addTearDown(c.retire);
      await tester.pumpWidget(page(f, c, ExistingRepository(f)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore draft'));
      await tester.pumpAndSettle();
      await edit(tester, 'Unknown title', 'Exact body');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(RemoteMarkdownCreationReviewPage), findsOneWidget);
      final pending = (await f.vault.read())!;
      expect(pending.pending, isTrue);
      expect(pending.input.content, 'Exact body');
      await tester.pump(const Duration(milliseconds: 700));
      expect((await f.vault.read())!.fingerprint, pending.fingerprint);
      expect(f.transport.posts, 1);
    },
  );
  testWidgets(
    'known ID cleanup failure stays review and cleanup sends no POST',
    (tester) async {
      final f = fixture.Fixture()..deleteFails = true;
      final c = await f.open();
      addTearDown(c.retire);
      await tester.pumpWidget(page(f, c, ExistingRepository(f)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.phase, MarkdownCreationPhase.cleanup);
      expect(f.transport.posts, 1);
      expect((await f.vault.read())!.knownId, 318);
      f.deleteFails = false;
      await tester.ensureVisible(find.text('Retry cleanup only'));
      await tester.tap(find.text('Retry cleanup only'));
      await tester.pumpAndSettle();
      expect(f.transport.posts, 1);
      expect(await f.vault.read(), isNull);
    },
  );
  testWidgets(
    'scope retirement before actual editor timer prevents late persistence',
    (tester) async {
      final f = fixture.Fixture();
      final c = await f.open();
      addTearDown(c.retire);
      await tester.pumpWidget(page(f, c, ExistingRepository(f)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore draft'));
      await tester.pumpAndSettle();
      await edit(tester, 'Old scope', 'Never sent');
      f.current = false;
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 700));
      expect(f.transport.posts, 0);
      expect(await f.vault.read(), isNull);
    },
  );
  test('retired bridge late ack/remove cannot clear unknown record', () async {
    final f = fixture.Fixture()..transport.drop = true;
    final c = await f.open();
    addTearDown(c.retire);
    final bridge = RemoteMarkdownEditorBridge(
      controller: c,
      underlying: ExistingRepository(f),
      isCurrent: () => f.current,
      onReview: () {},
    );
    await expectLater(
      bridge.save(
        Note(title: 'Trip', content: f.input.content, labels: ['travel']),
      ),
      throwsStateError,
    );
    final before = (await f.vault.read())!.fingerprint;
    await bridge.drafts.remove(null);
    await bridge.drafts.write(const Note(title: 'Late', content: 'Late'));
    expect((await f.vault.read())!.fingerprint, before);
    await expectLater(c.discardEditing(), throwsStateError);
  });
  test(
    'discard makes a fresh attempt and pending writers do not revive old key',
    () async {
      final f = fixture.Fixture();
      final c = await f.open();
      addTearDown(c.retire);
      final bridge = RemoteMarkdownEditorBridge(
        controller: c,
        underlying: ExistingRepository(f),
        isCurrent: () => f.current,
        onReview: () {},
      );
      await bridge.drafts.write(const Note(title: 'Before', content: 'Body'));
      final oldKey = c.record.key;
      final discard = bridge.drafts.remove(null);
      final stale = bridge.drafts.write(
        const Note(title: 'Stale', content: 'Body'),
      );
      await Future.wait([discard, stale]);
      expect(await f.vault.read(), isNull);
      expect(c.record.key, isNot(oldKey));
      await bridge.drafts.write(const Note(title: 'Fresh', content: 'Body'));
      expect((await f.vault.read())!.input.title, 'Fresh');
    },
  );
}
