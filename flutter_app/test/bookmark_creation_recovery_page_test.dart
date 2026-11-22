import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/bookmark_creation_attempt.dart';
import 'package:bookstark_flutter/core/bookmark_creation_controller.dart';
import 'package:bookstark_flutter/core/bookmark_creation_store.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmark_creation_recovery_page.dart';

void main() {
  testWidgets(
    'EN320 large recovery exposes full input and explicit end without submit',
    (tester) async {
      final values = <String, String>{};
      final scope = 'a' * 64, key = 'c' * 32;
      var prepares = 0;
      final store = BookmarkCreationStore(
        scope: scope,
        key: key,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final pending = BookmarkCreationAttempt(
        scope: scope,
        key: key,
        body: {
          'title': 'Exact title',
          'url': 'https://example.test/',
          'description': '\ufeffComplete description\r\n😀',
          'favicon': '',
          'is_public': false,
          'labels': ['comma,label', ' spaced ', ''],
        },
      );
      final initializing = Object();
      store.acquire(initializing);
      await store.insert(pending, initializing);
      await store.claim(pending, initializing);
      store.release(initializing);
      final controller = BookmarkCreationController(
        store: store,
        prepare: (_) async {
          prepares++;
          throw StateError('not allowed');
        },
        inspect: (_, id) async => BookmarkCreationReview(
          id: id,
          fingerprint: 'exact',
          display:
              'Actual complete source\nis_pinned: true\nnav_visible: true\norder_sort: 7',
          matchesFrozenInput: true,
          wire: const {},
        ),
      );
      await controller.reload();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 640),
                textScaler: TextScaler.linear(2),
                viewInsets: EdgeInsets.only(bottom: 180),
              ),
              child: BookmarkCreationRecoveryPage(
                controller: controller,
                english: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Unknown result. Creation will not be replayed.'),
          findsOneWidget,
        );
        final scrolling = find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first;
        final exactFrozen = find.byWidgetPredicate(
          (widget) =>
              widget is SelectableText &&
              widget.data == pending.body.toString(),
        );
        await tester.scrollUntilVisible(
          exactFrozen,
          160,
          scrollable: scrolling,
        );
        expect(exactFrozen, findsOneWidget);
        expect(
          tester.widget<SelectableText>(exactFrozen).data,
          pending.body.toString(),
        );
        expect(
          tester.widget<SelectableText>(exactFrozen).data,
          contains(pending.body['description'] as String),
        );
        Future<void> tapReachableEnd() async {
          final button = find.ancestor(
            of: find.text('End recovery record'),
            matching: find.byType(OutlinedButton),
          );
          await tester.scrollUntilVisible(button, 120, scrollable: scrolling);
          // scrollUntilVisible may expose only the leading edge. At 200% with
          // a keyboard inset the text/button centre can still be below y460.
          // Keep real user drags until the actual parent button is hittable.
          for (
            var attempt = 0;
            attempt < 8 && button.hitTestable().evaluate().isEmpty;
            attempt++
          ) {
            await tester.drag(scrolling, const Offset(0, -80));
            await tester.pumpAndSettle();
          }
          expect(button.hitTestable(), findsOneWidget);
          await tester.tap(button.hitTestable());
          await tester.pumpAndSettle();
        }

        await tapReachableEnd();
        expect(
          find.textContaining('does not mean the server did not create'),
          findsOneWidget,
        );
        await tester.tap(find.text('Keep record'));
        await tester.pumpAndSettle();
        expect(values, isNotEmpty);
        expect(prepares, 0);
        await tapReachableEnd();
        await tester.tap(find.text('End record'));
        await tester.pumpAndSettle();
        expect(values, isEmpty);
        expect(controller.endedDurably, isTrue);
        expect(prepares, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
  testWidgets('dialog captured for A never ends replacement B record', (
    tester,
  ) async {
    final values = <String, String>{};
    Future<BookmarkCreationController> make(String letter) async {
      final store = BookmarkCreationStore(
        scope: letter * 64,
        key: letter * 32,
        read: (k) async => values[k],
        write: (k, v) async {
          values[k] = v;
        },
        remove: (k) async {
          values.remove(k);
        },
        flush: () async {},
        isCurrent: () => true,
      );
      final c = BookmarkCreationController(
        store: store,
        prepare: (_) async {
          throw StateError('no send');
        },
        inspect: (_, _) async {
          throw StateError('no read');
        },
      );
      await c.begin(
        BookmarkCreationAttempt(
          scope: letter * 64,
          key: letter * 32,
          body: {
            'title': 'Exact',
            'url': 'https://example.test/',
            'description': '',
            'favicon': '',
            'is_public': false,
            'labels': <String>[],
          },
        ),
      );
      return c;
    }

    final a = await make('d'), b = await make('e');
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: BookmarkCreationRecoveryPage(controller: a, english: true),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('End recovery record'),
        180,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('End recovery record'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: BookmarkCreationRecoveryPage(controller: b, english: true),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('End record'));
      await tester.pumpAndSettle();
      expect(values.length, 2);
      expect(a.endedDurably, isFalse);
      expect(b.endedDurably, isFalse);
      await b.reload();
      await tester.pump();
      expect(b.record, isNotNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      a.dispose();
      b.dispose();
    }
  });
}
