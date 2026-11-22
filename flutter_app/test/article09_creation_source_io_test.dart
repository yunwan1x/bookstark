import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_article_creation_controller.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_article_creation_source_io.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'support/article_creation_storage.dart';

class PickSource extends NativeComplexSourceIo {
  PickSource(ComplexSourceIoScope scope, {this.result, this.wait})
    : super(
        owner: scope,
        lease: 'test-owned',
        generation: 1,
        allowMarkdown: true,
      );
  final ComplexSourceFile? result;
  final Completer<ComplexSourceFile?>? wait;
  int picks = 0;
  @override
  Future<ComplexSourceFile?> pick(ComplexEditorKind kind) async {
    picks++;
    return wait == null ? result : wait!.future;
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  late Directory dir;
  late LocalStore store;
  late LocalComplexNotesRepository actual;
  late LostReplySQL sql;
  late OwnedBytes bytes;
  late LocalArticleCreationVault vault;
  late LocalArticleCreationController c;
  late ComplexSourceIoScope scope;
  var current = true, grants = 0, remounts = 0;
  ComplexNoteEdit edit(String text) => ComplexNoteEdit(
    title: 'Draft',
    labels: const ['one,label'],
    document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, text),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('article09-io-');
    store = LocalStore(
      path: '${dir.path}/content.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    actual = LocalComplexNotesRepository(
      store,
      collection: 'article',
      kind: ComplexEditorKind.markdown,
    );
    sql = LostReplySQL(actual);
    bytes = OwnedBytes();
    vault = LocalArticleCreationVault(
      scope: actual.scope,
      store: bytes,
      maintenance: store.maintenance,
    );
    current = true;
    grants = 0;
    remounts = 0;
    c = LocalArticleCreationController(
      repository: sql,
      vault: vault,
      isCurrentScope: () => current,
    );
    c.edit(edit('Original'));
    await c.flush();
    scope = await ComplexSourceIoScope.activate(
      scope: List.filled(64, 'a').join(),
      isCurrent: () => current,
      invoke: (method, args) async => method == 'scopeState'
          ? {'epoch': 0}
          : method == 'activateScope'
          ? {'epoch': 1}
          : {'retired': true},
    );
  });
  tearDown(() async {
    c.dispose();
    actual.dispose();
    await store.close();
    await dir.delete(recursive: true);
  });
  LocalArticleCreationSourceIo flow(
    PickSource native, {
    Future<bool> Function()? checkpoint,
  }) => LocalArticleCreationSourceIo(
    controller: c,
    owner: scope,
    isCurrent: () => current,
    checkpoint: checkpoint ?? c.flush,
    prepareNative: () async {
      grants++;
      return native;
    },
    retireSurface: () async {},
    remount: () async {
      remounts++;
    },
  );
  test(
    'import durably checkpoints only draft; cold restore explicit Create inserts once',
    () async {
      final incoming = ComplexSourceFile(
        name: 'a.md',
        document: edit('\ufeff# Imported\r\n').document,
      );
      final io = flow(PickSource(scope, result: incoming));
      await io.run(importing: true, confirm: (_) async => true);
      expect(io.completed, isTrue);
      expect(sql.creates, 0);
      expect(await (await store.database).query('notes'), isEmpty);
      final record = await vault.read();
      expect(record!.edit.document.source, incoming.document.source);
      c.dispose();
      c = LocalArticleCreationController(
        repository: sql,
        vault: vault,
        record: record,
        isCurrentScope: () => current,
      );
      await c.save();
      expect(sql.creates, 1);
      expect(c.created!.document.source, incoming.document.source);
      expect(remounts, 1);
    },
  );
  test('cancel selection retains durable original and zero SQL', () async {
    final io = flow(PickSource(scope));
    await io.run(
      importing: true,
      confirm: (_) async => throw StateError('must not confirm'),
    );
    expect((await vault.read())!.edit.document.source, 'Original');
    expect(sql.creates, 0);
    expect(io.completed, isFalse);
  });
  test('failed checkpoint blocks actual native grant and picker', () async {
    final native = PickSource(scope);
    final io = flow(native, checkpoint: () async => false);
    await expectLater(
      io.run(importing: true, confirm: (_) async => true),
      throwsStateError,
    );
    expect(grants, 0);
    expect(native.picks, 0);
    expect(sql.creates, 0);
  });
  test(
    'scope retirement during picker cannot import late returned bytes',
    () async {
      final native = PickSource(scope, wait: Completer<ComplexSourceFile?>());
      final io = flow(native);
      final work = io.run(importing: true, confirm: (_) async => true);
      final check = expectLater(work, throwsStateError);
      for (var n = 0; n < 30 && native.picks == 0; n++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(native.picks, 1);
      current = false;
      native.wait!.complete(
        ComplexSourceFile(name: 'late.md', document: edit('Late').document),
      );
      await check;
      expect(c.draft.document.source, 'Original');
      expect(sql.creates, 0);
    },
  );
  test('busy second operation never acquires second native grant', () async {
    final native = PickSource(scope, wait: Completer<ComplexSourceFile?>());
    final io = flow(native);
    final work = io.run(importing: true, confirm: (_) async => true);
    for (var n = 0; n < 30 && native.picks == 0; n++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(native.picks, 1);
    await io.run(importing: true, confirm: (_) async => true);
    expect(grants, 1);
    native.wait!.complete(null);
    await work;
    expect(sql.creates, 0);
  });
}
