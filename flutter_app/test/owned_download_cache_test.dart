import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as paths;
import 'package:bookstark_flutter/core/owned_download_cache.dart';

void main() {
  late Directory temporary;
  late OwnedDownloadCache cache;
  setUp(() async {
    final root = Directory(
      '${Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ?? '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files'}/device-cache45',
    );
    await root.create(recursive: true);
    temporary = await root.createTemp('case-');
    cache = OwnedDownloadCache(temporary);
  });
  tearDown(() async {
    await temporary.delete(recursive: true);
  });
  Future<Directory> orphan({
    String id = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    bool marked = true,
  }) async {
    await cache.inspect();
    final directory = await Directory(
      paths.join(temporary.path, 'bookstark-download-cache-v1', id),
    ).create();
    if (marked) {
      await File(
        paths.join(directory.path, '.bookstark-cache-owner-v1.json'),
      ).writeAsString(
        jsonEncode({
          'format': 1,
          'id': id,
          'kind': 'drive',
          'process': 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
        }),
      );
    }
    return directory;
  }

  test(
    'an active download is excluded and its creator closes only its entry',
    () async {
      final lease = await cache.create('drive');
      final data = File(paths.join(lease.directory.path, 'partial'));
      await data.writeAsBytes([1, 2, 3, 4]);
      final result = await cache.clear();
      expect(result.activeEntries, 1);
      expect(result.eligibleBytes, 0);
      expect(result.removedBytes, 0);
      expect(await data.readAsBytes(), [1, 2, 3, 4]);
      await lease.close();
      await lease.close();
      expect(await lease.directory.exists(), false);
    },
  );

  test(
    'explicit cleanup removes only validated inactive marked payload bytes',
    () async {
      final directory = await orphan();
      await File(
        paths.join(directory.path, 'file.png'),
      ).writeAsBytes([1, 2, 3]);
      final legacy = await Directory(
        paths.join(temporary.path, 'bookstark-drive-files', 'read-legacy'),
      ).create(recursive: true);
      final legacyFile = File(paths.join(legacy.path, 'partial'));
      await legacyFile.writeAsString('Unmarked previous download');
      final before = await cache.inspect();
      expect(before.eligibleEntries, 1);
      expect(before.eligibleBytes, 3);
      expect(before.removedBytes, 0);
      final result = await cache.clear();
      expect(result.removedBytes, 3);
      expect(result.failedEntries, 0);
      expect(await directory.exists(), false);
      expect(await legacyFile.readAsString(), 'Unmarked previous download');
    },
  );

  test(
    'unmarked and malformed entries are retained and reported as skipped',
    () async {
      final unmarked = await orphan(marked: false);
      final payload = File(paths.join(unmarked.path, 'partial'));
      await payload.writeAsString('keep');
      final malformed = await orphan(id: 'cccccccccccccccccccccccccccccccc');
      await File(
        paths.join(malformed.path, '.bookstark-cache-owner-v1.json'),
      ).writeAsString('x' * 513);
      final result = await cache.clear();
      expect(result.skippedEntries, 2);
      expect(result.removedBytes, 0);
      expect(await payload.readAsString(), 'keep');
      expect(await malformed.exists(), true);
    },
  );

  test('payload symlink cannot remove the target or alter the link', () async {
    final original = File(paths.join(temporary.path, 'protected-original'));
    await original.writeAsBytes([9, 8, 7]);
    final directory = await orphan();
    final link = await Link(
      paths.join(directory.path, 'partial'),
    ).create(original.path);
    final result = await cache.clear();
    expect(result.removedBytes, 0);
    expect(result.skippedEntries, 1);
    expect(await original.readAsBytes(), [9, 8, 7]);
    expect(await link.exists(), true);
  }, skip: Platform.isWindows);

  test('a directory symlink cannot escape the owned cache root', () async {
    await cache.inspect();
    final external = await Directory(
      paths.join(temporary.path, 'protected'),
    ).create();
    final original = File(paths.join(external.path, 'partial'));
    await original.writeAsString('keep');
    await Link(
      paths.join(
        temporary.path,
        'bookstark-download-cache-v1',
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
    ).create(external.path);
    final result = await cache.clear();
    expect(result.removedBytes, 0);
    expect(result.skippedEntries, 1);
    expect(await original.readAsString(), 'keep');
  }, skip: Platform.isWindows);

  test(
    'an unexpected file prevents recursive deletion of the whole entry',
    () async {
      final directory = await orphan();
      final original = File(paths.join(directory.path, 'user-document.md'));
      await original.writeAsString('Keep exact original');
      await File(
        paths.join(directory.path, 'partial'),
      ).writeAsString('download');
      final result = await cache.clear();
      expect(result.removedBytes, 0);
      expect(result.skippedEntries, 1);
      expect(await original.readAsString(), 'Keep exact original');
      expect(await File(paths.join(directory.path, 'partial')).exists(), true);
    },
  );

  test(
    'failed creator cleanup preserves unexpected content for explicit review',
    () async {
      final lease = await cache.create('remote');
      final original = File(paths.join(lease.directory.path, 'unexpected'));
      await original.writeAsString('keep');
      await expectLater(lease.close(), throwsA(isA<FileSystemException>()));
      final result = await cache.clear();
      expect(result.activeEntries, 0);
      expect(result.skippedEntries, 1);
      expect(await original.readAsString(), 'keep');
    },
  );

  test(
    'cache root symlink is rejected before looking at protected data',
    () async {
      final external = await Directory(
        paths.join(temporary.path, 'protected'),
      ).create();
      final original = File(paths.join(external.path, 'partial'));
      await original.writeAsString('keep');
      await Link(
        paths.join(temporary.path, 'bookstark-download-cache-v1'),
      ).create(external.path);
      await expectLater(cache.clear(), throwsA(isA<FileSystemException>()));
      expect(await original.readAsString(), 'keep');
    },
    skip: Platform.isWindows,
  );
}
