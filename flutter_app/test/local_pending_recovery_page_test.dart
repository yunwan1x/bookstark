import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/features/local_backup/local_pending_recovery_page.dart';

const reference = LocalRecoveryReference(
  store: 'secure',
  kind: 'article-archive',
  key: 'owned-test-key',
  namespace: 'owned-test-namespace',
  recordId: 17,
);
LocalRecoverySummary summary({bool active = false}) => LocalRecoverySummary(
  references: active ? [reference] : [],
  complexKeys: [],
  unknown: 0,
  activeTransfers: 0,
  overflow: false,
  archivedArticles: [
    const LocalArchivedArticleDraft(
      reference,
      LocalArticleDraftDisposition.skipped,
    ),
  ],
);
void main() {
  testWidgets(
    'archived old drafts have an explicit review action without a false pending warning',
    (tester) async {
      var opened = 0, loaded = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalPendingRecoveryPage(
            english: true,
            load: () async {
              loaded++;
              return LocalPendingRecoveryView(summary(), [
                LocalPendingRecoveryItem(
                  title: 'Old reading plan',
                  detail: 'Restore was deferred',
                  archived: true,
                  reference: reference,
                  actionLabel: 'View old draft',
                  open: () async {
                    opened++;
                  },
                ),
              ]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No pending local drafts found.'), findsOneWidget);
      expect(find.text('Handled old article drafts'), findsOneWidget);
      expect(
        find.text(
          'Original drafts stay on this device and are excluded from backups.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Unsaved records are retained. Resolve them first.'),
        findsNothing,
      );
      await tester.tap(find.text('View old draft'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(loaded, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('real pending records remain separate from archived entries', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalPendingRecoveryPage(
          english: true,
          load: () async => LocalPendingRecoveryView(summary(active: true), [
            const LocalPendingRecoveryItem(
              title: 'Pending body',
              detail: 'Not saved',
              reference: reference,
            ),
            const LocalPendingRecoveryItem(
              title: 'Handled body',
              detail: 'Restore deferred',
              reference: reference,
              archived: true,
            ),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Pending'), findsOneWidget);
    expect(
      find.text('Unsaved records are retained. Resolve them first.'),
      findsOneWidget,
    );
    expect(find.text('Handled old article drafts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '320dp at 200 percent keeps old-draft review reachable without overflow',
    (tester) async {
      var opened = 0;
      tester.view.physicalSize = const Size(640, 1280);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: LocalPendingRecoveryPage(
            english: true,
            load: () async => LocalPendingRecoveryView(summary(), [
              LocalPendingRecoveryItem(
                title:
                    'A long handled article title with retained original content',
                detail:
                    'Restore was deferred and the original remains available',
                reference: reference,
                archived: true,
                actionLabel: 'View old draft',
                open: () async {
                  opened++;
                },
              ),
            ]),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('View old draft'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('View old draft'));
      await tester.pumpAndSettle();
      expect(find.text('View old draft').hitTestable(), findsOneWidget);
      await tester.tap(find.text('View old draft'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
