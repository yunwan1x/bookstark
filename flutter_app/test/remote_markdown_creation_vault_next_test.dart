import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';

MarkdownCreationScope scope([int owner = 7]) => MarkdownCreationScope(
  server: Uri.parse('https://demo.example/root/'),
  memberId: owner,
  collection: 'note',
);
MarkdownCreationInput input([String content = '\ufeff# 完整😀\r\n- item\r\n']) =>
    MarkdownCreationInput(
      title: 'Draft',
      content: content,
      labels: ['travel', 'work'],
    );
void main() {
  test('full snapshot exact bytes, immutable labels and scope hash', () {
    final labels = ['travel'];
    final value = MarkdownCreationInput(
      title: 'Draft',
      content: '\ufeff😀\r\n',
      labels: labels,
    );
    labels.clear();
    final r = MarkdownCreationRecord.fresh(scope(), value);
    final actual = MarkdownCreationRecord.parse(
      jsonDecode(jsonEncode(r.toJson())),
      scope(),
    );
    expect(actual.input.content, '\ufeff😀\r\n');
    expect(actual.input.labels, ['travel']);
    expect(actual.fingerprint, r.fingerprint);
    expect(
      () => MarkdownCreationRecord.parse(r.toJson(), scope(8)),
      throwsFormatException,
    );
    final damaged = Map<String, Object?>.from(r.toJson())
      ..['input_hash'] = 'wrong';
    expect(
      () => MarkdownCreationRecord.parse(damaged, scope()),
      throwsFormatException,
    );
    final html = Map<String, Object?>.from(r.toJson())..['format'] = 'html';
    expect(
      () => MarkdownCreationRecord.parse(html, scope()),
      throwsFormatException,
    );
  });
  test('CAS across vault instances and explicit flush readback', () async {
    final values = <String, String>{};
    var flushes = 0;
    RemoteMarkdownCreationVault make() => RemoteMarkdownCreationVault(
      scope: scope(),
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
      flush: () async {
        flushes++;
      },
    );
    final a = make(),
        b = make(),
        r = MarkdownCreationRecord.fresh(scope(), input());
    await a.compareAndWrite(null, r, guard: () {});
    expect(flushes, 1);
    await expectLater(
      b.compareAndWrite(null, r, guard: () {}),
      throwsStateError,
    );
    expect((await b.read())!.fingerprint, r.fingerprint);
    await a.compareAndRemove(r, guard: () {});
    expect(await b.read(), isNull);
    expect(flushes, 2);
  });
  test(
    'applied delete and lost flush restores journal and reports failure',
    () async {
      final values = <String, String>{};
      var fail = false;
      final vault = RemoteMarkdownCreationVault(
        scope: scope(),
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
        flush: () async {
          if (fail) {
            fail = false;
            throw StateError('Lost flush');
          }
        },
      );
      final r = MarkdownCreationRecord.fresh(
        scope(),
        input(),
      ).copy(pending: true, knownId: 318);
      await vault.compareAndWrite(null, r, guard: () {});
      fail = true;
      await expectLater(
        vault.compareAndRemove(r, guard: () {}),
        throwsStateError,
      );
      expect((await vault.read())!.fingerprint, r.fingerprint);
    },
  );
  test('corrupt storage is not empty and unknown schema is blocking', () async {
    final values = <String, String>{};
    final vault = RemoteMarkdownCreationVault(
      scope: scope(),
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
      flush: () async {},
    );
    values[vault.metadataKey('new')] = '{"schema":99}';
    await expectLater(vault.read(), throwsFormatException);
    expect(values.length, 1);
  });
  test('scope retirement after write never reports durable success', () async {
    final values = <String, String>{};
    var current = true;
    final vault = RemoteMarkdownCreationVault(
      scope: scope(),
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
        current = false;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
      flush: () async {},
    );
    final r = MarkdownCreationRecord.fresh(scope(), input());
    await expectLater(
      vault.compareAndWrite(
        null,
        r,
        guard: () {
          if (!current) throw StateError('Retired');
        },
      ),
      throwsStateError,
    );
  });
}
