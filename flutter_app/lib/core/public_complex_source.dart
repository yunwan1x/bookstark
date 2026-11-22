import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'public_complex_wire_stub.dart'
    if (dart.library.io) 'public_complex_wire_io.dart'
    as wire;

class PublicComplexReadFailure implements Exception {
  const PublicComplexReadFailure();
  @override
  String toString() => 'Public content unavailable';
}

class PublicComplexLocked implements Exception {
  const PublicComplexLocked();
}

class PublicComplexContent {
  const PublicComplexContent({
    required this.reference,
    required this.title,
    required this.document,
    required this.protected,
    this.chapterIdentify,
    this.identity,
  });
  final PublicShareReference reference;
  final PublicShareDetail? identity;
  final String title;
  final ComplexEditorDocument document;
  final bool protected;
  final String? chapterIdentify;
  // No capability token/password/account/cookie exists in this surface value.
}

/// Own anonymous client only. No BookstarkClient or account-cookie parameter.
/// IO client disables automatic decompression so both wire/plain budgets apply.
class AnonymousPublicComplexSource {
  AnonymousPublicComplexSource({
    required this.isCurrent,
    http.Client? anonymousTestClient,
  }) : _client = anonymousTestClient ?? wire.anonymousClient();
  final bool Function() isCurrent;
  final http.Client _client;
  final _abort = Completer<void>();
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    _abort.complete();
    _client.close();
  }

  void _guard() {
    if (_closed || !isCurrent()) throw const PublicComplexReadFailure();
  }

  int _limit(ComplexEditorKind kind) =>
      kind == ComplexEditorKind.markdown ? 4 * 1024 * 1024 : kind.maxBytes;
  Future<Uint8List> _request(
    PublicShareReference ref,
    String path, {
    String? password,
    String mime = 'application/json',
    int max = 26 * 1024 * 1024,
  }) async {
    _guard();
    // One absolute budget covers headers AND every compressed/decoded body chunk.
    final deadline = Timer(const Duration(seconds: 20), close);
    Future<T> wait<T>(Future<T> work) => Future.any<T>([
      work,
      _abort.future.then<T>((_) => throw const PublicComplexReadFailure()),
    ]);
    try {
      final uri = Uri.parse(ref.server.toString() + path);
      if (uri.origin != ref.server.origin ||
          uri.userInfo.isNotEmpty ||
          uri.hasFragment) {
        throw const PublicComplexReadFailure();
      }
      final request = http.AbortableRequest(
        password == null ? 'GET' : 'POST',
        uri,
        abortTrigger: _abort.future,
      )..followRedirects = false;
      request.headers['accept'] = mime;
      request.headers['cache-control'] = 'no-store';
      request.headers['accept-encoding'] = 'gzip';
      if (password != null) {
        ComplexEditorDocument.validateText(password);
        if (password.isEmpty || utf8.encode(password).length > 4096) {
          throw const PublicComplexReadFailure();
        }
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.body = jsonEncode({'password': password});
      }
      final response = await wait(_client.send(request));
      _guard();
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode != 200 ||
          media.split(';').first.trim() != mime ||
          media.contains('charset=') &&
              !RegExp(
                r'''charset=\s*["']?utf-8(?:["';\s]|$)''',
              ).hasMatch(media)) {
        await response.stream.listen((_) {}).cancel();
        throw const PublicComplexReadFailure();
      }
      final bytes = await wait(
        wire.bounded(
          response.stream,
          response.headers['content-encoding'],
          maxWire: max + 64 * 1024,
          maxPlain: max,
          abort: _abort.future,
        ),
      );
      _guard();
      return bytes;
    } catch (_) {
      throw const PublicComplexReadFailure();
    } // Never echo token URLs.
    finally {
      deadline.cancel();
    }
  }

  Future<Map<String, Object?>> _json(
    PublicShareReference ref,
    String path, {
    String? password,
  }) async {
    final bytes = await _request(ref, path, password: password);
    final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
    if (value is! Map || value['code'] != 0 || value['data'] is! Map) {
      throw const PublicComplexReadFailure();
    }
    return Map<String, Object?>.from(value['data'] as Map);
  }

  PublicShareDetail _identity(
    PublicShareReference ref,
    Map<String, Object?> row,
  ) => PublicShareDetail.fromJson(ref, {
    ...row,
    'content': '',
  }); // Existing MD parser's 4MiB body limit is not the complex format limit.
  ComplexEditorKind _kind(Object? format) {
    if (format is! String) throw const PublicComplexReadFailure();
    return ComplexEditorKind.parse(format);
  }

  /// Source-free initial dispatch; never passes a complex body to the old MD parser.
  Future<PublicShareDetail> inspect(PublicShareReference ref) async {
    try {
      final row = await _json(ref, ref.detailPath);
      final detail = _identity(ref, row);
      _guard();
      return detail;
    } catch (_) {
      throw const PublicComplexReadFailure();
    }
  }

  Future<PublicComplexContent> read(
    PublicShareReference ref, {
    String? chapterIdentify,
    String? password,
    String? editToken,
  }) async {
    _guard();
    // Any failure (including JSON/schema validation) exposes no URL/password.
    try {
      return await _read(
        ref,
        chapterIdentify: chapterIdentify,
        password: password,
        editToken: editToken,
      );
    } on PublicComplexLocked {
      rethrow;
    } catch (_) {
      throw const PublicComplexReadFailure();
    }
  }

  Future<PublicComplexContent> _read(
    PublicShareReference ref, {
    String? chapterIdentify,
    String? password,
    String? editToken,
  }) async {
    if (chapterIdentify != null && (password != null || editToken != null)) {
      throw const PublicComplexReadFailure();
    }
    var metadata = await _json(ref, ref.detailPath);
    var detail = _identity(ref, metadata);
    String path = ref.detailPath;
    var title = detail.title, format = detail.format, locked = detail.locked;
    var content = metadata['content'];
    PublicShareNode? chapterNode;
    if (chapterIdentify != null) {
      if (detail.kind != PublicShareKind.book || detail.locked) {
        throw const PublicComplexReadFailure();
      }
      PublicShareNode? find(List<PublicShareNode> nodes) {
        for (final node in nodes) {
          if (node.identify == chapterIdentify) return node;
          final child = find(node.children);
          if (child != null) return child;
        }
        return null;
      }

      final node = find(detail.nodes);
      if (node == null) throw const PublicComplexReadFailure();
      chapterNode = node;
      path = ref.chapterPath(chapterIdentify);
      metadata = await _json(ref, path);
      title = metadata['title'] as String;
      format = metadata['doc_type'] as String;
      if (format != node.format) throw const PublicComplexReadFailure();
      content = metadata['content'];
      locked = false;
    } else if (editToken != null) {
      if (editToken.isEmpty ||
          editToken.length > 256 ||
          detail.kind == PublicShareKind.book) {
        throw const PublicComplexReadFailure();
      }
      final query = Uri(queryParameters: {'token': editToken}).query;
      path = '${ref.detailPath}/edit?$query';
      metadata = await _json(ref, path);
      if (metadata['editable'] != true ||
          metadata['share_type'] != detail.kind.name ||
          metadata['doc_type'] != detail.format ||
          metadata['has_password'] != detail.protected) {
        throw const PublicComplexReadFailure();
      }
      title = metadata['title'] as String;
      format = metadata['doc_type'] as String;
      content = metadata['content'];
      locked = metadata['has_password'] == true;
    }
    final kind = _kind(format);
    if (locked && password == null) throw const PublicComplexLocked();
    Uint8List bytes;
    if (locked && editToken != null) {
      final query = Uri(queryParameters: {'token': editToken}).query;
      bytes = await _request(
        ref,
        '${ref.detailPath}/edit/content/unlock?$query',
        password: password,
        mime: kind == ComplexEditorKind.html
            ? 'text/html'
            : kind == ComplexEditorKind.richdoc
            ? 'application/json'
            : 'text/plain',
        max: _limit(kind),
      );
    } else if (locked) {
      if (detail.kind != PublicShareKind.blog) {
        throw const PublicComplexReadFailure();
      }
      if (kind == ComplexEditorKind.html || kind == ComplexEditorKind.richdoc) {
        bytes = await _request(
          ref,
          '${ref.detailPath}/verify-password/raw',
          password: password,
          mime: kind == ComplexEditorKind.html
              ? 'text/html'
              : 'application/json',
          max: _limit(kind),
        );
      } else {
        final plain = await _json(
          ref,
          '${ref.detailPath}/verify-password',
          password: password,
        );
        if (plain['content'] is! String) throw const PublicComplexReadFailure();
        ComplexEditorDocument.validateText(plain['content'] as String);
        bytes = Uint8List.fromList(utf8.encode(plain['content'] as String));
      }
    } else if (kind == ComplexEditorKind.html ||
        kind == ComplexEditorKind.richdoc) {
      final raw = metadata['content_url'];
      if (raw is! String) throw const PublicComplexReadFailure();
      final expected = editToken == null
          ? '$path/content/raw'
          : '${ref.detailPath}/edit/content/raw?${Uri(queryParameters: {'token': editToken}).query}';
      final mounted =
          ref.server.path.replaceFirst(RegExp(r'/+$'), '') + expected;
      if (raw != expected && raw != mounted) {
        throw const PublicComplexReadFailure();
      }
      bytes = await _request(
        ref,
        expected,
        mime: kind == ComplexEditorKind.html ? 'text/html' : 'application/json',
        max: _limit(kind),
      );
    } else {
      if (content is! String) throw const PublicComplexReadFailure();
      ComplexEditorDocument.validateText(content);
      bytes = Uint8List.fromList(utf8.encode(content));
    }
    if (bytes.length > _limit(kind)) throw const PublicComplexReadFailure();
    final document = ComplexEditorDocument.fromBytes(kind, bytes);
    final prefix = document.source.startsWith("\ufeff")
        ? document.source.substring(1)
        : document.source;
    if (prefix.startsWith("ENC:")) throw const PublicComplexReadFailure();
    // Recheck public availability/identity after raw/unlock, without preserving
    // a password/token in the result or promising a server version/CAS.
    final latest = _identity(ref, await _json(ref, ref.detailPath));
    if (latest.kind != detail.kind ||
        latest.targetId != detail.targetId ||
        latest.shareId != detail.shareId ||
        latest.format != detail.format ||
        latest.protected != detail.protected) {
      throw const PublicComplexReadFailure();
    }
    if (chapterNode != null) {
      PublicShareNode? findLatest(List<PublicShareNode> nodes) {
        for (final node in nodes) {
          if (node.identify == chapterIdentify) return node;
          final child = findLatest(node.children);
          if (child != null) return child;
        }
        return null;
      }

      final freshNode = findLatest(latest.nodes);
      if (freshNode == null ||
          freshNode.id != chapterNode.id ||
          freshNode.format != chapterNode.format) {
        throw const PublicComplexReadFailure();
      }
    }
    if (editToken != null) {
      final fresh = await _json(ref, path);
      if (fresh['editable'] != true ||
          fresh['doc_type'] != format ||
          fresh['modify_time'] != metadata['modify_time'] ||
          fresh['has_password'] != locked) {
        throw const PublicComplexReadFailure();
      }
    }
    _guard();
    return PublicComplexContent(
      reference: ref,
      title: title,
      document: document,
      protected: locked,
      chapterIdentify: chapterIdentify,
      identity: latest,
    );
  }
}
