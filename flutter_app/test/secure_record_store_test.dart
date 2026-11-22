import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/secure_record_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reopened stores serialize old late writes before a newer value and readback',
    () async {
      final values = <String, String>{};
      final started = Completer<void>(), release = Completer<void>();
      SecureRecordStore store({bool delayed = false}) => SecureRecordStore(
        prefix: 'queue-test',
        namespace: 'late-owner',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          if (delayed) {
            started.complete();
            await release.future;
          }
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final old = store(delayed: true).writeRecord(1, 'old');
      await started.future;
      final newer = store().writeRecord(1, 'new');
      final observed = store().readRecord(1);
      release.complete();
      await old;
      await newer;
      expect(await observed, 'new');
      expect(values.values.single, 'new');
    },
  );
  test(
    'namespace ordering includes different record IDs and leaves key format unchanged',
    () async {
      final values = <String, String>{};
      final started = Completer<void>(), release = Completer<void>();
      final old = SecureRecordStore(
        prefix: 'queue-test',
        namespace: 'ids',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          started.complete();
          await release.future;
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      SecureRecordStore fresh() => SecureRecordStore(
        prefix: 'queue-test',
        namespace: 'ids',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final first = old.writeRecord(null, 'pending');
      await started.future;
      final remove = fresh().removeRecord(null),
          save = fresh().writeRecord(7, 'saved');
      release.complete();
      await first;
      await remove;
      await save;
      expect(await fresh().readRecord(null), isNull);
      expect(await fresh().readRecord(7), 'saved');
      expect(
        fresh().metadataKey(7),
        'queue-test.${base64Url.encode(utf8.encode(jsonEncode(['ids', 7])))}',
      );
    },
  );
  test('unrelated namespaces remain independent during a held write', () async {
    final values = <String, String>{};
    final started = Completer<void>(), release = Completer<void>();
    SecureRecordStore store(String namespace) => SecureRecordStore(
      prefix: 'queue-test',
      namespace: namespace,
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        if (namespace == 'blocked') {
          started.complete();
          await release.future;
        }
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    final pending = store('blocked').writeRecord(1, 'a');
    await started.future;
    try {
      await store('independent').writeRecord(1, 'b');
      expect(await store('independent').readRecord(1), 'b');
    } finally {
      release.complete();
      await pending;
    }
  });
  test('failed prior writer cannot poison a newer owner queue', () async {
    final values = <String, String>{};
    final old = SecureRecordStore(
      prefix: 'queue-test',
      namespace: 'failed',
      readValue: (key) async => values[key],
      writeValue: (_, _) async {
        throw StateError('failed old write');
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    await expectLater(old.writeRecord(1, 'old'), throwsStateError);
    final fresh = SecureRecordStore(
      prefix: 'queue-test',
      namespace: 'failed',
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    await fresh.writeRecord(1, 'new');
    expect(await fresh.readRecord(1), 'new');
  });
}
