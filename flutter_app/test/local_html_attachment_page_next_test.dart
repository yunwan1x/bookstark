import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_html_notes_repository.dart';
import 'package:bookstark_flutter/core/local_html_scope.dart';
import 'package:bookstark_flutter/core/local_html_note_attachments.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'html_note_page_fake_surface_test_support.dart';

Future<void> progress(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)));
  }
  expect(ready(), isTrue);
  await tester.pump();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installFakeHtmlSessionChannel();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'));
  }

  for (final collection in ['note', 'article']) {
    testWidgets('real local $collection library link checkpoints draft; only real Save updates existing SQL',
        (tester) async {
      final small = collection == 'article';
      if (small) {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      late Directory root;
      late LocalStore store;
      late LocalHtmlNotesRepository repository;
      late HtmlEditorController editor;
      late LocalHtmlNoteAttachments assets;
      late ComplexSourceIoScope scope;
      var current = true;
      var inserted = 0, authorized = 0;
      final values = <String, String>{};
      final picker = Completer<XFile?>();
      var pickerEntered = false;
      const original = '\ufeff<p>Original😀</p>\r\n';
      await tester.runAsync(() async {
        root = await Directory.systemTemp.createTemp('html-page-attachment-');
        final paths = LocalDataPaths.legacy(
          databasePath: '${root.path}/data.db', privateSupport: root);
        store = LocalStore(path: paths.databasePath, dataPaths: paths,
          factory: databaseFactoryFfiNoIsolate);
        repository = LocalHtmlNotesRepository(store, collection: collection);
        final note = await repository.create(HtmlNoteEdit(
          title: 'Actual local HTML', source: original, labels: ['literal,label']));
        final vault = HtmlRecoveryVault(localDatabase: true,
          server: localHtmlRecoveryScope(store.path), memberId: 1,
          collection: collection, readValue: (key) async => values[key],
          writeValue: (key, value) async { values[key] = value; },
          deleteValue: (key) async { values.remove(key); });
        editor = HtmlEditorController(repository, note, recovery: vault);
        scope = await ComplexSourceIoScope.activate(scope: 'c' * 64,
          isCurrent: () => current, invoke: (method, args) async {
            if (method == 'scopeState') return {'epoch': 0};
            if (method == 'activateScope') return {'epoch': 1};
            if (method == 'retireScope') return {'retired': true};
            throw StateError('Unexpected scope command');
          });
        assets = await LocalHtmlNoteAttachments.open(store: store,
          editor: editor, sourceOwner: scope, isCurrentScope: () => current);
        await assets.importDeviceFile(XFile.fromData(
          utf8.encode('%PDF-1.4 local source'), name: 'manual.pdf', path: 'manual.pdf'));
        final db = await store.database;
        await db.execute('CREATE TABLE attachment_test_updates (id INTEGER)');
        await db.execute('CREATE TRIGGER attachment_test_update AFTER UPDATE ON notes '
          'BEGIN INSERT INTO attachment_test_updates(id) VALUES(NEW.id); END');
      });
      final control = FakeHtmlSurfaceControl(commandExtension:
          (command, args, source, locked, readOnly, apply) {
        // Synchronous strict checks: Flutter expect inside async peer callbacks
        // conflicts with test guardSync and is deliberately not used here.
        if (!locked || readOnly || !current) {
          throw StateError('Inactive local HTML engine');
        }
        if (command == 'authorizeLocalHtmlAttachments') {
          if (args.length != 5 || args[0] != 'c' * 64 || args[1] != 1 ||
              args[3] is! String ||
              args[4] != sha256.convert(utf8.encode(source)).toString()) {
            throw StateError('Invalid source-bound authorization');
          }
          authorized++;
          return {'generation': 73, 'identityDigest': args[2],
            'scopeEpoch': args[1], 'snapshotId': args[3], 'sourceDigest': args[4]};
        }
        if (command == 'insertLocalHtmlAttachmentSnapshot') {
          if (authorized != 1 || args.length != 3 || args[2] is! Map) {
            throw StateError('Missing one-use authorization');
          }
          final uri = Uri.parse(args[1] as String);
          final options = args[2] as Map;
          if (uri.scheme != 'bookstark-attachment' ||
              options['kind'] != 'file' || options['name'] is! String ||
              !(options['name'] as String).endsWith('-manual.pdf')) {
            throw StateError('Invalid actual local file link');
          }
          inserted++;
          apply('$source<a href="$uri">${options['name'] as String}</a>');
          return {'generation': 73, 'ready': true, 'kind': 'html',
            'inputLocked': true, 'dirty': true};
        }
        throw StateError('Unexpected engine port command');
      });
      try {
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(small ? 2 : 1),
              viewInsets: EdgeInsets.only(bottom: small ? 180 : 0)),
            child: child!),
          home: HtmlNotePage(
          controller: editor, labels: LocalLabelsRepository(store),
          fullPreviewBuilder: (_, source) => const Text('Preview fixture'),
          local: true, localInteractiveAvailable: true, english: true,
          sourceIoScope: scope, localHtmlAttachments: assets,
          pickLocalAttachmentFile: () {
            pickerEntered = true;
            return picker.future;
          },
          sourceSurfaceBuilder: fakeHtmlSourceSurface(control))));
        await tester.ensureVisible(find.text('Source'));
        await tester.tap(find.text('Source'));
        await progress(tester, () => control.sessionOpens == 1 &&
          !control.inputLocked);
        await tester.tap(find.byTooltip('Add local image or file'));
        await progress(tester,
          () => find.text('Choose from local file library').evaluate().isNotEmpty);
        await tapVisible(tester, find.text('Choose from local file library'));
        await progress(tester, () => find.textContaining('-manual.pdf')
          .evaluate().isNotEmpty);
        await tester.ensureVisible(find.textContaining('-manual.pdf').first);
        await tapVisible(tester, find.textContaining('-manual.pdf').first);
        await progress(tester,
          () => find.text('Insert attachment link').evaluate().isNotEmpty);
        await tester.ensureVisible(find.text('Insert attachment link'));
        await tapVisible(tester, find.text('Insert attachment link'));
        await progress(tester, () => inserted == 1 &&
          editor.draft.source.contains('bookstark-attachment:') &&
          values.isNotEmpty && !control.inputLocked);
        final before = (await tester.runAsync(
          () => repository.read(editor.baseline.metadata.id)))!;
        expect(before.source, original);
        expect(before.labels, ['literal,label']);
        expect(authorized, 1);
        final db = (await tester.runAsync(() => store.database))!;
        expect(await tester.runAsync(() => db.query('attachment_test_updates')),
          isEmpty);
        await progress(tester, () {
          final buttons = find.widgetWithText(FilledButton, 'Save').evaluate();
          return buttons.isNotEmpty &&
            (buttons.first.widget as FilledButton).onPressed != null;
        });
        await tester.tap(find.widgetWithText(FilledButton, 'Save'));
        await progress(tester, () => editor.phase == HtmlEditorPhase.saved && !editor.busy);
        final after = (await tester.runAsync(
          () => repository.read(editor.baseline.metadata.id)))!;
        expect(after.metadata.id, before.metadata.id);
        expect(after.source, control.source);
        expect(after.source, startsWith(original));
        expect(after.labels, before.labels);
        expect((await tester.runAsync(
          () => db.query('attachment_test_updates')))!, hasLength(1));
        expect(await tester.runAsync(
          () => db.query('html_creation_receipts')), hasLength(1));
        expect(values, isEmpty);
        expect(inserted, 1);
        // A held system picker is not repository work. Root retirement must
        // join real IO, but must not wait for human UI or accept its late file.
        await tester.tap(find.byTooltip('Add local image or file'));
        await progress(tester,
          () => find.text('Import from device').evaluate().isNotEmpty);
        await tapVisible(tester, find.text('Import from device'));
        await progress(tester, () => pickerEntered);
        var retired = false;
        unawaited(scope.retire().then((_) { retired = true; }));
        await progress(tester, () => retired);
        current = false;
        picker.complete(XFile.fromData(utf8.encode('%PDF-1.4 late'),
          name: 'late-must-not-import.pdf', path: 'late-must-not-import.pdf'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump();
        expect(inserted, 1);
        expect((await tester.runAsync(
          () => db.query('attachment_test_updates')))!, hasLength(1));
        final nodeRows = (await tester.runAsync(
          () => db.rawQuery('SELECT name FROM local_drive_nodes WHERE directory = 0')))!;
        expect(nodeRows.any((row) =>
          row['name'].toString().contains('late-must-not-import')), isFalse);
        expect((await tester.runAsync(
          () => repository.read(before.metadata.id)))!.source, after.source);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await progress(tester, () => control.retireCalls > 0);
        await tester.runAsync(() async {
          await assets.retireAndDrain();
          await scope.retire();
          editor.dispose();
          repository.dispose();
          await store.close();
          await root.delete(recursive: true);
        });
        current = false;
      }
    });
  }
}
