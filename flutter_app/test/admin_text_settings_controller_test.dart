import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_text_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final field in AdminAiTextField.values)
    {
      'key': field.key,
      'value': '# original\r\nlabel | {subject}\r\n',
      'description': '',
      'update_time': '',
    },
]);

class TextRepository extends AdminSettingsRepository {
  TextRepository() : super(BookstarkClient('https://example.invalid'));
  AdminSettingsSnapshot value = snapshot();
  int puts = 0;
  int resets = 0;
  int reads = 0;
  Map<String, String>? patch;
  Object? resetError;
  Object? readError;
  Completer<AdminResetOutcome>? barrier;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async {
    reads++;
    if (readError != null) throw readError!;
    return value;
  }

  @override
  Future<void> saveText(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminTextChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
  }

  @override
  Future<AdminResetOutcome> resetTextToDefault(
    AdminPrincipal owner,
    AdminAiTextField field, {
    Future<void>? abortTrigger,
  }) async {
    resets++;
    if (resetError != null) throw resetError!;
    if (barrier != null) return barrier!.future;
    return AdminResetOutcome(field, 'server-default');
  }
}

void main() {
  test('disposed editable raw text form cannot retain a queued edit', () async {
    final c = AdminTextSettingsController(
      TextRepository(),
      owner,
      prompts: true,
    );
    await c.load();
    c.dispose();
    c.edit('late-platform-text');
    expect(c.editable, isFalse);
    expect(c.drafts, isEmpty);
  });

  test('scene switch preserves raw text and PUT only dirty scene', () async {
    final repo = TextRepository();
    final c = AdminTextSettingsController(repo, owner, prompts: false);
    await c.load();
    c.edit('\ufeff# preserved\r\nlabel | {subject} | extra\r\n');
    c.select(AdminAiTextField.book);
    expect(c.text, '# original\r\nlabel | {subject}\r\n');
    await c.save();
    expect(repo.patch, {
      'ai_actions_selection':
          '\ufeff# preserved\r\nlabel | {subject} | extra\r\n',
    });
    expect(repo.resets, 0);
    c.dispose();
  });

  test('stale confirmation never resets a different selected scene', () async {
    final repo = TextRepository();
    final c = AdminTextSettingsController(repo, owner, prompts: true);
    await c.load();
    final revision = c.revision;
    c.select(AdminAiTextField.html);
    await c.resetToDefault(
      confirmedField: AdminAiTextField.markdown,
      confirmedRevision: revision,
    );
    expect(repo.resets, 0);
    c.dispose();
  });

  test('successful immediate reset keeps unrelated unsaved drafts', () async {
    final repo = TextRepository();
    final c = AdminTextSettingsController(repo, owner, prompts: true);
    await c.load();
    c.edit('markdown-draft');
    c.select(AdminAiTextField.html);
    await c.resetToDefault(
      confirmedField: c.selected,
      confirmedRevision: c.revision,
    );
    expect(repo.resets, 1);
    expect(repo.puts, 0);
    expect(c.drafts[AdminAiTextField.markdown], 'markdown-draft');
    expect(c.dirty, isTrue);
    c.dispose();
  });

  test(
    'lost reset response never replays and preserves unrelated drafts',
    () async {
      final repo = TextRepository()..resetError = TimeoutException('fixture');
      final c = AdminTextSettingsController(repo, owner, prompts: true);
      await c.load();
      c.edit('markdown-draft');
      c.select(AdminAiTextField.html);
      await c.resetToDefault(
        confirmedField: c.selected,
        confirmedRevision: c.revision,
      );
      expect(c.phase, AdminTextPhase.unknown);
      await c.resetToDefault(
        confirmedField: c.selected,
        confirmedRevision: c.revision,
      );
      await c.readCurrent();
      expect(repo.resets, 1);
      expect(c.phase, AdminTextPhase.reviewingCurrent);
      c.adoptReviewedCurrent();
      expect(c.drafts[AdminAiTextField.markdown], 'markdown-draft');
      c.dispose();
    },
  );

  test('known reset receipt read failure retries GET only', () async {
    final repo = TextRepository();
    final c = AdminTextSettingsController(repo, owner, prompts: true);
    await c.load();
    repo.readError = const FormatException('fixture');
    await c.resetToDefault(
      confirmedField: c.selected,
      confirmedRevision: c.revision,
    );
    expect(c.phase, AdminTextPhase.receiptNeedsRead);
    repo.readError = null;
    await c.readCurrent();
    expect(repo.resets, 1);
    expect(repo.puts, 0);
    expect(c.phase, AdminTextPhase.editing);
    c.dispose();
  });

  test('disposing during reset rejects receipt and avoids late read', () async {
    final repo = TextRepository()..barrier = Completer<AdminResetOutcome>();
    final c = AdminTextSettingsController(repo, owner, prompts: true);
    await c.load();
    final resetting = c.resetToDefault(
      confirmedField: c.selected,
      confirmedRevision: c.revision,
    );
    c.dispose();
    repo.barrier!.complete(
      const AdminResetOutcome(AdminAiTextField.markdown, 'default'),
    );
    await resetting;
    expect(c.drafts, isEmpty);
    expect(repo.reads, 1);
  });
}
