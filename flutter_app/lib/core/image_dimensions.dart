import 'dart:typed_data';

/// Read only bounded container metadata, before any raster decoding.
/// Flutter Web does not implement ImageDescriptor.width/height.
(int, int) encodedImageDimensions(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  bool has(int offset, int count) =>
      offset >= 0 && count >= 0 && offset + count <= bytes.length;
  int u16(int offset, [Endian endian = Endian.big]) =>
      data.getUint16(offset, endian);
  int u32(int offset, [Endian endian = Endian.big]) =>
      data.getUint32(offset, endian);
  bool text(int offset, String value) =>
      has(offset, value.length) &&
      List.generate(value.length, (index) => bytes[offset + index]).join(',') ==
          value.codeUnits.join(',');
  (int, int) valid(int width, int height) {
    if (width < 1 || height < 1) {
      throw const FormatException('Invalid image dimensions');
    }
    return (width, height);
  }

  if (has(0, 24) &&
      bytes[0] == 137 &&
      text(1, 'PNG\r\n\u001a\n') &&
      u32(8) == 13 &&
      text(12, 'IHDR')) {
    return valid(u32(16), u32(20));
  }
  if (has(0, 10) && (text(0, 'GIF87a') || text(0, 'GIF89a'))) {
    return valid(u16(6, Endian.little), u16(8, Endian.little));
  }
  if (has(0, 12) && text(0, 'RIFF') && text(8, 'WEBP')) {
    final limit = u32(4, Endian.little) + 8;
    if (limit > bytes.length || limit < 12) {
      throw const FormatException('Truncated WebP container');
    }
    for (var offset = 12; offset + 8 <= limit;) {
      final size = u32(offset + 4, Endian.little), start = offset + 8;
      if (start + size > limit) {
        throw const FormatException('Truncated WebP chunk');
      }
      int u24(int at) =>
          bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16);
      if (text(offset, 'VP8X') && size >= 10) {
        return valid(u24(start + 4) + 1, u24(start + 7) + 1);
      }
      if (text(offset, 'VP8 ') &&
          size >= 10 &&
          bytes[start + 3] == 157 &&
          bytes[start + 4] == 1 &&
          bytes[start + 5] == 42) {
        return valid(
          u16(start + 6, Endian.little) & 0x3fff,
          u16(start + 8, Endian.little) & 0x3fff,
        );
      }
      if (text(offset, 'VP8L') && size >= 5 && bytes[start] == 47) {
        return valid(
          1 + bytes[start + 1] + ((bytes[start + 2] & 63) << 8),
          1 +
              (bytes[start + 2] >> 6) +
              (bytes[start + 3] << 2) +
              ((bytes[start + 4] & 15) << 10),
        );
      }
      offset = start + size + (size & 1);
    }
  }
  if (has(0, 4) && bytes[0] == 255 && bytes[1] == 216) {
    var offset = 2;
    const frames = {
      192,
      193,
      194,
      195,
      197,
      198,
      199,
      201,
      202,
      203,
      205,
      206,
      207,
    };
    while (has(offset, 2)) {
      if (bytes[offset++] != 255) {
        throw const FormatException('Invalid JPEG marker');
      }
      while (has(offset, 1) && bytes[offset] == 255) {
        offset++;
      }
      if (!has(offset, 1)) break;
      final marker = bytes[offset++];
      if (marker == 217 || marker == 218) break;
      if (marker == 1 || (marker >= 208 && marker <= 215)) continue;
      if (!has(offset, 2)) break;
      final length = u16(offset);
      if (length < 2 || !has(offset, length)) {
        throw const FormatException('Truncated JPEG segment');
      }
      if (frames.contains(marker)) {
        if (length < 8) throw const FormatException('Invalid JPEG frame');
        return valid(u16(offset + 5), u16(offset + 3));
      }
      offset += length;
    }
  }
  if (has(0, 26) && text(0, 'BM')) {
    final header = u32(14, Endian.little);
    if (header == 12) {
      return valid(u16(18, Endian.little), u16(20, Endian.little));
    }
    if (header >= 40 && has(0, 54)) {
      return valid(
        data.getInt32(18, Endian.little),
        data.getInt32(22, Endian.little).abs(),
      );
    }
  }
  throw const FormatException('Unsupported or incomplete image metadata');
}
