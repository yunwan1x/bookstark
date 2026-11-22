// Synthetic fixture only; no production startup or data paths are selected.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_policy.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_index.dart';
import 'package:bookstark_flutter/features/html/local_html_browser_preview.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final support = await getApplicationSupportDirectory();
    final root = Directory('${support.path}/generation-raster-probe');
    final marker =
        jsonDecode(await File('${root.path}/owned.json').readAsString()) as Map;
    final nonce = marker['nonce'];
    if (marker.length != 3 ||
        marker['format'] != 1 ||
        marker['synthetic_only'] != true ||
        nonce is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce) ||
        await FileSystemEntity.type(root.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !(await root.resolveSymbolicLinks()).startsWith(
          '${await support.resolveSymbolicLinks()}/',
        )) {
      throw StateError('Expected owned synthetic marker');
    }
    final generation = LocalDataPaths.generation(
      id: nonce,
      privateSupport: root,
    );
    await File(generation.databasePath).parent.create(recursive: true);
    await generation.attachments.create();
    final db = await openDatabase(
      generation.databasePath,
      version: 15,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
      onCreate: (db, v) => createLegacyCandidateSchema15(db),
    );
    if ((await db.rawQuery('SELECT COUNT(*) AS n FROM notes')).single['n'] !=
        0) {
      throw StateError('Expected empty synthetic generation');
    }
    const html =
        '<!doctype html><html><head><title>passive-raster</title></head><body>'
        '<p id="marker">PASSIVE RASTER FIXTURE</p>'
        '<img id="owned" alt="owned green image" src="/upload-files/p.png" width="160" height="160">'
        '<img id="foreign" alt="blocked foreign image" src="https://example.invalid/forbidden.png">'
        '<script>document.title="SCRIPT_EXECUTED";document.body.dataset.executed="yes";</script>'
        '</body></html>';
    await db.insert('notes', {
      'id': 1,
      'title': 'synthetic',
      'content': html,
      'editor_type': 'html',
      'labels': '[]',
      'updated_at': 0,
    });
    final source = 'a' * 64, id = 'c' * 32;
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
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAKElEQVR4nO3NMQ0AAAgDsKlDMQKngoOkSf8mO7cEAoFAIBAIBALBl6DXUuguH/JmVwAAAABJRU5ErkJggg==',
    );
    await File(
      '${generation.attachments.path}/$id',
    ).writeAsBytes(png, flush: true);
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
    final repo = LocalGenerationContentRepository(
      database: db,
      generation: generation,
      isCurrent: () => true,
    );
    final content = await repo.open(1);
    final index = LegacyUploadAliasIndex(
      database: db,
      generation: generation,
      sourceSha256: source,
      policy: LegacyUploadAliasPolicy(
        isolatedOrigin: Uri.parse(
          'https://${'b' * 32}.bookstark-local.invalid',
        ),
      ),
      isCurrent: () => true,
    );
    final binding = GenerationHtmlRasterBinding(index: index, content: content);
    await File('${root.path}/ready.json').writeAsString(
      jsonEncode({
        'passed': true,
        'nonce': nonce,
        'schema': 15,
        'fixtureOnly': true,
        'productionUIConnected': false,
      }),
      flush: true,
    );
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: LocalHtmlBrowserPreview(
              document: binding.document,
              rasterLoader: binding.load,
              rasterScopeKey: binding.scopeKey,
              isRasterCurrent: () => binding.isCurrent,
            ),
          ),
        ),
      ),
    );
  } catch (error) {
    runApp(
      const MaterialApp(
        home: Scaffold(body: Text('Synthetic raster fixture failed')),
      ),
    );
  }
}
