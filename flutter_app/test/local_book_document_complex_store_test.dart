// NOT RUN. Requires SHARED-API-PATCH plus documents12-13 reader integration.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/local_books_repository.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/spreadsheet_document.dart';
import 'package:bookstark_flutter/core/notes_repository.dart' show NoteLocked;
import 'package:bookstark_flutter/core/local_book_document_complex_store.dart';
import 'package:bookstark_flutter/core/book_document_complex_session.dart';

class MemoryBytes implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  bool failRemove = false;
  @override
  Future<Uint8List?> read(String k) async =>
      values[k] == null ? null : Uint8List.fromList(values[k]!);
  @override
  Future<void> write(String k, Uint8List v) async {
    values[k] = Uint8List.fromList(v);
  }

  @override
  Future<void> remove(String k) async {
    if (failRemove) throw StateError('cleanup');
    values.remove(k);
  }
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
  Future<(LocalStore, int, int)> fixture(
    ComplexEditorKind kind,
    String source,
  ) async {
    final root =
        Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
        Directory.systemTemp.path;
    final dir = await Directory(root).createTemp('book-document-complex-');
    final store = LocalStore(
      path: '${dir.path}/db.sqlite',
      factory: databaseFactoryFfiNoIsolate,
    );
    addTearDown(() async {
      await store.close();
      await dir.delete(recursive: true);
    });
    final book = await LocalBooksRepository(
      store,
    ).save(const BookItem(name: 'book'));
    final db = await store.database;
    final id =
        (await db.query(
              'documents',
              columns: ['document_id'],
              where: 'book_id=?',
              whereArgs: [book],
            )).single['document_id']
            as int;
    await db.rawUpdate(
      'UPDATE documents SET doc_type=?,markdown=CAST(? AS TEXT),modify_time=? WHERE document_id=?',
      [
        kind.name,
        Uint8List.fromList(utf8.encode(source)),
        '2020-01-01T00:00:00.000Z',
        id,
      ],
    );
    return (store, book, id);
  }

  ComplexNoteEdit edit(ComplexNote baseline, String source) => ComplexNoteEdit(
    title: baseline.title,
    document: ComplexEditorDocument.parse(baseline.document.kind, source),
    labels: const [],
  );
  test(
    'all six kinds no-op preserve source and metadata without notes mutation',
    () async {
      final sources = <ComplexEditorKind, String>{
        ComplexEditorKind.html: '\ufeff<!doctype html>\r\n<p>😀 exact</p>',
        ComplexEditorKind.spreadsheet: SpreadsheetDocument.empty(
          workbookId: 'book-w',
          sheetId: 's',
        ).source,
        ComplexEditorKind.drawing: '{"elements":[],"future":{"keep":true}}',
        ComplexEditorKind.mindmap:
            '{"nodeData":{"id":"r","topic":"😀"},"future":7}',
        ComplexEditorKind.richdoc:
            '{"schema":"bookstark-richdoc","schema_version":1,"data":{"main":[]},"future":7}',
        ComplexEditorKind.presentation:
            '{"width":1280,"height":720,"slides":[{"id":"s","elements":[]}],"future":7}',
      };
      for (final entry in sources.entries) {
        final (store, book, id) = await fixture(entry.key, entry.value);
        final db = await store.database;
        final repo = LocalBookDocumentComplexStore(
          store,
          bookId: book,
          kind: entry.key,
          isCurrent: () => true,
        );
        addTearDown(repo.dispose);
        final rows = await db.query('documents'),
            notes = await db.query('notes');
        final baseline = await repo.read(id),
            saved = await repo.save(baseline, edit(baseline, entry.value));
        expect(saved.document.source, entry.value);
        expect(saved.collection, 'book-document');
        expect(saved.resourceFingerprint, matches(RegExp(r'^[a-f0-9]{64}$')));
        expect(await db.query('documents'), rows);
        expect(await db.query('notes'), notes);
      }
    },
  );
  test(
    'body-only save advances modify_time and preserves every other column',
    () async {
      final (store, book, id) = await fixture(
        ComplexEditorKind.html,
        '<p>old</p>',
      );
      final db = await store.database;
      final repo = LocalBookDocumentComplexStore(
        store,
        bookId: book,
        kind: ComplexEditorKind.html,
        isCurrent: () => true,
        now: () => DateTime.utc(2026, 11, 11),
      );
      addTearDown(repo.dispose);
      final baseline = await repo.read(id),
          before = (await db.query(
            'documents',
            where: 'document_id=?',
            whereArgs: [id],
          )).single;
      final source = '\ufeff\ufeff<p>${'a' * (262144 - 7)}🙂</p>\r\n';
      final saved = await repo.save(baseline, edit(baseline, source));
      final after = (await db.query(
        'documents',
        where: 'document_id=?',
        whereArgs: [id],
      )).single;
      expect(after['modify_time'], '2026-11-11T00:00:00.000Z');
      expect(
        (await db.rawQuery(
          'SELECT CAST(markdown AS BLOB) AS source FROM documents WHERE document_id=?',
          [id],
        )).single['source'],
        utf8.encode(source),
      );
      expect(saved.document.source, source);
      expect(saved.resourceFingerprint, isNot(baseline.resourceFingerprint));
      expect(
        {...after}
          ..remove('markdown')
          ..remove('modify_time'),
        {...before}
          ..remove('markdown')
          ..remove('modify_time'),
      );
      expect(
        (await db.rawQuery(
          'SELECT CAST(markdown AS BLOB) AS bytes FROM documents WHERE document_id=?',
          [id],
        )).single['bytes'],
        utf8.encode(source),
      );
    },
  );
  test(
    'stale source/metadata, wrong book, changed type, deleted and ENC reject with zero mutation',
    () async {
      for (final mutation in <Map<String, Object?>>[
        {'markdown': '<p>external</p>'},
        {'order_sort': 99},
        {'deleted': 1},
        {'doc_type': 'markdown'},
        {'book_id': 999999},
        {'markdown': '\ufeffENC:v9:opaque'},
      ]) {
        final (store, book, id) = await fixture(
          ComplexEditorKind.html,
          '<p>old</p>',
        );
        final db = await store.database;
        final repo = LocalBookDocumentComplexStore(
          store,
          bookId: book,
          kind: ComplexEditorKind.html,
          isCurrent: () => true,
        );
        addTearDown(repo.dispose);
        final baseline = await repo.read(id);
        if (mutation.containsKey('book_id')) {
          mutation['book_id'] = await LocalBooksRepository(
            store,
          ).save(const BookItem(name: 'other'));
        }
        await db.update(
          'documents',
          mutation,
          where: 'document_id=?',
          whereArgs: [id],
        );
        final rows = await db.query('documents'),
            books = await db.query('books');
        await expectLater(
          repo.save(baseline, edit(baseline, '<p>new</p>')),
          throwsA(anything),
        );
        expect(await db.query('documents'), rows);
        expect(await db.query('books'), books);
      }
    },
  );
  test('metadata edits, cipher input and retired owner never mutate', () async {
    final (store, book, id) = await fixture(
      ComplexEditorKind.html,
      '<p>old</p>',
    );
    final db = await store.database;
    var current = true;
    final repo = LocalBookDocumentComplexStore(
      store,
      bookId: book,
      kind: ComplexEditorKind.html,
      isCurrent: () => current,
    );
    addTearDown(repo.dispose);
    final baseline = await repo.read(id), before = await db.query('documents');
    await expectLater(
      repo.save(
        baseline,
        ComplexNoteEdit(
          title: 'renamed',
          document: baseline.document,
          labels: [],
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repo.save(
        baseline,
        ComplexNoteEdit(
          title: baseline.title,
          document: baseline.document,
          labels: ['new'],
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      repo.save(baseline, edit(baseline, 'ENC:v2:opaque')),
      throwsA(isA<NoteLocked>()),
    );
    current = false;
    await expectLater(
      repo.save(baseline, edit(baseline, '<p>new</p>')),
      throwsStateError,
    );
    expect(await db.query('documents'), before);
  });
  test(
    'cold recovery full baseline detects metadata-only drift without changing source',
    () async {
      final (store, book, id) = await fixture(
        ComplexEditorKind.html,
        '<p>old</p>',
      );
      final db = await store.database;
      final bytes = MemoryBytes();
      final first = await BookDocumentComplexSession.inspect(
        store: store,
        bookId: book,
        documentId: id,
        kind: ComplexEditorKind.html,
        recoveryStore: bytes,
        isCurrent: () => true,
      );
      final pending = ComplexRecoveryRecord.capture(
        first.baseline,
        edit(first.baseline, '<p>draft</p>'),
        pending: true,
      );
      await first.vault.write(pending);
      first.retire();
      await db.update(
        'documents',
        {'order_sort': 72},
        where: 'document_id=?',
        whereArgs: [id],
      );
      final cold = await BookDocumentComplexSession.inspect(
        store: store,
        bookId: book,
        documentId: id,
        kind: ComplexEditorKind.html,
        recoveryStore: bytes,
        isCurrent: () => true,
      );
      expect(cold.recovery!.baselineMatches(cold.baseline), false);
      final controller = await cold.enter(
        choice: BookDocumentDraftChoice.restore,
      );
      addTearDown(controller!.dispose);
      expect(controller.phase, ComplexSavePhase.unknown);
      expect(controller.editable, false);
      expect(controller.edit.document.source, '<p>draft</p>');
      expect(
        (await db.query(
          'documents',
          columns: ['markdown'],
          where: 'document_id=?',
          whereArgs: [id],
        )).single['markdown'],
        '<p>old</p>',
      );
      addTearDown(cold.retire);
    },
  );
  test(
    'received SQL save cleanup failure only retries draft removal',
    () async {
      final (store, book, id) = await fixture(
        ComplexEditorKind.html,
        '<p>old</p>',
      );
      final db = await store.database;
      final bytes = MemoryBytes()..failRemove = true;
      final session = await BookDocumentComplexSession.inspect(
        store: store,
        bookId: book,
        documentId: id,
        kind: ComplexEditorKind.html,
        recoveryStore: bytes,
        isCurrent: () => true,
      );
      final controller = await session.enter(
        choice: BookDocumentDraftChoice.restore,
      );
      addTearDown(controller!.dispose);
      addTearDown(session.retire);
      await controller.save(edit(controller.baseline, '<p>saved</p>'));
      expect(controller.phase, ComplexSavePhase.committedCleanupFailed);
      final rows = await db.query('documents');
      bytes.failRemove = false;
      await controller.retryCleanup();
      expect(await db.query('documents'), rows);
      expect(bytes.values, isEmpty);
    },
  );
  test(
    'preserved legacy long title supports body-only checkpoint without metadata editing',
    () async {
      final (store, book, id) = await fixture(
        ComplexEditorKind.html,
        '<p>old</p>',
      );
      final db = await store.database;
      final title = 'legacy${'长' * 300}';
      await db.update(
        'documents',
        {'document_name': title},
        where: 'document_id=?',
        whereArgs: [id],
      );
      final bytes = MemoryBytes();
      final session = await BookDocumentComplexSession.inspect(
        store: store,
        bookId: book,
        documentId: id,
        kind: ComplexEditorKind.html,
        recoveryStore: bytes,
        isCurrent: () => true,
      );
      final controller = await session.enter(
        choice: BookDocumentDraftChoice.restore,
      );
      addTearDown(controller!.dispose);
      addTearDown(session.retire);
      await controller.checkpoint(edit(controller.baseline, '<p>draft</p>'));
      expect(controller.draftDurable, true);
      final cold = await session.vault.read(id);
      expect(cold!.edit.title, title);
      expect(
        cold.baselineResourceFingerprint,
        controller.baseline.resourceFingerprint,
      );
      await expectLater(
        controller.checkpoint(
          ComplexNoteEdit(
            title: 'changed',
            document: controller.edit.document,
            labels: [],
          ),
        ),
        throwsStateError,
      );
      expect(
        (await db.query(
          'documents',
          where: 'document_id=?',
          whereArgs: [id],
        )).single['document_name'],
        title,
      );
    },
  );

  test(
    'rename conflict full review KeepDraft rebases metadata and saves only exact draft body',
    () async {
      final (store, book, id) = await fixture(
        ComplexEditorKind.html,
        '<p>old</p>',
      );
      final db = await store.database;
      final bytes = MemoryBytes();
      final session = await BookDocumentComplexSession.inspect(
        store: store,
        bookId: book,
        documentId: id,
        kind: ComplexEditorKind.html,
        recoveryStore: bytes,
        isCurrent: () => true,
      );
      final controller = await session.enter(
        choice: BookDocumentDraftChoice.restore,
      );
      addTearDown(controller!.dispose);
      addTearDown(session.retire);
      const source = '\ufeff<p>draft 😀</p>\r\n';
      await controller.checkpoint(edit(controller.baseline, source));
      await db.update(
        'documents',
        {'document_name': 'fresh renamed title', 'order_sort': 97},
        where: 'document_id=?',
        whereArgs: [id],
      );
      await controller.save(controller.edit);
      expect(controller.phase, ComplexSavePhase.conflict);
      final reviewed = await controller.observe();
      // The real UI must display complete draft and current versions before this call.
      await controller.adoptReviewed(reviewed, keepDraft: true);
      expect(controller.edit.title, 'fresh renamed title');
      expect(controller.edit.document.source, source);
      expect((await session.vault.read(id))!.edit.title, 'fresh renamed title');
      final before = (await db.query(
        'documents',
        where: 'document_id=?',
        whereArgs: [id],
      )).single;
      await controller.save(controller.edit);
      expect(controller.phase, ComplexSavePhase.ready);
      final after = (await db.query(
        'documents',
        where: 'document_id=?',
        whereArgs: [id],
      )).single;
      expect(after['document_name'], 'fresh renamed title');
      expect(after['order_sort'], 97);
      expect(after['parent_id'], before['parent_id']);
      expect(after['identify'], before['identify']);
      expect(
        (await db.rawQuery(
          'SELECT CAST(markdown AS BLOB) AS source FROM documents WHERE document_id=?',
          [id],
        )).single['source'],
        utf8.encode(source),
      );
      expect(
        {...after}
          ..remove('markdown')
          ..remove('modify_time'),
        {...before}
          ..remove('markdown')
          ..remove('modify_time'),
      );
    },
  );
}
