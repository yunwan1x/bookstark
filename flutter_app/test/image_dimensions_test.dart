import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/image_dimensions.dart';

Uint8List png(int width, int height) {
  final bytes = Uint8List(33);
  bytes.setAll(0, [137, 80, 78, 71, 13, 10, 26, 10]);
  final data = ByteData.sublistView(bytes);
  data.setUint32(8, 13);
  bytes.setAll(12, ascii.encode('IHDR'));
  data.setUint32(16, width);
  data.setUint32(20, height);
  return bytes;
}

Uint8List webp(String kind, List<int> payload) {
  final bytes = Uint8List(20 + payload.length + (payload.length & 1));
  bytes.setAll(0, ascii.encode('RIFF'));
  bytes.setAll(8, ascii.encode('WEBP'));
  bytes.setAll(12, ascii.encode(kind));
  final data = ByteData.sublistView(bytes);
  data.setUint32(4, bytes.length - 8, Endian.little);
  data.setUint32(16, payload.length, Endian.little);
  bytes.setAll(20, payload);
  return bytes;
}

void main() {
  test(
    'PNG and GIF metadata can be read without allocating decoded pixels',
    () {
      expect(encodedImageDimensions(png(800, 600)), (800, 600));
      expect(
        encodedImageDimensions(
          Uint8List.fromList([...ascii.encode('GIF89a'), 16, 0, 8, 0]),
        ),
        (16, 8),
      );
      expect(encodedImageDimensions(png(100000, 100000)), (
        100000,
        100000,
      )); // caller enforces pixel budget before decoding
      expect(() => encodedImageDimensions(png(0, 10)), throwsFormatException);
    },
  );
  test('WebP VP8X, VP8 and VP8L report correct canvas dimensions', () {
    expect(
      encodedImageDimensions(webp('VP8X', [0, 0, 0, 0, 255, 1, 0, 127, 0, 0])),
      (512, 128),
    );
    expect(
      encodedImageDimensions(
        webp('VP8 ', [0, 0, 0, 157, 1, 42, 128, 2, 224, 1]),
      ),
      (640, 480),
    );
    expect(encodedImageDimensions(webp('VP8L', [47, 15, 192, 1, 0])), (16, 8));
  });
  test(
    'JPEG skips metadata and reads baseline or progressive SOF without a full decode',
    () {
      for (final frame in [192, 194]) {
        final bytes = Uint8List.fromList([
          255,
          216,
          255,
          224,
          0,
          4,
          12,
          34,
          255,
          frame,
          0,
          8,
          8,
          1,
          224,
          2,
          128,
          3,
        ]);
        expect(encodedImageDimensions(bytes), (640, 480));
      }
    },
  );
  test(
    'top-down BMP signed height is normalized and truncated buffers fail without range errors',
    () {
      final bmp = Uint8List(54);
      bmp.setAll(0, ascii.encode('BM'));
      final data = ByteData.sublistView(bmp);
      data.setUint32(14, 40, Endian.little);
      data.setInt32(18, 20, Endian.little);
      data.setInt32(22, -10, Endian.little);
      expect(encodedImageDimensions(bmp), (20, 10));
      for (final bytes in [
        png(80, 40),
        webp('VP8X', [0, 0, 0, 0, 1, 0, 0, 1, 0, 0]),
        Uint8List.fromList([255, 216, 255, 192, 0, 8, 8, 1, 224, 2, 128, 3]),
        bmp,
      ]) {
        for (var n = 0; n < bytes.length; n++) {
          try {
            encodedImageDimensions(Uint8List.sublistView(bytes, 0, n));
          } on FormatException {
            continue;
          } catch (error) {
            fail('Truncated header leaked $error at $n');
          }
        }
      }
    },
  );
}
