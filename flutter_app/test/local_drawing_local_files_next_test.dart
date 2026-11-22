import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_editor_controller.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/local_drawing_image_owner.dart';
import 'package:bookstark_flutter/core/local_drawing_local_files.dart';

const _initialSource =
    '{"elements":[{"id":"original","type":"rectangle","x":0,"y":0,"width":20,"height":20}],"files":{},"appState":{},"unknown":"keep"}';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aN3sAAAAASUVORK5CYII=';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  for (final collection in ['note', 'article']) {
    test(
      'actual $collection local raster grants only captured image or hash-verified explicit choice',
      () async {
        final rig = _Rig(collection);
        await rig.open();
        try {
          final initialBody = rig.owner.bind(rig.controller.edit.document);
          final rows = await rig.files.available();
          expect(rows.single.name, endsWith('-actual.png'));
          final picked = await rig.files.selectLibraryFile(rows.single);
          expect(picked.attachment.name, rows.single.name);
          await expectLater(
            () => initialBody.read('a' * 64),
            throwsFormatException,
          );
          final approvedId = await rig.files.prepareExplicitInsertion(
            initialBody,
            picked,
            rig.controller.edit.document,
          );
          final image = await initialBody.read(approvedId);
          expect(sha256.convert(image.bytes).toString(), picked.sha256Hex);
          expect(image.mime, 'image/png');
          expect(
            (await rig.repository.read(rig.baseline.id)).document.source,
            _initialSource,
          );
          expect(await rig.updates(), 0);
          await expectLater(
            () => initialBody.read('https://example.test/image.png'),
            throwsFormatException,
          );
          await rig.sourceScope.retire();
          expect(initialBody.current, isFalse);
          expect(() => initialBody.read(approvedId), throwsStateError);
          expect(() => rig.files.available(), throwsStateError);
          expect(await rig.updates(), 0);
        } finally {
          await rig.close();
        }
      },
    );
  }
  test(
    'selected file mutated before insertion cannot expand runtime allowlist',
    () async {
      final rig = _Rig('note');
      await rig.open();
      try {
        final row = (await rig.files.available()).single;
        final picked = await rig.files.selectLibraryFile(row);
        final body = rig.owner.bind(rig.controller.edit.document);
        final file = File(
          '${rig.owner.attachments.directory.path}/${picked.attachment.uri.pathSegments.first}',
        );
        final bytes = await file.readAsBytes();
        bytes[bytes.length - 1] ^= 1;
        await file.writeAsBytes(bytes, flush: true);
        await expectLater(
          rig.files.prepareExplicitInsertion(
            body,
            picked,
            rig.controller.edit.document,
          ),
          throwsStateError,
        );
        await expectLater(() => body.read('a' * 64), throwsFormatException);
        expect(await rig.updates(), 0);
        expect(
          (await rig.repository.read(rig.baseline.id)).document.source,
          _initialSource,
        );
      } finally {
        await rig.close();
      }
    },
  );
  test(
    'valid over-reference body retained while local resource grants fail closed',
    () async {
      final rig = _Rig('note');
      await rig.open();
      try {
        final document = ComplexEditorDocument.parse(
          ComplexEditorKind.drawing,
          jsonEncode({
            'elements': List.generate(
              33,
              (i) => {'id': 'image-$i', 'type': 'image', 'fileId': 'file-$i'},
            ),
            'files': {
              for (var i = 0; i < 33; i++)
                'file-$i': {
                  'id': 'file-$i',
                  'dataURL':
                      'bookstark-attachment:///' +
                      i.toRadixString(16).padLeft(32, '0') +
                      '/a.png',
                },
            },
            'appState': {},
          }),
        );
        await rig.controller.checkpoint(
          ComplexNoteEdit(
            title: rig.baseline.title,
            document: document,
            labels: rig.baseline.labels,
          ),
        );
        final body = rig.owner.bind(document);
        expect(body.referencesUnavailable, isTrue);
        expect(body.references.files, isEmpty);
        expect(body.current, isTrue);
        expect(rig.controller.edit.document.source, document.source);
        expect(
          (await rig.repository.read(rig.baseline.id)).document.source,
          _initialSource,
        );
        expect(await rig.updates(), 0);
      } finally {
        await rig.close();
      }
    },
  );
  test(
    'Root retirement joins held actual import bytes; late read publishes nothing',
    () async {
      final rig = _Rig('article');
      await rig.open();
      final held = _HeldRaster();
      try {
        final importing = rig.files.importDeviceFile(held);
        final failed = expectLater(importing, throwsStateError);
        await held.entered.future;
        var retired = false;
        final retirement = rig.sourceScope.retire().then((_) {
          retired = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(retired, isFalse);
        expect(rig.owner.current, isFalse);
        held.release.complete();
        await failed;
        await retirement;
        expect(retired, isTrue);
        final db = await rig.store.database;
        expect(
          await db.rawQuery(
            "SELECT node_id FROM local_drive_nodes WHERE instr(name,'held')>0",
          ),
          isEmpty,
        );
        expect(
          (await rig.repository.read(rig.baseline.id)).document.source,
          _initialSource,
        );
        expect(await rig.updates(), 0);
      } finally {
        if (!held.release.isCompleted) held.release.complete();
        await rig.close();
      }
    },
  );

  test(
    'protected ephemeral controller cannot acquire ordinary-local asset capability',
    () async {
      final rig = _Rig('note');
      await rig.open();
      final protectedController = LocalComplexEditorController(
        repository: rig.repository,
        vault: rig.controller.vault,
        baseline: rig.baseline,
        ephemeralDrafts: true,
      );
      try {
        expect(
          () => LocalDrawingImageOwner.open(
            store: rig.store,
            controller: protectedController,
            sourceOwner: rig.sourceScope,
            isCurrentScope: () => true,
          ),
          throwsStateError,
        );
        expect(await rig.updates(), 0);
      } finally {
        protectedController.dispose();
        await rig.close();
      }
    },
  );
  test(
    'unknown retained editor grants no read/import/insertion and keeps recovery',
    () async {
      final rig = _Rig('note');
      await rig.open();
      final record = ComplexRecoveryRecord.capture(
        rig.baseline,
        ComplexNoteEdit(
          title: rig.baseline.title,
          document: rig.baseline.document,
          labels: rig.baseline.labels,
        ),
        pending: true,
      );
      await rig.controller.vault.write(record);
      final before = Map<String, Uint8List>.from(rig.vaultStore.values);
      final unknownController = LocalComplexEditorController(
        repository: rig.repository,
        vault: rig.controller.vault,
        baseline: rig.baseline,
        recovery: record,
      );
      final closedOwner = LocalDrawingImageOwner.open(
        store: rig.store,
        controller: unknownController,
        sourceOwner: rig.sourceScope,
        isCurrentScope: () => true,
      );
      final closedFiles = LocalDrawingLocalFiles(closedOwner);
      try {
        expect(unknownController.requiresReview, isTrue);
        expect(closedOwner.current, isFalse);
        expect(
          () => closedOwner.bind(unknownController.edit.document),
          throwsStateError,
        );
        expect(() => closedFiles.available(), throwsStateError);
        expect(rig.vaultStore.values, before);
        expect(await rig.updates(), 0);
        expect(
          (await rig.repository.read(rig.baseline.id)).document.source,
          _initialSource,
        );
      } finally {
        await closedFiles.retireAndDrain();
        await closedOwner.retireAndDrain();
        unknownController.dispose();
        await rig.close();
      }
    },
  );
}

class _Rig {
  _Rig(this.collection);
  final String collection;
  late Directory root;
  late LocalStore store;
  late LocalComplexNotesRepository repository;
  late ComplexNote baseline;
  late LocalComplexEditorController controller;
  late ComplexSourceIoScope sourceScope;
  late LocalDrawingImageOwner owner;
  late LocalDrawingLocalFiles files;
  final vaultStore = _MemoryBytesStore();
  Future<void> open() async {
    root = await Directory.systemTemp.createTemp('local-drawing-images-');
    final paths = LocalDataPaths.legacy(
      databasePath: '${root.path}/data.db',
      privateSupport: root,
    );
    store = LocalStore(
      path: paths.databasePath,
      dataPaths: paths,
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.drawing,
      collection: collection,
    );
    baseline = (await repository.createOnce(
      ComplexNoteEdit(
        title: 'Actual rich document',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.drawing,
          _initialSource,
        ),
        labels: ['literal,label'],
      ),
      creationKey: 'a' * 32,
    )).note;
    controller = LocalComplexEditorController(
      repository: repository,
      vault: ComplexRecoveryVault(
        scope: repository.scope,
        collection: collection,
        kind: ComplexEditorKind.drawing,
        store: vaultStore,
      ),
      baseline: baseline,
    );
    sourceScope = await ComplexSourceIoScope.activate(
      scope: 'c' * 64,
      isCurrent: () => true,
      invoke: (method, args) async {
        if (method == 'scopeState') return {'epoch': 0};
        if (method == 'activateScope') return {'epoch': 1};
        if (method == 'retireScope') return {'retired': true};
        throw StateError('Unexpected Root scope method');
      },
    );
    owner = LocalDrawingImageOwner.open(
      store: store,
      controller: controller,
      sourceOwner: sourceScope,
      isCurrentScope: () => true,
    );
    files = LocalDrawingLocalFiles(owner);
    await files.importDeviceFile(
      XFile.fromData(
        Uint8List.fromList(base64Decode(_png)),
        name: 'actual.png',
        path: 'actual.png',
      ),
    );
    final db = await store.database;
    await db.execute('CREATE TABLE drawing_test_updates(id INTEGER)');
    await db.execute(
      'CREATE TRIGGER drawing_test_update AFTER UPDATE ON notes '
      'BEGIN INSERT INTO drawing_test_updates(id) VALUES(NEW.id); END',
    );
  }

  Future<int> updates() async =>
      (await (await store.database).query('drawing_test_updates')).length;
  Future<void> close() async {
    await files.retireAndDrain();
    await owner.retireAndDrain();
    await sourceScope.retire();
    controller.dispose();
    repository.dispose();
    await store.close();
    await root.delete(recursive: true);
  }
}

class _MemoryBytesStore implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  int removeCount = 0, removeFailures = 0, writeFailures = 0;

  @override
  Future<Uint8List?> read(String key) async {
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    if (writeFailures > 0) {
      writeFailures--;
      throw StateError('Injected draft write failure');
    }
    values[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> remove(String key) async {
    removeCount++;
    if (removeFailures > 0) {
      removeFailures--;
      throw StateError('Injected cleanup failure');
    }
    values.clear();
  }
}

class _HeldRaster extends XFile {
  _HeldRaster() : super.fromData(Uint8List(0));
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  String get name => 'held.png';
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final bytes = Uint8List.fromList(base64Decode(_png));
    yield Uint8List.sublistView(bytes, 0, 8);
    entered.complete();
    await release.future;
    yield Uint8List.sublistView(bytes, 8);
  }
}
