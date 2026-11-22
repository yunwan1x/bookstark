import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/task_action_drafts.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_action_route.dart';

TaskEditorActionBindings binding(bool Function() current) =>
    TaskEditorActionBindings(
      scope: 'owned-test',
      memberId: 9,
      isCurrent: current,
      verifyExistingOwner: (_) async => true,
    );
void main() {
  testWidgets('one service per editor; dispose aborts and retires once', (
    tester,
  ) async {
    var creates = 0, retires = 0;
    late Future<void> stop;
    Future<TaskEditorOwnedActions> factory({
      required bool Function() isCurrent,
      required Future<void> abortTrigger,
    }) async {
      creates++;
      stop = abortTrigger;
      return TaskEditorOwnedActions(
        bindings: binding(isCurrent),
        retire: () {
          retires++;
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: ownedTaskEditorRoute(
          factory: factory,
          builder: (actions) =>
              Text(actions == null ? 'missing' : 'actual editor'),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('actual editor'), findsOneWidget);
    expect(creates, 1);
    expect(retires, 0);
    await tester.pumpWidget(const SizedBox());
    await stop;
    expect(retires, 1);
  });
  testWidgets('late CSRF preparation result retired and never builds editor', (
    tester,
  ) async {
    final ready = Completer<TaskEditorOwnedActions>();
    var built = 0, retires = 0;
    bool Function()? current;
    await tester.pumpWidget(
      MaterialApp(
        home: ownedTaskEditorRoute(
          factory: ({required isCurrent, required abortTrigger}) {
            current = isCurrent;
            return ready.future;
          },
          builder: (actions) {
            built++;
            return const Text('editor');
          },
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    expect(current!(), isFalse);
    ready.complete(
      TaskEditorOwnedActions(
        bindings: binding(() => true),
        retire: () {
          retires++;
        },
      ),
    );
    await tester.pump();
    expect(built, 0);
    expect(retires, 1);
  });
  testWidgets('preparation failure blocks editor and never auto retries', (
    tester,
  ) async {
    var creates = 0, built = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ownedTaskEditorRoute(
          factory: ({required isCurrent, required abortTrigger}) async {
            creates++;
            throw StateError('private error');
          },
          builder: (_) {
            built++;
            return const Text('editor');
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(creates, 1);
    expect(built, 0);
    expect(find.textContaining('private error'), findsNothing);
    expect(find.text('无法准备当前任务操作，请返回后重试。'), findsOneWidget);
  });
}
