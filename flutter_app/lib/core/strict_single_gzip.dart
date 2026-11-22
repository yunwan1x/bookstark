import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart' as archive;

/// One complete gzip member only. Never returns partial output, accepts a
/// concatenated member, or treats an incomplete header/trailer as empty data.
/// Both compressed storage and inflation writes are bounded before allocation.
Future<Uint8List> decodeStrictSingleGzip(
  Stream<List<int>> wire, {
  required int maxWire,
  required int maxPlain,
  required Future<void> abort,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (maxWire < 18 || maxPlain < 0 || timeout <= Duration.zero) {
    throw ArgumentError('Invalid gzip bounds');
  }
  final clock = Stopwatch()..start();
  var cancelled = false;
  var expired = false;
  final cancelledSignal = Completer<void>();
  void cancel() {
    cancelled = true;
    if (!cancelledSignal.isCompleted) cancelledSignal.complete();
  }

  unawaited(
    abort.then<void>(
      (_) => cancel(),
      onError: (Object _, StackTrace _) => cancel(),
    ),
  );
  final deadline = Completer<void>();
  final timer = Timer(timeout, () {
    expired = true;
    if (!deadline.isCompleted) deadline.complete();
  });
  void guard() {
    if (cancelled) throw const FormatException('Gzip read cancelled');
    if (expired || clock.elapsed >= timeout) {
      throw const FormatException('Gzip absolute deadline');
    }
  }

  Future<T> wait<T>(Future<T> work) async {
    guard();
    final result = await Future.any<T>([
      work,
      cancelledSignal.future.then<T>(
        (_) => throw const FormatException('Gzip read cancelled'),
      ),
      deadline.future.then<T>(
        (_) => throw const FormatException('Gzip absolute deadline'),
      ),
    ]);
    guard();
    return result;
  }

  final iterator = StreamIterator<List<int>>(wire);
  try {
    // Deliver an already completed abort before even starting the wire.
    await wait(Future<void>.value());
    final compressed = BytesBuilder(copy: false);
    while (await wait(iterator.moveNext())) {
      final chunk = iterator.current;
      if (chunk.length > maxWire - compressed.length) {
        throw const FormatException('Gzip wire limit');
      }
      compressed.add(chunk);
    }
    final bytes = compressed.takeBytes();
    if (bytes.length < 18 ||
        bytes[0] != 31 ||
        bytes[1] != 139 ||
        bytes[2] != 8 ||
        (bytes[3] & 0xe0) != 0) {
      throw const FormatException('Invalid gzip header');
    }
    final flags = bytes[3];
    var cursor = 10;
    void need(int count) {
      // Always reserve the trailer. Header strings cannot consume it.
      if (count < 0 ||
          cursor > bytes.length - 8 - count ||
          cursor + count > 65536) {
        throw const FormatException('Incomplete or excessive gzip header');
      }
    }

    if ((flags & 4) != 0) {
      need(2);
      final count = bytes[cursor] | (bytes[cursor + 1] << 8);
      cursor += 2;
      need(count);
      cursor += count;
    }
    for (final flag in [8, 16]) {
      if ((flags & flag) != 0) {
        while (true) {
          need(1);
          if (bytes[cursor++] == 0) break;
        }
      }
    }
    if ((flags & 2) != 0) {
      need(2);
      final expected = bytes[cursor] | (bytes[cursor + 1] << 8);
      if ((archive.getCrc32(Uint8List.sublistView(bytes, 0, cursor)) &
              0xffff) !=
          expected) {
        throw const FormatException('Gzip header CRC mismatch');
      }
      cursor += 2;
    }
    guard();
    final input = archive.InputMemoryStream(bytes)..position = cursor;
    final output = _BoundedGzipOutput(maxPlain, guard);
    final inflate = archive.Inflate.lazy(input, output: output);
    bool more;
    do {
      guard();
      more = inflate.inflateBlock();
      // One absolute deadline covers wire waits and CPU work. Yield between
      // blocks so scope cancellation can be observed without publishing output.
      await wait(Future<void>.delayed(Duration.zero));
    } while (more);
    if (!inflate.isFinished || input.length != 8) {
      throw const FormatException(
        'Gzip trailer missing, concatenated or trailing bytes',
      );
    }
    final expectedCrc = input.readUint32();
    final expectedSize = input.readUint32();
    final plain = output.getBytes();
    if (!input.isEOS ||
        expectedCrc != archive.getCrc32(plain) ||
        expectedSize != (plain.length & 0xffffffff)) {
      throw const FormatException('Gzip CRC or size mismatch');
    }
    await wait(Future<void>.value());
    return plain;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('Invalid or incomplete gzip');
  } finally {
    timer.cancel();
    clock.stop();
    // Do not wait forever for an uncooperative upstream on cancellation.
    final closing = iterator.cancel();
    unawaited(closing.catchError((Object _, StackTrace _) {}));
  }
}

class _BoundedGzipOutput extends archive.OutputMemoryStream {
  _BoundedGzipOutput(this.maximum, this.guard)
    : _capacity = math.min(maximum, 32768),
      super(size: math.min(maximum, 32768));
  final int maximum;
  final void Function() guard;
  int _capacity;
  void _room(int count) {
    guard();
    if (count < 0 || count > maximum - length) {
      throw const FormatException('Gzip expansion limit');
    }
    final needed = length + count;
    if (needed > _capacity) {
      _capacity = math.min(
        maximum,
        math.max(needed, math.max(1, _capacity * 2)),
      );
      super.reserve(_capacity);
    }
  }

  @override
  void reserve(int total) {
    guard();
    if (total < 0 || total > maximum) {
      throw const FormatException('Gzip expansion limit');
    }
    if (total > _capacity) {
      _capacity = total;
      super.reserve(total);
    }
  }

  @override
  void writeByte(int value) {
    _room(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _room(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(archive.InputStream stream) {
    _room(stream.length);
    super.writeStream(stream);
  }

  @override
  void writeBackReference(int distance, int count) {
    if (distance < 1 || distance > length) {
      throw const FormatException('Invalid gzip distance');
    }
    _room(count);
    super.writeBackReference(distance, count);
  }
}
