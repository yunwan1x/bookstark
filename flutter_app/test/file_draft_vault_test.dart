import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/file_draft_vault.dart';
import 'package:bookstark_flutter/core/drive_models.dart';
import 'package:bookstark_flutter/core/drive_repository.dart';

DriveNode source({
  int id = 7,
  String path = '资料/a.md',
  bool public = false,
  String publicPath = '',
}) => DriveNode(
  id: id,
  name: driveBasename(path),
  path: path,
  directory: false,
  size: 3,
  etag: 'fixture-hash',
  mime: 'text/markdown',
  modified: '',
  isPublic: public,
  publicPath: publicPath,
);
DriveText document(DriveNode file, [String text = '原文\r\n']) =>
    DriveText.decode(
      file,
      Uint8List.fromList([239, 187, 191, ...utf8.encode(text)]),
    );
void main() {
  test(
    'file drafts preserve real identity, BOM, baseline hash and pending save hash across secure storage instances',
    () async {
      final values = <String, String>{};
      FileDraftVault vault() => FileDraftVault(
        namespace: 'server-A/member-1',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final node = source(), doc = document(node), pending = 'a' * 64;
      await vault().write(
        FileDraftRecord.fromDocument(
          doc,
          '修改后\r\n',
          pendingHash: pending,
          changedOn: DateTime.utc(2026, 11, 4),
        ),
      );
      final read = (await vault().read(node))!;
      expect(read.content, '修改后\r\n');
      expect(read.hasBom, isTrue);
      expect(read.baseHash, doc.hash);
      expect(read.pendingHash, pending);
      expect(read.sameBase(doc), isTrue);
      expect(read.changedOn, DateTime.utc(2026, 11, 4));
      await vault().remove(node);
      expect(await vault().read(node), isNull);
    },
  );
  test(
    'server/member, path and actual node ID all isolate otherwise identical drafts',
    () async {
      final values = <String, String>{};
      FileDraftVault vault(String namespace) => FileDraftVault(
        namespace: namespace,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final node = source();
      await vault(
        'A/1',
      ).write(FileDraftRecord.fromDocument(document(node), 'private draft'));
      expect(await vault('A/2').read(node), isNull);
      expect(await vault('B/1').read(node), isNull);
      expect(await vault('A/1').read(source(id: 8)), isNull);
      expect(await vault('A/1').read(source(path: '别处/a.md')), isNull);
    },
  );
  test(
    'publication changes or changed source bytes invalidate the saved draft baseline',
    () {
      final node = source(),
          draft = FileDraftRecord.fromDocument(document(node), 'my edit');
      expect(draft.sameBase(document(node, '新版')), isFalse);
      expect(
        draft.sameBase(
          document(source(public: true, publicPath: 'files/a.md')),
        ),
        isFalse,
      );
    },
  );
  test(
    'unreadable records are retained, and rejected writes do not destroy an older valid draft',
    () async {
      String? stored;
      final vault = FileDraftVault(
        namespace: 'A/1',
        readValue: (_) async => stored,
        writeValue: (_, value) async {
          stored = value;
        },
        deleteValue: (_) async {
          stored = null;
        },
      );
      final node = source();
      stored = 'not JSON';
      await expectLater(vault.read(node), throwsFormatException);
      expect(stored, 'not JSON');
      await vault.write(FileDraftRecord.fromDocument(document(node), 'safe'));
      final valid = stored;
      expect(
        () => vault.write(
          FileDraftRecord.fromDocument(document(node), 'x' * maxDriveTextBytes),
        ),
        throwsFormatException,
      );
      expect(stored, valid);
      final row = jsonDecode(stored!) as Map;
      row['id'] = 8;
      stored = jsonEncode(row);
      await expectLater(vault.read(node), throwsFormatException);
      expect(stored, isNotNull);
    },
  );
  test(
    'queued writes and removal preserve order after a storage write failure',
    () async {
      final values = <String, String>{}, first = Completer<void>();
      var writes = 0;
      final vault = FileDraftVault(
        namespace: 'A/1',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          writes++;
          if (writes == 1) {
            await first.future;
            throw StateError('storage unavailable');
          }
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final node = source(), doc = document(node);
      final failed = vault.write(FileDraftRecord.fromDocument(doc, 'first'));
      final checked = expectLater(failed, throwsStateError);
      final second = vault.write(FileDraftRecord.fromDocument(doc, 'second'));
      final remove = vault.remove(node);
      first.complete();
      await checked;
      await second;
      await remove;
      expect(await vault.read(node), isNull);
      expect(writes, 2);
    },
  );
}
