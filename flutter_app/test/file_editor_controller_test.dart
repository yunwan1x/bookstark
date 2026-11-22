import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/file_draft_vault.dart';
import 'package:bookstark_flutter/core/file_editor_controller.dart';
import '../tool/fixtures/drive.dart';

class InterruptedDrive extends DriveFixture {
  InterruptedDrive() : super(seed: false);
  bool interrupt = false;
  @override
  Future<DriveNode> saveText(
    DriveText document,
    String content, {
    AttachmentCancellation? cancellation,
  }) async {
    final node = await super.saveText(
      document,
      content,
      cancellation: cancellation,
    );
    if (interrupt) throw StateError('connection closed after server write');
    return node;
  }
}

void main() {
  late InterruptedDrive repo;
  late Map<String, String> storage;
  late FileDraftVault vault;
  late DriveNode file;
  bool failWrite = false, failDelete = false;
  setUp(() {
    repo = InterruptedDrive();
    file = repo.addFile(
      'test.md',
      utf8.encode('\ufefffirst\r\nsecond'),
      'text/markdown',
    );
    storage = {};
    failWrite = false;
    failDelete = false;
    vault = FileDraftVault(
      namespace: 'server/member',
      readValue: (key) async => storage[key],
      writeValue: (key, value) async {
        if (failWrite) throw StateError('disk');
        storage[key] = value;
      },
      deleteValue: (key) async {
        if (failDelete) throw StateError('disk');
        storage.remove(key);
      },
    );
  });
  test(
    'durable draft restores BOM and CRLF then canonical save clears it',
    () async {
      var editor = FileEditorController(repo, vault);
      await editor.load(file);
      await editor.edit('first\r\nchanged');
      editor = FileEditorController(repo, vault);
      await editor.load(file);
      expect(editor.content, 'first\r\nchanged');
      expect(editor.document!.hasBom, isTrue);
      await editor.save();
      expect(repo.data[file.path]!, utf8.encode('\ufefffirst\r\nchanged'));
      expect(editor.dirty, isFalse);
      expect(storage, isEmpty);
    },
  );
  test('failed pending draft prevents any server write', () async {
    final editor = FileEditorController(repo, vault);
    await editor.load(file);
    await editor.edit('changed');
    failWrite = true;
    await expectLater(editor.save(), throwsStateError);
    expect(repo.saves, 0);
    expect(editor.content, 'changed');
  });
  test(
    'interrupted write survives reopen and verification never resends',
    () async {
      var editor = FileEditorController(repo, vault);
      await editor.load(file);
      await editor.edit('saved despite interruption');
      repo.interrupt = true;
      await expectLater(editor.save(), throwsStateError);
      expect(repo.saves, 1);
      expect(editor.writable, isFalse);
      editor = FileEditorController(repo, vault);
      await editor.load(repo.nodes[file.path]!);
      expect(await editor.verifyPending(), isTrue);
      expect(repo.saves, 1);
      expect(storage, isEmpty);
    },
  );
  test('saved file with failed cleanup retries only deletion', () async {
    final editor = FileEditorController(repo, vault);
    await editor.load(file);
    await editor.edit('changed');
    failDelete = true;
    await expectLater(editor.save(), throwsStateError);
    expect(editor.dirty, isFalse);
    expect(editor.cleanupPending, isTrue);
    failDelete = false;
    await editor.retryCleanup();
    expect(repo.saves, 1);
    expect(storage, isEmpty);
  });
  test('changed public context requires explicit reviewed baseline', () async {
    var editor = FileEditorController(repo, vault);
    await editor.load(file);
    await editor.edit('private draft');
    await repo.publish(file, 'published.md');
    editor = FileEditorController(repo, vault);
    await editor.load(repo.nodes[file.path]!);
    expect(editor.conflict, isTrue);
    await expectLater(editor.save(), throwsStateError);
    expect(repo.saves, 0);
    await editor.acceptReviewedBase(
      await repo.readText(repo.nodes[file.path]!),
    );
    await editor.save();
    expect(editor.document!.node.isPublic, isTrue);
  });
}
