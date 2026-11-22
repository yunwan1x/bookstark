import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:file_selector/file_selector.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/drive_source.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/attachments.dart';

class Source extends XFile {
  Source(this.bytes) : super('actual.bin');
  Uint8List bytes;
  DateTime modified = DateTime(2026, 11, 4);
  final ranges = <(int, int)>[];
  bool truncate = false;
  @override
  Future<int> length() async => bytes.length;
  @override
  Future<DateTime> lastModified() async => modified;
  @override
  Stream<Uint8List> openRead([int? start, int? end]) async* {
    final from = start ?? 0, to = end ?? bytes.length;
    ranges.add((from, to));
    yield Uint8List.fromList(
      bytes.sublist(from, truncate && to > from ? to - 1 : to),
    );
  }
}

void main() {
  test(
    'source hashing and second-pass upload consume bounded ranges and verify actual bytes',
    () async {
      final bytes = Uint8List.fromList(List.generate(700000, (n) => n % 251)),
          file = Source(bytes);
      final snapshot = await DriveSourceSnapshot.prepare(
        file,
        maxBytes: 800000,
      );
      expect(snapshot.hash, crypto.sha256.convert(bytes).toString());
      expect(file.ranges.length, 3);
      expect(
        file.ranges.every((range) => range.$2 - range.$1 <= 256 * 1024),
        isTrue,
      );
      var sent = 0;
      final received = BytesBuilder(copy: false);
      await for (final chunk in snapshot.verifiedStream(
        onSent: (count, total) {
          sent = count;
          expect(total, bytes.length);
        },
      )) {
        received.add(chunk);
      }
      expect(received.takeBytes(), bytes);
      expect(sent, bytes.length);
      expect(file.ranges.length, 6);
    },
  );
  test(
    'content change with unchanged length and timestamp is still caught while streaming',
    () async {
      final file = Source(Uint8List.fromList([1, 2, 3]));
      final snapshot = await DriveSourceSnapshot.prepare(file, maxBytes: 10);
      file.bytes = Uint8List.fromList([9, 2, 3]);
      await expectLater(
        snapshot.verifiedStream().drain<void>(),
        throwsFormatException,
      );
    },
  );
  test(
    'metadata changes, truncated source, limits and pre-cancel never become successful uploads',
    () async {
      final file = Source(Uint8List.fromList([1, 2, 3]));
      await expectLater(
        DriveSourceSnapshot.prepare(file, maxBytes: 2),
        throwsA(isA<ApiFailure>()),
      );
      expect(file.ranges, isEmpty);
      final cancel = AttachmentCancellation()..cancel();
      await expectLater(
        DriveSourceSnapshot.prepare(file, maxBytes: 10, cancellation: cancel),
        throwsA(isA<AttachmentCancelled>()),
      );
      file.truncate = true;
      await expectLater(
        DriveSourceSnapshot.prepare(file, maxBytes: 10),
        throwsFormatException,
      );
      file.truncate = false;
      final snapshot = await DriveSourceSnapshot.prepare(file, maxBytes: 10);
      file.modified = DateTime(2026, 11, 5);
      await expectLater(snapshot.verifyMetadata(), throwsFormatException);
    },
  );
  test(
    'possession proof hashes nonce bytes plus exact requested chunks in original index order',
    () async {
      const chunk = 1 << 20;
      final data = Uint8List.fromList(
            List.generate(chunk * 2 + 17, (n) => n % 253),
          ),
          file = Source(data),
          nonce = Uint8List.fromList(List.generate(24, (n) => n));
      final snapshot = await DriveSourceSnapshot.prepare(
        file,
        maxBytes: 3 * chunk,
      );
      file.ranges.clear();
      final result = await snapshot.prove(
        nonce: nonce,
        chunkSize: chunk,
        indices: [0, 2, 1],
      );
      expect(result, [
        for (final index in [0, 2, 1])
          crypto.sha256.convert([
            ...nonce,
            ...data.sublist(
              index * chunk,
              (index * chunk + chunk).clamp(0, data.length),
            ),
          ]).toString(),
      ]);
      expect(file.ranges, [
        (0, chunk),
        (2 * chunk, data.length),
        (chunk, 2 * chunk),
      ]);
      for (final indices in [
        [-1],
        [3],
        [0, 0],
        [0, 1, 2, 3],
      ]) {
        await expectLater(
          snapshot.prove(nonce: nonce, chunkSize: chunk, indices: indices),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'empty files retain their real SHA256 and zero-byte upload stream',
    () async {
      final snapshot = await DriveSourceSnapshot.prepare(
        Source(Uint8List(0)),
        maxBytes: 0,
      );
      expect(snapshot.hash, crypto.sha256.convert([]).toString());
      expect(await snapshot.verifiedStream().toList(), isEmpty);
    },
  );
}
