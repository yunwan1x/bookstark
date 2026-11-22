import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The legacy Go ZIP dialect. Validate before handing data to a ZIP decoder:
/// common decoders merge duplicate names and may eagerly inflate symlinks.
final class LegacyZipLimits {
  const LegacyZipLimits({
    this.maxArchiveBytes = 2 * 1024 * 1024 * 1024,
    this.maxEntries = 32768,
    this.maxEntryBytes = 512 * 1024 * 1024,
    this.maxTotalBytes = 2 * 1024 * 1024 * 1024,
    this.maxCentralBytes = 32 * 1024 * 1024,
    this.maxNameBytes = 1024,
  });
  final int maxArchiveBytes;
  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;
  final int maxCentralBytes;
  final int maxNameBytes;
}

final class LegacyZipEntry {
  const LegacyZipEntry({
    required this.name,
    required this.isDirectory,
    required this.flags,
    required this.method,
    required this.crc32,
    required this.compressedBytes,
    required this.uncompressedBytes,
    required this.dataOffset,
    required this.recordOffset,
    required this.recordEnd,
  });
  final String name;
  final bool isDirectory;
  final int flags;
  final int method;
  final int crc32;
  final int compressedBytes;
  final int uncompressedBytes;
  final int dataOffset;
  final int recordOffset;
  final int recordEnd;
}

final class LegacyZipIndex {
  const LegacyZipIndex._(this.entries, this.totalBytes, this.archiveBytes);
  final List<LegacyZipEntry> entries;
  final int totalBytes;
  final int archiveBytes;

  /// Read-only and bounded; never extracts paths or inflates archive contents.
  /// The caller owns the immutable private inbox for the entire import.
  static Future<LegacyZipIndex> read(
    File file, {
    LegacyZipLimits limits = const LegacyZipLimits(),
  }) async {
    if ([
      limits.maxArchiveBytes,
      limits.maxEntries,
      limits.maxEntryBytes,
      limits.maxTotalBytes,
      limits.maxCentralBytes,
      limits.maxNameBytes,
    ].any((value) => value <= 0)) {
      throw ArgumentError('ZIP limits must be positive');
    }
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      _bad('Expected an owned regular ZIP file');
    }
    final input = await file.open(mode: FileMode.read);
    try {
      final size = await input.length();
      if (size < 22 || size > limits.maxArchiveBytes) {
        _bad('ZIP archive size is outside limits');
      }
      final tailStart = size > 65557 ? size - 65557 : 0;
      final tail = await _read(input, tailStart, size - tailStart, size);
      var end = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (_u32(tail, i) == 0x06054b50 &&
            i + 22 + _u16(tail, i + 20) == tail.length) {
          if (end != -1) _bad('Ambiguous ZIP end record');
          end = i;
        }
      }
      if (end == -1) _bad('ZIP end record is missing');
      final endOffset = tailStart + end;
      final count = _u16(tail, end + 10);
      final centralSize = _u32(tail, end + 12);
      final centralOffset = _u32(tail, end + 16);
      if (_u16(tail, end + 4) != 0 ||
          _u16(tail, end + 6) != 0 ||
          _u16(tail, end + 8) != count ||
          count == 65535 ||
          centralOffset == 0xffffffff ||
          centralSize == 0xffffffff) {
        _bad('Multi-disk and ZIP64 archives are unsupported');
      }
      if (count > limits.maxEntries ||
          centralSize > limits.maxCentralBytes ||
          centralOffset + centralSize != endOffset) {
        _bad('Invalid or excessive ZIP directory');
      }
      final central = await _read(input, centralOffset, centralSize, size);
      final entries = <LegacyZipEntry>[];
      final names = <String>{};
      final kinds = <String, bool>{};
      var cursor = 0;
      var total = 0;
      for (var index = 0; index < count; index++) {
        if (cursor + 46 > central.length ||
            _u32(central, cursor) != 0x02014b50) {
          _bad('Truncated ZIP directory record');
        }
        final flags = _u16(central, cursor + 8);
        final method = _u16(central, cursor + 10);
        final crc = _u32(central, cursor + 16);
        final compressed = _u32(central, cursor + 20);
        final expanded = _u32(central, cursor + 24);
        final nameLength = _u16(central, cursor + 28);
        final extraLength = _u16(central, cursor + 30);
        final commentLength = _u16(central, cursor + 32);
        final attributes = _u32(central, cursor + 38);
        final localOffset = _u32(central, cursor + 42);
        final next = cursor + 46 + nameLength + extraLength + commentLength;
        if (nameLength == 0 ||
            nameLength > limits.maxNameBytes ||
            next > central.length ||
            _u16(central, cursor + 34) != 0 ||
            flags & ~0x080e != 0 ||
            (method != 0 && method != 8) ||
            (method == 0 && flags & 6 != 0) ||
            expanded > limits.maxEntryBytes ||
            compressed == 0xffffffff ||
            expanded == 0xffffffff ||
            localOffset == 0xffffffff) {
          _bad('Unsupported ZIP entry or excessive entry size');
        }
        _extra(central, cursor + 46 + nameLength, extraLength);
        final rawName = central.sublist(cursor + 46, cursor + 46 + nameLength);
        if (rawName.length >= 3 &&
            rawName[0] == 0xef &&
            rawName[1] == 0xbb &&
            rawName[2] == 0xbf) {
          _bad('ZIP paths cannot start with a byte-order mark');
        }
        String name;
        try {
          name = utf8.decode(rawName, allowMalformed: false);
        } on FormatException {
          _bad('ZIP path is not valid UTF-8');
        }
        final directory = name.endsWith('/');
        final canonical = _name(name, directory);
        final folded = canonical.toLowerCase();
        if (!names.add(folded)) _bad('Duplicate or aliased ZIP path');
        final mode = (attributes >> 16) & 0xf000;
        if ((mode != 0 && mode != 0x8000 && mode != 0x4000) ||
            (mode == 0x4000 && !directory) ||
            (mode == 0x8000 && directory) ||
            (attributes & 0x10 != 0 && !directory)) {
          _bad('Special or inconsistent ZIP entry');
        }
        if ((directory && (expanded != 0 || crc != 0)) ||
            (method == 0 && compressed != expanded)) {
          _bad('Invalid ZIP entry lengths');
        }
        total += expanded;
        if (total > limits.maxTotalBytes) _bad('ZIP expansion exceeds limit');
        kinds[folded] = directory;

        final header = await _read(input, localOffset, 30, centralOffset);
        if (_u32(header, 0) != 0x04034b50 ||
            _u16(header, 6) != flags ||
            _u16(header, 8) != method ||
            _u16(header, 26) != nameLength) {
          _bad('ZIP local header disagrees with directory');
        }
        final localName = await _read(
          input,
          localOffset + 30,
          nameLength,
          centralOffset,
        );
        for (var n = 0; n < nameLength; n++) {
          if (localName[n] != rawName[n]) _bad('ZIP local path differs');
        }
        final localExtra = await _read(
          input,
          localOffset + 30 + nameLength,
          _u16(header, 28),
          centralOffset,
        );
        _extra(localExtra, 0, localExtra.length);
        final dataOffset = localOffset + 30 + nameLength + _u16(header, 28);
        var recordEnd = dataOffset + compressed;
        if (recordEnd > centralOffset) _bad('ZIP payload overlaps directory');
        if (flags & 8 == 0) {
          if (_u32(header, 14) != crc ||
              _u32(header, 18) != compressed ||
              _u32(header, 22) != expanded) {
            _bad('ZIP local sizes or checksum differ');
          }
        } else {
          // Go archive/zip writes signed descriptors; accept the standard
          // unsigned variant as well when unambiguous.
          final first = await _read(input, recordEnd, 4, centralOffset);
          final signed = _u32(first, 0) == 0x08074b50;
          final descriptor = await _read(
            input,
            recordEnd,
            signed ? 16 : 12,
            centralOffset,
          );
          final at = signed ? 4 : 0;
          if (_u32(descriptor, at) != crc ||
              _u32(descriptor, at + 4) != compressed ||
              _u32(descriptor, at + 8) != expanded) {
            _bad('ZIP data descriptor differs');
          }
          recordEnd += descriptor.length;
          // A nonzero local placeholder must agree, rather than providing a
          // second contradictory interpretation to another decoder.
          for (final pair in [(14, crc), (18, compressed), (22, expanded)]) {
            final placeholder = _u32(header, pair.$1);
            if (placeholder != 0 && placeholder != pair.$2) {
              _bad('Conflicting ZIP descriptor placeholder');
            }
          }
        }
        entries.add(
          LegacyZipEntry(
            name: name,
            isDirectory: directory,
            flags: flags,
            method: method,
            crc32: crc,
            compressedBytes: compressed,
            uncompressedBytes: expanded,
            dataOffset: dataOffset,
            recordOffset: localOffset,
            recordEnd: recordEnd,
          ),
        );
        cursor = next;
      }
      if (cursor != central.length) _bad('Unlisted ZIP directory data');
      for (final path in kinds.keys) {
        var slash = path.indexOf('/');
        while (slash != -1) {
          if (kinds[path.substring(0, slash)] == false) {
            _bad('ZIP file is also used as a directory');
          }
          slash = path.indexOf('/', slash + 1);
        }
      }
      final ordered = [...entries]
        ..sort((a, b) => a.recordOffset.compareTo(b.recordOffset));
      var position = 0;
      for (final entry in ordered) {
        if (entry.recordOffset != position) {
          _bad('Overlapping or unlisted ZIP local records');
        }
        position = entry.recordEnd;
      }
      if (position != centralOffset || await input.length() != size) {
        _bad('ZIP local records or input size changed');
      }
      return LegacyZipIndex._(List.unmodifiable(entries), total, size);
    } finally {
      await input.close();
    }
  }
}

Never _bad(String message) => throw FormatException(message);

String _name(String name, bool directory) {
  if (name.contains('\\') ||
      name.contains(':') ||
      name.codeUnits.any((c) => c < 32 || c == 127)) {
    _bad('Unsafe ZIP path');
  }
  final path = directory ? name.substring(0, name.length - 1) : name;
  if (path.isEmpty ||
      path
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    _bad('Unsafe ZIP path');
  }
  return path;
}

int _u16(Uint8List data, int at) =>
    ByteData.sublistView(data).getUint16(at, Endian.little);
int _u32(Uint8List data, int at) =>
    ByteData.sublistView(data).getUint32(at, Endian.little);

Future<Uint8List> _read(
  RandomAccessFile input,
  int offset,
  int length,
  int boundary,
) async {
  if (offset < 0 || length < 0 || offset + length > boundary) {
    _bad('ZIP record extends outside its bounds');
  }
  await input.setPosition(offset);
  final data = await input.read(length);
  if (data.length != length) _bad('Truncated ZIP input');
  return data;
}

void _extra(Uint8List data, int offset, int length) {
  final end = offset + length;
  while (offset < end) {
    if (offset + 4 > end) _bad('Truncated ZIP extra record');
    final kind = _u16(data, offset);
    final bytes = _u16(data, offset + 2);
    offset += 4;
    if (offset + bytes > end) _bad('Truncated ZIP extra payload');
    if (kind == 0x0001 || kind == 0x7075) {
      _bad('ZIP size and path override extensions are unsupported');
    }
    offset += bytes;
  }
}
