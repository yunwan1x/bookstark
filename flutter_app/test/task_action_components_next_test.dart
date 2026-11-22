import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/task_action_drafts.dart';
import 'package:bookstark_flutter/features/tasks/task_action_components.dart';
import 'task_action_drafts_next_test.dart' show FakeTopics, task, snap;

void main() {
  testWidgets(
    'suggestion preview never saves and explicit apply preserves same task ID',
    (tester) async {
      final origin = snap(task());
      var applied = 0;
      final proposal = TaskTextSuggestion(
        origin: origin,
        content: 'Review release',
        complete: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: TaskSuggestionPreviewPage(
            suggestion: proposal,
            readCurrentDraft: () async => origin,
            compareAndApply: (expected, update) async {
              applied++;
              expect(expected, origin.fingerprint);
              expect(update.id, 42);
              expect(update.parentId, 11);
              expect(update.topicId, 9);
              expect(update.done, true);
              return true;
            },
            isCurrent: () => true,
            english: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(applied, 0);
      await tester.ensureVisible(find.text('Put into editor'));
      await tester.tap(find.text('Put into editor'));
      await tester.pumpAndSettle();
      expect(applied, 1);
    },
  );
  testWidgets('stale suggestion cannot call apply callback', (tester) async {
    final origin = snap(task());
    var applied = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: TaskSuggestionPreviewPage(
          suggestion: TaskTextSuggestion(
            origin: origin,
            content: 'New',
            complete: true,
          ),
          readCurrentDraft: () async => snap(task().copyWith(done: false)),
          compareAndApply: (_, _) async {
            applied++;
            return true;
          },
          isCurrent: () => true,
          english: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Put into editor'));
    await tester.tap(find.text('Put into editor'));
    await tester.pumpAndSettle();
    expect(applied, 0);
    expect(find.textContaining('Review again.'), findsOneWidget);
  });
  testWidgets(
    'topic select performs fresh read; clear is explicit zero; cancel makes no mutation',
    (tester) async {
      final repo = FakeTopics();
      TaskTopicChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await Navigator.push<TaskTopicChoice>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TaskTopicPickerPage(
                        source: OwnedTaskTopicSource(
                          repository: repo,
                          scope: 'owned',
                          isCurrent: () => true,
                        ),
                        currentTopicId: 9,
                        english: true,
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Use selected topic'));
      await tester.tap(find.text('Use selected topic'));
      await tester.pumpAndSettle();
      expect(result!.id, 9);
      expect(repo.reads, 1);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No topic'));
      await tester.ensureVisible(find.text('Use selected topic'));
      await tester.tap(find.text('Use selected topic'));
      await tester.pumpAndSettle();
      expect(result!.id, 0);
      expect(repo.reads, 1);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel and keep current topic'));
      await tester.tap(find.text('Cancel and keep current topic'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
  testWidgets('split suggestions expose copy only and cannot create tasks', (
    tester,
  ) async {
    final copied = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskSplitSuggestionList(
            suggestions: const ['Draft checklist', 'Review with team'],
            english: true,
            onCopy: (text) async {
              copied.add(text);
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Copy suggestion').first);
    await tester.pumpAndSettle();
    expect(copied, ['Draft checklist']);
    expect(find.textContaining('No automatic child creation.'), findsOneWidget);
  });
}
