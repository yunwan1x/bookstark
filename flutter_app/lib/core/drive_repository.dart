import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:mime/mime.dart';
import 'drive_source.dart';
import 'api_client.dart';
import 'attachments.dart';
import 'drive_models.dart';

const maxDriveTextBytes = 2 * 1024 * 1024;

class DriveRead {
  const DriveRead({
    required this.stream,
    required this.status,
    required this.headers,
    required this.length,
  });
  final Stream<List<int>> stream;
  final int status;
  final Map<String, String> headers;
  final int? length;
}

abstract class DriveRepository {
  bool get local;
  Future<DriveProfile> profile({AttachmentCancellation? cancellation});
  Future<List<DriveNode>> list(
    String path, {
    AttachmentCancellation? cancellation,
  });
  Future<DriveRead> open(
    DriveNode file, {
    String? range,
    String? ifRange,
    AttachmentCancellation? cancellation,
  });
  Future<DriveNode> mkdir(
    String parent,
    String name, {
    AttachmentCancellation? cancellation,
  });
  Future<void> rename(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  });
  Future<void> copy(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  });
  Future<void> remove(DriveNode source, {AttachmentCancellation? cancellation});
  Future<DriveUploadResult> upload(
    DriveSourceSnapshot source, {
    required String target,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  });
  Future<DriveNode> saveText(
    DriveText document,
    String content, {
    AttachmentCancellation? cancellation,
  });
  Future<Uri> publish(
    DriveNode file,
    String publicPath, {
    AttachmentCancellation? cancellation,
  });
  Future<void> unpublish(
    DriveNode file, {
    AttachmentCancellation? cancellation,
  });
  void dispose();
  Future<DriveNode?> lookup(
    String path, {
    AttachmentCancellation? cancellation,
  }) async {
    final value = drivePath(path);
    if (value.isEmpty) throw const FormatException('Root is not a file');
    try {
      final rows = await list(driveParent(value), cancellation: cancellation);
      final matches = rows.where((row) => row.path == value).toList();
      if (matches.length > 1) {
        throw const FormatException('Duplicate file identity');
      }
      return matches.isEmpty ? null : matches.single;
    } on ApiFailure catch (error) {
      if (error.status == 404) return null;
      rethrow;
    }
  }

  Future<DriveNode> verify(
    DriveNode expected, {
    AttachmentCancellation? cancellation,
  }) async {
    final actual = await lookup(expected.path, cancellation: cancellation);
    if (actual == null ||
        actual.id != expected.id ||
        actual.directory != expected.directory ||
        actual.etag != expected.etag ||
        actual.isPublic != expected.isPublic ||
        actual.publicPath != expected.publicPath) {
      throw DriveConflict(expected, actual);
    }
    return actual;
  }

  Future<Uint8List> bytes(
    DriveNode file, {
    int maxBytes = 64 * 1024 * 1024,
    AttachmentCancellation? cancellation,
  }) async {
    if (file.directory) {
      throw const FormatException('Directory cannot be downloaded as a file');
    }
    if (file.size > maxBytes) {
      throw const ApiFailure(413, '文件超过读取上限 / File exceeds read bound');
    }
    final response = await open(file, cancellation: cancellation),
        builder = BytesBuilder(copy: false);
    if (response.length != null && response.length! > maxBytes) {
      await response.stream.listen((_) {}).cancel();
      throw const ApiFailure(413, '文件超过读取上限 / File exceeds read bound');
    }
    await for (final chunk in response.stream) {
      cancellation?.check();
      if (builder.length + chunk.length > maxBytes) {
        throw const ApiFailure(413, '文件超过读取上限 / File exceeds read bound');
      }
      builder.add(chunk);
    }
    if (response.length != null && builder.length != response.length) {
      throw const FormatException('Incomplete file download');
    }
    cancellation?.check();
    return builder.takeBytes();
  }

  Future<DriveText> readText(
    DriveNode file, {
    AttachmentCancellation? cancellation,
  }) async {
    final before = await verify(file, cancellation: cancellation);
    final raw = await bytes(
      before,
      maxBytes: maxDriveTextBytes,
      cancellation: cancellation,
    );
    final after = await verify(before, cancellation: cancellation);
    final text = DriveText.decode(after, raw);
    if (after.etag.isNotEmpty && after.etag != text.hash) {
      throw DriveConflict(before, after);
    }
    return text;
  }
}

class RemoteDriveRepository extends DriveRepository {
  RemoteDriveRepository(this.client);
  final BookstarkClient client;
  bool _closed = false;
  @override
  bool get local => false;
  void _check(AttachmentCancellation? cancellation) {
    if (_closed) throw StateError('File space closed');
    cancellation?.check();
  }

  String _query(String endpoint, String path) =>
      '/api/webdav/files$endpoint?${Uri(queryParameters: {'path': drivePath(path)}).query}';
  Uri _sameOrigin(String value) {
    final uri = Uri.parse(value);
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.origin != client.baseUri.origin ||
        uri.hasFragment ||
        uri.hasQuery) {
      throw const FormatException('Invalid server file URL');
    }
    return uri;
  }

  @override
  Future<DriveProfile> profile({AttachmentCancellation? cancellation}) async {
    _check(cancellation);
    final row = await client.get(
      '/api/webdav/profile',
      abortTrigger: cancellation?.signal,
    );
    int number(String key) {
      final n = row[key];
      if (n is! int || n < 0) throw const FormatException('Invalid file limit');
      return n;
    }

    if (row['account'] is! String ||
        row['has_app_password'] is! bool ||
        row['usage'] is! Map ||
        row['built_in'] != true) {
      throw const FormatException('Invalid file profile');
    }
    return DriveProfile(
      usage: DriveUsage.fromJson(row['usage'] as Map),
      fileMaxBytes: number('file_max_bytes'),
      publicMaxBytes: number('public_max_bytes'),
      endpoint: _sameOrigin(row['endpoint'] as String),
      publicBase: _sameOrigin(row['public_base_url'] as String),
      account: row['account'] as String,
      hasAppPassword: row['has_app_password'] as bool,
    );
  }

  @override
  Future<List<DriveNode>> list(
    String path, {
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    final parent = drivePath(path),
        row = await client.get(
          _query('', parent),
          abortTrigger: cancellation?.signal,
        ),
        data = row['data'];
    if (data is! List) {
      throw const FormatException('Invalid directory response');
    }
    final files = data.map((item) => DriveNode.fromJson(item as Map)).toList();
    if (files.any((file) => driveParent(file.path) != parent) ||
        files.map((file) => file.id).toSet().length != files.length ||
        files.map((file) => file.name).toSet().length != files.length) {
      throw const FormatException('Invalid directory membership');
    }
    return files;
  }

  @override
  Future<DriveRead> open(
    DriveNode file, {
    String? range,
    String? ifRange,
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    if (file.directory) {
      throw const FormatException('Cannot download a directory');
    }
    final response = await client.downloadResponse(
      _query('/download', file.path),
      range: range,
      ifRange: ifRange,
      abortTrigger: cancellation?.signal,
    );
    return DriveRead(
      stream: response.stream,
      status: response.statusCode,
      headers: Map.unmodifiable(response.headers),
      length: response.contentLength,
    );
  }

  Future<DriveNode> _canonicalAfterWrite(DriveWriteReceipt receipt) async {
    try {
      final actual = await lookup(receipt.requestedPath);
      if (actual == null ||
          actual.id != receipt.id ||
          actual.directory != receipt.directory ||
          (!receipt.directory &&
              (actual.etag != receipt.hash || actual.size != receipt.size))) {
        throw const FormatException(
          'Acknowledged file differs from the current listing',
        );
      }
      return actual;
    } catch (error) {
      throw DriveWriteAcknowledged(receipt, error);
    }
  }

  @override
  Future<DriveNode> mkdir(
    String parent,
    String name, {
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    final target = driveChild(parent, name);
    final row = await client.post('/api/webdav/files/mkdir', {
      'path': drivePath(parent),
      'name': driveName(name),
    }, abortTrigger: cancellation?.signal);
    // The shipped Go mkdir response has an empty path. Confirm by real listing.
    final id = row['id'];
    if (id is! int ||
        id <= 0 ||
        row['name'] != name ||
        row['type'] != 'dir' ||
        (row['path'] != '' && row['path'] != target)) {
      throw const FormatException('Invalid directory creation receipt');
    }
    return _canonicalAfterWrite(
      DriveWriteReceipt(
        id: id,
        name: name,
        requestedPath: target,
        hash: '',
        size: 0,
        directory: true,
      ),
    );
  }

  Future<void> _relocate(
    String action,
    DriveNode source,
    String target,
    AttachmentCancellation? cancellation,
  ) async {
    _check(cancellation);
    final destination = drivePath(target);
    if (destination.isEmpty ||
        destination == source.path ||
        destination.startsWith('${source.path}/')) {
      throw const FormatException(
        'Target cannot be the source or its descendant',
      );
    }
    await verify(source, cancellation: cancellation);
    await client.post('/api/webdav/files/$action', {
      'path': source.path,
      'new_path': destination,
    }, abortTrigger: cancellation?.signal);
  }

  @override
  Future<void> rename(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => _relocate('rename', source, target, cancellation);
  @override
  Future<void> copy(
    DriveNode source,
    String target, {
    AttachmentCancellation? cancellation,
  }) => _relocate('copy', source, target, cancellation);
  @override
  Future<void> remove(
    DriveNode source, {
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    await verify(source, cancellation: cancellation);
    await client.mutate(
      'DELETE',
      _query('', source.path),
      {},
      abortTrigger: cancellation?.signal,
    );
  }

  Future<void> _target(
    String path,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
  ) async {
    final actual = await lookup(path, cancellation: cancellation);
    if (expected == null) {
      if (actual != null) throw DriveConflict(null, actual);
    } else if (expected.path != path ||
        actual == null ||
        actual.directory ||
        actual.id != expected.id ||
        actual.etag != expected.etag ||
        actual.isPublic != expected.isPublic ||
        actual.publicPath != expected.publicPath) {
      throw DriveConflict(expected, actual);
    }
  }

  @override
  Future<DriveNode> saveText(
    DriveText document,
    String content, {
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    final bytes = document.encode(content);
    if (bytes.length > maxDriveTextBytes) {
      throw const ApiFailure(
        413,
        '文本超过2MiB编辑上限 / Text exceeds the 2 MiB editor bound',
      );
    }
    await verify(document.node, cancellation: cancellation);
    final row = await client.mutate('PUT', '/api/webdav/files/content', {
      'path': document.node.path,
      'content': document.encodedContent(content),
      'content_type': document.node.mime,
    }, abortTrigger: cancellation?.signal);
    final node = DriveNode.fromJson(row['file'] as Map);
    if (node.path != document.node.path ||
        node.id != document.node.id ||
        node.directory ||
        node.etag != crypto.sha256.convert(bytes).toString()) {
      throw const FormatException(
        'Saved file confirmation does not match content',
      );
    }
    return _canonicalAfterWrite(
      DriveWriteReceipt(
        id: node.id,
        name: node.name,
        requestedPath: node.path,
        hash: node.etag,
        size: node.size,
      ),
    );
  }

  @override
  Future<Uri> publish(
    DriveNode file,
    String publicPath, {
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    if (file.directory) throw const FormatException('Only files can be public');
    await verify(file, cancellation: cancellation);
    final path = drivePublicPath(publicPath);
    if (path.isEmpty) throw const FormatException('Public path required');
    final base = (await profile(cancellation: cancellation)).publicBase!;
    final row = await client.post('/api/webdav/files/public', {
      'path': file.path,
      'public_path': path,
    }, abortTrigger: cancellation?.signal);
    final asset = row['asset'];
    if (asset is! Map ||
        asset['node_id'] != file.id ||
        asset['enabled'] != true ||
        asset['public_path'] != path) {
      throw const FormatException(
        'Public file confirmation does not match source',
      );
    }
    final url = _sameOrigin(row['url'] as String);
    final expected = [
      ...base.pathSegments.where((part) => part.isNotEmpty),
      ...path.split('/'),
    ];
    if (url.pathSegments.length != expected.length ||
        List.generate(
          expected.length,
          (index) => url.pathSegments[index] != expected[index],
        ).any((different) => different)) {
      throw const FormatException('Public URL does not match saved path');
    }
    return url;
  }

  @override
  Future<void> unpublish(
    DriveNode file, {
    AttachmentCancellation? cancellation,
  }) async {
    _check(cancellation);
    await verify(file, cancellation: cancellation);
    await client.mutate(
      'DELETE',
      _query('/public', file.path),
      {},
      abortTrigger: cancellation?.signal,
    );
  }

  @override
  Future<DriveUploadResult> upload(
    DriveSourceSnapshot source, {
    required String target,
    DriveNode? expected,
    AttachmentCancellation? cancellation,
    void Function(int, int)? onSent,
  }) async {
    _check(cancellation);
    final path = drivePath(target);
    if (path.isEmpty) throw const FormatException('Upload target required');
    final limits = await profile(cancellation: cancellation);
    final snapshot = source;
    if (snapshot.size > limits.fileMaxBytes) {
      throw const ApiFailure(
        413,
        '文件超过服务器单文件上限 / File exceeds server single-file limit',
      );
    }
    await snapshot.verifyMetadata(cancellation: cancellation);
    await _target(path, expected, cancellation);
    final mime = lookupMimeType(path) ?? 'application/octet-stream';
    await snapshot.verifyMetadata(cancellation: cancellation);
    final check = await client.post('/api/webdav/files/upload/check', {
      'path': path,
      'hash': snapshot.hash,
      'size': snapshot.size,
      'content_type': mime,
    }, abortTrigger: cancellation?.signal);
    Future<DriveUploadResult> confirmed(Map row, bool reused) async {
      final node = DriveNode.fromJson(row['file'] as Map);
      if (node.path != path ||
          node.directory ||
          node.etag != snapshot.hash ||
          node.size != snapshot.size) {
        throw const FormatException(
          'Upload confirmation does not match selected file',
        );
      }
      final canonical = await _canonicalAfterWrite(
        DriveWriteReceipt(
          id: node.id,
          name: node.name,
          requestedPath: path,
          hash: node.etag,
          size: node.size,
        ),
      );
      return DriveUploadResult(canonical, deduplicated: reused);
    }

    if (check['action'] == 'linked') return confirmed(check, true);
    if (check['action'] == 'prove') {
      final nonce = check['nonce'],
          token = check['token'],
          chunkSize = check['chunk_size'],
          indices = check['chunk_indices'];
      if (nonce is! String ||
          !RegExp(r'^[0-9a-fA-F]{48}$').hasMatch(nonce) ||
          token is! String ||
          !RegExp(r'^[0-9a-fA-F]{48}$').hasMatch(token) ||
          chunkSize is! int ||
          indices is! List ||
          indices.any((index) => index is! int)) {
        throw const FormatException('Invalid upload proof response');
      }
      final rawNonce = Uint8List.fromList([
        for (var n = 0; n < nonce.length; n += 2)
          int.parse(nonce.substring(n, n + 2), radix: 16),
      ]);
      final hashes = await snapshot.prove(
        nonce: rawNonce,
        chunkSize: chunkSize,
        indices: indices.cast<int>(),
        cancellation: cancellation,
      );
      await _target(path, expected, cancellation);
      final result = await client.post('/api/webdav/files/upload/prove', {
        'token': token,
        'chunk_hashes': hashes,
      }, abortTrigger: cancellation?.signal);
      return confirmed(result, true);
    }
    if (check['action'] != 'upload') {
      throw const FormatException('Unknown upload action');
    }
    await _target(path, expected, cancellation);
    final row = await client.upload(
      '/api/webdav/files/upload',
      name: driveBasename(path),
      data: snapshot.verifiedStream(cancellation: cancellation, onSent: onSent),
      length: snapshot.size,
      fields: {'path': driveParent(path)},
      abortTrigger: cancellation?.signal,
    );
    if (row['deduplicated'] is! bool) {
      throw const FormatException('Missing upload deduplication result');
    }
    return confirmed(row, row['deduplicated'] as bool);
  }

  @override
  void dispose() {
    _closed = true;
  }
}
