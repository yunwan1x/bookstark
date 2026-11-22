import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/note_list_query.dart';
import 'package:bookstark_flutter/core/note_list_source.dart';
import 'package:bookstark_flutter/core/note_pin_actions.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class _Repo extends Fake implements NotesRepository {
  final removed = <int>[];
  Completer<void>? gate;
  @override
  Future<void> remove(int id) async {
    removed.add(id);
    await gate?.future;
  }

  @override
  Future<Note> read(int id) async =>
      throw StateError('List must use typed opener');
}

class _Source extends Fake implements NoteListSource {
  final queries = <NoteListQuery>[];
  @override
  NoteListCapabilities get capabilities => NoteListCapabilities.server;
  @override
  Future<NoteListPage> list(NoteListQuery query, {int page = 1}) async {
    queries.add(query);
    return NoteListPage(
      page: page,
      hasMore: page == 1,
      total: 3,
      totalPages: 2,
      items: [
        for (final id in page == 1 ? [1, 2] : [3])
          FilteredNoteListEntry(
            id: id,
            title: 'N$id',
            contentPreview: 'Snippet',
            pinned: false,
            visibility: NoteVisibilityFilter.private,
            editorType: 'mindmap',
          ),
      ],
    );
  }
}

class _Pins extends Fake implements NotePinActions {
  final singles = <int>[], batches = <Set<int>>[];
  @override
  String get scope => 'fixture-note-owner';
  @override
  int get maxBatchIds => 500;
  @override
  void retire() {}
  @override
  Future<NotePinActionResult> setPinned(int id, bool desired) async {
    singles.add(id);
    return NotePinActionResult(
      id: id,
      property: NoteActionProperty.pin,
      desired: desired,
      mutationAttempted: true,
      issue: NoteActionIssue.unknown,
    );
  }

  @override
  Future<NoteBatchPinResult> pinSelected(Iterable<int> ids) async {
    final requested = Set<int>.of(ids);
    batches.add(requested);
    return NoteBatchPinResult(
      scope: scope,
      requestedIds: requested,
      verifiedIds: requested.contains(1) ? {1} : {},
      issues: {
        for (final id in requested.where((id) => id != 1))
          id: NoteActionIssue.unknown,
      },
      mutationAttempted: true,
    );
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      160,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  _Repo repo,
  _Source source, {
  _Pins? pins,
  Future<void> Function(int)? open,
  bool small = false,
}) async {
  tester.view.physicalSize = small
      ? const Size(320, 568)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(small ? 2 : 1),
          viewInsets: small
              ? const EdgeInsets.only(bottom: 180)
              : EdgeInsets.zero,
        ),
        child: child!,
      ),
      home: NotesPage(
        repository: repo,
        listSource: source,
        pinActions: pins,
        onOpenExisting: open,
        english: small,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'typed open passes real ID through central callback without repository body read',
    (tester) async {
      final opened = <int>[];
      await _mount(
        tester,
        _Repo(),
        _Source(),
        open: (id) async {
          opened.add(id);
        },
      );
      await _tap(tester, find.text('N1'));
      expect(opened, [1]);
    },
  );
  testWidgets(
    'filter cancellation keeps selected IDs and original query; apply confirms clearing',
    (tester) async {
      final source = _Source();
      await _mount(tester, _Repo(), source);
      await _tap(tester, find.text('选择'));
      await _tap(tester, find.text('N1'));
      await _tap(tester, find.text('筛选 · 0'));
      await tester.enterText(
        find.byKey(const Key('note-filter-label')),
        'new label',
      );
      await _tap(tester, find.text('应用筛选'));
      expect(find.text('更改筛选并清除选择？'), findsOneWidget);
      await _tap(tester, find.text('返回并保留'));
      expect(source.queries.length, 1);
      expect(find.text('已选 1 项'), findsOneWidget);
      await _tap(tester, find.text('筛选 · 0'));
      await tester.enterText(
        find.byKey(const Key('note-filter-label')),
        'new label',
      );
      await _tap(tester, find.text('应用筛选'));
      await _tap(tester, find.text('应用并清除选择'));
      expect(source.queries.last.label, 'new label');
      expect(find.text('已选 1 项'), findsNothing);
      expect(find.text('筛选 · 1'), findsOneWidget);
    },
  );
  testWidgets(
    'batch pin snapshots only selected IDs and retains failed offscreen selection',
    (tester) async {
      final source = _Source(), pins = _Pins();
      await _mount(tester, _Repo(), source, pins: pins);
      await _tap(tester, find.text('选择'));
      await _tap(tester, find.text('N1'));
      await _tap(tester, find.text('加载更多'));
      await _tap(tester, find.text('N3'));
      await _tap(tester, find.text('置顶所选'));
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '置顶所选'),
      );
      await _tap(tester, confirm);
      expect(pins.batches.single, {1, 3});
      expect(find.text('已选 1 项'), findsOneWidget);
      expect(find.text('含其他页 1 项'), findsOneWidget);
      expect(find.text('N3'), findsNothing);
    },
  );
  testWidgets(
    'unknown single pin is never automatically retried or optimistically set',
    (tester) async {
      final pins = _Pins();
      await _mount(tester, _Repo(), _Source(), pins: pins);
      await _tap(tester, find.byTooltip('笔记操作').first);
      await _tap(tester, find.text('置顶'));
      expect(pins.singles, [1]);
      expect(find.text('结果尚未确认，请核对状态后重新操作。'), findsOneWidget);
      expect(find.text('已置顶'), findsNothing);
    },
  );
  testWidgets(
    'account replacement stops remaining captured DELETE IDs and never uses new repository',
    (tester) async {
      final before = _Repo()..gate = Completer<void>();
      await _mount(tester, before, _Source());
      await _tap(tester, find.text('选择'));
      await _tap(tester, find.text('全选已加载'));
      await _tap(tester, find.widgetWithText(OutlinedButton, '移到回收站'));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, '移到回收站'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(before.removed, [1]);
      final after = _Repo();
      await _mount(tester, after, _Source());
      before.gate!.complete();
      await tester.pumpAndSettle();
      expect(before.removed, [1]);
      expect(after.removed, isEmpty);
    },
  );
  testWidgets(
    'English320 large text keyboard filter and selection remain scrollable',
    (tester) async {
      await _mount(tester, _Repo(), _Source(), pins: _Pins(), small: true);
      expect(tester.takeException(), isNull);
      await _tap(tester, find.text('Filters · 0'));
      await _tap(tester, find.text('Apply filters'));
      await _tap(tester, find.text('Select'));
      await _tap(tester, find.text('N1'));
      expect(tester.takeException(), isNull);
    },
  );
}
