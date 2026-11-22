import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_data_maintenance.dart';
import 'package:bookstark_flutter/core/local_recovery_inventory.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

Map<String, Object> prefs({
  List<String> keys = const [],
  List<String> html = const [],
  bool overflow = false,
}) => {
  'format': 1,
  'secureKeys': keys,
  'htmlKeys': html,
  'overflow': overflow,
  'valuesIncluded': false,
};
Map<String, Object> complex({
  List<String> keys = const [],
  int unknown = 0,
  int active = 0,
  bool overflow = false,
}) => {
  'format': 1,
  'keys': keys,
  'unknownFiles': unknown,
  'activeTransfers': active,
  'overflow': overflow,
  'valuesIncluded': false,
};
String key(String prefix, String namespace, Object? id) =>
    '$prefix.${base64Url.encode(utf8.encode(jsonEncode([namespace, id])))}';
LocalRecoveryInventory inventory(
  Map<String, Object> a,
  Map<String, Object> b, {
  Set<String> namespaces = const {'local'},
}) => LocalRecoveryInventory(
  maintenance: LocalDataMaintenance(),
  localNamespaces: namespaces,
  preferencesMetadata: () async => a,
  complexMetadata: () async => b,
);

void main() {
  test('empty supported native metadata allows local preflight', () async {
    final summary = await inventory(prefs(), complex()).read();
    expect(summary.needsAttention, isFalse);
    expect(summary.requireClear, returnsNormally);
  });

  test(
    'only local nested drafts and local HTML are included, with source store',
    () async {
      final local = key(
        'bookstark.draft.v1',
        jsonEncode(['local', 'article']),
        7,
      );
      final remote = key(
        'bookstark.draft.v1',
        jsonEncode(['https://server.test', 1]),
        9,
      );
      final html = key(
        'bookstark.local-html-recovery.v1',
        jsonEncode(['https://local.invalid/owned', 1, 'note', 'html']),
        8,
      );
      final summary = await inventory(
        prefs(keys: [local, remote], html: [html]),
        complex(),
      ).read();
      expect(summary.references.map((r) => r.kind), ['note', 'html']);
      expect(summary.references.map((r) => r.store), ['secure', 'html']);
      expect(summary.references.map((r) => r.recordId), [7, 8]);
      expect(
        () => summary.requireClear(),
        throwsA(isA<PendingLocalRecovery>()),
      );
    },
  );

  test(
    'ordinary drafts accidentally stored in HTML preferences are retained',
    () async {
      final local = key('bookstark.task-draft.v1', 'local', 1);
      final summary = await inventory(prefs(html: [local]), complex()).read();
      expect(summary.references.single.store, 'html');
      expect(summary.references.single.kind, 'task');
    },
  );

  test(
    'hashed chapter journal binds known local generation namespaces',
    () async {
      final generation = 'local-generation:${'a' * 32}';
      String document(String scope) =>
          'bookstark.document-create.v1.${sha256.convert(utf8.encode(scope))}';
      final summary = await inventory(
        prefs(
          keys: [
            document('local'),
            document(generation),
            document(jsonEncode(['https://server.test', 1])),
          ],
        ),
        complex(),
        namespaces: {'local', generation},
      ).read();
      expect(summary.references.map((r) => r.namespace), ['local', generation]);
      expect(
        summary.unknown,
        1,
      ); // Unmatched hashed scope cannot be classified safely.
      expect(
        summary.references.every((r) => r.kind == 'document-create'),
        isTrue,
      );
    },
  );

  test(
    'malformed, orphan and unknown local records block without deletion',
    () async {
      final original = [
        'bookstark.local-unknown.v9.owned',
        'bookstark.local-html-recovery.v1.invalid!',
        'bookstark.document-create.v1.invalid',
      ];
      final summary = await inventory(prefs(keys: original), complex()).read();
      expect(summary.unknown, 3);
      expect(summary.needsAttention, isTrue);
      expect(original, hasLength(3));
    },
  );

  test(
    'complex pending files, transfers, unknown files and overflow each block',
    () async {
      for (final native in [
        complex(keys: ['b' * 64]),
        complex(active: 1),
        complex(unknown: 1),
        complex(overflow: true),
      ]) {
        final summary = await inventory(prefs(), native).read();
        expect(summary.needsAttention, isTrue);
        expect(
          () => summary.requireClear(),
          throwsA(isA<PendingLocalRecovery>()),
        );
      }
      expect(
        (await inventory(
          prefs(overflow: true),
          complex(),
        ).read()).needsAttention,
        isTrue,
      );
    },
  );

  test(
    'unsupported, duplicate, oversized or body-bearing metadata cannot pass',
    () async {
      final local = key('bookstark.draft.v1', 'local', 1);
      for (final native in <Map<String, Object>>[
        {...prefs(), 'format': 2},
        {...prefs(), 'format': 1.0},
        {...prefs(), 'valuesIncluded': true},
        {
          ...prefs(),
          'values': {'mustNotBeAccepted': 'body'},
        },
        prefs(keys: [local, local]),
        prefs(keys: List.generate(4097, (i) => 'owned$i')),
      ]) {
        await expectLater(
          inventory(native, complex()).read(),
          throwsFormatException,
        );
      }
      await expectLater(
        inventory(prefs(), complex(keys: ['not-a-hash'])).read(),
        throwsFormatException,
      );
    },
  );

  test(
    'inventory waits for already queued secure writes before querying native',
    () async {
      final gate = LocalDataMaintenance();
      final entered = Completer<void>(), release = Completer<void>();
      final values = <String, String>{};
      final vault = SecureRecordStore(
        prefix: 'bookstark.draft.v1',
        namespace: 'local',
        maintenance: gate,
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          entered.complete();
          await release.future;
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final writing = vault.writeRecord(7, 'retained source');
      await entered.future;
      var nativeCalled = false;
      final scan = LocalRecoveryInventory(
        maintenance: gate,
        localNamespaces: {'local'},
        preferencesMetadata: () async {
          nativeCalled = true;
          return prefs(keys: values.keys.toList());
        },
        complexMetadata: () async => complex(),
      ).read();
      await Future<void>.value();
      expect(nativeCalled, isFalse);
      release.complete();
      await writing;
      final summary = await scan;
      expect(summary.references.single.recordId, 7);
      expect(values.values.single, 'retained source');
    },
  );
}
