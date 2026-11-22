import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/note_list_query.dart';
import 'package:bookstark_flutter/features/notes/note_filter_sheet.dart';

void main() {
  Future<void> mount(
    WidgetTester tester, {
    required NoteListQuery initial,
    required void Function(NoteListQuery?) result,
    NoteListCapabilities capabilities = NoteListCapabilities.server,
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
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => result(
                await showNoteFilterSheet(
                  context,
                  initial: initial,
                  capabilities: capabilities,
                  english: small,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    // Exercise real sheet scrolling. ensureVisible alone can race the focused
    // field's delayed showOnScreen and leave the footer below the viewport.
    final scroll = find.byKey(const Key('note-filter-scroll'));
    for (var step = 0; step < 30; step++) {
      await tester.pumpAndSettle();
      final rect = tester.getRect(finder);
      final viewport = tester.getRect(scroll);
      if (rect.center.dy >= viewport.top &&
          rect.center.dy <= viewport.bottom &&
          rect.center.dy >= 0 &&
          rect.center.dy <
              tester.view.physicalSize.height / tester.view.devicePixelRatio) {
        await tester.tap(finder);
        await tester.pumpAndSettle();
        return;
      }
      await tester.drag(scroll, const Offset(0, -180));
    }
    fail('Filter action never became reachable by scrolling');
  }

  testWidgets('cancel keeps original immutable query after staged edits', (
    tester,
  ) async {
    const initial = NoteListQuery(label: 'original', hasCode: true);
    NoteListQuery? result;
    var completed = false;
    await mount(
      tester,
      initial: initial,
      result: (value) {
        result = value;
        completed = true;
      },
    );
    await tester.enterText(
      find.byKey(const Key('note-filter-label')),
      'edited',
    );
    await tap(tester, find.byTooltip('返回'));
    expect(completed, isTrue);
    expect(result, isNull);
    expect(initial.label, 'original');
    expect(initial.hasCode, isTrue);
  });
  testWidgets(
    'reset only stages defaults; apply keeps keyword and returns filters',
    (tester) async {
      const initial = NoteListQuery(
        keyword: 'keep keyword',
        label: 'tag',
        pin: NotePinFilter.pinned,
        visibility: NoteVisibilityFilter.public,
        hasCode: true,
      );
      NoteListQuery? result;
      await mount(
        tester,
        initial: initial,
        result: (value) {
          result = value;
        },
      );
      await tap(tester, find.text('重置'));
      expect(result, isNull);
      expect(initial.label, 'tag');
      await tap(tester, find.text('应用筛选'));
      expect(result, const NoteListQuery(keyword: 'keep keyword'));
    },
  );
  testWidgets('local sheet never advertises unsupported server conditions', (
    tester,
  ) async {
    await mount(
      tester,
      initial: const NoteListQuery(),
      result: (_) {},
      capabilities: NoteListCapabilities.local,
    );
    expect(find.byKey(const Key('note-filter-code')), findsNothing);
    expect(find.byKey(const Key('note-filter-date')), findsNothing);
    expect(find.byKey(const ValueKey('note-filter-pin-pinned')), findsNothing);
    expect(
      find.byKey(const ValueKey('note-filter-visibility-public')),
      findsNothing,
    );
  });
  testWidgets(
    '320dp 200 percent English keyboard can reset and apply without overflow',
    (tester) async {
      NoteListQuery? result;
      await mount(
        tester,
        initial: const NoteListQuery(label: 'tag', hasCode: true),
        small: true,
        result: (value) {
          result = value;
        },
      );
      expect(tester.takeException(), isNull);
      await tester.enterText(
        find.byKey(const Key('note-filter-label')),
        'new tag',
      );
      await tap(tester, find.text('Reset'));
      await tap(tester, find.text('Apply filters'));
      expect(result, const NoteListQuery());
      expect(tester.takeException(), isNull);
    },
  );
}
