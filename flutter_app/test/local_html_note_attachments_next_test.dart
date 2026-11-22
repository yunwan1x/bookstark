import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:file_selector/file_selector.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_note_attachments.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'));
  }
  for (final collection in ['note', 'article']) {
    test('real $collection file import stays local/library-visible and body unchanged', () async {
      final root = await Directory.systemTemp.createTemp('html-attachments-');
      final paths = LocalDataPaths.legacy(
        databasePath: '${root.path}/data.db', privateSupport: root);
      final store = LocalStore(path: paths.databasePath, dataPaths: paths,
        factory: databaseFactoryFfiNoIsolate);
      final repository = LocalHtmlNotesRepository(store, collection: collection);
      LocalHtmlNoteAttachments? assets;
      HtmlEditorController? editor;
      ComplexSourceIoScope? scope;
      var current = true, retireCalls = 0;
      const original = '\ufeff<p>Original😀</p>\r\n';
      try {
        final note = await repository.create(HtmlNoteEdit(
          title: 'Actual local HTML', source: original, labels: ['原标签']));
        editor = HtmlEditorController(repository, note);
        scope = await ComplexSourceIoScope.activate(scope: 'c' * 64,
          isCurrent: () => current, invoke: (method, args) async {
            if (method == 'scopeState') return {'epoch': 0};
            if (method == 'activateScope') return {'epoch': 1};
            if (method == 'retireScope') { retireCalls++; return {'retired': true}; }
            throw StateError('Unexpected Native operation');
          });
        assets = await LocalHtmlNoteAttachments.open(store: store,
          editor: editor, sourceOwner: scope, isCurrentScope: () => current);
        final db = await store.database;
        final receiptBefore = await db.query('html_creation_receipts');
        final picked = await assets.importDeviceFile(
          XFile.fromData(utf8.encode('%PDF-1.4 exact'), name: 'manual.pdf', path: 'manual.pdf'));
        expect(picked.image, isFalse);
        expect(picked.attachment.uri.scheme, 'bookstark-attachment');
        expect(await assets.attachments.read(picked.attachment.uri),
          orderedEquals(utf8.encode('%PDF-1.4 exact')));
        final files = await assets.available();
        expect(files, hasLength(1));
        expect(files.single.path, startsWith('HTML附件/'));
        expect(files.single.name, endsWith('-manual.pdf'));
        final saved = await repository.read(note.metadata.id);
        expect(saved.source, original);
        expect(saved.metadata.id, note.metadata.id);
        expect(saved.labels, ['原标签']);
        expect(await db.query('html_creation_receipts'), receiptBefore);
        final again = await assets.selectLibraryFile(files.single);
        expect(again.sha256Hex, picked.sha256Hex);
        expect(again.attachment.uri, isNot(picked.attachment.uri));
        expect((await repository.read(note.metadata.id)).source, original);
        // Root's real beforeTransition awaits this same scope retirement API.
        await scope.retire();
        expect(retireCalls, 1);
        expect(() => assets!.available(), throwsStateError);
        expect((await repository.read(note.metadata.id)).source, original);
        current = false;
      } finally {
        await assets?.retireAndDrain();
        await scope?.retire();
        editor?.dispose();
        repository.dispose();
        await store.close();
        await root.delete(recursive: true);
      }
    });
  }
}
