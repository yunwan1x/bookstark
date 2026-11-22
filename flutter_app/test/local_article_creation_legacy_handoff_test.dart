import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_handoff.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'support/article_creation_storage.dart';

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
  late Directory directory;
  late LocalStore store;
  late LocalComplexNotesRepository repository;
  late OwnedBytes bytes;
  late LocalArticleCreationVault vault;
  late DraftVault legacy;
  late LocalArticleCreationLegacyHandoff handoff;
  final prefs = <String, String>{}, events = <String>[], reads = <String>[];
  var current = true,
      failMarker = false,
      failFlush = false,
      seal = 0,
      mutateOnRead = false;
  late String original;
  const body = '\ufeff\ufeff# 旧新建草稿\r\n- 保留字节\r\n';
  String getKey() => legacy.metadataKey(null);
  String markerKey() =>
      LocalArticleCreationLegacyScope.fromLegacyKey(getKey()).markerKey;
  LocalArticleCreationLegacyReceipt receipt() =>
      LocalArticleCreationLegacyReceipt.parse(prefs[markerKey()]!);
  Future<int> count() async =>
      (await (await store.database).query('notes')).length;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('article-null-handoff-');
    store = LocalStore(
      path: '${directory.path}/content.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    repository = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.markdown,
      collection: 'article',
    );
    bytes = OwnedBytes();
    vault = LocalArticleCreationVault(
      scope: repository.scope,
      store: bytes,
      maintenance: store.maintenance,
    );
    prefs.clear();
    events.clear();
    reads.clear();
    current = true;
    failMarker = false;
    failFlush = false;
    seal = 0;
    mutateOnRead = false;
    legacy = DraftVault(
      namespace: jsonEncode(['local', 'article']),
      maintenance: store.maintenance,
      readValue: (key) async {
        reads.add(key);
        if (mutateOnRead && key == getKey()) {
          seal++;
          mutateOnRead = false;
        }
        return prefs[key];
      },
      writeValue: (key, value) async {
        if (key.startsWith(LocalArticleCreationLegacyScope.markerPrefix)) {
          if (failMarker) throw StateError('Owned marker write failure');
          events.add('marker');
        }
        prefs[key] = value;
      },
      deleteValue: (_) async =>
          throw StateError('Original must never be deleted'),
    );
    await legacy.write(
      const Note(
        title: 'Legacy new article',
        content: body,
        labels: ['z', 'old,label'],
      ),
    );
    original = prefs[getKey()]!;
    bytes.beforeWrite = (_) async {
      events.add('durable-copy');
    };
    handoff = LocalArticleCreationLegacyHandoff(
      legacy: legacy,
      expectedLegacyNamespace: legacy.namespace,
      ownedNamespaces: const {'local'},
      vault: vault,
      repository: repository,
      maintenance: store.maintenance,
      fingerprintLegacyDraft: () async {
        final raw = prefs[getKey()];
        // Opaque deterministic fixture seal; not real native encryption proof.
        return raw == null
            ? null
            : sha256.convert(utf8.encode('owned-seal-$seal:$raw')).toString();
      },
      flushMarker: () async {
        events.add('flush');
        if (failFlush) throw StateError('Owned marker flush failure');
      },
      isCurrentScope: () => current,
    );
    events.clear();
    reads.clear();
  });
  tearDown(() async {
    repository.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'explicit transfer durably copies before marker and retains original exact',
    () async {
      final draft = await handoff.inspect();
      expect(draft, isNotNull);
      final record = await handoff.restore(draft!);
      expect(
        events.indexOf('durable-copy'),
        lessThan(events.indexOf('marker')),
      );
      expect(events.indexOf('marker'), lessThan(events.lastIndexOf('flush')));
      expect(record.edit.document.source, body);
      expect(record.edit.labels, ['z', 'old,label']);
      expect(record.legacyBinding!.digest, draft.digest);
      expect(prefs[getKey()], original);
      expect(receipt().creationKey, record.key);
      expect(await count(), 0);
      expect(await handoff.inspect(), isNull);
    },
  );
  test(
    'skip archives only metadata with no new creation and readonly review writes no record',
    () async {
      final draft = await handoff.inspect();
      await handoff.skip(draft!);
      expect(bytes.values, isEmpty);
      expect(prefs[getKey()], original);
      expect(
        receipt().disposition,
        LocalArticleCreationLegacyDisposition.skipped,
      );
      expect(receipt().creationKey, isNull);
      final before = Map<String, String>.from(prefs);
      final view = await handoff.readHandled();
      expect(view.draft.edit.document.source, body);
      expect(prefs, before);
      expect(await count(), 0);
      expect(await handoff.inspect(), isNull);
    },
  );
  test(
    'copy survives failed marker write and next inspection repairs receipt without a second copy',
    () async {
      final draft = await handoff.inspect();
      failMarker = true;
      await expectLater(handoff.restore(draft!), throwsStateError);
      final copied = await vault.read();
      expect(copied, isNotNull);
      expect(copied!.legacyBinding, isNotNull);
      expect(prefs.containsKey(markerKey()), isFalse);
      failMarker = false;
      events.clear();
      expect(await handoff.inspect(), isNull);
      expect(events, contains('marker'));
      expect(events, isNot(contains('durable-copy')));
      expect(receipt().creationKey, copied.key);
      expect((await vault.read())!.key, copied.key);
      expect(prefs[getKey()], original);
    },
  );
  test(
    'marker flush failure retains both originals and repairs after restart',
    () async {
      final draft = await handoff.inspect();
      failFlush = true;
      await expectLater(handoff.restore(draft!), throwsStateError);
      final copied = await vault.read();
      expect(copied, isNotNull);
      failFlush = false;
      expect(await handoff.inspect(), isNull);
      expect(receipt().creationKey, copied!.key);
      expect(prefs[getKey()], original);
      expect(await count(), 0);
    },
  );
  test(
    'another typed creation cannot be overwritten while original skip remains explicit',
    () async {
      final other = LocalArticleCreationRecord(
        scope: repository.scope,
        key: newComplexCreationKey(),
        edit: ComplexNoteEdit(
          title: 'other',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            'other body',
          ),
          labels: const [],
        ),
        pending: true,
      );
      await vault.write(other);
      events.clear();
      final draft = await handoff.inspect();
      await expectLater(handoff.restore(draft!), throwsStateError);
      expect((await vault.read())!.sameInput(other), isTrue);
      await handoff.skip(draft);
      expect((await vault.read())!.sameInput(other), isTrue);
      expect(receipt().creationKey, isNull);
      expect(prefs[getKey()], original);
    },
  );
  test(
    'changed old draft after user review cannot be copied or marked',
    () async {
      final draft = await handoff.inspect();
      await legacy.write(
        const Note(title: 'changed', content: 'new input', labels: []),
      );
      final changed = prefs[getKey()];
      await expectLater(handoff.restore(draft!), throwsStateError);
      await expectLater(handoff.skip(draft), throwsStateError);
      expect(bytes.values, isEmpty);
      expect(prefs.containsKey(markerKey()), isFalse);
      expect(prefs[getKey()], changed);
    },
  );
  test(
    'changed ciphertext during body read fails without copying or marking',
    () async {
      mutateOnRead = true;
      await expectLater(handoff.inspect(), throwsStateError);
      expect(bytes.values, isEmpty);
      expect(prefs.containsKey(markerKey()), isFalse);
      expect(prefs[getKey()], original);
    },
  );
  test(
    'a copied draft edited later still repairs using original provenance',
    () async {
      final draft = await handoff.inspect();
      final record = await handoff.restore(draft!);
      final changed = record.copy(
        edit: ComplexNoteEdit(
          title: 'later title',
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.markdown,
            'later body',
          ),
          labels: const ['later'],
        ),
      );
      await vault.write(changed);
      prefs.remove(markerKey());
      expect(await handoff.inspect(), isNull);
      expect((await vault.read())!.edit.document.source, 'later body');
      expect(receipt().digest, draft.digest);
      expect(receipt().creationKey, record.key);
      expect(prefs[getKey()], original);
    },
  );
  test(
    'created linked article never becomes a new creation when old archive is restored',
    () async {
      final draft = await handoff.inspect();
      final record = await handoff.restore(draft!);
      final created = await repository.createOnce(
        record.edit,
        creationKey: record.key,
      );
      await vault.remove(creationKey: record.key);
      await expectLater(
        handoff.restore(draft),
        throwsA(isA<LocalArticleCreationAlreadyCommitted>()),
      );
      await expectLater(handoff.skip(draft), throwsStateError);
      expect(bytes.values, isEmpty);
      expect(await count(), 1);
      await (await store.database).delete(
        'notes',
        where: 'id = ?',
        whereArgs: [created.note.id],
      );
      await expectLater(
        handoff.restore(draft),
        throwsA(isA<LocalArticleCreationAlreadyCommitted>()),
      );
      expect(await count(), 0);
      expect(
        await (await store.database).query('html_creation_receipts'),
        hasLength(1),
      );
      expect(prefs[getKey()], original);
    },
  );
  test(
    'resealed identical old input keeps the same SQL creation link',
    () async {
      final draft = await handoff.inspect();
      final record = await handoff.restore(draft!);
      await repository.createOnce(record.edit, creationKey: record.key);
      await vault.remove(creationKey: record.key);
      seal++;
      expect(await handoff.inspect(), isNull);
      expect(receipt().creationKey, record.key);
      final archived = await handoff.readHandled();
      expect(archived.receipt.ciphertextSHA256, isNot(draft.ciphertextSHA256));
      await expectLater(
        handoff.restore(archived.draft),
        throwsA(isA<LocalArticleCreationAlreadyCommitted>()),
      );
      expect(await count(), 1);
    },
  );
  test(
    'a genuinely changed old input may explicitly start a different creation without altering the prior one',
    () async {
      final first = await handoff.inspect();
      final originalRecord = await handoff.restore(first!);
      await repository.createOnce(
        originalRecord.edit,
        creationKey: originalRecord.key,
      );
      await vault.remove(creationKey: originalRecord.key);
      await legacy.write(
        const Note(
          title: 'another legacy draft',
          content: 'new body',
          labels: [],
        ),
      );
      final expected = prefs[getKey()];
      final second = await handoff.inspect();
      expect(second, isNotNull);
      final next = await handoff.restore(second!);
      expect(next.key, isNot(originalRecord.key));
      expect(next.edit.document.source, 'new body');
      expect(await count(), 1);
      expect(prefs[getKey()], expected);
    },
  );
  test('scope change after reading prevents any durable transfer', () async {
    final draft = await handoff.inspect();
    current = false;
    await expectLater(handoff.restore(draft!), throwsStateError);
    expect(bytes.values, isEmpty);
    expect(prefs.containsKey(markerKey()), isFalse);
    expect(prefs[getKey()], original);
  });
  test(
    'invalid or oversized old record is retained and never becomes an empty draft',
    () async {
      for (final raw in [
        '{"version":1.0,"title":"bad","content":"","labels":[]}',
        '{"version":1,"title":"bad","content":"","labels":[7]}',
        ' ' * (24 * 1024 * 1024 + 1),
      ]) {
        prefs[getKey()] = raw;
        await expectLater(handoff.inspect(), throwsFormatException);
        expect(prefs[getKey()], raw);
        expect(bytes.values, isEmpty);
      }
    },
  );
  test(
    'a changed existing creation link cannot be overwritten by an old restore approval',
    () async {
      final draft = await handoff.inspect();
      final copied = await handoff.restore(draft!);
      final changed = LocalArticleCreationLegacyReceipt(
        digest: draft.digest,
        ciphertextSHA256: draft.ciphertextSHA256,
        disposition: LocalArticleCreationLegacyDisposition.restored,
        creationKey: 'e' * 32,
      );
      prefs[markerKey()] = changed.encode();
      await expectLater(
        handoff.restore(draft, expectedCreationKey: copied.key),
        throwsStateError,
      );
      expect(receipt().creationKey, 'e' * 32);
      expect((await vault.read())!.key, copied.key);
      expect(prefs[getKey()], original);
    },
  );
}
