import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';

void main() {
  final values = <String, String>{};
  Future<void>? gate;
  HtmlCreationVault vault({
    bool local = true,
    int member = 1,
    String collection = 'note',
  }) => HtmlCreationVault(
    server: Uri.parse('https://same.invalid/database'),
    memberId: member,
    collection: collection,
    localDatabase: local,
    readValue: (k) async => values[k],
    writeValue: (k, v) async {
      await gate;
      values[k] = v;
    },
    deleteValue: (k) async {
      values.remove(k);
    },
  );
  HtmlCreationRecord record({bool pending = false, int? createdId}) =>
      HtmlCreationRecord(
        key: newHtmlCreationKey(),
        memberId: 1,
        collection: 'note',
        edit: HtmlNoteEdit(
          title: '',
          source: '<!doctype html>\r\n<p>草稿🧪</p>\r',
          labels: ['one,literal,label'],
        ),
        pending: pending,
        createdId: createdId,
      );
  setUp(() {
    values.clear();
    gate = null;
  });
  test(
    'creation key and complete ordinary draft survive restart while local/remote/member/type scopes stay separate',
    () async {
      final draft = record(pending: true, createdId: 7), v = vault();
      await v.write(draft);
      final restored = (await vault().read())!;
      expect(restored.key, draft.key);
      expect(restored.edit.source, draft.edit.source);
      expect(restored.edit.title, '');
      expect(restored.edit.labels, draft.edit.labels);
      expect(restored.createdId, 7);
      expect(restored.pending, true);
      expect(await vault(local: false).read(), isNull);
      expect(await vault(member: 2).read(), isNull);
      expect(await vault(collection: 'article').read(), isNull);
      await vault(local: false).remove();
      expect(await v.read(), isNotNull);
    },
  );
  test(
    'unknown fields including passwords are rejected and the original corrupt record remains for explicit handling',
    () async {
      final v = vault();
      await v.write(record());
      final key = values.keys.single;
      final data = jsonDecode(values[key]!) as Map<String, dynamic>;
      data['password'] = 'must not enter schema';
      values[key] = jsonEncode(data);
      await expectLater(v.read(), throwsFormatException);
      expect(values.containsKey(key), true);
      expect(() => record(createdId: 8), throwsFormatException);
      expect(
        () => HtmlCreationRecord(
          key: 'bad',
          memberId: 1,
          collection: 'note',
          edit: HtmlNoteEdit(title: 'x', source: '', labels: []),
          pending: false,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'later cross-instance removal waits for a delayed write and cannot resurrect a dismissed creation',
    () async {
      final delay = Completer<void>();
      gate = delay.future;
      final write = vault().write(record());
      await Future<void>.delayed(Duration.zero);
      final remove = vault().remove();
      delay.complete();
      await write;
      await remove;
      expect(values, isEmpty);
      expect(await vault().read(), isNull);
    },
  );
}
