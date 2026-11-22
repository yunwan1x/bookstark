import 'dart:async';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_ai_settings_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_smtp_settings_controller.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot({String key = 'fixture-key'}) =>
    AdminSettingsSnapshot.parse([
      for (final entry in {
        'ai_enabled': '1',
        'ai_provider': 'openai',
        'ai_base_url': 'https://example.invalid/v1',
        'ai_api_key': key,
        'ai_model': 'fixture-model',
        'ai_temperature': '0.70',
        'ai_max_tokens': '2048',
      }.entries)
        {
          'key': entry.key,
          'value': entry.value,
          'description': '',
          'update_time': '',
        },
    ]);

class FakeRepository extends AdminSettingsRepository {
  FakeRepository() : super(BookstarkClient('https://example.invalid'));
  AdminSettingsSnapshot value = snapshot();
  int puts = 0;
  int reads = 0;
  Map<String, String>? patch;
  Object? saveError;
  Object? readError;
  Completer<AdminAiTestOutcome>? test;
  Completer<void>? saveBarrier;
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
  Future<void> saveAi(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminAiChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
    if (saveBarrier != null) await saveBarrier!.future;
    if (saveError != null) throw saveError!;
  }

  @override
  Future<AdminAiTestOutcome> testAi(
    AdminPrincipal owner, {
    required String provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    Future<void>? abortTrigger,
  }) => test!.future;
}

void main() {
  test('disposed editable secret forms reject queued platform edits', () async {
    final ai = AdminAiSettingsController(FakeRepository(), owner);
    await ai.load();
    ai.dispose();
    ai.edit('ai_api_key', 'late-platform-secret');
    expect(ai.editable, isFalse);
    expect(ai.draft, isEmpty);
    final smtp = AdminSmtpSettingsController(FakeRepository(), owner);
    await smtp.load();
    smtp.dispose();
    smtp.edit('smtp_password', 'late-platform-secret');
    expect(smtp.editable, isFalse);
    expect(smtp.draft, isEmpty);
  });

  test(
    'unchanged numeric spelling is omitted and save freezes edits',
    () async {
      final repo = FakeRepository()..saveBarrier = Completer<void>();
      final c = AdminAiSettingsController(repo, owner);
      await c.load();
      c.edit('ai_model', 'new-model');
      final save = c.save();
      c.edit('ai_api_key', 'should-not-apply');
      expect(c.draft['ai_api_key'], 'fixture-key');
      expect(repo.patch, {'ai_model': 'new-model'});
      repo.saveBarrier!.complete();
      await save;
      expect(c.phase, AdminAiPhase.saved);
      c.dispose();
    },
  );

  test('clear confirmation expires when revision changes', () async {
    final repo = FakeRepository();
    final c = AdminAiSettingsController(repo, owner);
    await c.load();
    c.edit('ai_api_key', '');
    final oldRevision = c.revision;
    c.edit('ai_model', 'new-model');
    await c.save(confirmedClearRevision: oldRevision);
    expect(repo.puts, 0);
    await c.save(confirmedClearRevision: c.revision);
    expect(repo.patch!['ai_api_key'], '');
    c.dispose();
  });

  test(
    'known receipt and failed read retries GET without another PUT',
    () async {
      final repo = FakeRepository();
      final c = AdminAiSettingsController(repo, owner);
      await c.load();
      c.edit('ai_model', 'new-model');
      repo.readError = const FormatException('fixture');
      await c.save();
      expect(c.phase, AdminAiPhase.committedNeedsRead);
      repo.readError = null;
      await c.readCurrent();
      expect(repo.puts, 1);
      expect(c.phase, AdminAiPhase.saved);
      c.dispose();
    },
  );

  test(
    'unknown save requires explicit review even when current matches',
    () async {
      final repo = FakeRepository()..saveError = TimeoutException('fixture');
      final c = AdminAiSettingsController(repo, owner);
      await c.load();
      c.edit('ai_model', 'new-model');
      await c.save();
      expect(c.phase, AdminAiPhase.unknown);
      await c.save();
      expect(repo.puts, 1);
      await c.readCurrent();
      expect(c.phase, AdminAiPhase.reviewingCurrent);
      expect(c.draft['ai_model'], 'new-model');
      c.adoptReviewedCurrent();
      expect(c.draft['ai_model'], 'fixture-model');
      expect(c.dirty, isFalse);
      c.dispose();
    },
  );

  test('cancelled connection result cannot become a current success', () async {
    final repo = FakeRepository()..test = Completer<AdminAiTestOutcome>();
    final c = AdminAiSettingsController(repo, owner);
    await c.load();
    final testing = c.testConnection();
    c.cancelTest();
    c.edit('ai_model', 'changed');
    repo.test!.complete(
      const AdminAiTestOutcome(connected: true, latencyMs: 1),
    );
    await testing;
    expect(c.testOutcome, isNull);
    expect(c.testStale, isTrue);
    expect(repo.puts, 0);
    c.dispose();
  });

  test('completed test becomes stale after an edit', () async {
    final repo = FakeRepository()..test = Completer<AdminAiTestOutcome>();
    final c = AdminAiSettingsController(repo, owner);
    await c.load();
    repo.test!.complete(
      const AdminAiTestOutcome(connected: false, latencyMs: 1),
    );
    await c.testConnection();
    expect(c.testOutcome!.connected, isFalse);
    c.edit('ai_model', 'changed');
    expect(c.testStale, isTrue);
    c.dispose();
  });

  test(
    'disposed form rejects a late save response and clears credentials',
    () async {
      final repo = FakeRepository()..saveBarrier = Completer<void>();
      final c = AdminAiSettingsController(repo, owner);
      await c.load();
      c.edit('ai_model', 'changed');
      final saving = c.save();
      c.dispose();
      repo.saveBarrier!.complete();
      await saving;
      expect(c.draft, isEmpty);
      expect(c.baseline, isNull);
      expect(repo.reads, 1);
    },
  );

  test('invalid changed numeric value never submits', () async {
    final repo = FakeRepository();
    final c = AdminAiSettingsController(repo, owner);
    await c.load();
    c.edit('ai_temperature', 'NaN');
    await c.save();
    expect(repo.puts, 0);
    expect(c.phase, AdminAiPhase.editing);
    c.dispose();
  });
}
