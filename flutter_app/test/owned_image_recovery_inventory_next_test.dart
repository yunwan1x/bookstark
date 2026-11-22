import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_journal.dart';

void main() {
  String opaque(String owner, String document) =>
      OwnedComplexImageUploadJournal.keyPrefix +
      base64Url.encode(utf8.encode(jsonEncode([owner, document])));
  const a = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const b = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const c = 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';
  LocalRecoveryInventory inventory(
    List<String> secure, {
    List<String> html = const [],
  }) => LocalRecoveryInventory(
    maintenance: LocalDataMaintenance(),
    localNamespaces: {'local'},
    preferencesMetadata: () async => {
      'format': 1,
      'secureKeys': secure,
      'htmlKeys': html,
      'overflow': false,
      'valuesIncluded': false,
    },
    complexMetadata: () async => {
      'format': 1,
      'keys': <String>[],
      'unknownFiles': 0,
      'activeTransfers': 0,
      'overflow': false,
      'valuesIncluded': false,
    },
    readArticleReceipt: (_) async => throw StateError('Must not read values'),
    readArticleCreationReceipt: (_) async =>
        throw StateError('Must not read values'),
    fingerprintArticleDraft: (_) async =>
        throw StateError('Must not read values'),
    fingerprintArticleCreationDraft: (_) async =>
        throw StateError('Must not read values'),
  );
  test(
    'all opaque account owners remain blocking without value reads',
    () async {
      final result = await inventory([opaque(a, b), opaque(c, b)]).read();
      expect(result.references.map((r) => r.kind), [
        'owned-image-upload',
        'owned-image-upload',
      ]);
      expect(result.references.map((r) => r.namespace), [a, c]);
      expect(result.references.map((r) => r.recordId), [b, b]);
      expect(() => result.requireClear(), throwsA(isA<PendingLocalRecovery>()));
    },
  );
  test('malformed key remains unknown blocking', () async {
    final result = await inventory([
      '${OwnedComplexImageUploadJournal.keyPrefix}broken',
    ]).read();
    expect(result.needsAttention, true);
    expect(result.references, isEmpty);
    expect(() => result.requireClear(), throwsA(isA<PendingLocalRecovery>()));
  });
  test('wrong storage is retained as unknown rather than accepted', () async {
    final result = await inventory([], html: [opaque(a, b)]).read();
    expect(result.needsAttention, true);
    expect(result.references, isEmpty);
  });
  test('unhashed account or document identity is never accepted', () async {
    final result = await inventory([
      opaque('https://do-not-accept.invalid', b),
      opaque(a, '7'),
    ]).read();
    expect(result.needsAttention, true);
    expect(result.references, isEmpty);
  });
}
