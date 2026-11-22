import 'package:bookstark_flutter/core/label_creation_resolution.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/features/labels/label_editor_page.dart';
import '../tool/fixtures/label_management.dart';

LabelCreationResolution result(
  String name, {
  LabelCreationOrigin origin = LabelCreationOrigin.manualExisting,
}) => LabelCreationResolution(
  origin: origin,
  wire: {
    'label_id': 42,
    'label_name': name,
    'book_count': 0,
    'blog_count': 0,
    'bookmark_count': 0,
    'document_count': 0,
  },
);
void main() {
  testWidgets(
    'durable create bypasses legacy same-name lookup and uses explicit recovery callback',
    (tester) async {
      var calls = 0, requests = 0;
      final client = BookstarkClient(
        'https://fixture.invalid',
        transport: MockClient((_) async {
          requests++;
          throw StateError('Legacy list/create endpoint must not be used');
        }),
      );
      final repo = RemoteLabelManagementRepository(
        client,
        canManage: false,
        createRecoverably: (name) async {
          calls++;
          if (calls == 1) throw StateError('synthetic retained unknown ledger');
          return result(name);
        },
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: LabelEditorPage(repository: repo, english: true)),
        );
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Exact name');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(requests, 0);
        expect(find.text('Verify creation result'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).enabled,
          isFalse,
        );
        await tester.tap(find.text('Verify creation result'));
        await tester.pumpAndSettle();
        expect(calls, 2);
        expect(requests, 0);
        expect(find.text('Edit label'), findsOneWidget);
        expect(
          find.text(
            'Existing global label adopted. This is not proof that this creation request succeeded.',
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            'The actual ID acknowledgement for this creation was received.',
          ),
          findsNothing,
        );
        // Callbacks represent actual coordinator entry; no test claims two HTTP POSTs.
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        client.close();
      }
    },
  );
  testWidgets('held A save cannot update replacement B editor or its vault', (
    tester,
  ) async {
    final entered = Completer<void>(),
        release = Completer<LabelCreationResolution>(),
        completed = Completer<void>();
    var activeA = true, deletedA = 0, deletedB = 0, requests = 0;
    final client = BookstarkClient(
      'https://fixture.invalid',
      transport: MockClient((_) async {
        requests++;
        throw StateError('No legacy request expected');
      }),
    );
    final repoA = RemoteLabelManagementRepository(
      client,
      canManage: true,
      isCurrent: () => activeA,
      createRecoverably: (name) async {
        entered.complete();
        try {
          return await release.future;
        } finally {
          completed.complete();
        }
      },
    );
    final repoB = LabelManagementFixture();
    DraftVault vault(String scope, void Function() deleted) => DraftVault(
      namespace: scope,
      readValue: (_) async => null,
      writeValue: (_, _) async {},
      deleteValue: (_) async {
        deleted();
      },
    );
    final vaultA = vault('label-owner-A', () {
          deletedA++;
        }),
        vaultB = vault('label-owner-B', () {
          deletedB++;
        });
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: LabelEditorPage(
            repository: repoA,
            vault: vaultA,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A exact');
      await tester.tap(find.text('Save'));
      // This callback and in-memory vault are in the widget fakeAsync zone.
      // Pump it rather than blocking runAsync on a fake-zone Completer.
      for (var i = 0; i < 20 && !entered.isCompleted; i++) {
        await tester.pump();
      }
      expect(
        entered.isCompleted,
        isTrue,
        reason: 'actual A recovery callback must be entered',
      );
      activeA = false;
      await tester.pumpWidget(
        MaterialApp(
          home: LabelEditorPage(
            repository: repoB,
            vault: vaultB,
            label: const ManagedLabel(id: 77, name: 'B exact'),
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      release.complete(result('A exact'));
      for (var i = 0; i < 20 && !completed.isCompleted; i++) {
        await tester.pump();
      }
      expect(
        completed.isCompleted,
        isTrue,
        reason: 'held A callback must finish before assertions',
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'B exact',
      );
      expect(deletedA, 0);
      expect(deletedB, 0);
      expect(repoB.saveCalls, 0);
      expect(requests, 0);
      expect(find.textContaining('Label owner changed'), findsNothing);
    } finally {
      if (!release.isCompleted) release.complete(result('A exact'));
      await tester.pumpWidget(const SizedBox.shrink());
      client.close();
    }
  });
  testWidgets('old restore dialog cannot discard replacement owner draft', (
    tester,
  ) async {
    final valuesA = <String, String>{}, valuesB = <String, String>{};
    var deleteA = 0, deleteB = 0;
    DraftVault vault(
      String name,
      Map<String, String> values,
      void Function() deleted,
    ) => DraftVault(
      namespace: name,
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        deleted();
        values.remove(k);
      },
    );
    final a = vault('restore-owner-A', valuesA, () {
          deleteA++;
        }),
        b = vault('restore-owner-B', valuesB, () {
          deleteB++;
        });
    await a.write(const Note(id: 1, title: 'A draft', content: ''));
    final repoA = LabelManagementFixture(), repoB = LabelManagementFixture();
    final beforeA = Map<String, String>.of(valuesA),
        beforeB = Map<String, String>.of(valuesB);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: LabelEditorPage(
            repository: repoA,
            vault: a,
            label: const ManagedLabel(id: 1, name: 'A baseline'),
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Label draft found'), findsOneWidget);
      await tester.pumpWidget(
        MaterialApp(
          home: LabelEditorPage(
            repository: repoB,
            vault: b,
            label: const ManagedLabel(id: 2, name: 'B baseline'),
            english: true,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Discard draft'));
      await tester.pumpAndSettle();
      expect(valuesA, beforeA);
      expect(valuesB, beforeB);
      expect(deleteA, 0);
      expect(deleteB, 0);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'B baseline',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
