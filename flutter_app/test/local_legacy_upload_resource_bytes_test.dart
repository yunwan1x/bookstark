import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<void> replace(List<int> bytes) async {
    await file.writeAsBytes(bytes);
    await db.update('legacy_import_upload_blobs', {
      'file_size': bytes.length,
      'file_sha256': sha256.convert(bytes).toString(),
    });
  }

  test(
    'HTML binding exposes passive source and retires without owning content',
    () async {
      await db.update(
        'notes',
        {'editor_type': 'html', 'content': '<img src="/upload-files/p.png">'},
        where: 'id=?',
        whereArgs: [1],
      );
      final html = await repo.open(1);
      final binding = GenerationHtmlRasterBinding(index: index, content: html);
      expect(binding.document.scriptsEnabled, isFalse);
      expect(binding.document.resources, isEmpty);
      expect(binding.document.source, contains(html.source));
      expect(html.source, '<img src="/upload-files/p.png">');
      expect((await binding.load('/upload-files/p.png'))?.bytes, png);
      binding.dispose();
      expect(await binding.load('/upload-files/p.png'), isNull);
      expect(() => binding.document, throwsA(isA<GenerationContentFailure>()));
      expect(html.isCurrent, isTrue);
      html.close();
    },
  );
  test(
    'article Markdown converts headings and raster URLs without changing source',
    () async {
      const original =
          '# Article\n\n**Kept**\n\n![p](/upload-files/p.png)\n<script>blocked()</script>';
      await db.update(
        'notes',
        {'collection': 'article', 'content': original},
        where: 'id=?',
        whereArgs: [1],
      );
      final article = await repo.open(1, collection: 'article');
      final binding = GenerationHtmlRasterBinding(
        index: index,
        content: article,
      );
      expect(article.source, original);
      expect(binding.document.source, contains('<h1'));
      expect(binding.document.source, contains('<strong>Kept</strong>'));
      expect(binding.document.source, contains('src="/upload-files/p.png"'));
      expect(binding.document.scriptsEnabled, isFalse);
      expect((await binding.load('/upload-files/p.png'))?.bytes, png);
      binding.dispose();
      article.close();
    },
  );
  test('HTML binding rejects Markdown and drops closed HTML content', () async {
    expect(
      () => GenerationHtmlRasterBinding(index: index, content: handle),
      throwsArgumentError,
    );
    await db.update(
      'notes',
      {'editor_type': 'html'},
      where: 'id=?',
      whereArgs: [1],
    );
    final html = await repo.open(1);
    final binding = GenerationHtmlRasterBinding(index: index, content: html);
    html.close();
    expect(binding.isCurrent, isFalse);
    expect(await binding.load('/upload-files/p.png'), isNull);
  });
  test(
    'same-generation opened content reads verified immutable PNG with actual header MIME',
    () async {
      final image = await index.readRaster(
        '/upload-files/p.png?v=1',
        content: handle,
      );
      expect(image, isNotNull);
      expect(image!.mime, 'image/png');
      expect(image.bytes, png);
      expect(image.sha256Hex, sha256.convert(png).toString());
      expect(() => image.bytes[0] = 0, throwsUnsupportedError);
    },
  );
  test(
    'closed note handle and closed alias index cannot return bytes',
    () async {
      handle.close();
      expect(
        await index.readRaster('/upload-files/p.png', content: handle),
        isNull,
      );
      handle = await repo.open(1);
      index.dispose();
      expect(
        await index.readRaster('/upload-files/p.png', content: handle),
        isNull,
      );
    },
  );
  test(
    'closing plaintext content while native-style lookup awaits discards the pending bytes',
    () async {
      final paused = _PausedDatabase(db);
      final actual = LegacyUploadAliasIndex(
        database: paused,
        generation: generation,
        sourceSha256: source,
        policy: policy,
        isCurrent: () => true,
      );
      final pending = actual.readRaster('/upload-files/p.png', content: handle);
      await paused.selected.future.timeout(const Duration(seconds: 5));
      handle.close();
      paused.release.complete();
      expect(await pending, isNull);
      actual.dispose();
    },
  );
  test('wrong generation handle never selects an alias', () async {
    final other = LocalDataPaths.generation(id: 'f' * 32, privateSupport: root);
    await File(other.databasePath).parent.create(recursive: true);
    final peer = await databaseFactoryFfiNoIsolate.openDatabase(
      other.databasePath,
      options: OpenDatabaseOptions(
        version: 15,
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      ),
    );
    await peer.insert('notes', {
      'id': 1,
      'title': 'peer',
      'content': 'peer',
      'updated_at': 0,
    });
    final peerRepo = LocalGenerationContentRepository(
      database: peer,
      generation: other,
      isCurrent: () => true,
    );
    try {
      final opened = await peerRepo.open(1);
      expect(
        await index.readRaster('/upload-files/p.png', content: opened),
        isNull,
      );
    } finally {
      peerRepo.dispose();
      await peer.close();
    }
  });
  test(
    'same-length modified file is rejected by the stored exact hash',
    () async {
      final changed = png.toList()..[png.length - 1] = 0;
      await file.writeAsBytes(changed);
      expect(
        await index.readRaster('/upload-files/p.png', content: handle),
        isNull,
      );
    },
  );
  test(
    'missing file and symlink do not expose unrelated target bytes',
    () async {
      await file.delete();
      expect(
        await index.readRaster('/upload-files/p.png', content: handle),
        isNull,
      );
      final outside = File('${root.path}/unrelated.png');
      await outside.writeAsBytes(png);
      await Link(file.path).create(outside.path);
      expect(
        await index.readRaster('/upload-files/p.png', content: handle),
        isNull,
      );
      expect(await outside.readAsBytes(), png);
    },
  );
  test(
    'attachment directory symlink is rejected even if target bytes match',
    () async {
      final moved = await generation.attachments.rename('${root.path}/moved');
      await Link(generation.attachments.path).create(moved.path);
      expect(
        await index.readRaster('/upload-files/p.png', content: handle),
        isNull,
      );
      expect(await File('${moved.path}/$id').readAsBytes(), png);
    },
  );
  test(
    'CSS JavaScript HTML and SVG never enter the passive raster path',
    () async {
      for (final text in [
        'body { color:red }',
        'alert(1)',
        '<!doctype html><script>x</script>',
        '<svg xmlns="http://www.w3.org/2000/svg"><script>x</script></svg>',
      ]) {
        await replace(utf8.encode(text));
        expect(
          await index.readRaster('/upload-files/p.png', content: handle),
          isNull,
        );
      }
    },
  );
  test(
    'foreign URL and explicit size bound fail without a network fallback',
    () async {
      expect(
        await index.readRaster(
          'https://evil.invalid/upload-files/p.png',
          content: handle,
        ),
        isNull,
      );
      expect(
        await index.readRaster(
          '/upload-files/p.png',
          content: handle,
          maxBytes: png.length - 1,
        ),
        isNull,
      );
      await expectLater(
        index.readRaster(
          '/upload-files/p.png',
          content: handle,
          maxBytes: 20 * 1024 * 1024 + 1,
        ),
        throwsArgumentError,
      );
    },
  );
}
