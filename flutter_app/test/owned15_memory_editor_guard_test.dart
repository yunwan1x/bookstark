import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/owned15_editor_lifetime.dart';
import 'package:bookstark_flutter/core/owned15_save_journal.dart';
import 'package:bookstark_flutter/features/local_backup/owned15_memory_editor_guard.dart';

void main() {
  testWidgets(
    'background locks body before real repository/crypto drain and resume cannot reveal it',
    (tester) async {
      final repositoryDrain = Completer<void>(),
          cryptoDrain = Completer<void>();
      final journal = Owned15SaveJournal(
        draftNamespace: 'local-fixture-generation',
        collection: 'note',
        resourceId: 9,
        isCurrent: () => true,
        readValue: (_) async => null,
        writeValue: (_, _) async {},
        deleteValue: (_) async {},
        flush: () async {},
      );
      var closes = 0, retired = 0;
      final owner = Owned15EditorLifetime(
        journal: journal,
        isCurrentScope: () => true,
        drainCrypto: () => cryptoDrain.future,
        onDrained: (_) {
          retired++;
        },
      );
      owner.bindRepository(
        close: () {
          closes++;
        },
        drain: () => repositoryDrain.future,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Owned15MemoryEditorGuard(
              owner: owner,
              english: true,
              child: const Scaffold(body: Text('runtime unsaved fixture')),
            ),
          ),
        );
        expect(find.text('runtime unsaved fixture'), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        expect(find.text('runtime unsaved fixture'), findsNothing);
        expect(
          find.textContaining('Unsaved changes are no longer available'),
          findsOneWidget,
        );
        expect(owner.current, isFalse);
        expect(closes, 1);
        expect(retired, 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(find.text('runtime unsaved fixture'), findsNothing);
        repositoryDrain.complete();
        await tester.pump();
        expect(retired, 0);
        cryptoDrain.complete();
        await owner.retire();
        expect(retired, 1);
      } finally {
        if (!repositoryDrain.isCompleted) repositoryDrain.complete();
        if (!cryptoDrain.isCompleted) cryptoDrain.complete();
        await owner.retire();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
