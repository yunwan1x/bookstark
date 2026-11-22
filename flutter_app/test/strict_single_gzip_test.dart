import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:archive/archive.dart' as archive;
import 'package:bookstark_flutter/core/strict_single_gzip.dart';

Future<List<int>> decode(List<int> value, {int cap = 1024}) =>
    decodeStrictSingleGzip(
      Stream.value(value),
      maxWire: 1048576,
      maxPlain: cap,
      abort: Completer<void>().future,
    );
void main() {
  test(
    'valid single gzip preserves bytes including empty and binary',
    () async {
      for (final source in <List<int>>[
        [],
        [0, 255, 13, 10, 239, 187, 191],
        List.filled(1024, 65),
      ]) {
        expect(await decode(gzip.encode(source)), source);
      }
    },
  );
  test(
    'plain cap enforced before expansion write; exact cap succeeds',
    () async {
      expect(
        await decode(gzip.encode(List.filled(1024, 65))),
        List.filled(1024, 65),
      );
      await expectLater(
        decode(gzip.encode(List.filled(1025, 65))),
        throwsFormatException,
      );
    },
  );
  test(
    'every truncated prefix is rejected including short header and trailer',
    () async {
      final valid = gzip.encode(List.generate(256, (i) => i));
      for (var length = 0; length < valid.length; length++) {
        await expectLater(
          decode(valid.sublist(0, length)),
          throwsFormatException,
          reason: 'truncated prefix length $length',
        );
      }
    },
  );
  test(
    'CRC ISIZE reserved flags concat and trailing junk are rejected',
    () async {
      final valid = gzip.encode([1, 2, 3, 4]);
      final crc = [...valid]..[valid.length - 8] ^= 1;
      final size = [...valid]..[valid.length - 4] ^= 1;
      final reserved = [...valid]..[3] |= 0x20;
      for (final bad in [
        crc,
        size,
        reserved,
        [...valid, ...valid],
        [...valid, 0],
      ]) {
        await expectLater(decode(bad), throwsFormatException);
      }
    },
  );
  test('multi chunk wire exact cap and over cap', () async {
    final value = gzip.encode([1, 2, 3]);
    final chunks = value.map((b) => [b]);
    expect(
      await decodeStrictSingleGzip(
        Stream.fromIterable(chunks),
        maxWire: value.length,
        maxPlain: 3,
        abort: Completer<void>().future,
      ),
      [1, 2, 3],
    );
    await expectLater(
      decodeStrictSingleGzip(
        Stream.fromIterable(chunks),
        maxWire: value.length - 1,
        maxPlain: 3,
        abort: Completer<void>().future,
      ),
      throwsFormatException,
    );
  });
  test('optional name comment extra and header CRC are validated', () async {
    final original = gzip.encode([1, 2, 3]);
    // Optional fields are framing only; preserve the original deflate+trailer.
    final header = [...original.take(10)]..[3] = 4 | 8 | 16;
    final valid = [...header, 2, 0, 7, 8, 110, 0, 99, 0, ...original.skip(10)];
    expect(await decode(valid), [1, 2, 3]);
    final crcHeader = [...original.take(10)]..[3] = 2;
    final crc = archive.getCrc32(crcHeader) & 0xffff;
    final withCrc = [...crcHeader, crc & 255, crc >> 8, ...original.skip(10)];
    expect(await decode(withCrc), [1, 2, 3]);
    withCrc[10] ^= 1;
    await expectLater(decode(withCrc), throwsFormatException);
    final missingTerminator = [...header, ...List.filled(40, 65)];
    await expectLater(decode(missingTerminator), throwsFormatException);
  });
  test(
    'already cancelled and stalled stream cancellation publish no partial data',
    () async {
      final abort = Completer<void>()..complete();
      await expectLater(
        decodeStrictSingleGzip(
          Stream.value(gzip.encode([1])),
          maxWire: 1024,
          maxPlain: 1024,
          abort: abort.future,
        ),
        throwsFormatException,
      );
      var cancelled = false;
      final input = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final laterAbort = Completer<void>();
      final pending = decodeStrictSingleGzip(
        input.stream,
        maxWire: 1024,
        maxPlain: 1024,
        abort: laterAbort.future,
      );
      laterAbort.complete();
      await expectLater(pending, throwsFormatException);
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await input.close();
    },
  );
  test('continual small chunks do not reset absolute deadline', () async {
    final controller = StreamController<List<int>>();
    final timer = Timer.periodic(
      const Duration(milliseconds: 2),
      (_) => controller.add([31]),
    );
    try {
      await expectLater(
        decodeStrictSingleGzip(
          controller.stream,
          maxWire: 1024,
          maxPlain: 1024,
          abort: Completer<void>().future,
          timeout: const Duration(milliseconds: 35),
        ),
        throwsFormatException,
      );
    } finally {
      timer.cancel();
      await controller.close();
    }
  });
}
