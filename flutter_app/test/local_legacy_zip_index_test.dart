import 'dart:io';
import 'dart:typed_data';

import 'package:bookstark_flutter/core/local_legacy_zip_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporary;
  late Uint8List good;
  var serial = 0;
  setUpAll(() async {
    good = await File('test/fixtures/legacy_zip/go-export.zip').readAsBytes();
  });
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('legacy-zip-index-');
  });
  tearDown(() async => temporary.delete(recursive: true));

  Future<LegacyZipIndex> inspect(
    List<int> bytes, {
    LegacyZipLimits limits = const LegacyZipLimits(),
  }) async {
    final file = File('${temporary.path}/input-${serial++}.zip');
    await file.writeAsBytes(bytes, flush: true);
    return LegacyZipIndex.read(file, limits: limits);
  }

  test('genuine Go export signed descriptors, UTF8 and both methods', () async {
    final index = await inspect(good);
    expect(index.entries.map((entry) => entry.name), [
      'manifest.json',
      'blogs.json',
      'uploads/',
      'uploads/资料.txt',
    ]);
    expect(index.entries.first.flags & 8, 8);
    expect(index.entries.map((entry) => entry.method).toSet(), {0, 8});
    expect(index.entries[2].isDirectory, isTrue);
    expect(index.totalBytes, greaterThan(50));
    expect(index.archiveBytes, good.length);
    expect(() => index.entries.clear(), throwsUnsupportedError);
  });

  test(
    'truncations and trailing garbage never become an empty archive',
    () async {
      for (final length in [0, 21, 30, good.length - 1, good.length - 22]) {
        await expectLater(
          inspect(good.sublist(0, length)),
          throwsFormatException,
        );
      }
      await expectLater(inspect([...good, 0]), throwsFormatException);
    },
  );

  test('archive, directory, name, entry and aggregate limits', () async {
    for (final limit in [
      LegacyZipLimits(maxArchiveBytes: good.length - 1),
      const LegacyZipLimits(maxCentralBytes: 20),
      const LegacyZipLimits(maxEntries: 3),
      const LegacyZipLimits(maxNameBytes: 5),
      const LegacyZipLimits(maxEntryBytes: 10),
      const LegacyZipLimits(maxTotalBytes: 50),
    ]) {
      await expectLater(inspect(good, limits: limit), throwsFormatException);
    }
    await expectLater(
      inspect(good, limits: const LegacyZipLimits(maxEntries: 0)),
      throwsArgumentError,
    );
  });

  test(
    'encrypted, unsupported methods, ZIP64 and multi-disk rejected',
    () async {
      final central = _signature(good, 0x02014b50);
      final end = good.length - 22;
      for (final patch in <void Function(ByteData)>[
        (data) => data.setUint16(central + 8, 1, Endian.little),
        (data) => data.setUint16(central + 10, 99, Endian.little),
        (data) => data.setUint16(end + 4, 1, Endian.little),
        (data) => data.setUint16(end + 10, 65535, Endian.little),
        (data) => data.setUint32(central + 24, 0xffffffff, Endian.little),
        (data) => data.setUint32(central + 42, 0xffffffff, Endian.little),
      ]) {
        final bytes = Uint8List.fromList(good);
        patch(ByteData.sublistView(bytes));
        await expectLater(inspect(bytes), throwsFormatException);
      }
    },
  );

  test(
    'symlinks and other Unix special modes rejected before inflation',
    () async {
      final central = _signature(good, 0x02014b50);
      for (final mode in [0xa000, 0x1000, 0x6000, 0x4000]) {
        final bytes = Uint8List.fromList(good);
        ByteData.sublistView(
          bytes,
        ).setUint32(central + 38, mode << 16, Endian.little);
        await expectLater(inspect(bytes), throwsFormatException);
      }
    },
  );

  test('local name and descriptor must match directory exactly', () async {
    final index = await inspect(good);
    final entry = index.entries.first;
    for (final offset in [
      entry.recordOffset + 30,
      entry.recordEnd - 12,
      entry.recordEnd - 8,
      entry.recordEnd - 4,
    ]) {
      final bytes = Uint8List.fromList(good);
      bytes[offset] ^= 1;
      await expectLater(inspect(bytes), throwsFormatException);
    }
    final placeholder = Uint8List.fromList(good);
    ByteData.sublistView(placeholder).setUint32(14, 42, Endian.little);
    await expectLater(inspect(placeholder), throwsFormatException);
  });

  test(
    'unsafe paths, case aliases and duplicate file/directory names',
    () async {
      final index = await inspect(good);
      final central = _signature(good, 0x02014b50);
      for (final replacement in [
        '../ifest.json',
        '/anifest.json',
        'C:ni fest.jsn',
        'man\\fest.json',
      ]) {
        expect(replacement.length, 13);
        final bytes = Uint8List.fromList(good);
        bytes.setRange(30, 43, replacement.codeUnits);
        bytes.setRange(central + 46, central + 59, replacement.codeUnits);
        await expectLater(inspect(bytes), throwsFormatException);
      }
      expect(index.entries[1].name.length, 10);
      final bytes = Uint8List.fromList(good);
      final secondCentral = _nextCentral(good, central);
      const alias = 'BLOGS.JSON';
      bytes.setRange(
        index.entries[1].recordOffset + 30,
        index.entries[1].recordOffset + 40,
        alias.codeUnits,
      );
      bytes.setRange(secondCentral + 46, secondCentral + 56, alias.codeUnits);
      // Case changes alone are legal; collisions are checked separately by
      // changing a same-length synthetic ZIP below.
      expect((await inspect(bytes)).entries[1].name, alias);
    },
  );

  test('genuine Go case aliases and parent-file collisions rejected', () async {
    for (final name in ['case-alias.zip', 'parent-file.zip']) {
      final bytes = await File('test/fixtures/legacy_zip/$name').readAsBytes();
      await expectLater(inspect(bytes), throwsFormatException);
    }
  });

  test('unlisted prefixes and overlapping local ranges rejected', () async {
    final central = _signature(good, 0x02014b50);
    final bytes = Uint8List.fromList(good);
    ByteData.sublistView(bytes).setUint32(central + 42, 1, Endian.little);
    await expectLater(inspect(bytes), throwsFormatException);
  });

  test('symlink input is rejected without following it', () async {
    final file = File('${temporary.path}/original.zip');
    await file.writeAsBytes(good);
    final link = Link('${temporary.path}/alias.zip');
    await link.create(file.path);
    await expectLater(
      LegacyZipIndex.read(File(link.path)),
      throwsFormatException,
    );
  });
}

int _signature(Uint8List bytes, int signature) {
  final data = ByteData.sublistView(bytes);
  for (var at = 0; at + 4 <= bytes.length; at++) {
    if (data.getUint32(at, Endian.little) == signature) return at;
  }
  throw StateError('Fixture signature missing');
}

int _nextCentral(Uint8List bytes, int at) {
  final data = ByteData.sublistView(bytes);
  return at +
      46 +
      data.getUint16(at + 28, Endian.little) +
      data.getUint16(at + 30, Endian.little) +
      data.getUint16(at + 32, Endian.little);
}
