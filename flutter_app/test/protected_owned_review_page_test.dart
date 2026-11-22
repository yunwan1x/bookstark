import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/protected_complex_lifetime.dart';
import 'package:bookstark_flutter/core/protected_owned_complex_journal.dart';
import 'package:bookstark_flutter/features/complex_editors/protected_owned_review_page.dart';

String hex(String value) => List.filled(64, value).join();
ComplexNote snapshot(String source, String fp) => ComplexNote(
  scope: hex('a'),
  id: 91,
  collection: 'owned-blog-recovery',
  title: 'Current source',
  labels: ['unchanged'],
  version: 0,
  document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
  resourceFingerprint: fp,
);

class Env {
  final values = <String, String>{};
  bool current = true;
  late final journal = ProtectedOwnedComplexJournal(
    scope: hex('a'),
    ownerTag: hex('b'),
    isCurrent: () => current,
    readValue: (k) async {
      return values[k];
    },
    writeValue: (k, v) async {
      values[k] = v;
    },
    deleteValue: (k) async {
      values.remove(k);
    },
    flush: () async {},
  );
  late final owner = ProtectedComplexLifetime(
    journal: journal,
    isCurrentScope: () => current,
    onDrained: (_) {},
  );
  Future<void> begin() => journal.claimUnknown(
    baselineFingerprint: hex('c'),
    inputDigest: hex('d'),
  );
}

Future<void> mountReview(
  WidgetTester tester,
  Widget page, {
  bool large = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: large
          ? (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 180),
              ),
              child: child!,
            )
          : null,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push<bool>(MaterialPageRoute<bool>(builder: (_) => page)),
            child: const Text('Open recovery'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open recovery'));

  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 3),
  );
}

Future<void> reveal(WidgetTester tester, Finder target) async {
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

void main() {
  testWidgets('return retains unknown marker and never sends or finishes', (
    tester,
  ) async {
    final e = Env();
    await e.begin();
    try {
      var finishes = 0;
      final actual = snapshot('# Current remote source', hex('e'));
      await mountReview(
        tester,
        ProtectedOwnedReviewPage(
          owner: e.owner,
          initial: actual,
          english: true,
          readFresh: () async => actual,
          finishReviewed: (_) async {
            finishes++;
          },
        ),
      );
      expect(
        find.textContaining('prior edited body was not retained'),
        findsOneWidget,
      );
      expect(find.textContaining('Current remote source'), findsWidgets);

      await tester.tap(find.byTooltip('Return and retain record'));

      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 3),
      );

      expect(finishes, 0);
      expect(e.values.length, 1);
      expect(find.text('Open recovery'), findsOneWidget);
      expect(find.byType(ProtectedOwnedReviewPage), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      // Lifetime Futures belong to the test body's fake-async zone. Drain them
      // before leaving that zone, including assertion failures; addTearDown's
      // later zone must not be asked to advance these queued microtasks.
      await e.owner.retire();
    }
  });
  testWidgets('fresh changed version blocks marker end until reviewed again', (
    tester,
  ) async {
    final e = Env();
    await e.begin();
    try {
      var finishes = 0;
      final first = snapshot('# Old server version', hex('e'));
      final fresh = snapshot('# Changed current version', hex('f'));
      await mountReview(
        tester,
        ProtectedOwnedReviewPage(
          owner: e.owner,
          initial: first,
          english: true,
          readFresh: () async => fresh,
          finishReviewed: (reviewed) async {
            finishes++;
            await e.journal.endReviewed(
              reviewedFingerprint: reviewed.resourceFingerprint!,
              fresh: () async => ProtectedComplexObservation(
                fingerprint: fresh.resourceFingerprint!,
                inputDigest: hex('d'),
              ),
            );
          },
        ),
      );
      final end = find.text('Reviewed current version; end this record');
      await reveal(tester, end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(finishes, 0);
      expect(e.values.length, 1);
      expect(find.textContaining('server version changed'), findsOneWidget);
      expect(find.textContaining('Changed current version'), findsWidgets);
      await reveal(tester, end);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(finishes, 1);
      expect(e.values, isEmpty);
      expect(find.text('Open recovery'), findsOneWidget);
      expect(find.byType(ProtectedOwnedReviewPage), findsNothing);
    } finally {
      // Lifetime Futures belong to the test body's fake-async zone. Drain them
      // before leaving that zone, including assertion failures; addTearDown's
      // later zone must not be asked to advance these queued microtasks.
      await e.owner.retire();
    }
  });
  testWidgets(
    'EN320 200 percent keyboard source/review action remains reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final e = Env();
      await e.begin();
      try {
        final actual = snapshot(
          '# Current source\r\n\nNo prior request proof.',
          hex('e'),
        );
        var reads = 0, finishes = 0;
        await mountReview(
          tester,
          ProtectedOwnedReviewPage(
            owner: e.owner,
            initial: actual,
            english: true,
            readFresh: () async {
              reads++;
              return actual;
            },
            finishReviewed: (_) async {
              finishes++;
            },
          ),
          large: true,
        );
        final read = find.text('Read current version again');
        await reveal(tester, read);
        await tester.tap(read);
        await tester.pumpAndSettle();
        expect(reads, 1);
        expect(finishes, 0);
        expect(e.values.length, 1);
        expect(tester.takeException(), isNull);
      } finally {
        // Lifetime Futures belong to the test body's fake-async zone. Drain them
        // before leaving that zone, including assertion failures; addTearDown's
        // later zone must not be asked to advance these queued microtasks.
        await e.owner.retire();
      }
    },
  );
}
