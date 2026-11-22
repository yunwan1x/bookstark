import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';

void main() {
  test(
    'shared record queue preserves the pre-refactor encrypted draft key and payload',
    () async {
      final key =
          'bookstark.draft.v1.${base64Url.encode(utf8.encode(jsonEncode(['old-server', 7])))}';
      final storage = {
        key: jsonEncode({
          'version': 1,
          'title': 'Existing draft',
          'content': 'Keep original text',
          'labels': ['reading'],
          'updated_at': 123,
        }),
      };
      final vault = DraftVault(
        namespace: 'old-server',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      expect((await vault.read(7))!.content, 'Keep original text');
      await vault.write(
        const Note(id: 7, title: 'Updated', content: 'New text'),
      );
      expect(storage.keys, [key]);
      expect(jsonDecode(storage[key]!)['content'], 'New text');
    },
  );

  test(
    'drafts isolate server, account, document and new note; restore after recreation',
    () async {
      final storage = <String, String>{};
      DraftVault vault(String namespace) => DraftVault(
        namespace: namespace,
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      await vault(
        'https://a/|1',
      ).write(const Note(id: 7, title: '草稿', content: '正文', labels: ['阅读']));
      await vault(
        'https://a/|1',
      ).write(const Note(title: '新笔记', content: '未保存'));
      expect((await vault('https://a/|1').read(7))!.content, '正文');
      expect((await vault('https://a/|1').read(null))!.title, '新笔记');
      expect(await vault('https://a/|2').read(7), isNull);
      expect(await vault('https://b/|1').read(7), isNull);
      expect(await vault('https://a/|1').read(8), isNull);
    },
  );
  test(
    'protected notes are rejected before persistence; queued clear wins over earlier writes',
    () async {
      final storage = <String, String>{};
      final vault = DraftVault(
        namespace: 'local',
        readValue: (key) async => storage[key],
        writeValue: (key, value) async {
          await Future<void>.delayed(const Duration(milliseconds: 1));
          storage[key] = value;
        },
        deleteValue: (key) async {
          storage.remove(key);
        },
      );
      await expectLater(
        vault.write(
          const Note(
            id: 1,
            title: 'secret',
            content: 'private',
            isProtected: true,
            unlockPassword: 'password',
          ),
        ),
        throwsArgumentError,
      );
      expect(storage, isEmpty);
      final write = vault.write(
        const Note(id: 2, title: 'note', content: 'stale'),
      );
      final clear = vault.remove(2);
      await Future.wait([write, clear]);
      expect(await vault.read(2), isNull);
    },
  );
}
