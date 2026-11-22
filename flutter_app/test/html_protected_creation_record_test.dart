import 'dart:convert';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_protected_creation_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const key = '0123456789abcdef0123456789abcdef';
  final edit = HtmlNoteEdit(
    title: 'private title sentinel',
    source: '<p>private body sentinel</p>',
    labels: ['private label sentinel'],
  );
  HtmlProtectedCreationRecord sealed() => HtmlProtectedCreationRecord.seal(
    key: key,
    memberId: 3,
    collection: 'note',
    edit: edit,
    candidateId: 71,
  );
  test(
    'sealed candidate has only digest and never fabricates a POST receipt',
    () {
      final record = HtmlProtectedCreationRecord.parse(sealed().toJson());
      expect(record.createdId, isNull);
      expect(record.candidateId, 71);
      expect(record.inputDigest, htmlCreationInputDigest(edit));
      final encoded = jsonEncode(record.toJson());
      for (final text in [
        'private title sentinel',
        'private body sentinel',
        'private label sentinel',
        'password',
      ]) {
        expect(encoded, isNot(contains(text)));
      }
      for (final extra in ['title', 'source', 'labels', 'password']) {
        expect(
          () => HtmlProtectedCreationRecord.parse({
            ...record.toJson(),
            extra: 'secret',
          }),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'server vault atomically replaces plaintext record and reads protected variant',
    () async {
      final values = <String, String>{};
      final vault = HtmlCreationVault(
        server: Uri.parse('https://books.example/mount'),
        memberId: 3,
        collection: 'note',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      await vault.write(
        HtmlCreationRecord(
          key: key,
          memberId: 3,
          collection: 'note',
          edit: edit,
          pending: true,
        ),
      );
      expect(values.values.single, contains('private body sentinel'));
      await vault.writeProtected(sealed());
      expect(values.length, 1);
      expect(values.values.single, isNot(contains('private')));
      final record = await vault.readRecovery();
      expect(record, isA<HtmlProtectedCreationRecord>());
      await expectLater(vault.read(), throwsFormatException);
      await vault.remove();
      expect(values, isEmpty);
    },
  );
  test(
    'local and wrong-owner vaults reject protected server records before writing',
    () {
      var writes = 0;
      HtmlCreationVault vault({bool local = false, int member = 3}) =>
          HtmlCreationVault(
            server: Uri.parse('https://books.example'),
            memberId: member,
            collection: 'note',
            localDatabase: local,
            readValue: (_) async => null,
            writeValue: (_, _) async {
              writes++;
            },
            deleteValue: (_) async {},
          );
      expect(
        () => vault(local: true).writeProtected(sealed()),
        throwsFormatException,
      );
      expect(
        () => vault(member: 4).writeProtected(sealed()),
        throwsFormatException,
      );
      expect(writes, 0);
    },
  );
  test(
    'known receipt and candidate remain separate under strict schema validation',
    () {
      final raw = {...sealed().toJson(), 'created_id': 9};
      final record = HtmlProtectedCreationRecord.parse(raw);
      expect(record.createdId, 9);
      expect(record.candidateId, 71);
      for (final change in [
        {'pending': false},
        {'protected': false},
        {'input_digest': 'bad'},
        {'candidate_id': 0},
      ]) {
        expect(
          () => HtmlProtectedCreationRecord.parse({...raw, ...change}),
          throwsFormatException,
        );
      }
    },
  );
}
