import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_backup_codec.dart';

LocalBackupFile declared(String path, List<int> bytes) => LocalBackupFile(
  path: path,
  bytes: bytes.length,
  sha256: sha256.convert(bytes).toString(),
);
LocalBackupManifest manifest(List<LocalBackupFile> files) =>
    LocalBackupManifest(
      id: 'a' * 32,
      createdAt: '2026-11-08T00:00:00.000Z',
      sqliteVersion: '3.42.0',
      tables: {for (final name in LocalBackupManifest.requiredTables) name: 0},
      files: files,
    );
Future<Uint8List> bytesOf(Stream<List<int>> source) async {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in source) {
    buffer.add(chunk);
  }
  return buffer.takeBytes();
}

Uint8List rawEnvelope(String json, [List<int> payload = const []]) {
  final metadata = utf8.encode(json);
  final header = ByteData(12);
  header.buffer.asUint8List().setRange(0, 8, ascii.encode('BSTKBK01'));
  header.setUint32(8, metadata.length, Endian.big);
  return Uint8List.fromList([
    ...header.buffer.asUint8List(),
    ...metadata,
    ...payload,
  ]);
}

Future<LocalBackupManifest> verify(List<int> bytes) =>
    LocalBackupCodec.decode(Stream.value(bytes), (_, body) async {
      await body.drain<void>();
    });

void main() {
  final db = [
    83,
    81,
    76,
    105,
    116,
    101,
  ]; // Envelope fixture, not a valid SQLite DB.
  final attachment = utf8.encode('\uFEFF完整原文\r\nemoji😀');
  final fileMap = {
    'database/content.db': db,
    'attachments/${'b' * 32}': attachment,
    'drive-blobs/${'c' * 32}.blob': [0, 255, 1, 2, 3],
  };
  final valid = manifest(
    fileMap.entries.map((e) => declared(e.key, e.value)).toList(),
  );

  test('fragmented framing preserves exact Unicode and binary bytes', () async {
    final wire = await bytesOf(
      LocalBackupCodec.encode(
        valid,
        (file) => Stream.value(fileMap[file.path]!),
      ),
    );
    final extracted = <String, List<int>>{};
    final checked = await LocalBackupCodec.decode(
      Stream.fromIterable(wire.map((byte) => [byte])),
      (file, body) async {
        extracted[file.path] = await bytesOf(body);
      },
    );
    expect(extracted, fileMap);
    expect(
      checked.totalBytes,
      fileMap.values.fold<int>(0, (n, b) => n + b.length),
    );
    expect(checked.tables.keys.toSet(), LocalBackupManifest.requiredTables);
    // Decoding this fixture proves framing and hashes, not SQLite validity.
  });

  test(
    'wrong magic, truncated header, manifest or body are rejected',
    () async {
      final wire = await bytesOf(
        LocalBackupCodec.encode(
          valid,
          (file) => Stream.value(fileMap[file.path]!),
        ),
      );
      for (final cut in [0, 7, 11, 15, wire.length - 1]) {
        await expectLater(verify(wire.sublist(0, cut)), throwsFormatException);
      }
      final wrong = Uint8List.fromList(wire)..[0] = 0;
      await expectLater(verify(wrong), throwsFormatException);
    },
  );

  test(
    'corrupted payload and undeclared trailing bytes are rejected',
    () async {
      final wire = await bytesOf(
        LocalBackupCodec.encode(
          valid,
          (file) => Stream.value(fileMap[file.path]!),
        ),
      );
      final changed = Uint8List.fromList(wire)..[wire.length - 1] ^= 1;
      await expectLater(verify(changed), throwsFormatException);
      await expectLater(verify([...wire, 0]), throwsFormatException);
    },
  );

  test(
    'duplicate JSON keys and alternative metadata encoding are rejected',
    () async {
      final json = jsonEncode(valid.toJson());
      final duplicate = json.replaceFirst(
        '"version":1',
        '"version":1,"version":1',
      );
      for (final bad in [duplicate, ' $json', json.replaceFirst(':', ': ')]) {
        var consumed = false;
        await expectLater(
          LocalBackupCodec.decode(Stream.value(rawEnvelope(bad)), (
            _,
            body,
          ) async {
            consumed = true;
            await body.drain<void>();
          }),
          throwsFormatException,
        );
        expect(consumed, isFalse);
      }
    },
  );

  test(
    'unknown version, schema, fields and missing tables fail before extraction',
    () async {
      for (final edit in <void Function(Map<String, Object>)>[
        (m) => m['version'] = 2,
        (m) => m['version'] = 1.0,
        (m) => m['schema'] = 14.0,
        (m) => m['schema'] = 999,
        (m) => m['sql'] = 'CREATE TRIGGER injected',
        (m) => m['tables'] = <String, int>{'notes': 1},
        (m) => m['files'] = [
          {...valid.files.first.toJson(), 'link': '/etc/passwd'},
        ],
      ]) {
        final raw = valid.toJson();
        edit(raw);
        var consumed = false;
        await expectLater(
          LocalBackupCodec.decode(Stream.value(rawEnvelope(jsonEncode(raw))), (
            _,
            body,
          ) async {
            consumed = true;
            await body.drain<void>();
          }),
          throwsFormatException,
        );
        expect(consumed, isFalse);
      }
    },
  );

  test('path escape, duplicate files and size limits are enforced', () {
    for (final path in [
      '/database/content.db',
      '../data',
      'attachments/..',
      'attachments/a/b',
      'attachments/a\\b',
      'attachments/a:stream',
      'attachments/a.',
      'unknown/a',
    ]) {
      expect(() => declared(path, []), throwsFormatException);
    }
    expect(
      () => manifest([valid.files.first, valid.files.first]),
      throwsFormatException,
    );
    expect(
      () => manifest([
        valid.files.first,
        declared('attachments/A', []),
        declared('attachments/a', []),
      ]),
      throwsFormatException,
    );
    expect(
      () => LocalBackupFile(
        path: 'database/content.db',
        bytes: 0,
        sha256: sha256.convert([]).toString(),
      ),
      throwsFormatException,
    );
    expect(
      () => LocalBackupFile(
        path: 'attachments/a',
        bytes: LocalBackupManifest.maxFileBytes + 1,
        sha256: 'f' * 64,
      ),
      throwsFormatException,
    );
    expect(
      () => manifest([
        for (var i = 0; i < 5; i++)
          LocalBackupFile(
            path: i == 0 ? 'database/content.db' : 'attachments/file$i',
            bytes: LocalBackupManifest.maxFileBytes,
            sha256: 'f' * 64,
          ),
      ]),
      throwsFormatException,
    );
  });

  test(
    'manifest length bound is checked before reading or opening files',
    () async {
      final header = ByteData(12);
      header.buffer.asUint8List().setRange(0, 8, ascii.encode('BSTKBK01'));
      header.setUint32(8, LocalBackupManifest.maxManifestBytes + 1, Endian.big);
      await expectLater(
        verify(header.buffer.asUint8List()),
        throwsFormatException,
      );
    },
  );

  test(
    'export rejects files changed after inventory hash/size check',
    () async {
      final only = manifest([
        declared('database/content.db', [1, 2, 3]),
      ]);
      for (final body in [
        [1, 2],
        [1, 2, 3, 4],
        [1, 2, 4],
      ]) {
        await expectLater(
          bytesOf(LocalBackupCodec.encode(only, (_) => Stream.value(body))),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'consumer cannot skip verification or silently cancel a partial file',
    () async {
      final wire = await bytesOf(
        LocalBackupCodec.encode(
          valid,
          (file) => Stream.value(fileMap[file.path]!),
        ),
      );
      await expectLater(
        LocalBackupCodec.decode(Stream.value(wire), (_, body) async {}),
        throwsStateError,
      );
      await expectLater(
        LocalBackupCodec.decode(Stream.value(wire), (_, body) async {
          await body.take(1).drain<void>();
        }),
        throwsStateError,
      );
    },
  );

  test('large source chunks produce bounded output chunks', () async {
    final body = List<int>.generate(
      LocalBackupCodec.chunkBytes * 3 + 7,
      (i) => i % 256,
    );
    final only = manifest([declared('database/content.db', body)]);
    final chunks = await LocalBackupCodec.encode(
      only,
      (_) => Stream.value(body),
    ).toList();
    expect(
      chunks.skip(2).every((c) => c.length <= LocalBackupCodec.chunkBytes),
      isTrue,
    );
    await verify(chunks.expand((c) => c).toList());
  });
  test(
    'verified wire metadata keeps its exact representation for retained hashes',
    () async {
      final original = valid.toJson();
      final reversed = {
        for (final entry in original.entries.toList().reversed)
          entry.key: entry.value,
      };
      final raw = jsonEncode(reversed);
      final payload = valid.files.expand((f) => fileMap[f.path]!).toList();
      Uint8List? seen;
      await LocalBackupCodec.decode(Stream.value(rawEnvelope(raw, payload)), (
        _,
        body,
      ) async {
        await body.drain<void>();
      }, onMetadata: (bytes) => seen = bytes);
      expect(utf8.decode(seen!), raw);
      expect(sha256.convert(seen!), sha256.convert(utf8.encode(raw)));
      expect(() => seen![0] = 0, throwsUnsupportedError);
    },
  );
}
