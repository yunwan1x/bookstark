import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_index.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late Directory staging;
  late File source;
  late Uint8List good;
  late String receipt;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('legacy-zip-stage-');
    staging = await Directory('${root.path}/staging').create();
    source = File('${root.path}/source.zip');
    good = await File('test/fixtures/legacy_zip/go-export.zip').readAsBytes();
    await source.writeAsBytes(good);
    receipt = sha256.convert(good).toString();
    await File('${staging.path}/existing-user-file').writeAsString('preserve');
  });
  tearDown(() async => root.delete(recursive: true));
  Future<int> space() async => 4 * 1024 * 1024 * 1024;
  Future<LegacyZipStage> inspect({
    String? expected,
    Future<int> Function()? availableBytes,
    bool Function()? cancelled,
  }) => LegacyZipStage.inspect(
    source,
    privateParent: staging,
    expectedSha256: expected ?? receipt,
    availableBytes: availableBytes ?? space,
    isCancelled: cancelled,
  );
  Future<void> expectClean() async {
    expect(
      (await staging.list().toList()).map(
        (entry) => entry.uri.pathSegments.last,
      ),
      ['existing-user-file'],
    );
    expect(
      await File('${staging.path}/existing-user-file').readAsString(),
      'preserve',
    );
  }

  test(
    'actual Go deflate and store payloads retain exact body and attachment',
    () async {
      final result = await inspect();
      expect(result.sourceSha256, receipt);
      expect(result.sourceBytes, good.length);
      expect(result.files.keys, [
        'manifest.json',
        'blogs.json',
        'uploads/资料.txt',
      ]);
      final bodyFile = result.files['blogs.json']!;
      final body = jsonDecode(await bodyFile.file.readAsString()) as List;
      expect((body.single as Map)['blog_content'], '\uFEFF# text\r\n');
      final attachment = result.files['uploads/资料.txt']!;
      expect(await attachment.file.readAsString(), 'exact attachment\r\n');
      for (final entry in result.files.values) {
        expect(entry.file.parent.path, result.directory.path);
        expect(entry.file.uri.pathSegments.last, startsWith('entry-'));
        expect(await entry.file.length(), entry.bytes);
        expect(
          sha256.convert(await entry.file.readAsBytes()).toString(),
          entry.sha256Hex,
        );
      }
    },
  );

  test('a mismatched source receipt creates no stage', () async {
    await expectLater(inspect(expected: '0' * 64), throwsFormatException);
    await expectClean();
  });

  test(
    'stored corruption passes structural inspection but fails payload CRC',
    () async {
      final index = await LegacyZipIndex.read(source);
      good[index.entries.last.dataOffset] ^= 1;
      await source.writeAsBytes(good);
      receipt = sha256.convert(good).toString();
      await expectLater(inspect(), throwsFormatException);
      await expectClean();
    },
  );

  test('truncated or corrupt deflate cannot publish partial stage', () async {
    final index = await LegacyZipIndex.read(source);
    good[index.entries.first.dataOffset] = 0xff;
    await source.writeAsBytes(good);
    receipt = sha256.convert(good).toString();
    await expectLater(inspect(), throwsA(anything));
    await expectClean();
  });

  test(
    'false inflated size is stopped independently of directory limits',
    () async {
      final index = await LegacyZipIndex.read(source);
      final entry = index.entries.first;
      final bytes = ByteData.sublistView(good);
      var central = 0;
      while (bytes.getUint32(central, Endian.little) != 0x02014b50) {
        central++;
      }
      bytes.setUint32(central + 24, 1, Endian.little);
      bytes.setUint32(entry.recordEnd - 4, 1, Endian.little);
      await source.writeAsBytes(good);
      receipt = sha256.convert(good).toString();
      await expectLater(inspect(), throwsFormatException);
      await expectClean();
    },
  );

  test(
    'cancellation after staging begins removes only its own random child',
    () async {
      await expectLater(
        inspect(
          cancelled: () =>
              staging.listSync().any((entry) => entry is Directory),
        ),
        throwsA(isA<LegacyZipStageCancelled>()),
      );
      await expectClean();
    },
  );

  test(
    'insufficient initial space does not allocate stage or alter source',
    () async {
      await expectLater(
        inspect(availableBytes: () async => 128 * 1024 * 1024),
        throwsA(isA<LocalBackupSpaceUnavailable>()),
      );
      await expectClean();
      expect(sha256.convert(await source.readAsBytes()).toString(), receipt);
    },
  );

  test(
    'source replacement during inspection never yields an accepted stage',
    () async {
      var calls = 0;
      await expectLater(
        inspect(
          availableBytes: () async {
            if (++calls == 1) {
              final changed = Uint8List.fromList(good);
              // Alter the archive comment length so this source no longer matches
              // the SAF-copy receipt, without touching any staged payload.
              changed[changed.length - 1] = 1;
              await source.writeAsBytes(changed);
            }
            return space();
          },
        ),
        throwsFormatException,
      );
      await expectClean();
    },
  );
}
