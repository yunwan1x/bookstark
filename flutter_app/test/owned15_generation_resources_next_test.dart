import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:typed_data';
import 'package:bookstark_flutter/core/owned15_generation_resources.dart';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_policy.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_index.dart';

class _PausedDatabase implements Database {
  _PausedDatabase(this.inner);
  final Database inner;
  final selected = Completer<void>(), release = Completer<void>();
  @override
  String get path => inner.path;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final value = await inner.rawQuery(sql, arguments);
    if (sql.contains('FROM legacy_import_upload_blobs')) {
      selected.complete();
      await release.future;
    }
    return value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingDatabase implements Database {
  _CountingDatabase(this.inner);
  final Database inner;
  int queries = 0;
  @override
  String get path => inner.path;
  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    queries++;
    return inner.rawQuery(sql, arguments);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoWriteNotes extends Fake implements NotesRepository {
  int writes = 0;
  @override
  Future<int> save(Note note) async {
    writes++;
    throw StateError('No explicit Save in memory-source test');
  }
}

void main() {
  late Directory root;
  late Database db;
  late LocalDataPaths generation;
  late LocalGenerationContentRepository repo;
  late GenerationContentHandle handle;
  late LegacyUploadAliasIndex index;
  late File file;
  final source = 'a' * 64, id = 'c' * 32;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==',
  );
  final origin = Uri.parse('https://${'b' * 32}.bookstark-local.invalid');
  final policy = LegacyUploadAliasPolicy(isolatedOrigin: origin);
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('legacy-raster-');
    generation = LocalDataPaths.generation(id: 'e' * 32, privateSupport: root);
    await File(generation.databasePath).parent.create(recursive: true);
    await generation.attachments.create();
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      generation.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      ),
    );
    await db.insert('notes', {
      'id': 1,
      'title': 'note',
      'content': '![p](/upload-files/p.png)',
      'labels': '[]',
      'updated_at': 0,
    });
    await db.insert('legacy_import_sources', {
      'source_sha256': source,
      'source_kind': 'go_zip_v1',
      'manifest_json': '{}',
      'format_recipe_json': '{}',
      'imported_at': '2026-11-09T00:00:00Z',
    });
    await db.insert('legacy_import_records', {
      'kind': 'upload',
      'local_id': 1,
      'source_sha256': source,
      'source_key': '["upload","p.png"]',
      'payload': '{}',
      'payload_sha256': sha256.convert(utf8.encode('{}')).toString(),
    });
    await db.insert('legacy_import_upload_blobs', {
      'attachment_id': id,
      'source_sha256': source,
      'logical_name': 'uploads/p.png',
      'alias_path': '/upload-files/p.png',
      'file_size': png.length,
      'file_sha256': sha256.convert(png).toString(),
    });
    await db.insert('legacy_import_upload_bindings', {
      'source_sha256': source,
      'upload_id': 1,
      'role': 'original',
      'attachment_id': id,
    });
    file = File('${generation.attachments.path}/$id');
    await file.writeAsBytes(png);
    repo = LocalGenerationContentRepository(
      database: db,
      generation: generation,
      isCurrent: () => true,
    );
    handle = await repo.open(1);
    index = LegacyUploadAliasIndex(
      database: db,
      generation: generation,
      sourceSha256: source,
      policy: policy,
      isCurrent: () => true,
    );
  });
  tearDown(() async {
    index.dispose();
    repo.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  Owned15GenerationResources make({bool Function()? current}) =>
      Owned15GenerationResources(
        index: index,
        content: handle,
        generation: generation,
        sourceDigest: sha256.convert(utf8.encode(handle.source)).toString(),
        fullFingerprint: 'd' * 64,
        scopeIdentity: 'f' * 64,
        references: {'/upload-files/p.png'},
        isCurrent: current ?? () => true,
      );

  test(
    'exact original binding returns immutable verified raster, no HTTP',
    () async {
      final reader = make();
      final value = await reader.read(Uri.parse('/upload-files/p.png'));
      expect(value?.bytes, png);
      expect(value?.mime, 'image/png');
      expect(value?.sha256Hex, sha256.convert(png).toString());
      expect(() => value!.bytes[0] = 0, throwsUnsupportedError);
      await reader.retire();
      expect(value!.bytes.every((b) => b == 0), isTrue);
      expect(await reader.read(Uri.parse('/upload-files/p.png')), isNull);
    },
  );
  test(
    'foreign origin, query, path traversal and unapproved aliases denied',
    () async {
      final reader = make();
      for (final raw in [
        'https://example.invalid/upload-files/p.png',
        '//example.invalid/upload-files/p.png',
        '/upload-files/p.png?token=x',
        '/upload-files/%2e%2e/p.png',
        '/upload-files/other.png',
      ]) {
        expect(await reader.read(Uri.parse(raw)), isNull);
      }
      await reader.retire();
    },
  );
  test('false current rejects before any blob lookup', () async {
    final counted = _CountingDatabase(db);
    final borrowed = LegacyUploadAliasIndex(
      database: counted,
      generation: generation,
      sourceSha256: source,
      policy: policy,
      isCurrent: () => true,
    );
    final reader = Owned15GenerationResources(
      index: borrowed,
      content: handle,
      generation: generation,
      sourceDigest: sha256.convert(utf8.encode(handle.source)).toString(),
      fullFingerprint: 'd' * 64,
      scopeIdentity: 'f' * 64,
      references: {'/upload-files/p.png'},
      isCurrent: () => false,
    );
    expect(await reader.read(Uri.parse('/upload-files/p.png')), isNull);
    expect(counted.queries, 0);
    await reader.retire();
  });
  test('mutated bytes cannot inherit original provenance hash', () async {
    await file.writeAsBytes(List.filled(png.length, 0));
    final reader = make();
    expect(await reader.read(Uri.parse('/upload-files/p.png')), isNull);
    await reader.retire();
  });
  test('attachments symlink never grants original path', () async {
    await file.delete();
    final other = File('${root.path}/external-raster');
    await other.writeAsBytes(png);
    await Link(file.path).create(other.path);
    final reader = make();
    expect(await reader.read(Uri.parse('/upload-files/p.png')), isNull);
    await reader.retire();
  });
  test('valid hash cannot bypass raster pixel allocation limit', () async {
    final huge = Uint8List.fromList(png);
    ByteData.sublistView(huge).setUint32(16, 8192);
    ByteData.sublistView(huge).setUint32(20, 8192);
    await file.writeAsBytes(huge);
    await db.update('legacy_import_upload_blobs', {
      'file_sha256': sha256.convert(huge).toString(),
    });
    final reader = make();
    expect(await reader.read(Uri.parse('/upload-files/p.png')), isNull);
    await reader.retire();
  });
  test('retirement joins actual outstanding metadata lookup', () async {
    final paused = _PausedDatabase(db);
    final borrowed = LegacyUploadAliasIndex(
      database: paused,
      generation: generation,
      sourceSha256: source,
      policy: policy,
      isCurrent: () => true,
    );
    final reader = Owned15GenerationResources(
      index: borrowed,
      content: handle,
      generation: generation,
      sourceDigest: sha256.convert(utf8.encode(handle.source)).toString(),
      fullFingerprint: 'd' * 64,
      scopeIdentity: 'f' * 64,
      references: {'/upload-files/p.png'},
      isCurrent: () => true,
    );
    final reading = reader.read(Uri.parse('/upload-files/p.png'));
    await paused.selected.future;
    var drained = false;
    final closing = reader.retire().then((_) {
      drained = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    paused.release.complete();
    expect(await reading, isNull);
    await closing;
    expect(drained, isTrue);
    borrowed.dispose();
  });
  testWidgets(
    'actual native editor source change revokes its old grant before Save',
    (tester) async {
      final reader = make();
      final noWrites = _NoWriteNotes();
      Note? changed;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: NoteEditorPage(
              repository: noWrites,
              note: Note(
                id: 1,
                title: 'Source fixture',
                content: handle.source,
                labels: const ['preserved'],
              ),
              drafts: null,
              allowAttachmentInsertion: false,
              onMemoryDraftChanged: (snapshot) {
                changed = snapshot;
                if (snapshot.content != handle.source) {
                  unawaited(reader.retire());
                }
              },
            ),
          ),
        );
        final input = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.controller?.text == handle.source,
        );
        expect(input, findsOneWidget);
        await tester.enterText(input, '# Explicit unsaved replacement');
        await tester.pump();
        expect(reader.current, isFalse);
        expect(changed?.id, 1);
        expect(changed?.labels, ['preserved']);
        expect(changed?.content, '# Explicit unsaved replacement');
        expect(noWrites.writes, 0);
        expect(
          (await tester.runAsync(() => repo.open(1)))!.source,
          '![p](/upload-files/p.png)',
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(reader.retire);
      }
    },
  );
}
