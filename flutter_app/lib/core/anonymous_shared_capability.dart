import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'complex_editor_document.dart';
import 'public_edit_link.dart';
import 'public_complex_wire_stub.dart'
    if (dart.library.io) 'public_complex_wire_io.dart'
    as wire;

class SharedCapabilityFailure implements Exception {
  const SharedCapabilityFailure(this.status);
  final int status;
  @override
  String toString() =>
      'Shared editing unavailable; review the current resource';
}

class SharedCapabilityIdentity {
  SharedCapabilityIdentity._(this.json);
  final Map<String, Object?> json;
  int get targetId => json['target_id'] as int;
  int get shareId => json['share_id'] as int;
  String get shareType => json['share_type'] as String;
  String get collection => json['blog_type'] as String;
  bool get protected => json['protected'] as bool;
  ComplexEditorKind get kind =>
      ComplexEditorKind.parse(json['format'] as String);
  factory SharedCapabilityIdentity.parse(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid shared identity');
    final json = Map<String, Object?>.from(raw);
    const keys = {
      'share_id',
      'target_id',
      'owner_member_id',
      'book_id',
      'share_type',
      'format',
      'protected',
      'blog_type',
    };
    if (json.length != keys.length ||
        !json.keys.every(keys.contains) ||
        ![
          'share_id',
          'target_id',
          'owner_member_id',
        ].every((k) => json[k] is int && (json[k] as int) > 0) ||
        json['book_id'] is! int ||
        json['protected'] is! bool ||
        json['format'] is! String) {
      throw const FormatException('Invalid shared identity');
    }
    ComplexEditorKind.parse(json['format'] as String);
    if (json['share_type'] == 'blog') {
      if (json['book_id'] != 0 ||
          !{'note', 'article'}.contains(json['blog_type'])) {
        throw const FormatException('Invalid shared collection');
      }
    } else if (json['share_type'] == 'document') {
      if ((json['book_id'] as int) <= 0 || json['blog_type'] != '') {
        throw const FormatException('Invalid shared chapter');
      }
    } else {
      throw const FormatException('Whole books cannot shared-edit');
    }
    return SharedCapabilityIdentity._(Map.unmodifiable(json));
  }
  bool same(SharedCapabilityIdentity other) =>
      jsonEncode(json) == jsonEncode(other.json);
}

class SharedCapabilitySource {
  SharedCapabilitySource._(
    this.identity,
    this.title,
    this.modified,
    this.document,
  );
  final SharedCapabilityIdentity identity;
  final String title, modified;
  final ComplexEditorDocument document;
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode([identity.json, title, modified, document.digest]),
        ),
      )
      .toString();
  factory SharedCapabilitySource.parse(Map<String, Object?> row) {
    const keys = {
      'identity',
      'title',
      'modify_time',
      'source_base64',
      'source_sha256',
      'bytes',
    };
    if (row.length != keys.length ||
        !row.keys.every(keys.contains) ||
        row['title'] is! String ||
        row['modify_time'] is! String ||
        row['source_base64'] is! String ||
        row['source_sha256'] is! String ||
        row['bytes'] is! int) {
      throw const FormatException('Invalid shared source response');
    }
    final key = SharedCapabilityIdentity.parse(row['identity']);
    final encoded = row['source_base64'] as String;
    final limit = key.kind == ComplexEditorKind.markdown
        ? 500 * 1024
        : key.kind.maxBytes;
    if (encoded.length > ((limit + 2) ~/ 3) * 4 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(encoded)) {
      throw const FormatException('Shared source exceeds limit');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != row['bytes'] ||
        bytes.length > limit ||
        base64Encode(bytes) != encoded ||
        sha256.convert(bytes).toString() != row['source_sha256']) {
      throw const FormatException('Shared source bytes mismatch');
    }
    final doc = ComplexEditorDocument.fromBytes(key.kind, bytes);
    final plain = doc.source.startsWith('\ufeff')
        ? doc.source.substring(1)
        : doc.source;
    if (plain.startsWith('ENC:')) throw const SharedCapabilityFailure(423);
    final title = row['title'] as String,
        modified = row['modify_time'] as String;
    ComplexEditorDocument.validateText(title);
    if (utf8.encode(title).length > 65536 ||
        modified.isEmpty ||
        modified.length > 128 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(modified)) {
      throw const FormatException('Shared metadata exceeds bound');
    }
    return SharedCapabilitySource._(key, title, modified, doc);
  }
}

class PreparedSharedCapabilitySave {
  PreparedSharedCapabilitySave._(this._owner, this._body);
  final AnonymousSharedCapability _owner;
  String? _body;
  bool _claimed = false;
  Future<Map<String, Object?>> sendOnce() => sendAfter(onSubmit: () async {});
  Future<Map<String, Object?>> sendAfter({
    required Future<void> Function() onSubmit,
  }) async {
    if (_claimed || _body == null) {
      throw StateError('Shared mutation already consumed');
    }
    _claimed = true;
    // prepare already completed the dedicated anonymous CSRF handshake. Durable
    // submission claim is awaited here, before the single actual mutation send.
    _owner._guard();
    await onSubmit();
    _owner._guard();
    final body = _body;
    if (body == null) throw StateError('Shared mutation retired');
    return _owner._json('PUT', '', body: body);
  }

  void retire() {
    _claimed = true;
    _body = null;
  }
}

/// No BookstarkClient argument: never imports account cookies or authorization.
class AnonymousSharedCapability {
  AnonymousSharedCapability(
    this.link, {
    required this.isCurrent,
    http.Client Function()? anonymousTestClient,
  }) : _clientFactory = anonymousTestClient ?? wire.anonymousClient;
  final PublicEditLink link;
  final bool Function() isCurrent;
  final http.Client Function() _clientFactory;
  final _retire = StreamController<void>.broadcast(sync: true);
  final _clients = <http.Client>{};
  String? _csrf;
  bool _closed = false;
  void close() {
    if (_closed) return;
    _closed = true;
    _retire.add(null);
    unawaited(_retire.close());
    for (final c in List.of(_clients)) {
      c.close();
    }
    _clients.clear();
    _csrf = null;
  }

  void _guard() {
    if (_closed || !isCurrent()) throw const SharedCapabilityFailure(0);
  }

  Uri _uri(String suffix) {
    final path = Uri.parse(link.requestPath);
    final fixed = '${path.path}/cas$suffix';
    if (!{'', '/read'}.contains(suffix) ||
        !RegExp(r'^/api/shares/[^/]+/edit$').hasMatch(path.path)) {
      throw const FormatException('Invalid shared route');
    }
    final ref = link.reference;
    return ref.server.replace(
      path: '${ref.server.path}$fixed',
      query: path.query,
    );
  }

  Future<(Map<String, Object?>, String?)> _perform(
    String method,
    Uri uri, {
    String? body,
    int max = 28 * 1024 * 1024 + 128 * 1024,
  }) async {
    _guard();
    if (uri.origin != link.reference.server.origin ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const SharedCapabilityFailure(0);
    }
    final client = _clientFactory();
    _clients.add(client);
    final stop = Completer<void>();
    void cancel() {
      if (!stop.isCompleted) stop.complete();
      client.close();
    }

    final retired = _retire.stream.listen((_) => cancel());
    final timer = Timer(const Duration(seconds: 20), cancel);
    Future<T> wait<T>(Future<T> value) => Future.any([
      value,
      stop.future.then<T>((_) => throw const SharedCapabilityFailure(0)),
    ]);
    try {
      final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: stop.future,
      )..followRedirects = false;
      request.headers.addAll({
        'accept': 'application/json',
        'cache-control': 'no-store',
        'accept-encoding': 'gzip',
      });
      if (body != null) {
        if (_csrf == null ||
            utf8.encode(body).length > 28 * 1024 * 1024 + 128 * 1024) {
          throw const SharedCapabilityFailure(0);
        }
        request.headers.addAll({
          'content-type': 'application/json; charset=utf-8',
          'cookie': 'csrf_token=$_csrf',
          'x-csrf-token': _csrf!,
        });
        request.body = body;
      }
      final response = await wait(client.send(request));
      _guard();
      if (response.statusCode != 200) {
        await response.stream.listen((_) {}).cancel();
        throw SharedCapabilityFailure(response.statusCode);
      }
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (media.split(';').first.trim() != 'application/json' ||
          media.contains('charset=') &&
              !RegExp(
                r'''charset=\s*["']?utf-8(?:["';\s]|$)''',
              ).hasMatch(media)) {
        await response.stream.listen((_) {}).cancel();
        throw const SharedCapabilityFailure(0);
      }
      final bytes = await wait(
        wire.bounded(
          response.stream,
          response.headers['content-encoding'],
          maxWire: max + 64 * 1024,
          maxPlain: max,
          abort: stop.future,
        ),
      );
      _guard();
      final value = jsonDecode(utf8.decode(bytes, allowMalformed: false));
      if (value is! Map || value['code'] != 0) {
        throw const SharedCapabilityFailure(0);
      }
      return (Map<String, Object?>.from(value), response.headers['set-cookie']);
    } finally {
      timer.cancel();
      cancel();
      await retired.cancel();
      _clients.remove(client);
    }
  }

  Future<void> _ensureCsrf() async {
    _guard();
    if (_csrf != null) return;
    final ref = link.reference.server;
    final result = await _perform(
      'GET',
      ref.replace(path: '${ref.path}/api/csrf-token'),
      max: 16 * 1024,
    );
    final value = result.$1['csrf_token'];
    if (value is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(value) ||
        !(result.$2 ?? '').contains('csrf_token=$value')) {
      throw const SharedCapabilityFailure(0);
    }
    _guard();
    _csrf = value; // ONLY own CSRF cookie, never returned member cookies.
  }

  Future<Map<String, Object?>> _json(
    String method,
    String suffix, {
    String? body,
  }) async {
    if (body != null) await _ensureCsrf();
    final result = await _perform(
      method,
      _uri(suffix),
      body: body,
      max: method == 'PUT' ? 128 * 1024 : 28 * 1024 * 1024 + 128 * 1024,
    );
    final data = result.$1['data'];
    if (data is! Map) throw const SharedCapabilityFailure(0);
    return Map<String, Object?>.from(data);
  }

  Future<Map<String, Object?>> lockedMetadata() async {
    final path = Uri.parse(link.requestPath), ref = link.reference.server;
    final result = await _perform(
      'GET',
      ref.replace(path: '${ref.path}${path.path}', query: path.query),
      max: 512 * 1024,
    );
    final data = result.$1['data'];
    if (data is! Map ||
        data['editable'] != true ||
        data['has_password'] != true) {
      throw const SharedCapabilityFailure(0);
    }
    return Map<String, Object?>.from(data);
  }

  Future<SharedCapabilitySource> read({String? password}) async {
    if (password != null) {
      ComplexEditorDocument.validateText(password);
      if (password.isEmpty || utf8.encode(password).length > 4096) {
        throw const SharedCapabilityFailure(423);
      }
    }
    return SharedCapabilitySource.parse(
      await _json(
        password == null ? 'GET' : 'POST',
        password == null ? '' : '/read',
        body: password == null ? null : jsonEncode({'password': password}),
      ),
    );
  }

  Future<PreparedSharedCapabilitySave> prepare(
    SharedCapabilitySource baseline,
    ComplexEditorDocument doc, {
    String? password,
  }) async {
    _guard();
    if (baseline.identity.kind != doc.kind) {
      throw const FormatException('Shared kind changed');
    }
    if (doc.kind == ComplexEditorKind.markdown && doc.byteLength > 500 * 1024) {
      throw const FormatException('Shared Markdown exceeds limit');
    }
    final value = doc.source.startsWith('\ufeff')
        ? doc.source.substring(1)
        : doc.source;
    if (value.startsWith('ENC:')) throw const SharedCapabilityFailure(423);
    if (baseline.identity.protected && (password == null || password.isEmpty)) {
      throw const SharedCapabilityFailure(423);
    }
    if (password != null && (utf8.encode(password).length > 4096)) {
      throw const SharedCapabilityFailure(423);
    }
    final body = jsonEncode({
      'source_base64': base64Encode(utf8.encode(doc.source)),
      'expected_source_sha256': baseline.document.digest,
      'expected_identity': baseline.identity.json,
      'password': ?password,
    });
    if (utf8.encode(body).length > 28 * 1024 * 1024 + 128 * 1024) {
      throw const FormatException('Shared source exceeds wire budget');
    }
    await _ensureCsrf();
    _guard();
    return PreparedSharedCapabilitySave._(this, body);
  }
}
