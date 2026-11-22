import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_recovery_vault.dart';

HtmlNote note({bool protected = false}) => HtmlNote(
  metadata: HtmlNoteMetadata(
    id: 7,
    memberId: 4,
    collection: 'note',
    title: ' Original title ',
    version: 3,
    modifiedAt: 8,
    protected: protected,
  ),
  source: '<html>原文\r\n<script>x=1</script></html>\r\n',
  labels: ['old,label', ' 原标签 '],
  unlockPassword: protected ? ' SECRET_PASSWORD ' : null,
);
HtmlNoteEdit edit() => HtmlNoteEdit(
  title: '',
  source: '<html>草稿😀\r\n</html>',
  labels: ['draft,label'],
);

class Storage {
  final values = <String, String>{};
  int writes = 0;
  Future<void> Function()? wait;
  HtmlRecoveryVault vault({
    String server = 'https://example.test/mount',
    int member = 4,
    String collection = 'note',
    bool localDatabase = false,
  }) => HtmlRecoveryVault(
    server: Uri.parse(server),
    localDatabase: localDatabase,
    memberId: member,
    collection: collection,
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      writes++;
      await wait?.call();
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
}

void main() {
  test(
    'local and remote recovery cannot read or remove each other even with identical URI and identity',
    () async {
      final storage = Storage();
      final remote = storage.vault(),
          local = storage.vault(localDatabase: true);
      await remote.write(
        HtmlRecoveryRecord.capture(note(), edit(), pending: false),
      );
      expect(await local.read(7), isNull);
      await local.write(
        HtmlRecoveryRecord.capture(note(), edit(), pending: true),
      );
      expect(storage.values.length, 2);
      expect((await remote.read(7))!.pending, false);
      expect((await local.read(7))!.pending, true);
      await local.remove(7);
      expect(await local.read(7), isNull);
      expect((await remote.read(7))!.pending, false);
      expect(
        storage.values.keys.single,
        startsWith('bookstark.html-recovery.v1.'),
      );
    },
  );

  test(
    'normal draft roundtrip preserves exact original metadata, HTML and incomplete draft',
    () async {
      final s = Storage(), n = note(), d = edit();
      final v = s.vault();
      await v.write(HtmlRecoveryRecord.capture(n, d, pending: false));
      final r = (await v.read(7))!;
      expect(r.pending, false);
      expect(r.protected, false);
      expect(r.baseline!.metadata.title, n.metadata.title);
      expect(r.baseline!.source, n.source);
      expect(r.baseline!.labels, n.labels);
      expect(r.edit!.source, d.source);
      expect(r.edit!.title, '');
      expect(r.edit!.labels, d.labels);
      expect(r.baseline!.unlockPassword, isNull);
    },
  );
  test(
    'protected pending intent stores only identity and digests, never protected plaintext',
    () async {
      final s = Storage(), v = s.vault();
      final n = HtmlNote(
        metadata: const HtmlNoteMetadata(
          id: 7,
          memberId: 4,
          collection: 'note',
          title: 'SECRET_TITLE',
          version: 3,
          modifiedAt: 8,
          protected: true,
        ),
        source: 'SECRET_SOURCE',
        labels: ['SECRET_LABEL'],
        unlockPassword: 'SECRET_PASSWORD',
      );
      final d = HtmlNoteEdit(
        title: 'SECRET_NEW_TITLE',
        source: 'SECRET_NEW_SOURCE',
        labels: ['SECRET_NEW_LABEL'],
      );
      await v.write(HtmlRecoveryRecord.capture(n, d, pending: true));
      expect(s.values.values.single, isNot(contains('SECRET')));
      final r = (await v.read(7))!;
      expect(r.baseline, isNull);
      expect(r.edit, isNull);
      expect(r.pending, true);
      expect(
        r.matchesCurrent(
          HtmlNote(
            metadata: const HtmlNoteMetadata(
              id: 7,
              memberId: 4,
              collection: 'note',
              title: 'SECRET_NEW_TITLE',
              version: 4,
              modifiedAt: 9,
              protected: true,
            ),
            source: d.source,
            labels: d.labels,
          ),
        ),
        true,
      );
    },
  );
  test(
    'ever protected and ephemeral password prevent ordinary draft persistence',
    () async {
      expect(
        () => HtmlRecoveryRecord.capture(
          note(protected: true),
          edit(),
          pending: false,
        ),
        throwsStateError,
      );
      expect(
        () => HtmlRecoveryRecord.capture(
          note(),
          edit(),
          pending: false,
          everProtected: true,
        ),
        throwsStateError,
      );
      final r = HtmlRecoveryRecord.capture(
        note(),
        edit(),
        pending: true,
        everProtected: true,
      );
      expect(r.edit, isNull);
      expect(r.baseline, isNull);
    },
  );
  test(
    'server mount, owner, collection and HTML namespace isolate records',
    () async {
      final s = Storage(), v = s.vault();
      await v.write(HtmlRecoveryRecord.capture(note(), edit(), pending: true));
      for (final other in [
        s.vault(server: 'https://example.test/other'),
        s.vault(server: 'http://example.test/mount'),
        s.vault(member: 5),
        s.vault(collection: 'article'),
      ]) {
        expect(await other.read(7), isNull);
      }
      expect(s.values.keys.single, startsWith('bookstark.html-recovery.v1.'));
      expect(
        () => s
            .vault(member: 5)
            .write(HtmlRecoveryRecord.capture(note(), edit(), pending: true)),
        throwsFormatException,
      );
    },
  );
  test(
    'tampered source and identity fail closed without removing evidence',
    () async {
      final s = Storage(), v = s.vault();
      await v.write(HtmlRecoveryRecord.capture(note(), edit(), pending: true));
      final key = s.values.keys.single, original = s.values.values.single;
      var row = jsonDecode(original) as Map<String, dynamic>;
      (row['edit'] as Map)['source'] = 'changed';
      s.values[key] = jsonEncode(row);
      await expectLater(v.read(7), throwsFormatException);
      expect(s.values.containsKey(key), true);
      row = jsonDecode(original) as Map<String, dynamic>;
      row['member_id'] = 5;
      s.values[key] = jsonEncode(row);
      await expectLater(v.read(7), throwsFormatException);
    },
  );
  test(
    'protected record rejects injected plaintext and unknown secret fields',
    () async {
      final s = Storage(), v = s.vault();
      await v.write(
        HtmlRecoveryRecord.capture(
          note(protected: true),
          edit(),
          pending: true,
        ),
      );
      final key = s.values.keys.single, original = s.values.values.single;
      for (final field in ['edit', 'baseline', 'password']) {
        final row = jsonDecode(original) as Map<String, dynamic>;
        row[field] = {'source': 'SECRET'};
        s.values[key] = jsonEncode(row);
        await expectLater(v.read(7), throwsFormatException);
      }
    },
  );
  test('oversized draft is rejected before secure storage write', () async {
    final s = Storage(), v = s.vault();
    expect(
      () => v.write(
        HtmlRecoveryRecord.capture(
          note(),
          HtmlNoteEdit(
            title: 'title',
            source: 'x' * (5 * 1024 * 1024 + 1),
            labels: [],
          ),
          pending: true,
        ),
      ),
      throwsFormatException,
    );
    expect(s.writes, 0);
  });
  test(
    'pending intent has no fabricated receipts; ordered removal cannot resurrect draft',
    () async {
      final s = Storage(), v = s.vault(), gate = Completer<void>();
      s.wait = () => gate.future;
      final write = v.write(
        HtmlRecoveryRecord.capture(note(), edit(), pending: true),
      );
      final remove = s.vault().remove(7);
      gate.complete();
      await write;
      await remove;
      expect(await v.read(7), isNull);
      s.wait = null;
      await v.write(HtmlRecoveryRecord.capture(note(), edit(), pending: true));
      expect(s.values.values.single, isNot(contains('receipt')));
      expect((await v.read(7))!.pending, true);
    },
  );
}
