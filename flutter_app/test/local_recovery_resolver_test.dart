import 'dart:convert';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_editor_drafts.dart';
import 'package:bookstark_flutter/core/local_assistant_write_journal.dart';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_html_scope.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/core/local_recovery_resolver.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';

void main() {
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  late Directory root;
  late LocalStore store;
  final keys = <String>[], html = <String>[], complex = <String>[];
  final archiveReceipts = <String, String>{}, fingerprints = <String, String>{};
  String key(String kind, String namespace, Object? id) =>
      'bookstark.$kind.v1.${base64Url.encode(utf8.encode(jsonEncode([namespace, id])))}';
  setUp(() async {
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '${Directory.systemTemp.path}/bookstark-unit',
    );
    await base.create(recursive: true);
    root = await base.createTemp('recovery-resolver-');
    final layout = LocalDataPaths.legacy(
      databasePath: '${root.path}/content.db',
      privateSupport: root,
    );
    store = LocalStore(
      path: layout.databasePath,
      dataPaths: layout,
      factory: databaseFactoryFfiNoIsolate,
    );
    await store.database;
    keys.clear();
    html.clear();
    complex.clear();
    archiveReceipts.clear();
    fingerprints.clear();
  });
  tearDown(() async {
    await store.close();
    await root.delete(recursive: true);
  });
  LocalRecoveryResolver resolver({Set<String> namespaces = const {'local'}}) =>
      LocalRecoveryResolver(
        store: store,
        inventory: LocalRecoveryInventory(
          maintenance: store.maintenance,
          localNamespaces: namespaces,
          readArticleReceipt: (key) async => archiveReceipts[key],
          readArticleCreationReceipt: (key) async => archiveReceipts[key],
          fingerprintArticleCreationDraft: (key) async => fingerprints[key],
          fingerprintArticleDraft: (key) async => fingerprints[key],
          preferencesMetadata: () async => {
            'format': 1,
            'secureKeys': keys.toList(),
            'htmlKeys': html.toList(),
            'overflow': false,
            'valuesIncluded': false,
          },
          complexMetadata: () async => {
            'format': 1,
            'keys': complex.toList(),
            'unknownFiles': 0,
            'activeTransfers': 0,
            'overflow': false,
            'valuesIncluded': false,
          },
        ),
      );
  test(
    'owned existing/new/article/excerpt scopes resolve without reading any draft body',
    () async {
      final note = await store.createNote('已核对标题', '正文');
      final article = await store.createNote(
        '文章标题',
        '文章',
        collection: 'article',
      );
      keys.addAll([
        key('draft', 'local', note),
        key('draft', 'local', null),
        key('draft', jsonEncode(['local', 'article']), article),
        key('draft', jsonEncode(['local', 'excerpt', 18]), null),
      ]);
      final result = await resolver().read();
      expect(result.records.map((r) => r.destination?.kind), [
        'note',
        'note',
        'note',
        'excerpt',
      ]);
      expect(result.records.first.destination!.title, '已核对标题');
      expect(result.records[2].destination!.collection, 'article');
      expect(
        result.records.last.destination!.namespace,
        jsonEncode(['local', 'excerpt', 18]),
      );
      expect(keys.length, 4);
    },
  );
  test(
    'other generation, removed resource and misplaced secure vault remain blocked and kept',
    () async {
      final note = await store.createNote('原始', '正文');
      keys.addAll([
        key('draft', 'local-generation:${'a' * 32}', note),
        key('draft', 'local', 999),
      ]);
      html.add(key('draft', 'local', note));
      final original = [...keys, ...html];
      final result = await resolver().read();
      expect(result.records.every((r) => r.destination == null), isTrue);
      expect([...keys, ...html], original);
      expect(result.summary.needsAttention, isTrue);
    },
  );
  test(
    'HTML existing/new scopes bind exact database path and collection',
    () async {
      final note = await store.createNote('HTML', '源文');
      await (await store.database).update(
        'notes',
        {'editor_type': 'html'},
        where: 'id = ?',
        whereArgs: [note],
      );
      final server = localHtmlRecoveryScope(store.path).toString();
      html.addAll([
        key(
          'local-html-recovery',
          jsonEncode([server, 1, 'note', 'html']),
          note,
        ),
        key(
          'local-html-create',
          jsonEncode([server, 1, 'article', 'html', 'new']),
          'new',
        ),
        key(
          'local-html-create',
          jsonEncode([server, 1, 'note', 'html', 'new']),
          'wrong',
        ),
      ]);
      final result = await resolver().read();
      expect(result.records[0].destination!.kind, 'html');
      expect(result.records[1].destination!.collection, 'article');
      expect(result.records[2].destination, isNull);
      expect(html.length, 3);
    },
  );
  test(
    'Markdown article complex journal resolves using metadata while ordinary Markdown notes stay native',
    () async {
      final nativeNote = await store.createNote('Native note', 'native body');
      final article = await store.createNote(
        'Web article',
        'article body',
        collection: 'article',
      );
      final db = await store.database;
      for (final id in [nativeNote, article]) {
        await db.rawUpdate(
          'UPDATE notes SET content = CAST(? AS TEXT) WHERE id = ?',
          [
            Uint8List.fromList([0xff]),
            id,
          ],
        );
      }
      final repository = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.markdown,
        collection: 'article',
      );
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: 'article',
        kind: ComplexEditorKind.markdown,
        store: NativeComplexRecoveryStore(),
      );
      complex.addAll([vault.metadataKey(article), 'f' * 64]);
      final result = await resolver().read();
      expect(result.records.first.destination?.kind, 'complex');
      expect(result.records.first.destination?.collection, 'article');
      expect(result.records.first.destination?.id, article);
      expect(result.records.first.destination?.title, 'Web article');
      expect(result.records.last.destination, isNull);
      expect(
        result.records.where((r) => r.destination?.id == nativeNote),
        isEmpty,
      );
      expect(result.summary.needsAttention, isTrue);
      expect(complex.length, 2);
    },
  );

  test(
    'hashed complex journal binds current metadata; orphan stays blocked without decrypting',
    () async {
      final note = await store.createNote('表格', '原文不由盘点解析');
      await (await store.database).update(
        'notes',
        {'editor_type': 'spreadsheet'},
        where: 'id = ?',
        whereArgs: [note],
      );
      final repository = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.spreadsheet,
      );
      final vault = ComplexRecoveryVault(
        scope: repository.scope,
        collection: 'note',
        kind: ComplexEditorKind.spreadsheet,
        store: NativeComplexRecoveryStore(),
      );
      complex.addAll([vault.metadataKey(note), 'f' * 64]);
      final result = await resolver().read();
      expect(result.records.first.destination!.kind, 'complex');
      expect(result.records.first.destination!.id, note);
      expect(result.records.first.destination!.title, '表格');
      expect(result.records.last.destination, isNull);
      expect(complex.length, 2);
    },
  );
  test(
    'handled article metadata remains reviewable after deletion without reading its body',
    () async {
      final id = await store.createNote(
        'Original title',
        'body',
        collection: 'article',
      );
      final namespace = jsonEncode(['local', 'article']);
      final old = key('draft', namespace, id);
      final marker = key('local-article-draft-handoff', namespace, id);
      keys.addAll([old, marker]);
      archiveReceipts[marker] = LocalArticleDraftReceipt(
        digest: 'a' * 64,
        disposition: LocalArticleDraftDisposition.skipped,
        ciphertextSHA256: 'b' * 64,
      ).encode();
      fingerprints[old] = 'b' * 64;
      await (await store.database).rawUpdate(
        'UPDATE notes SET content = CAST(? AS TEXT), deleted = 1 WHERE id = ?',
        [
          Uint8List.fromList([0xff]),
          id,
        ],
      );
      final result = await resolver().read();
      expect(result.summary.needsAttention, isFalse);
      expect(result.records.single.archived, isTrue);
      expect(result.records.single.destination!.kind, 'article-archive');
      expect(result.records.single.destination!.id, id);
      expect(result.records.single.destination!.title, 'Original title');
      expect(
        result.records.single.archivedDisposition,
        LocalArticleDraftDisposition.skipped,
      );
      expect(
        (await (await store.database).query(
          'notes',
          columns: ['deleted'],
          where: 'id = ?',
          whereArgs: [id],
        )).single['deleted'],
        1,
      );
    },
  );

  test(
    'retained-generation old archive is readonly-addressable without binding a current-space ID',
    () async {
      final generation = 'local-generation:${'a' * 32}';
      final namespace = jsonEncode([generation, 'article']);
      final old = key('draft', namespace, 999);
      final marker = key('local-article-draft-handoff', namespace, 999);
      keys.addAll([old, marker]);
      archiveReceipts[marker] = LocalArticleDraftReceipt(
        digest: 'a' * 64,
        disposition: LocalArticleDraftDisposition.restored,
        ciphertextSHA256: 'b' * 64,
      ).encode();
      fingerprints[old] = 'b' * 64;
      final result = await resolver(namespaces: {'local', generation}).read();
      expect(result.summary.needsAttention, isFalse);
      expect(result.records.single.archived, isTrue);
      expect(result.records.single.destination!.kind, 'article-archive');
      expect(result.records.single.destination!.namespace, namespace);
      expect(result.records.single.destination!.id, 999);
      expect(result.records.single.destination!.title, isEmpty);
    },
  );
  test(
    'new article binary slot resolves without a fake SQL ID or reading invalid source bytes',
    () async {
      final repository = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.markdown,
        collection: 'article',
      );
      final vault = LocalArticleCreationVault(
        scope: repository.scope,
        store: NativeComplexRecoveryStore(),
      );
      complex.add(vault.metadataKey);
      repository.dispose();
      final id = await store.createNote(
        'invalid byte body',
        'source',
        collection: 'article',
      );
      final db = await store.database;
      await db.rawUpdate(
        "UPDATE notes SET content = CAST(X'80' AS TEXT) WHERE id = ?",
        [id],
      );
      final result = await resolver().read();
      expect(result.summary.needsAttention, isTrue);
      expect(result.records.single.destination!.kind, 'article-create');
      expect(result.records.single.destination!.id, isNull);
      expect(result.records.single.destination!.collection, 'article');
      expect(result.records.single.reference.key, vault.metadataKey);
      expect(
        (await db.rawQuery(
          'SELECT CAST(content AS BLOB) bytes FROM notes WHERE id = ?',
          [id],
        )).single['bytes'],
        Uint8List.fromList([128]),
      );
    },
  );
  test(
    'handled null-ID original resolves a readonly archive with its creation disposition',
    () async {
      final original = key('draft', jsonEncode(['local', 'article']), null);
      final scope = LocalArticleCreationLegacyScope.fromLegacyKey(original);
      keys.addAll([original, scope.markerKey]);
      archiveReceipts[scope.markerKey] = LocalArticleCreationLegacyReceipt(
        digest: 'a' * 64,
        ciphertextSHA256: 'b' * 64,
        disposition: LocalArticleCreationLegacyDisposition.restored,
        creationKey: 'c' * 32,
      ).encode();
      fingerprints[original] = 'b' * 64;
      final result = await resolver().read();
      expect(result.summary.needsAttention, isFalse);
      final record = result.records.single;
      expect(record.archived, isTrue);
      expect(record.archivedDisposition, isNull);
      expect(
        record.archivedCreationDisposition,
        LocalArticleCreationLegacyDisposition.restored,
      );
      expect(record.destination!.kind, 'article-create-archive');
      expect(record.destination!.id, isNull);
      expect(record.destination!.namespace, scope.namespace);
    },
  );
  test(
    'retained-generation null archive has no invented current-space target ID',
    () async {
      final retained = 'local-generation:${'d' * 32}';
      final original = key('draft', jsonEncode([retained, 'article']), null);
      final scope = LocalArticleCreationLegacyScope.fromLegacyKey(original);
      keys.addAll([original, scope.markerKey]);
      archiveReceipts[scope.markerKey] = LocalArticleCreationLegacyReceipt(
        digest: 'a' * 64,
        ciphertextSHA256: 'b' * 64,
        disposition: LocalArticleCreationLegacyDisposition.skipped,
        creationKey: null,
      ).encode();
      fingerprints[original] = 'b' * 64;
      final result = await resolver(namespaces: {'local', retained}).read();
      expect(result.summary.needsAttention, isFalse);
      expect(result.records.single.destination!.namespace, scope.namespace);
      expect(result.records.single.destination!.id, isNull);
      expect(result.records.single.archived, isTrue);
    },
  );
  test(
    'AI pending and full editor drafts resolve metadata-only dedicated routes on active16',
    () async {
      final marker = LocalAssistantWriteMarker(
        namespace: 'local',
        bindingId: 'b' * 32,
        draftId: 'd' * 32,
        kind: LocalAssistantDraftKind.note,
      );
      final noteScope = LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: 'b' * 32,
        draft: 'd' * 32,
        kind: LocalAssistantDraftKind.note,
      );
      final taskScope = LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: 'c' * 32,
        draft: 'e' * 32,
        kind: LocalAssistantDraftKind.task,
      );
      keys.addAll([
        marker.key,
        key('draft', noteScope, null),
        key('task-draft', taskScope, 'new:0'),
      ]);
      final db = await store.database;
      final before = await db.rawQuery(
        'SELECT name, sql FROM sqlite_master ORDER BY name',
      );
      final result = await resolver().read();
      expect(result.records.map((r) => r.destination?.kind), [
        'ai-create',
        'ai-editor',
        'ai-editor',
      ]);
      for (final record in result.records) {
        expect(record.destination!.id, isNull);
        expect(record.destination!.title, isEmpty);
        expect(record.destination!.assistant!.namespace, 'local');
        expect(record.destination!.assistant!.inputHash, isNull);
      }
      expect(result.records[1].destination!.namespace, noteScope);
      expect(
        result.records[2].destination!.assistant!.kind,
        LocalAssistantDraftKind.task,
      );
      expect(result.summary.needsAttention, isTrue);
      expect(
        (await db.rawQuery('PRAGMA user_version')).single.values.single,
        16,
      );
      expect(
        await db.rawQuery('SELECT name, sql FROM sqlite_master ORDER BY name'),
        before,
      );
      expect(keys.length, 3);
    },
  );

  test(
    'AI malformed cross-generation and misplaced identities stay blocking without ordinary creation',
    () async {
      String scope(String base, String kind, {String? binding}) =>
          jsonEncode([base, 'assistant', binding ?? 'b' * 32, 'd' * 32, kind]);
      final foreign = 'local-generation:${'a' * 32}';
      final marker = LocalAssistantWriteMarker(
        namespace: foreign,
        bindingId: 'b' * 32,
        draftId: 'd' * 32,
        kind: LocalAssistantDraftKind.note,
      );
      keys.addAll([
        marker.key,
        key('draft', scope(foreign, 'note'), null),
        key('draft', scope('local', 'note'), '1'),
        key('task-draft', scope('local', 'task'), 'new:7'),
        key('draft', scope('local', 'task'), null),
        key('draft', scope('local', 'note', binding: 'BAD'), null),
        key('draft', scope('local', 'html'), null),
        key('draft', jsonEncode(['local', 'assistant']), null),
        '${LocalAssistantWriteMarker.prefix}invalid',
      ]);
      html.add(key('draft', scope('local', 'note'), null));
      final original = [...keys, ...html];
      final result = await resolver(namespaces: {'local', foreign}).read();
      expect(result.records.every((r) => r.destination == null), isTrue);
      expect(result.summary.needsAttention, isTrue);
      expect(result.summary.unknown, 1);
      expect([...keys, ...html], original);
    },
  );

  test('noncanonical AI editor namespace stays blocking', () async {
    final namespace =
        '[ "local", "assistant", "${'b' * 32}", "${'d' * 32}", "note" ]';
    keys.add(key('draft', namespace, null));
    final result = await resolver().read();
    expect(result.records.single.destination, isNull);
    expect(result.summary.needsAttention, isTrue);
  });
  test(
    'AI recovery binds the active generation rather than legacy local or another generation',
    () async {
      await store.close();
      final layout = LocalDataPaths.generation(
        id: 'a' * 32,
        privateSupport: root,
      );
      store = LocalStore(
        path: layout.databasePath,
        dataPaths: layout,
        factory: databaseFactoryFfiNoIsolate,
      );
      await store.database;
      final current = layout.draftNamespace;
      for (final base in [current, 'local', 'local-generation:${'f' * 32}']) {
        final marker = LocalAssistantWriteMarker(
          namespace: base,
          bindingId: 'b' * 32,
          draftId: 'd' * 32,
          kind: LocalAssistantDraftKind.task,
        );
        keys.add(marker.key);
        keys.add(
          key(
            'task-draft',
            LocalAssistantEditorDrafts.editorNamespace(
              base: base,
              binding: 'b' * 32,
              draft: 'd' * 32,
              kind: LocalAssistantDraftKind.task,
            ),
            'new:0',
          ),
        );
      }
      final result = await resolver(
        namespaces: {current, 'local', 'local-generation:${'f' * 32}'},
      ).read();
      expect(result.records.take(2).map((r) => r.destination?.kind), [
        'ai-create',
        'ai-editor',
      ]);
      expect(
        result.records
            .take(2)
            .every((r) => r.destination!.assistant!.namespace == current),
        isTrue,
      );
      expect(
        result.records.skip(2).every((r) => r.destination == null),
        isTrue,
      );
      expect(result.summary.needsAttention, isTrue);
    },
  );
  test(
    'canonical positive assistant editor IDs remain dedicated metadata destinations',
    () async {
      final noteScope = LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: 'b' * 32,
        draft: 'd' * 32,
        kind: LocalAssistantDraftKind.note,
      );
      final taskScope = LocalAssistantEditorDrafts.editorNamespace(
        base: 'local',
        binding: 'c' * 32,
        draft: 'e' * 32,
        kind: LocalAssistantDraftKind.task,
      );
      keys.addAll([
        key('draft', noteScope, 23),
        key('task-draft', taskScope, 47),
        key('draft', noteScope, '23'),
        key('task-draft', taskScope, 0),
        key('task-draft', taskScope, -1),
      ]);
      final result = await resolver().read();
      expect(result.records.take(2).map((r) => r.destination?.kind), [
        'ai-editor',
        'ai-editor',
      ]);
      expect(
        result.records.take(2).map((r) => r.destination?.assistantResourceId),
        [23, 47],
      );
      for (final record in result.records.take(2)) {
        expect(record.destination!.id, isNull);
        expect(record.destination!.assistant!.inputHash, isNull);
      }
      expect(result.records.skip(2).every((r) => r.destination == null), true);
      expect(result.summary.needsAttention, true);
    },
  );
}
