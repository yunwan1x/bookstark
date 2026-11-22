import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/note_unlock_dialog.dart';

void main() {
  testWidgets(
    'unlock prevents duplicate requests and retries after wrong password',
    (tester) async {
      var calls = 0;
      var pending = Completer<Note>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NoteUnlockDialog(
              onUnlock: (password) {
                calls++;
                expect(password, 'wrong');
                return pending.future;
              },
            ),
          ),
        ),
      );
      await tester.enterText(find.byKey(const Key('note-password')), 'wrong');
      await tester.tap(find.text('解锁'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(calls, 1);
      pending.completeError(StateError('incorrect'));
      await tester.pumpAndSettle();
      expect(find.textContaining('incorrect'), findsOneWidget);
      expect(find.text('wrong'), findsOneWidget);
      pending = Completer<Note>();
      await tester.tap(find.text('解锁'));
      await tester.pump();
      expect(calls, 2);
      pending.completeError(StateError('incorrect again'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'English unlock dialog scrolls on small screens at double text size',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: NoteUnlockDialog(
              english: true,
              onUnlock: (_) async => const Note(id: 1, title: '', content: ''),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Unlock'), findsOneWidget);
    },
  );
}
