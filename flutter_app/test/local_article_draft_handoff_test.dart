import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/complex_recovery_vault.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/local_article_draft_handoff.dart';
import 'package:bookstark_flutter/core/local_article_draft_receipt.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

class _Bytes implements ComplexRecoveryBytesStore {
  final records = <String, Uint8List>{};
  int writes = 0;
  bool failBefore = false, failAfter = false;
  @override
  Future<Uint8List?> read(String key) async =>
      records[key] == null ? null : Uint8List.fromList(records[key]!);
  @override
  Future<void> write(String key, Uint8List value) async {
    writes++;
    if (failBefore) throw StateError('copy unavailable');
    records[key] = Uint8List.fromList(value);
    if (failAfter) throw StateError('copy receipt lost');
  }

  @override
  Future<void> remove(String key) async {
    records.remove(key);
  }
}

void main() {
  const scope =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  final namespace = jsonEncode(['local-generation-A', 'article']);
  late LocalDataMaintenance gate;
  late DraftVault legacy;
  late ComplexRecoveryVault recovery;
  late _Bytes bytes;
  late LocalArticleDraftHandoff bridge;
  late ComplexNote baseline, fresh;
  final preferences = <String, String>{}, deleted = <String>[];
  bool current = true, failMarker = false, failFlush = false;
  int flushes = 0;
  ComplexNote note(String source, {String title = 'Saved', int version = 1}) =>
      ComplexNote(
        scope: scope,
        id: 17,
        collection: 'article',
        title: title,
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          source,
        ),
        version: version,
        labels: ['base'],
      );
  setUp(() async {
    preferences.clear();
    deleted.clear();
    current = true;
    failMarker = false;
    failFlush = false;
    flushes = 0;
    gate = LocalDataMaintenance();
    bytes = _Bytes();
    legacy = DraftVault(
      namespace: namespace,
      maintenance: gate,
      readValue: (key) async => preferences[key],
      writeValue: (key, value) async {
        if (failMarker &&
            key.startsWith('bookstark.local-article-draft-handoff.')) {
          throw StateError('marker unavailable');
        }
        preferences[key] = value;
      },
      deleteValue: (key) async {
        deleted.add(key);
        preferences.remove(key);
      },
    );
    recovery = ComplexRecoveryVault(
      scope: scope,
      collection: 'article',
      kind: ComplexEditorKind.markdown,
      store: bytes,
      maintenance: gate,
    );
    baseline = note('# saved\r\n');
    fresh = baseline;
    bridge = LocalArticleDraftHandoff(
      legacy: legacy,
      expectedLegacyNamespace: namespace,
      recovery: recovery,
      maintenance: gate,
      readCurrent: (_) async => fresh,
      isCurrentScope: () => current,
      flushMarker: () async {
        flushes++;
        if (failFlush) throw StateError('not durable');
      },
    );
    await legacy.write(
      const Note(
        id: 17,
        title: 'Old draft title',
        content: '\ufeff# 原有文章草稿😀\r\n',
        labels: ['old'],
      ),
    );
  });
  LocalArticleDraftHandoff secured(Future<String?> Function(int) fingerprint) =>
      LocalArticleDraftHandoff(
        legacy: legacy,
        expectedLegacyNamespace: namespace,
        recovery: recovery,
        maintenance: gate,
        readCurrent: (_) async => fresh,
        isCurrentScope: () => current,
        fingerprintLegacyDraft: fingerprint,
        flushMarker: () async {
          flushes++;
          if (failFlush) throw StateError('not durable');
        },
      );
  LocalArticleDraftReceipt receipt() => LocalArticleDraftReceipt.parse(
    preferences.entries
        .singleWhere(
          (e) => e.key.startsWith(LocalArticleDraftReceipt.keyPrefix),
        )
        .value,
  );

  test(
    'explicit restore copies recovery first, stores only a digest receipt and preserves old bytes',
    () async {
      final original = Map<String, String>.from(preferences);
      final candidate = (await bridge.inspect(baseline))!;
      final record = await bridge.restore(candidate, baseline);
      expect(record.edit.document.source, '\ufeff# 原有文章草稿😀\r\n');
      expect((await recovery.read(17))!.encode(), record.encode());
      expect(bytes.writes, 1);
      for (final entry in original.entries) {
        expect(preferences[entry.key], entry.value);
      }
      final marker = preferences.entries
          .singleWhere((e) => !original.containsKey(e.key))
          .value;
      expect(marker, contains(candidate.digest));
      expect(marker, isNot(contains('Old draft title')));
      expect(marker, isNot(contains('原有文章')));
      expect(deleted, isEmpty);
      expect(await bridge.inspect(baseline), isNull);
      expect(await bridge.inspect(baseline, forceReview: true), isNotNull);
      expect(flushes, greaterThanOrEqualTo(2));
    },
  );
  test(
    'skip is explicit, durable and keeps the original draft available for review',
    () async {
      final candidate = (await bridge.inspect(baseline))!;
      await bridge.skip(candidate, baseline);
      expect(bytes.writes, 0);
      expect(await bridge.inspect(baseline), isNull);
      expect(
        (await bridge.inspect(baseline, forceReview: true))!.digest,
        candidate.digest,
      );
      expect((await legacy.read(17))!.title, 'Old draft title');
      expect(deleted, isEmpty);
    },
  );
  test('copy failure cannot mark the old draft handled', () async {
    final candidate = (await bridge.inspect(baseline))!;
    bytes.failBefore = true;
    await expectLater(bridge.restore(candidate, baseline), throwsStateError);
    expect(preferences.length, 1);
    expect(await bridge.inspect(baseline), isNotNull);
    expect(await recovery.read(17), isNull);
    expect(deleted, isEmpty);
  });
  test(
    'lost copy reply is read back before receipt retry and never replays the copy',
    () async {
      final candidate = (await bridge.inspect(baseline))!;
      bytes.failAfter = true;
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      expect(preferences.length, 1);
      bytes.failAfter = false;
      await bridge.restore(candidate, baseline);
      expect(bytes.writes, 1);
      expect(await bridge.inspect(baseline), isNull);
      expect((await legacy.read(17))!.content, candidate.edit.document.source);
    },
  );
  test(
    'marker or flush failure retains both sources and remains retryable',
    () async {
      final candidate = (await bridge.inspect(baseline))!;
      failMarker = true;
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      expect(
        (await recovery.read(17))!.edit.document.source,
        candidate.edit.document.source,
      );
      expect(preferences.length, 1);
      failMarker = false;
      failFlush = true;
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      await expectLater(bridge.inspect(baseline), throwsStateError);
      failFlush = false;
      await bridge.restore(candidate, baseline);
      expect(bytes.writes, 1);
      expect(await bridge.inspect(baseline), isNull);
      expect(deleted, isEmpty);
    },
  );
  test('another recovery, especially pending, is never overwritten', () async {
    final candidate = (await bridge.inspect(baseline))!;
    final other = ComplexRecoveryRecord.capture(
      baseline,
      ComplexNoteEdit(
        title: 'Other',
        document: ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          '# other',
        ),
        labels: [],
      ),
      pending: true,
    );
    await recovery.write(other);
    await expectLater(bridge.restore(candidate, baseline), throwsStateError);
    expect(bytes.writes, 1);
    expect((await recovery.read(17))!.encode(), other.encode());
    expect(preferences.length, 1);
  });
  test(
    'old draft or saved baseline changes after review block the handoff',
    () async {
      final candidate = (await bridge.inspect(baseline))!;
      await legacy.write(
        const Note(id: 17, title: 'Changed', content: '# changed'),
      );
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      expect(bytes.writes, 0);
      fresh = note('# newer', version: 2);
      final changed = (await bridge.inspect(baseline))!;
      await expectLater(
        bridge.skip(changed, baseline),
        throwsA(isA<ComplexNoteConflict>()),
      );
      expect(preferences.length, 1);
    },
  );
  test(
    'account generation and legacy namespace cannot cross the local handoff',
    () async {
      final candidate = (await bridge.inspect(baseline))!;
      current = false;
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      expect(bytes.writes, 0);
      expect(
        () => LocalArticleDraftHandoff(
          legacy: legacy,
          expectedLegacyNamespace: 'another-generation',
          recovery: recovery,
          maintenance: gate,
          readCurrent: (_) async => fresh,
          flushMarker: () async {},
          isCurrentScope: () => true,
        ),
        throwsArgumentError,
      );
      expect(deleted, isEmpty);
    },
  );

  test(
    'native fingerprint is captured after the durable recovery copy and original bytes are retained',
    () async {
      final original = preferences[legacy.metadataKey(17)];
      var calls = 0;
      bridge = secured((id) async {
        expect(id, 17);
        expect(bytes.writes, 1);
        calls++;
        return 'c' * 64;
      });
      final candidate = (await bridge.inspect(baseline))!;
      await bridge.restore(candidate, baseline);
      expect(receipt().version, 2);
      expect(receipt().ciphertextSHA256, 'c' * 64);
      expect(receipt().disposition, LocalArticleDraftDisposition.restored);
      expect(calls, 1);
      expect(preferences[legacy.metadataKey(17)], original);
      expect(deleted, isEmpty);
    },
  );

  test(
    'missing fingerprint cannot mark handled and an existing durable copy is not replayed',
    () async {
      String? fingerprint;
      bridge = secured((_) async => fingerprint);
      final candidate = (await bridge.inspect(baseline))!;
      final original = preferences[legacy.metadataKey(17)];
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      expect(bytes.writes, 1);
      expect(preferences.length, 1);
      expect(preferences[legacy.metadataKey(17)], original);
      fingerprint = 'c' * 64;
      await bridge.restore(candidate, baseline);
      expect(bytes.writes, 1);
      expect(receipt().ciphertextSHA256, fingerprint);
      expect(deleted, isEmpty);
    },
  );

  test(
    'version one receipt upgrades only after the reviewed old source matches',
    () async {
      final candidate = (await bridge.inspect(baseline))!;
      await bridge.skip(candidate, baseline);
      expect(receipt().version, 1);
      final original = preferences[legacy.metadataKey(17)];
      bridge = secured((_) async => 'c' * 64);
      expect(await bridge.inspect(baseline), isNull);
      expect(receipt().version, 2);
      expect(receipt().ciphertextSHA256, 'c' * 64);
      expect(preferences[legacy.metadataKey(17)], original);
      expect(bytes.writes, 0);
    },
  );

  test(
    'changed legacy source cannot be hidden by upgrading a stale version one receipt',
    () async {
      await bridge.skip((await bridge.inspect(baseline))!, baseline);
      final before = preferences.entries
          .singleWhere(
            (e) => e.key.startsWith(LocalArticleDraftReceipt.keyPrefix),
          )
          .value;
      await legacy.write(
        const Note(id: 17, title: 'New draft', content: '# different'),
      );
      var fingerprints = 0;
      bridge = secured((_) async {
        fingerprints++;
        return 'c' * 64;
      });
      expect(await bridge.inspect(baseline), isNotNull);
      expect(fingerprints, 0);
      expect(
        preferences.entries
            .singleWhere(
              (e) => e.key.startsWith(LocalArticleDraftReceipt.keyPrefix),
            )
            .value,
        before,
      );
      expect(bytes.writes, 0);
    },
  );

  test(
    'already saved identical draft is marked matched without copying or deleting its body',
    () async {
      await legacy.write(
        Note(
          id: baseline.id,
          title: baseline.title,
          content: baseline.document.source,
          labels: baseline.labels,
        ),
      );
      final original = preferences[legacy.metadataKey(17)];
      bridge = secured((_) async => 'c' * 64);
      expect(await bridge.inspect(baseline), isNull);
      expect(receipt().version, 2);
      expect(receipt().disposition, LocalArticleDraftDisposition.matched);
      expect(bytes.records, isEmpty);
      expect(preferences[legacy.metadataKey(17)], original);
      expect(deleted, isEmpty);
    },
  );

  test(
    'candidate is rechecked after the fingerprint await before receipt mutation',
    () async {
      bridge = secured((_) async {
        await legacy.write(
          const Note(
            id: 17,
            title: 'Changed while awaiting',
            content: '# later',
          ),
        );
        return 'c' * 64;
      });
      final candidate = (await bridge.inspect(baseline))!;
      await expectLater(bridge.restore(candidate, baseline), throwsStateError);
      expect(bytes.writes, 1);
      expect(
        preferences.keys.where(
          (k) => k.startsWith(LocalArticleDraftReceipt.keyPrefix),
        ),
        isEmpty,
      );
      expect(deleted, isEmpty);
    },
  );
}
