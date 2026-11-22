import 'dart:convert';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'note proposal preserves Markdown and BOM and has stable canonical digest',
    () {
      final payload = LocalAssistantDraftPayload.note(
        title: '  Title  ',
        content: '\ufeff## Heading\n\n**原文**  ',
      );
      expect(payload.title, 'Title');
      expect(payload.content, '\ufeff## Heading\n\n**原文**  ');
      expect(
        LocalAssistantDraftPayload.fromJson(
          jsonDecode(jsonEncode(payload.toJson())),
        ).digest,
        payload.digest,
      );
      expect(payload.digest, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        LocalAssistantDraftPayload.note(
          title: 'Title',
          content: '${payload.content}x',
        ).digest,
        isNot(payload.digest),
      );
    },
  );
  test(
    'model supplied IDs paths editor formats and SQL are rejected as fields',
    () {
      for (final field in [
        'id',
        'path',
        'sql',
        'editor_type',
        'labels',
        'status',
        'url',
      ]) {
        expect(
          () => LocalAssistantDraftPayload.fromJson({
            'kind': 'note',
            'title': 'Title',
            'content': 'Body',
            field: 'injected',
          }),
          throwsFormatException,
        );
      }
      expect(
        () => LocalAssistantDraftPayload.fromJson({
          'kind': 'article',
          'title': 'Title',
          'content': 'Body',
        }),
        throwsFormatException,
      );
    },
  );
  test('note budgets count UTF8 bytes and reject malformed Unicode', () {
    expect(
      () => LocalAssistantDraftPayload.note(
        title: List.filled(67, '中').join(),
        content: 'body',
      ),
      throwsFormatException,
    );
    expect(
      () => LocalAssistantDraftPayload.note(
        title: 't',
        content: List.filled(8001, '中').join(),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalAssistantDraftPayload.note(
        title: 't',
        content: String.fromCharCode(0xd800),
      ),
      throwsFormatException,
    );
    expect(
      () =>
          LocalAssistantDraftPayload.note(title: 'x\nsecret', content: 'body'),
      throwsFormatException,
    );
  });
  test(
    'task proposals validate actual calendar dates and existing content bounds',
    () {
      final payload = LocalAssistantDraftPayload.task(
        content: ' 阅读 ',
        dueDate: '2028-02-29',
      );
      expect(payload.content, '阅读');
      expect(payload.toJson(), {
        'kind': 'task',
        'content': '阅读',
        'due_date': '2028-02-29',
      });
      expect(LocalAssistantDraftPayload.task(content: 'task').dueDate, '');
      for (final date in [
        '2026-02-29',
        '2026-13-01',
        '0000-01-01',
        'tomorrow',
      ]) {
        expect(
          () => LocalAssistantDraftPayload.task(content: 'task', dueDate: date),
          throwsFormatException,
        );
      }
      expect(
        () => LocalAssistantDraftPayload.task(
          content: List.filled(1001, 'x').join(),
        ),
        throwsFormatException,
      );
      expect(
        () => LocalAssistantDraftPayload.task(
          content: String.fromCharCode(0xd800),
        ),
        throwsFormatException,
      );
    },
  );
}
