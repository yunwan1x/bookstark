import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class Repository implements NotesRepository {
  Completer<int>? pending;
  @override
  Future<int> save(Note note) async => pending == null ? 7 : pending!.future;
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<Note> read(int id) async => throw UnimplementedError();
  @override
  Future<void> remove(int id) async {}
}

void main() {
  late Map<String, String> storage;
  late DraftVault vault;
  setUp(() {
    storage = {};
    vault = DraftVault(
      namespace: 'test',
      readValue: (key) async => storage[key],
      writeValue: (key, value) async {
        storage[key] = value;
      },
      deleteValue: (key) async {
        storage.remove(key);
      },
    );
  });
  const saved = Note(id: 7, title: '原题', content: '已保存内容');
  Future<void> mount(
    WidgetTester tester, {
    Note note = saved,
    Repository? repository,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorPage(
          repository: repository ?? Repository(),
          note: note,
          drafts: vault,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keep draft leaves the route and restores on reopening', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => NoteEditorPage(
                    repository: Repository(),
                    note: saved,
                    drafts: vault,
                  ),
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '离开后恢复');
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保留草稿并返回'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorPage), findsNothing);
    expect((await vault.read(7))!.content, '离开后恢复');
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复草稿'));
    await tester.pumpAndSettle();
    expect(find.text('离开后恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'draft recovery requires a choice and restores text and dirty state',
    (tester) async {
      await vault.write(saved.copyWith(content: '尚未提交的草稿'));
      await mount(tester);
      expect(find.text('发现未保存草稿'), findsOneWidget);
      await tester.tap(find.text('恢复草稿'));
      await tester.pumpAndSettle();
      expect(find.text('尚未提交的草稿'), findsOneWidget);
      expect(find.text('未保存'), findsOneWidget);
      expect(find.text('草稿已保留 · 尚未提交'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'discarding recovered draft leaves saved content and removes draft',
    (tester) async {
      await vault.write(saved.copyWith(content: '旧草稿'));
      await mount(tester);
      await tester.tap(find.text('使用已保存内容'));
      await tester.pumpAndSettle();
      expect(find.text('已保存内容'), findsOneWidget);
      expect(await vault.read(7), isNull);
    },
  );
  testWidgets(
    'typing is retained after debounce and later edits during save stay as draft',
    (tester) async {
      final repository = Repository()..pending = Completer<int>();
      await mount(tester, repository: repository);
      await tester.enterText(find.byType(TextField).last, '提交内容');
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect((await vault.read(7))!.content, '提交内容');
      await tester.tap(find.text('保存'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).last, '保存期间继续输入');
      repository.pending!.complete(7);
      await tester.pumpAndSettle();
      expect(find.text('未保存'), findsOneWidget);
      expect((await vault.read(7))!.content, '保存期间继续输入');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('protected editor never reads or writes disk drafts', (
    tester,
  ) async {
    var accesses = 0;
    vault = DraftVault(
      namespace: 'secret',
      readValue: (key) async {
        accesses++;
        return null;
      },
      writeValue: (key, value) async {
        accesses++;
      },
      deleteValue: (key) async {
        accesses++;
      },
    );
    await mount(
      tester,
      note: const Note(
        id: 7,
        title: 'private',
        content: 'secret',
        isProtected: true,
        unlockPassword: 'ephemeral',
      ),
    );
    await tester.enterText(find.byType(TextField).last, 'private update');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('保留草稿并返回'), findsNothing);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(accesses, 0);
  });
  testWidgets('draft storage failure is visible and never marked retained', (
    tester,
  ) async {
    vault = DraftVault(
      namespace: 'broken',
      readValue: (key) async => null,
      writeValue: (key, value) async => throw StateError('storage unavailable'),
      deleteValue: (key) async {},
    );
    await mount(tester);
    await tester.enterText(find.byType(TextField).last, 'keep this text');
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.textContaining('草稿未保留'), findsOneWidget);
    expect(find.text('草稿已保留 · 尚未提交'), findsNothing);
    expect(find.text('keep this text'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
