import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Version-one framing contains no compression or filesystem instructions.
/// SQLite schema/data trust is checked separately after extracting to a new,
/// application-owned generation. A valid envelope alone is not a valid restore.
class LocalBackupFile {
  LocalBackupFile({
    required this.path,
    required this.bytes,
    required this.sha256,
  }) {
    if (!_allowedPath(path) ||
        bytes < 0 ||
        bytes > LocalBackupManifest.maxFileBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256)) {
      throw const FormatException('Invalid local backup file declaration');
    }
    if (path == 'database/content.db' && bytes == 0) {
      throw const FormatException('Empty backup database');
    }
  }
  final String path, sha256;
  final int bytes;
  static bool _allowedPath(String value) {
    if (value == 'database/content.db') return true;
    final parts = value.split('/');
    return parts.length == 2 &&
        {'attachments', 'drive-blobs'}.contains(parts.first) &&
        RegExp(r'^[A-Za-z0-9._-]{1,200}$').hasMatch(parts.last) &&
        parts.last != '.' &&
        parts.last != '..' &&
        !parts.last.endsWith('.');
  }

  Map<String, Object> toJson() => {
    'path': path,
    'bytes': bytes,
    'sha256': sha256,
  };
  factory LocalBackupFile.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        !_keys(value, {'path', 'bytes', 'sha256'}) ||
        value['path'] is! String ||
        value['bytes'] is! int ||
        value['sha256'] is! String) {
      throw const FormatException('Invalid local backup file metadata');
    }
    return LocalBackupFile(
      path: value['path'] as String,
      bytes: value['bytes'] as int,
      sha256: value['sha256'] as String,
    );
  }
}

bool _keys(Map<String, dynamic> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

class LocalBackupManifest {
  LocalBackupManifest({
    required this.id,
    required this.createdAt,
    required this.sqliteVersion,
    this.databaseSchema = schemaVersion,
    required Map<String, int> tables,
    required List<LocalBackupFile> files,
  }) : tables = Map.unmodifiable(tables),
       files = List.unmodifiable(files) {
    if (!{14, 15, 16}.contains(databaseSchema) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        createdAt.length > 40 ||
        !createdAt.endsWith('Z') ||
        DateTime.tryParse(createdAt)?.toUtc().toIso8601String() != createdAt ||
        !RegExp(
          r'^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$',
        ).hasMatch(sqliteVersion) ||
        !this.tables.keys.toSet().containsAll(
          requiredTablesFor(databaseSchema),
        ) ||
        this.tables.keys.any(
          (key) =>
              !requiredTablesFor(databaseSchema).contains(key) &&
              key != 'android_metadata',
        ) ||
        this.tables.values.any((count) => count < 0 || count > 100000000) ||
        this.files.isEmpty ||
        this.files.length > maxFiles ||
        this.files.first.path != 'database/content.db' ||
        this.files.map((file) => file.path.toLowerCase()).toSet().length !=
            this.files.length ||
        this.files.where((file) => file.path == 'database/content.db').length !=
            1 ||
        totalBytes > maxTotalBytes) {
      throw const FormatException(
        'Invalid or unsupported local backup manifest',
      );
    }
    if (utf8.encode(jsonEncode(toJson())).length > maxManifestBytes) {
      throw const FormatException('Local backup manifest exceeds its limit');
    }
  }
  static const version = 1;
  static const schemaVersion = 14;
  static const maxManifestBytes = 8 * 1024 * 1024;
  static const maxFiles = 32768;
  static const maxFileBytes = 512 * 1024 * 1024;
  static const maxTotalBytes = 2 * 1024 * 1024 * 1024;
  static const requiredTables = {
    'notes',
    'tasks',
    'trash_entries',
    'books',
    'documents',
    'bookmarks',
    'topics',
    'topic_summaries',
    'topic_resources',
    'topic_comments',
    'local_labels',
    'label_recommendation_settings',
    'local_images',
    'local_drive_nodes',
    'html_creation_receipts',
    'html_preview_resources',
    'sqlite_sequence',
  };
  static const requiredTables15 = {
    ...requiredTables,
    'legacy_import_sources',
    'legacy_import_records',
    'legacy_import_label_relations',
    'legacy_friend_links',
    'legacy_import_upload_blobs',
    'legacy_import_upload_bindings',
  };
  static const requiredTables16 = {
    ...requiredTables,
    'assistant_creation_receipts',
  };
  static Set<String> requiredTablesFor(int schema) => switch (schema) {
    14 => requiredTables,
    15 => requiredTables15,
    16 => requiredTables16,
    _ => throw const FormatException('Unsupported backup database schema'),
  };
  final int databaseSchema;
  final String id, createdAt, sqliteVersion;
  final Map<String, int> tables;
  final List<LocalBackupFile> files;
  int get totalBytes => files.fold(0, (sum, file) => sum + file.bytes);
  Map<String, Object> toJson() => {
    'format': 'bookstark-local',
    'version': databaseSchema == 14
        ? version
        : databaseSchema == 15
        ? 3
        : 2,
    'schema': databaseSchema,
    'id': id,
    'createdAt': createdAt,
    'sqliteVersion': sqliteVersion,
    'tables': tables,
    'files': files.map((file) => file.toJson()).toList(),
  };
  factory LocalBackupManifest.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        !_keys(value, {
          'format',
          'version',
          'schema',
          'id',
          'createdAt',
          'sqliteVersion',
          'tables',
          'files',
        }) ||
        value['format'] != 'bookstark-local' ||
        value['version'] is! int ||
        value['schema'] is! int ||
        !((value['version'] == 1 && value['schema'] == 14) ||
            (value['version'] == 2 && value['schema'] == 16) ||
            (value['version'] == 3 && value['schema'] == 15)) ||
        value['id'] is! String ||
        value['createdAt'] is! String ||
        value['sqliteVersion'] is! String ||
        value['tables'] is! Map<String, dynamic> ||
        value['files'] is! List ||
        (value['files'] as List).length > maxFiles) {
      throw const FormatException('Unsupported local backup metadata');
    }
    final rawTables = value['tables'] as Map<String, dynamic>;
    if (rawTables.values.any((value) => value is! int)) {
      throw const FormatException('Invalid backup table counts');
    }
    return LocalBackupManifest(
      databaseSchema: value['schema'] as int,
      id: value['id'] as String,
      createdAt: value['createdAt'] as String,
      sqliteVersion: value['sqliteVersion'] as String,
      tables: rawTables.cast<String, int>(),
      files: (value['files'] as List).map(LocalBackupFile.fromJson).toList(),
    );
  }
}

typedef BackupFileReader = Stream<List<int>> Function(LocalBackupFile file);
typedef BackupFileConsumer =
    Future<void> Function(LocalBackupFile file, Stream<List<int>> bytes);

class LocalBackupCodec {
  static final _magic = ascii.encode('BSTKBK01');
  static const chunkBytes = 64 * 1024;
  static const maxArchiveBytes =
      12 +
      LocalBackupManifest.maxManifestBytes +
      LocalBackupManifest.maxTotalBytes;

  static Stream<List<int>> encode(
    LocalBackupManifest manifest,
    BackupFileReader openFile,
  ) async* {
    final metadata = utf8.encode(jsonEncode(manifest.toJson()));
    final header = ByteData(12);
    header.buffer.asUint8List().setRange(0, 8, _magic);
    header.setUint32(8, metadata.length, Endian.big);
    yield header.buffer.asUint8List();
    yield metadata;
    for (final file in manifest.files) {
      final digest = _DigestSink();
      final hash = sha256.startChunkedConversion(digest);
      var count = 0;
      try {
        await for (final chunk in openFile(file)) {
          if (count + chunk.length > file.bytes) {
            throw const FormatException('Backup source grew during export');
          }
          for (var offset = 0; offset < chunk.length; offset += chunkBytes) {
            final part = chunk.sublist(
              offset,
              math.min(offset + chunkBytes, chunk.length),
            );
            hash.add(part);
            count += part.length;
            yield part;
          }
        }
      } finally {
        hash.close();
      }
      if (count != file.bytes || digest.value?.toString() != file.sha256) {
        throw const FormatException('Backup source changed during export');
      }
    }
  }

  /// The consumer must consume the complete stream and finish/flush its sink.
  /// On any failure its generation is untrusted and must never be activated.
  static Future<LocalBackupManifest> decode(
    Stream<List<int>> input,
    BackupFileConsumer consume, {
    void Function(Uint8List bytes)? onMetadata,
  }) async {
    final reader = _Reader(input);
    try {
      final header = await reader.exact(12);
      if (ascii.decode(header.sublist(0, 8), allowInvalid: true) !=
          'BSTKBK01') {
        throw const FormatException('Not a BookStark local backup');
      }
      final length = ByteData.sublistView(header).getUint32(8, Endian.big);
      if (length == 0 || length > LocalBackupManifest.maxManifestBytes) {
        throw const FormatException('Backup manifest exceeds its limit');
      }
      final metadata = await reader.exact(length);
      final text = utf8.decode(metadata);
      final raw = jsonDecode(text);
      // The writer emits canonical JSON. This rejects duplicate keys and
      // alternative encodings before any user-supplied filename is used.
      if (jsonEncode(raw) != text) {
        throw const FormatException(
          'Noncanonical or duplicate backup metadata',
        );
      }
      final manifest = LocalBackupManifest.fromJson(raw);
      onMetadata?.call(Uint8List.fromList(metadata).asUnmodifiableView());
      for (final file in manifest.files) {
        var complete = false;
        Stream<List<int>> body() async* {
          final digest = _DigestSink();
          final hash = sha256.startChunkedConversion(digest);
          var remaining = file.bytes;
          try {
            while (remaining > 0) {
              final chunk = await reader.part(math.min(remaining, chunkBytes));
              remaining -= chunk.length;
              hash.add(chunk);
              yield chunk;
            }
          } finally {
            hash.close();
          }
          if (digest.value?.toString() != file.sha256) {
            throw const FormatException('Backup file hash does not match');
          }
          complete = true;
        }

        await consume(file, body());
        if (!complete) {
          throw StateError('Backup consumer did not verify the complete file');
        }
      }
      if (await reader.hasMore()) {
        throw const FormatException('Unexpected bytes after backup');
      }
      return manifest;
    } finally {
      await reader.close();
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

class _Reader {
  _Reader(Stream<List<int>> input) : _iterator = StreamIterator(input);
  final StreamIterator<List<int>> _iterator;
  List<int> _chunk = const [];
  int _offset = 0;
  Future<bool> hasMore() async {
    while (_offset == _chunk.length) {
      if (!await _iterator.moveNext().timeout(const Duration(seconds: 30))) {
        return false;
      }
      _chunk = _iterator.current;
      _offset = 0;
    }
    return true;
  }

  Future<Uint8List> part(int limit) async {
    if (!await hasMore()) throw const FormatException('Truncated local backup');
    final count = math.min(limit, _chunk.length - _offset);
    final result = Uint8List.fromList(_chunk.sublist(_offset, _offset + count));
    _offset += count;
    return result;
  }

  Future<Uint8List> exact(int count) async {
    final result = BytesBuilder(copy: false);
    var remaining = count;
    while (remaining > 0) {
      final chunk = await part(
        math.min(remaining, LocalBackupCodec.chunkBytes),
      );
      result.add(chunk);
      remaining -= chunk.length;
    }
    return result.takeBytes();
  }

  Future<void> close() => _iterator.cancel();
}
