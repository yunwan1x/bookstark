import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:bookstark_flutter/features/notes/owned_note_list_scope.dart';

class _Wire {
  final queries = <Map<String, String>>[], batches = <List<int>>[];
  final pinned = <int>{};
  int mutations = 0;
  late final client = BookstarkClient(
    'https://owned.test/prefix',
    transport: MockClient((request) async {
      Map<String, Object?> row(int id, String collection) => {
        'blog_id': id,
        'member_id': 7,
        'blog_type': collection,
        'blog_title': 'N$id',
        'editor_type': 'markdown',
        'visibility': 0,
        'is_pinned': pinned.contains(id) ? 1 : 0,
        'has_password': false,
        'content_preview': 'Actual bounded preview',
        'labels': <String>[],
        'modify_time': '2026-11-11T10:00:00Z',
      };
      http.Response reply(Map<String, Object?> body, {int status = 200}) =>
          http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            status,
            headers: {'content-type': 'application/json'},
          );
      if (request.method == 'GET' && request.url.path == '/prefix/api/blogs') {
        final q = request.url.queryParameters;
        queries.add(Map.of(q));
        expect(q['metadata_only'], '1');
        final page = int.parse(q['page']!);
        return reply({
          'code': 0,
          'data': [
            for (final id in page == 1 ? [1, 2] : [3]) row(id, q['type']!),
          ],
          'page': page,
          'page_size': 20,
          'total': 3,
          'total_pages': 2,
        });
      }
      if (request.method == 'POST' &&
          request.url.path == '/prefix/api/blogs/batch-pin') {
        mutations++;
        final ids = List<int>.from(
          (jsonDecode(request.body) as Map)['ids'] as List,
        );
        batches.add(ids);
        pinned.add(1);
        return reply({
          'code': 0,
          'data': {'affected': 1},
        });
      }
      final match = RegExp(
        r'^/prefix/api/blogs/(\d+)$',
      ).firstMatch(request.url.path);
      if (request.method == 'GET' && match != null) {
        final id = int.parse(match.group(1)!);
        if (id == 3 && batches.isNotEmpty) {
          return reply({'code': 503, 'data': null}, status: 503);
        }
        return reply({'code': 0, 'data': row(id, 'note')});
      }
      fail('Unexpected list HTTP: ${request.method} ${request.url.path}');
    }),
  );
  _Wire() {
    client.restoreSession({
      'token': 'fixture-only',
      'csrf_token': 'fixture-csrf',
    });
  }
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  // A lazy ListView unmounts the header after opening a lower row. Search up
  // first, then down; only dragging down cannot find a virtualized top action.
  for (final direction in [150.0, -150.0]) {
    for (var i = 0; i < 30; i++) {
      if (finder.evaluate().isNotEmpty) {
        await tester.ensureVisible(finder);
        await tester.pumpAndSettle();
        final y = tester.getCenter(finder).dy;
        if (y >= 0 &&
            y <
                tester.view.physicalSize.height /
                    tester.view.devicePixelRatio) {
          await tester.tap(finder);
          await tester.pumpAndSettle();
          return;
        }
      }
      final sheet = find.byKey(const Key('note-filter-scroll'));
      final container = sheet.evaluate().isNotEmpty
          ? sheet
          : find.byType(ListView).first;
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: container, matching: find.byType(Scrollable)).first,
      );
      if (direction > 0 &&
          scroll.position.pixels <= scroll.position.minScrollExtent + 1) {
        break;
      }
      if (direction < 0 &&
          scroll.position.pixels >= scroll.position.maxScrollExtent - 1) {
        break;
      }
      await tester.drag(container, Offset(0, direction));
      await tester.pumpAndSettle();
    }
  }
  fail('Real list action was not reachable');
}

Future<void> _showTop(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    final list = find.byType(ListView).first;
    final scroll = tester.state<ScrollableState>(
      find.descendant(of: list, matching: find.byType(Scrollable)).first,
    );
    final remaining = scroll.position.pixels - scroll.position.minScrollExtent;
    if (remaining <= 1) return;
    await tester.drag(list, Offset(0, remaining < 180 ? remaining : 180));
    await tester.pumpAndSettle();
  }
}

Widget _page(
  _Wire wire, {
  required bool english,
  required NoteCollection collection,
  required int generation,
  required bool Function() current,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(
      textScaler: TextScaler.linear(2),
      viewInsets: const EdgeInsets.only(bottom: 180),
    ),
    child: child!,
  ),
  home: OwnedNoteListScope(
    identity: (generation, collection),
    isCurrent: current,
    create: (owner) => OwnedNoteListBinding.remote(
      client: wire.client,
      memberId: 7,
      collection: collection,
      scope: 'production-$generation-${collection.name}',
      isCurrent: owner,
    ),
    builder: (context, binding) => NotesPage(
      repository: binding.repository,
      listSource: binding.source,
      pinActions: binding.actions,
      collection: collection,
      english: english,
      isCurrentScope: current,
    ),
  ),
);
void main() {
  for (final english in [false, true]) {
    testWidgets(
      'production filter keep/apply and stable rebuild 320 font2 $english',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final wire = _Wire();
        addTearDown(wire.client.close);
        Widget page() => _page(
          wire,
          english: english,
          collection: NoteCollection.note,
          generation: 1,
          current: () => true,
        );
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        await _tap(tester, find.text(english ? 'Select' : '选择'));
        await _tap(tester, find.text('N1'));
        await tester.pumpWidget(page());
        await tester.pumpAndSettle();
        expect(
          wire.queries.length,
          1,
        ); // Rebuild must not replace production source.
        await _showTop(tester);
        expect(find.text(english ? '1 selected' : '已选 1 项'), findsOneWidget);
        Future<void> stage() async {
          await _tap(tester, find.text(english ? 'Filters · 0' : '筛选 · 0'));
          await tester.enterText(
            find.byKey(const Key('note-filter-label')),
            'exact-label',
          );
          await _tap(tester, find.text(english ? 'Apply filters' : '应用筛选'));
        }

        await stage();
        await _tap(tester, find.text(english ? 'Keep selection' : '返回并保留'));
        expect(wire.queries.length, 1);
        await _showTop(tester);
        expect(find.text(english ? '1 selected' : '已选 1 项'), findsOneWidget);
        await stage();
        await _tap(
          tester,
          find.text(english ? 'Apply and clear selection' : '应用并清除选择'),
        );
        expect(wire.queries.length, 2);
        expect(wire.queries.last['label'], 'exact-label');
        expect(wire.queries.last['type'], 'note');
        expect(wire.mutations, 0);
        expect(find.text(english ? '1 selected' : '已选 1 项'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'production batch explicit pages retains unknown offscreen ID and collection switch retires selection',
    (tester) async {
      final wire = _Wire();
      addTearDown(wire.client.close);
      await tester.pumpWidget(
        _page(
          wire,
          english: true,
          collection: NoteCollection.note,
          generation: 1,
          current: () => true,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Select'));
      await _tap(tester, find.text('N1'));
      await _tap(tester, find.text('Load more'));
      await _tap(tester, find.text('N3'));
      await _tap(tester, find.text('Pin selected'));
      await _tap(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Pin selected'),
        ),
      );
      expect(wire.batches, [
        [1, 3],
      ]);
      expect(wire.mutations, 1);
      await _showTop(tester);
      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('1 on other pages'), findsOneWidget);
      expect(find.text('N3'), findsNothing);
      await tester.pumpWidget(
        _page(
          wire,
          english: true,
          collection: NoteCollection.article,
          generation: 2,
          current: () => true,
        ),
      );
      await tester.pumpAndSettle();
      expect(wire.queries.last['type'], 'article');
      expect(find.text('1 selected'), findsNothing);
      await _tap(tester, find.text('Select'));
      expect(find.text('Pin selected'), findsNothing);
      expect(wire.mutations, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'old filter confirmation cannot query a replacement account or preserve old selection',
    (tester) async {
      final old = _Wire(), next = _Wire();
      addTearDown(old.client.close);
      addTearDown(next.client.close);
      await tester.pumpWidget(
        _page(
          old,
          english: true,
          collection: NoteCollection.note,
          generation: 1,
          current: () => true,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Select'));
      await _tap(tester, find.text('N1'));
      await _tap(tester, find.text('Filters · 0'));
      await tester.enterText(
        find.byKey(const Key('note-filter-label')),
        'old-owner-label',
      );
      await _tap(tester, find.text('Apply filters'));
      expect(find.text('Change filters and clear selection?'), findsOneWidget);
      await tester.pumpWidget(
        _page(
          next,
          english: true,
          collection: NoteCollection.note,
          generation: 2,
          current: () => true,
        ),
      );
      await tester.pumpAndSettle();
      await _tap(tester, find.text('Apply and clear selection'));
      expect(old.queries.length, 1);
      expect(next.queries.length, 1);
      expect(next.queries.single.containsKey('label'), false);
      expect(old.mutations, 0);
      expect(next.mutations, 0);
      expect(find.text('1 selected'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
