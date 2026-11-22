import 'dart:convert';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_article_creation_legacy_metadata.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryBytes implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  bool failBeforeWrite = false, failAfterWrite = false;
  int calls = 0;
  @override
  Future<Uint8List?> read(String key) async {
    calls++;
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    calls++;
    if (failBeforeWrite) throw StateError('Owned simulated disk failure');
    values[key] = Uint8List.fromList(bytes);
    if (failAfterWrite) throw StateError('Owned simulated lost write receipt');
  }

  @override
  Future<void> remove(String key) async {
    calls++;
    values.remove(key);
  }
}

void main() {
  const key = '11111111111111111111111111111111';
  final scope = 'a' * 64;
  LocalArticleCreationRecord record({
    String title = '',
    String source = '\ufeff\ufeff# 原稿\r\n',
    List<String> labels = const ['z', 'a,b'],
    String? creationKey,
    bool pending = false,
    int? createdId,
    String? owner,
    LocalArticleCreationLegacyBinding? binding,
  }) => LocalArticleCreationRecord(
    scope: owner ?? scope,
    key: creationKey ?? key,
    edit: ComplexNoteEdit(
      title: title,
      document: ComplexEditorDocument.parse(ComplexEditorKind.markdown, source),
      labels: labels,
    ),
    pending: pending,
    createdId: createdId,
    legacyBinding: binding,
  );
  Uint8List changeMetadata(
    Uint8List encoded,
    void Function(Map<String, dynamic>) change,
  ) {
    final length = ByteData.sublistView(encoded, 0, 4).getUint32(0, Endian.big);
    final fields =
        (jsonDecode(utf8.decode(encoded.sublist(4, 4 + length))) as Map)
            .cast<String, dynamic>();
    change(fields);
    final head = utf8.encode(jsonEncode(fields));
    return (BytesBuilder()
          ..add(
            (ByteData(
              4,
            )..setUint32(0, head.length, Endian.big)).buffer.asUint8List(),
          )
          ..add(head)
          ..add(encoded.sublist(4 + length)))
        .takeBytes();
  }

  test(
    'unfinished empty title and exact BOM CRLF ordered labels round trip',
    () {
      final original = record();
      final decoded = LocalArticleCreationRecord.decode(original.encode());
      expect(decoded.sameInput(original), isTrue);
      expect(decoded.edit.title, isEmpty);
      expect(decoded.pending, isFalse);
      expect(decoded.createdId, isNull);
      expect(decoded.edit.labels, ['z', 'a,b']);
      expect(() => decoded.edit.validate(), throwsFormatException);
    },
  );
  test(
    'full 20MiB source fits bounded binary transport without base64 expansion',
    () {
      final original = record(
        source: '\ufeff\ufeff${'a' * (20 * 1024 * 1024 - 6)}',
      );
      final bytes = original.encode();
      expect(
        bytes.length,
        lessThanOrEqualTo(NativeComplexRecoveryStore.maxBytes),
      );
      final decoded = LocalArticleCreationRecord.decode(bytes);
      expect(decoded.edit.document.byteLength, 20 * 1024 * 1024);
      expect(decoded.edit.document.digest, original.edit.document.digest);
      expect(decoded.edit.document.source.startsWith('\ufeff\ufeff'), isTrue);
    },
  );
  test('damaged body and advertised body length cannot be adopted', () {
    final bytes = record().encode();
    final corrupted = Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1;
    expect(
      () => LocalArticleCreationRecord.decode(corrupted),
      throwsFormatException,
    );
    expect(
      () => LocalArticleCreationRecord.decode(
        changeMetadata(bytes, (m) => m['sourceBytes'] = 0),
      ),
      throwsFormatException,
    );
  });
  test(
    'closed metadata refuses foreign type kind collection and numeric ambiguity',
    () {
      final bytes = record().encode();
      for (final patch in <Map<String, dynamic>>[
        {'type': 'existing-note'},
        {'kind': 'html'},
        {'collection': 'note'},
        {'format': 1.0},
        {'createdId': 0},
        {'createdId': 2},
        {'extra': 'field'},
        {'scope': 'not-a-scope'},
        {'key': 'not-a-key'},
        {
          'labels': ['same', 'same'],
        },
      ]) {
        expect(
          () => LocalArticleCreationRecord.decode(
            changeMetadata(bytes, (m) => m.addAll(patch)),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test('short oversized and misleading binary header are refused', () {
    expect(
      () => LocalArticleCreationRecord.decode(Uint8List(3)),
      throwsFormatException,
    );
    final bytes = record().encode();
    ByteData.sublistView(bytes, 0, 4).setUint32(0, 128 * 1024 + 1, Endian.big);
    expect(
      () => LocalArticleCreationRecord.decode(bytes),
      throwsFormatException,
    );
    expect(
      () => LocalArticleCreationRecord.decode(
        Uint8List(NativeComplexRecoveryStore.maxBytes + 1),
      ),
      throwsFormatException,
    );
  });
  test(
    'known created ID requires pending and only valid Markdown draft metadata',
    () {
      expect(() => record(createdId: 1), throwsFormatException);
      expect(() => record(title: 'a' * 201), throwsFormatException);
      expect(() => record(labels: ['']), throwsFormatException);
      expect(record(pending: true, createdId: 1).createdId, 1);
    },
  );
  test(
    'foreign scope bytes are retained and never opened as the current draft',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      store.values[vault.metadataKey] = record(owner: 'b' * 64).encode();
      await expectLater(vault.read(), throwsFormatException);
      expect(store.values, hasLength(1));
      await expectLater(
        vault.write(record(owner: 'b' * 64)),
        throwsFormatException,
      );
    },
  );
  test(
    'a different creation cannot overwrite the durable existing slot',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      await vault.write(record());
      await expectLater(
        vault.write(record(creationKey: '2' * 32)),
        throwsStateError,
      );
      expect((await vault.read())!.key, key);
    },
  );
  test('pending input is sealed against edits and pending downgrade', () async {
    final store = MemoryBytes();
    final vault = LocalArticleCreationVault(scope: scope, store: store);
    final pending = record(title: 'original', pending: true);
    await vault.write(pending);
    await expectLater(
      vault.write(record(title: 'changed', pending: true)),
      throwsStateError,
    );
    await expectLater(
      vault.write(pending.copy(pending: false)),
      throwsStateError,
    );
    expect((await vault.read())!.sameInput(pending), isTrue);
    await vault.write(pending.copy(createdId: 9));
    await expectLater(
      vault.write(pending.copy(createdId: 10)),
      throwsStateError,
    );
    expect((await vault.read())!.createdId, 9);
  });
  test('late cleanup cannot delete a different subsequent creation', () async {
    final store = MemoryBytes();
    final vault = LocalArticleCreationVault(scope: scope, store: store);
    await vault.write(record());
    await vault.remove(creationKey: key);
    await vault.write(record(creationKey: '2' * 32));
    await expectLater(vault.remove(creationKey: key), throwsStateError);
    expect((await vault.read())!.key, '2' * 32);
  });
  test(
    'failed storage write preserves prior bytes and permits explicit retry',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      final original = record(title: 'first');
      await vault.write(original);
      store.failBeforeWrite = true;
      await expectLater(vault.write(record(title: 'second')), throwsStateError);
      expect((await vault.read())!.sameInput(original), isTrue);
      store.failBeforeWrite = false;
      await vault.write(record(title: 'second'));
      expect((await vault.read())!.edit.title, 'second');
    },
  );
  test(
    'lost durable write receipt is readable after reconstructing the vault',
    () async {
      final store = MemoryBytes()..failAfterWrite = true;
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      final pending = record(title: 'sealed', pending: true);
      await expectLater(vault.write(pending), throwsStateError);
      store.failAfterWrite = false;
      final reopened = LocalArticleCreationVault(scope: scope, store: store);
      expect((await reopened.read())!.pending, isTrue);
      await expectLater(
        reopened.write(record(title: 'changed')),
        throwsStateError,
      );
      expect((await reopened.read())!.sameInput(pending), isTrue);
    },
  );
  test(
    'fresh confirmed absence permits editing the same uncommitted creation',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      final pending = record(title: 'original', pending: true);
      await vault.write(pending);
      final resumed = await vault.resumeAfterAbsent(
        pending,
        stillAbsent: () async => true,
      );
      expect(resumed.pending, isFalse);
      await vault.write(record(title: 'corrected title'));
      expect((await vault.read())!.edit.title, 'corrected title');
    },
  );
  test(
    'an existing receipt prevents pending downgrade and keeps exact bytes',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      final pending = record(title: 'original', pending: true);
      await vault.write(pending);
      final before = Uint8List.fromList(store.values[vault.metadataKey]!);
      await expectLater(
        vault.resumeAfterAbsent(pending, stillAbsent: () async => false),
        throwsStateError,
      );
      expect(store.values[vault.metadataKey], before);
    },
  );
  test(
    'stale source approval cannot unseal a different pending draft',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      await vault.write(record(title: 'original', pending: true));
      var checked = false;
      await expectLater(
        vault.resumeAfterAbsent(
          record(title: 'different', pending: true),
          stillAbsent: () async {
            checked = true;
            return true;
          },
        ),
        throwsStateError,
      );
      expect(checked, isFalse);
      expect((await vault.read())!.pending, isTrue);
    },
  );
  test(
    'retirement during a fresh absence check prevents any subsequent write',
    () async {
      final gate = LocalDataMaintenance();
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(
        scope: scope,
        store: store,
        maintenance: gate,
      );
      final pending = record(title: 'original', pending: true);
      await vault.write(pending);
      final before = Uint8List.fromList(store.values[vault.metadataKey]!);
      await expectLater(
        vault.resumeAfterAbsent(
          pending,
          stillAbsent: () async {
            gate.retire();
            return true;
          },
        ),
        throwsStateError,
      );
      expect(store.values[vault.metadataKey], before);
    },
  );

  test(
    'retired space rejects reads writes and cleanup before touching bytes',
    () async {
      final maintenance = LocalDataMaintenance();
      await maintenance.exclusive(() async {
        maintenance.retire();
      });
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(
        scope: scope,
        store: store,
        maintenance: maintenance,
      );
      await expectLater(vault.read(), throwsA(isA<LocalStorageRetired>()));
      await expectLater(
        vault.write(record()),
        throwsA(isA<LocalStorageRetired>()),
      );
      await expectLater(
        vault.remove(creationKey: key),
        throwsA(isA<LocalStorageRetired>()),
      );
      expect(store.calls, 0);
    },
  );
  LocalArticleCreationLegacyBinding binding(String digest) =>
      LocalArticleCreationLegacyBinding(
        legacyKey:
            'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode([
              jsonEncode(['local', 'article']),
              null,
            ])))}',
        digest: digest,
        ciphertextSHA256: 'b' * 64,
      );
  test(
    'legacy provenance survives edits pending and binary cold reconstruction',
    () {
      final original = record(binding: binding('a' * 64));
      final edited = original.copy(
        edit: ComplexNoteEdit(
          title: 'new title',
          document: original.edit.document,
          labels: original.edit.labels,
        ),
        pending: true,
      );
      final reopened = LocalArticleCreationRecord.decode(edited.encode());
      expect(reopened.legacyBinding!.same(original.legacyBinding), isTrue);
      expect(reopened.edit.title, 'new title');
      expect(reopened.sameInput(edited), isTrue);
    },
  );
  test(
    'legacy binding cannot be replaced or dropped even before pending',
    () async {
      final store = MemoryBytes();
      final vault = LocalArticleCreationVault(scope: scope, store: store);
      final original = record(binding: binding('a' * 64));
      await vault.write(original);
      await expectLater(
        vault.write(record(binding: binding('c' * 64))),
        throwsStateError,
      );
      await expectLater(vault.write(record()), throwsStateError);
      expect(
        (await vault.read())!.legacyBinding!.same(original.legacyBinding),
        isTrue,
      );
    },
  );
  test(
    'binary metadata refuses invalid legacy purpose and unexpected provenance fields',
    () {
      final original = record(binding: binding('a' * 64)).encode();
      for (final patch in [
        {
          'legacyKey': 'account',
          'digest': 'a' * 64,
          'ciphertextSHA256': 'b' * 64,
        },
        {...binding('a' * 64).toJson(), 'body': 'not metadata'},
        {
          'legacyKey': binding('a' * 64).legacyKey,
          'digest': 'wrong',
          'ciphertextSHA256': 'b' * 64,
        },
      ]) {
        expect(
          () => LocalArticleCreationRecord.decode(
            changeMetadata(original, (m) => m['legacyBinding'] = patch),
          ),
          throwsFormatException,
        );
      }
    },
  );
}
