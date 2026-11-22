// Synthetic-only, headless real Android protected-generation API acceptance.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as paths;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_import_mapping.dart';
import 'package:bookstark_flutter/core/local_legacy_import_records.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_rows.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_metadata.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_uploads.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_upload_copy.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_policy.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_index.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'generation_content_fixture_seed.dart';

class _ObservedChannel extends MethodChannel {
  _ObservedChannel() : super('bookstark/local_content_crypto');
  final started = Completer<void>();
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) {
    final pending = super.invokeMethod<T>(method, arguments);
    if (method == 'unlock' && !started.isCompleted) {
      started.complete();
    }
    return pending;
  }
}

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
    final result = await inner.rawQuery(sql, arguments);
    if (sql.contains('FROM legacy_import_upload_blobs')) {
      selected.complete();
      await release.future;
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _require(bool value) {
  if (!value) {
    throw StateError('Owned generation probe mismatch');
  }
}

Future<Map<String, dynamic>> _json(File file) async {
  _require(
    await FileSystemEntity.type(file.path, followLinks: false) ==
            FileSystemEntityType.file &&
        await file.length() <= 32768,
  );
  final result = jsonDecode(await file.readAsString());
  _require(result is Map<String, dynamic>);
  return result as Map<String, dynamic>;
}

Future<void> _emit(
  Directory root,
  String name,
  Map<String, Object?> value,
) async {
  final output = File(paths.join(root.path, name));
  _require(
    await FileSystemEntity.type(output.path, followLinks: false) ==
        FileSystemEntityType.notFound,
  );
  await output.writeAsString(jsonEncode(value), flush: true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SizedBox.shrink());
  Directory? root;
  Database? database;
  LocalGenerationContentRepository? repository;
  var owned = false, phase = 'startup', operation = 'validate-marker';
  try {
    final support = await getApplicationSupportDirectory();
    root = Directory(paths.join(support.path, 'generation-content-probe'));
    _require(
      await FileSystemEntity.type(root.path, followLinks: false) ==
          FileSystemEntityType.directory,
    );
    _require(
      (await root.resolveSymbolicLinks()).startsWith(
        (await support.resolveSymbolicLinks()) + paths.separator,
      ),
    );
    owned = true;
    final marker = await _json(File(paths.join(root.path, 'owned.json')));
    _require(
      marker.length == 5 &&
          marker['format'] == 1 &&
          marker['synthetic_only'] == true &&
          {'build', 'verify'}.contains(marker['phase']) &&
          marker['nonce'] is String &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(marker['nonce'] as String) &&
          marker['fixture'] is String,
    );
    phase = marker['phase'] as String;
    final fixture = marker['fixture'] as String,
        nonce = marker['nonce'] as String;
    final vector = generationContentProbeCases[fixture];
    _require(vector != null);
    final selected = vector!,
        expected = selected['sourceSha256']!,
        password = selected['password']!;
    final edited = '\ufeff${selected['plain']!}\r\n# saved🙂\r\n';
    final input = File(paths.join(root.path, 'source.zip'));
    _require(
      await FileSystemEntity.type(input.path, followLinks: false) ==
          FileSystemEntityType.file,
    );
    _require(
      (await sha256.bind(input.openRead()).first).toString() == expected,
    );
    final generation = LocalDataPaths.generation(
      id: nonce,
      privateSupport: root,
    );
    final target = File(generation.databasePath);
    if (phase == 'build') {
      _require(
        await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.notFound,
      );
      operation = 'inspect-pinned-go-zip';
      final stage = await LegacyZipStage.inspect(
        input,
        privateParent: root,
        expectedSha256: expected,
        availableBytes: NativeLocalDataControl().availableBytes,
      );
      final source = await LegacyGoExport.inspect(stage);
      final format = LegacyFormatSource.fromInspection(source, scopeKey: nonce);
      final choice = LegacyFormatSelection(
        format,
        choices: {
          for (final item in format.items)
            item.id: item.collection == 'article'
                ? LegacyContentFormat.html
                : LegacyContentFormat.markdown,
        },
      );
      final records = LegacyImportRecords.fromExport(
        source,
        LegacyImportMapping.fromRecipe(
          source,
          choice.toJson(),
          scopeKey: nonce,
        ),
      );
      final uploads = LegacyCandidateUploads.fromRecords(records, stage);
      final work = await Directory(paths.join(root.path, 'copy-work')).create();
      final copied = await copyLegacyCandidateUploads(
        uploads,
        privateParent: work,
        availableBytes: NativeLocalDataControl().availableBytes,
      );
      await target.parent.create(recursive: true);
      operation = 'build-private-candidate';
      database = await databaseFactory.openDatabase(
        target.path,
        options: OpenDatabaseOptions(
          version: 15,
          singleInstance: false,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
          onCreate: (db, v) => createLegacyCandidateSchema15(db),
        ),
      );
      await database.transaction((tx) async {
        await writeLegacyCandidateMetadata(
          tx,
          records,
          importedAt: DateTime.utc(2026, 11, 9),
        );
        await writeLegacyCandidatePrimaryRows(
          tx,
          LegacyCandidateRows.fromRecords(records),
        );
        await writeLegacyCandidateUploads(tx, uploads, copied);
      });
      _require(
        await FileSystemEntity.type(
              generation.attachments.path,
              followLinks: false,
            ) ==
            FileSystemEntityType.notFound,
      );
      await copied.directory.rename(generation.attachments.path);
    } else {
      final built = await _json(
        File(paths.join(root.path, 'build-proof.json')),
      );
      _require(
        built['passed'] == true &&
            built['nonce'] == nonce &&
            built['fixture'] == fixture &&
            built['source_sha256'] == expected &&
            built['generation'] == nonce,
      );
      _require(
        await FileSystemEntity.type(target.path, followLinks: false) ==
            FileSystemEntityType.file,
      );
      operation = 'open-read-only-candidate';
      database = await databaseFactory.openDatabase(
        target.path,
        options: OpenDatabaseOptions(
          readOnly: true,
          singleInstance: false,
          onConfigure: (db) async {
            await db.execute('PRAGMA trusted_schema=OFF');
            await db.execute('PRAGMA foreign_keys=ON');
          },
        ),
      );
    }
    final db = database;
    repository = LocalGenerationContentRepository(
      database: db,
      generation: generation,
      isCurrent: () => true,
      clock: () => DateTime.utc(2026, 11, 9),
    );
    final repo = repository;
    operation = 'password-free-open';
    var locked = false;
    try {
      final handle = await repo.open(1);
      handle.close();
    } on GenerationContentLocked catch (error) {
      locked = error.metadata.id == 1 && error.metadata.isProtected;
    }
    _require(locked);
    operation = 'list-protected-preview';
    final list = await repo.list();
    _require(list.singleWhere((r) => r.metadata.id == 1).preview.isEmpty);
    _require(
      (await repo.list(
        keyword: fixture == 'protected-native-unicode' ? '原文' : 'exact',
      )).isEmpty,
    );
    var cancelledNative = false;
    if (phase == 'build') {
      operation = 'wrong-password';
      var wrong = false;
      try {
        final value = await repo.open(1, password: 'incorrect synthetic');
        value.close();
      } on LocalContentCryptoFailure catch (error) {
        wrong = error.reason == LocalContentCryptoReason.wrongPassword;
      }
      _require(wrong);
      operation = 'native-unlock-original';
      final original = await repo.open(1, password: password);
      _require(
        original.source == selected['plain'] && original.metadata.revision == 1,
      );
      operation = 'native-encrypt-save';
      final saved = await repo.save(
        original,
        title: '${original.metadata.title} saved',
        source: edited,
        labels: [...original.metadata.labels, 'native,edited'],
      );
      _require(
        saved.source == edited &&
            saved.metadata.revision == 2 &&
            !original.isCurrent,
      );
      saved.close();
    } else {
      operation = 'cold-native-unlock';
      final opened = await repo.open(1, password: password);
      _require(opened.source == edited && opened.metadata.revision == 2);
      opened.close();
    }
    operation = 'generation-alias-lookup';
    final policy = LegacyUploadAliasPolicy(
      isolatedOrigin: Uri.parse('https://$nonce.bookstark-local.invalid'),
    );
    final index = LegacyUploadAliasIndex(
      database: db,
      generation: generation,
      sourceSha256: expected,
      policy: policy,
      isCurrent: () => true,
    );
    final alias = await index.lookup('/upload-files/bytes.bin?cache=1#ignored');
    _require(
      alias != null &&
          alias.isCurrent &&
          alias.generationId == nonce &&
          alias.bytes == 7,
    );
    final file = File(
      paths.join(generation.attachments.path, alias!.attachmentId),
    );
    _require(
      await FileSystemEntity.type(file.path, followLinks: false) ==
          FileSystemEntityType.file,
    );
    _require(
      (await sha256.bind(file.openRead()).first).toString() == alias.sha256Hex,
    );
    index.dispose();
    _require(!alias.isCurrent);
    final paused = _PausedDatabase(db);
    final retiring = LegacyUploadAliasIndex(
      database: paused,
      generation: generation,
      sourceSha256: expected,
      policy: policy,
      isCurrent: () => true,
    );
    final late = retiring.lookup('/upload-files/bytes.bin');
    await paused.selected.future.timeout(const Duration(seconds: 10));
    retiring.dispose();
    paused.release.complete();
    _require(await late == null);
    if (phase == 'build') {
      operation = 'retire-during-native-unlock';
      final observed = _ObservedChannel();
      final retiringRepo = LocalGenerationContentRepository(
        database: db,
        generation: generation,
        isCurrent: () => true,
        crypto: NativeLocalContentCrypto(channel: observed),
      );
      final pending = retiringRepo.open(1, password: password);
      await observed.started.future.timeout(const Duration(seconds: 15));
      retiringRepo.dispose();
      try {
        final value = await pending;
        value.close();
      } on LocalContentCryptoFailure catch (error) {
        cancelledNative = error.reason == LocalContentCryptoReason.cancelled;
      } on GenerationContentFailure catch (error) {
        cancelledNative = {
          GenerationContentReason.retired,
          GenerationContentReason.cancelled,
        }.contains(error.reason);
      }
      _require(cancelledNative);
    }
    operation = 'final-read-only-facts';
    repo.dispose();
    repository = null;
    final notes = await db.rawQuery(
      'SELECT id,revision,legacy_version,typeof(content) AS body_type,length(CAST(content AS BLOB)) AS body_bytes,'
      "CASE WHEN substr(content,1,7)='ENC:v1:' THEN 1 ELSE 0 END AS encrypted FROM notes ORDER BY id",
    );
    _require(
      notes.first['id'] == 1 &&
          notes.first['revision'] == 2 &&
          notes.first['body_type'] == 'text' &&
          notes.first['encrypted'] == 1,
    );
    _require(
      (await db.rawQuery('PRAGMA integrity_check')).single.values.single ==
          'ok',
    );
    _require((await db.rawQuery('PRAGMA foreign_key_check')).isEmpty);
    for (final name in ['pointer.json', 'intent.json']) {
      _require(
        !await File(paths.join(root.path, 'local-data-v1', name)).exists(),
      );
    }
    final facts = <String, Object?>{
      'passed': true,
      'synthetic_only': true,
      'phase': phase,
      'fixture': fixture,
      'nonce': nonce,
      'source_sha256': expected,
      'generation': nonce,
      'schema': 15,
      'note_revision': 2,
      'live_protected_body_encrypted': true,
      'edited_plain_sha256': sha256.convert(utf8.encode(edited)).toString(),
      'password_free_open_locked': true,
      'protected_preview_and_search_hidden': true,
      'wrong_password_checked_in_build': true,
      'native_unlock_retirement_checked_in_build': true,
      'source_bound_generation_alias': true,
      'late_alias_result_discarded': true,
      'read_only': phase == 'verify',
      'actual_webview_rendered': false,
      'activation_requested': false,
      'all45_complete': false,
    };
    await db.close();
    database = null;
    await _emit(
      root,
      phase == 'build' ? 'build-proof.json' : 'cold-proof.json',
      facts,
    );
  } catch (error) {
    if (owned && root != null) {
      await _emit(root, 'failure-$phase.json', {
        'passed': false,
        'phase': phase,
        'operation': operation,
        'error_type': error.runtimeType.toString(),
        if (error is GenerationContentFailure)
          'fixed_reason': error.reason.name,
        if (error is LocalContentCryptoFailure)
          'fixed_reason': error.reason.name,
        if (error is GenerationContentWriteUncertain)
          'known_committed': error.knownCommitted,
        'source_values_redacted': true,
      });
    }
  } finally {
    repository?.dispose();
    await database?.close();
  }
}
