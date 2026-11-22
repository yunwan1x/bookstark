import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_assistant_proposal_tools.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_ledger.dart';

void main() {
  late Map<String, String> storage;
  late LocalAssistantDraftLedger ledger;
  late LocalAssistantProposalTools tools;
  setUp(() {
    storage = {};
    ledger = LocalAssistantDraftLedger(
      namespace: 'isolated',
      readValue: (key) async => storage[key],
      writeValue: (key, value) async {
        storage[key] = value;
      },
    );
    tools = LocalAssistantProposalTools(ledger);
  });
  test(
    'model proposal remains pending with no resource ID or confirmation authority',
    () async {
      final result = await tools.invoke('propose_note', {
        'title': '阅读',
        'content': '\ufeff# 原文',
      });
      expect(result['saved'], false);
      expect(result['status'], 'pending');
      final record = (await ledger.load()).single;
      expect(record.resourceId, isNull);
      expect(record.state, LocalAssistantDraftState.pending);
      expect(record.payload.content, '\ufeff# 原文');
      expect(record.id, result['draft_id']);
    },
  );
  test(
    'extra SQL ID status and confirmation fields cannot become draft authority',
    () async {
      for (final field in [
        'id',
        'sql',
        'status',
        'confirm',
        'kind',
        'editor_type',
      ]) {
        await expectLater(
          tools.invoke('propose_task', {'content': 'Task', field: 'injected'}),
          throwsFormatException,
        );
      }
      await expectLater(
        tools.invoke('create_task', {'content': 'Task'}),
        throwsFormatException,
      );
      expect(storage, isEmpty);
    },
  );
  test(
    'calendar validation and existing quota are enforced before acknowledging a proposal',
    () async {
      await expectLater(
        tools.invoke('propose_task', {
          'content': 'Task',
          'due_date': '2027-02-29',
        }),
        throwsFormatException,
      );
      expect(storage, isEmpty);
      for (var i = 0; i < 6; i++) {
        await tools.invoke('propose_task', {
          'content': 'Task $i',
          'due_date': '2028-02-29',
        });
      }
      await expectLater(
        tools.invoke('propose_task', {'content': 'Overflow'}),
        throwsStateError,
      );
      expect((await ledger.load()).length, 6);
      expect(
        (await ledger.load()).every((row) => row.resourceId == null),
        true,
      );
    },
  );
}
