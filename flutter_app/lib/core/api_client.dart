import 'local_legacy_json.dart';
import 'prepared_owned_image_upload.dart';
import 'image_dimensions.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'drive_models.dart' show drivePath, driveName;
import 'go_text.dart';
import 'article_metadata_json.dart';
import 'note_list_metadata_json.dart';
import 'raw_document_client.dart';
import 'public_edit_link.dart';
import 'public_share_models.dart';

import 'dart:convert';
import 'dart:async';

import 'server_events.dart';
import 'public_feed_models.dart';

import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

enum DriveMutationAction { mkdir, rename, copy, remove }

/// Prepared fixed authenticated request. It performs no mutation until sendOnce.
/// The business transport MUST await its durable onSubmit before calling sendOnce.
class PreparedAuthenticatedJsonRequest {
  PreparedAuthenticatedJsonRequest._(
    this.uri,
    this.bodyDigestSource,
    this._send,
    this.retire,
  );
  final Uri uri;
  final String bodyDigestSource;
  final Future<Map<String, Object?>> Function() _send;
  final void Function() retire;
  bool _used = false;
  Future<Map<String, Object?>> sendOnce() {
    if (_used) throw const ApiFailure(409, 'Request already used');
    _used = true;
    return _send();
  }

  Future<Map<String, Object?>> sendAfter({
    required Future<void> Function() onSubmit,
  }) async {
    if (_used) throw const ApiFailure(409, 'Request already used');
    _used = true;
    try {
      await onSubmit();
      return await _send();
    } finally {
      retire();
    }
  }
}

class BookstarkClient {
  BookstarkClient(
    String server, {
    http.Client? transport,
    http.Client? rawDocumentTransport,
  }) : baseUri = normalizeServer(server),
       _transport = transport ?? http.Client(),
       _rawDocumentTransport = rawDocumentTransport,
       _ownsRawDocumentTransport = rawDocumentTransport == null;
  final Uri baseUri;
  final http.Client _transport;
  http.Client? _rawDocumentTransport;
  final bool _ownsRawDocumentTransport;
  final _rawDocumentStops = <Completer<void>>{};
  int _rawSessionEpoch = 0;
  int get sessionRevision => _rawSessionEpoch;
  bool _rawClosed = false;
  String _rawSessionIdentity() =>
      jsonEncode([_rawSessionEpoch, _cookies, _language]);
  void _retireRawDocumentReads() {
    _rawSessionEpoch++;
    for (final stop in _rawDocumentStops.toList()) {
      if (!stop.isCompleted) stop.complete();
    }
    _rawDocumentStops.clear();
  }

  final Map<String, String> _cookies = {};
  String? _language;
  String? get language => _language;
  set language(String? value) {
    if (value != null && !['zh', 'en'].contains(value)) {
      throw ArgumentError.value(value);
    }
    _language = value;
  }

  static Uri normalizeServer(String value) {
    final uri = Uri.parse(value.trim());
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('请输入不含账号、查询参数或片段的 HTTP/HTTPS 服务器地址');
    }
    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  Uri _endpoint(String path) {
    if (!path.startsWith('/api/') ||
        path.startsWith('//') ||
        Uri.parse(path).hasAuthority ||
        Uri.parse(path).hasScheme) {
      throw const FormatException('API 请求只能访问当前服务器');
    }
    final suffix = Uri.parse(path);
    return baseUri.replace(
      path: '${baseUri.path}${suffix.path}',
      query: suffix.hasQuery ? suffix.query : null,
    );
  }

  Map<String, String> exportSession() => Map.unmodifiable(_cookies);
  void restoreSession(Map<String, String> cookies) {
    _retireRawDocumentReads();
    _cookies.clear();
    for (final entry in cookies.entries) {
      if (['token', 'csrf_token'].contains(entry.key) &&
          !RegExp(r'[\r\n;]').hasMatch(entry.value)) {
        _cookies[entry.key] = entry.value;
      }
    }
  }

  Future<Map<String, Object?>> login(String account, String password) =>
      _authJson(
        'POST',
        '/api/login',
        body: {'account': account, 'password': password},
      );

  Future<Map<String, Object?>> accountFormConfiguration() =>
      _authJson('GET', '/api/register-config');

  Future<Map<String, Object?>> submitAccountForm(
    String path,
    Map<String, Object?> body, {
    void Function()? onSubmitted,
  }) async {
    if (!{
      '/api/register',
      '/api/password/forgot',
      '/api/password/reset',
    }.contains(path)) {
      throw ArgumentError('Unsupported account form');
    }
    _endpoint(path);
    if (!_cookies.containsKey('csrf_token')) {
      await _authJson('GET', '/api/csrf-token');
    }
    if (!_cookies.containsKey('csrf_token')) {
      throw const ApiFailure(403, '服务器未返回 CSRF Cookie，请检查服务器配置');
    }
    return _authJson(
      'POST',
      path,
      body: body,
      csrf: true,
      onSubmitted: onSubmitted,
    );
  }

  Future<Map<String, Object?>> _authJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool csrf = false,
    void Function()? onSubmitted,
  }) async {
    final stopped = Completer<void>();
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    Future<Map<String, Object?>> perform() async {
      final request = http.AbortableRequest(
        method,
        _endpoint(path),
        abortTrigger: stopped.future,
      );
      if (body != null) {
        final encoded = utf8.encode(jsonEncode(body));
        if (encoded.length > 16 * 1024) {
          throw const FormatException('Authentication request exceeds limit');
        }
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.bodyBytes = encoded;
      }
      _authenticate(request);
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      if (csrf) request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      onSubmitted?.call();
      final response = await _transport.send(request);
      late Uint8List bytes;
      try {
        bytes = await readBoundedResponse(response, maxBytes: 64 * 1024);
      } on ApiFailure {
        // A locally detected oversized reply is not an HTTP rejection receipt.
        throw const FormatException('Authentication response exceeds limit');
      }
      if (stopped.isCompleted) {
        throw TimeoutException('Retired authentication request');
      }
      return _decode(
        http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        ),
      );
    }

    try {
      return await perform().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          stop();
          throw TimeoutException('Authentication request timed out');
        },
      );
    } finally {
      stop();
    }
  }

  /// Narrow speech catalogue: bounded body, deadline, no redirects/cookie writes.
  Future<Map<String, Object?>> speechVoicesJson({
    required Future<void> abortTrigger,
  }) async {
    final stop = Completer<void>();
    void cancel() {
      if (!stop.isCompleted) stop.complete();
    }

    abortTrigger.then(
      (_) => cancel(),
      onError: (Object _, StackTrace _) => cancel(),
    );
    final timer = Timer(const Duration(seconds: 15), cancel);
    try {
      if (stop.isCompleted) throw StateError('Speech catalogue cancelled');
      final request = http.AbortableRequest(
        'GET',
        _endpoint('/api/ai/tts/voices'),
        abortTrigger: stop.future,
      )..followRedirects = false;
      _authenticate(request);
      request.headers['accept'] = 'application/json';
      final response = await _transport.send(request);
      final bytes = await readBoundedResponse(response, maxBytes: 16 * 1024);
      if (stop.isCompleted) throw StateError('Speech catalogue cancelled');
      if ((response.headers['content-type'] ?? '')
              .split(';')
              .first
              .trim()
              .toLowerCase() !=
          'application/json') {
        throw const FormatException('Speech catalogue must be JSON');
      }
      return _decode(
        http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
        ),
      );
    } finally {
      timer.cancel();
      cancel();
    }
  }

  // Token+explicit epoch define identity. Normal CSRF and UI language changes
  // are deliberately not ownership transitions.
  void Function() _legacySessionGuard() {
    final epoch = sessionRevision, token = _cookies['token'];
    void guard() {
      if (_rawClosed ||
          sessionRevision != epoch ||
          _cookies['token'] != token) {
        throw const ApiFailure(499, 'Legacy request identity retired');
      }
    }

    guard();
    return guard;
  }

  Future<Map<String, Object?>> get(String path, {Future<void>? abortTrigger}) =>
      _request('GET', path, abortTrigger: abortTrigger);
  Future<Map<String, Object?>> post(
    String path,
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
  }) => mutate('POST', path, body, abortTrigger: abortTrigger);

  Future<Map<String, Object?>> mutate(
    String method,
    String path,
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
    void Function()? beforeSubmit,
  }) async {
    if (!['POST', 'PUT', 'PATCH', 'DELETE'].contains(method)) {
      throw ArgumentError.value(method);
    }
    _endpoint(path);
    final guard = _legacySessionGuard();
    await _ensureCsrf(abortTrigger: abortTrigger);
    guard();
    return _request(
      method,
      path,
      body: body,
      csrf: true,
      sessionGuard: guard,
      beforeSubmit: beforeSubmit,
      abortTrigger: abortTrigger,
    );
  }

  Future<void> _ensureCsrf({Future<void>? abortTrigger}) async {
    if (!_cookies.containsKey('csrf_token')) {
      await _request('GET', '/api/csrf-token', abortTrigger: abortTrigger);
    }
    if (!_cookies.containsKey('csrf_token')) {
      throw const ApiFailure(403, '服务器未返回 CSRF Cookie，请检查服务器配置');
    }
  }

  Future<Map<String, Object?>> _request(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool csrf = false,
    Future<void>? abortTrigger,
    void Function()? beforeSubmit,
    void Function()? sessionGuard,
  }) async {
    final guard = sessionGuard ?? _legacySessionGuard();
    guard();
    final request = http.AbortableRequest(
      method,
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    return _sendJson(
      request,
      csrf: csrf,
      beforeSubmit: beforeSubmit,
      sessionGuard: guard,
    );
  }

  Future<Map<String, Object?>> upload(
    String path, {
    required String name,
    required Stream<List<int>> data,
    required int length,
    Map<String, String> fields = const {},
    Future<void>? abortTrigger,
    void Function()? beforeSubmit,
  }) async {
    _endpoint(path);
    if (length < 0 || RegExp(r'[\r\n]').hasMatch(name)) {
      throw const FormatException('Invalid upload');
    }
    final guard = _legacySessionGuard();
    await _ensureCsrf(abortTrigger: abortTrigger);
    guard();
    final request = http.AbortableMultipartRequest(
      'POST',
      _endpoint(path),
      abortTrigger: abortTrigger,
    )..fields.addAll(fields);
    request.files.add(http.MultipartFile('file', data, length, filename: name));
    return _sendJson(
      request,
      csrf: true,
      beforeSubmit: beforeSubmit,
      sessionGuard: guard,
    );
  }

  void _authenticate(http.BaseRequest request) {
    request.followRedirects = false;
    final cookies = _cookies.entries.map((e) => '${e.key}=${e.value}').toList();
    if (_language != null) {
      cookies.add('lang=$_language');
      request.headers['accept-language'] = _language!;
    }
    if (cookies.isNotEmpty) request.headers['cookie'] = cookies.join('; ');
  }

  Stream<ServerEvent> postEvents(
    String path,
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
    void Function()? beforeSubmit,
  }) => decodeServerEvents(
    postStream(
      path,
      body,
      accept: 'text/event-stream',
      abortTrigger: abortTrigger,
      beforeSubmit: beforeSubmit,
    ),
  );

  /// Authenticated, same-origin streaming POST shared by SSE and framed audio.
  /// The format decoder owns byte/frame limits; cancellation aborts transport.
  Stream<List<int>> postStream(
    String path,
    Map<String, Object?> body, {
    required String accept,
    Future<void>? abortTrigger,
    void Function()? beforeSubmit,
  }) async* {
    _endpoint(path);
    if (!{'text/event-stream', 'application/x-ndjson'}.contains(accept)) {
      throw ArgumentError.value(accept);
    }
    final stopped = Completer<void>();
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    abortTrigger?.then(
      (_) => stop(),
      onError: (Object error, StackTrace stack) => stop(),
    );
    try {
      await _ensureCsrf(abortTrigger: stopped.future);
      final request = http.AbortableRequest(
        'POST',
        _endpoint(path),
        abortTrigger: stopped.future,
      );
      request.followRedirects = false;
      _authenticate(request);
      request.headers['accept'] = accept;
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
      beforeSubmit?.call();
      final response = await _transport
          .send(request)
          .timeout(const Duration(seconds: 45));
      final matchesType =
          (response.headers['content-type'] ?? '')
              .split(';')
              .first
              .trim()
              .toLowerCase() ==
          accept;
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          !matchesType) {
        final bytes = await readBoundedResponse(response, maxBytes: 256 * 1024);
        _decode(
          http.Response.bytes(
            bytes,
            response.statusCode,
            headers: response.headers,
          ),
        );
        throw ApiFailure(
          502,
          accept == 'text/event-stream'
              ? '服务器未返回事件流 / Server did not return an event stream'
              : '服务器未返回音频数据流 / Server did not return an audio stream',
        );
      }
      yield* response.stream.timeout(const Duration(seconds: 45));
    } finally {
      stop();
    }
  }

  /// Legacy servers expose full discovery filters only on this read-only page.
  /// Return bounded inert text; callers must parse data, never execute scripts.
  Future<String> publicFeedHtml(
    PublicFeedQuery query, {
    Future<void>? abortTrigger,
  }) async {
    final suffix = Uri.parse(query.requestPath);
    final request = http.AbortableRequest(
      'GET',
      baseUri.replace(path: '${baseUri.path}/shares', query: suffix.query),
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'text/html';
    final response = await _transport.send(request);
    final bytes = await readBoundedResponse(
      response,
      maxBytes: 4 * 1024 * 1024,
    );
    if (response.statusCode != 200) {
      throw ApiFailure(
        response.statusCode,
        '无法加载公开广场 / Unable to load public feed',
      );
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (contentType.split(';').first.trim() != 'text/html' ||
        contentType.contains('charset=') &&
            !RegExp(
              r'''charset=\s*["']?utf-8(?:["';\s]|$)''',
            ).hasMatch(contentType)) {
      throw const FormatException('Public feed must be UTF-8 HTML');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }

  Future<void> prepareTaskCompletion({Future<void>? abortTrigger}) =>
      _publicDeadline(
        (abort) => _ensureCsrf(abortTrigger: abort),
        abortTrigger: abortTrigger,
      );

  /// Original bounded task envelope, retaining member_id for strict action checks.
  Future<Map<String, Object?>> ownedTaskMetadataJson(
    int id, {
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Invalid task ID');
    return _noteBoundedJson(
      'GET',
      '/api/tasks/$id',
      abortTrigger: abortTrigger,
    );
  }

  /// Native-only raw wire GET. Never uses the normal (auto-decoding) transport,
  /// never accepts a metadata-supplied arbitrary URL, and never applies cookies
  /// from the response to this session.
  Future<http.StreamedResponse> rawDocumentGet(
    Uri uri, {
    required int maxWireBytes,
    required Future<void> abortTrigger,
  }) async {
    final prefix = baseUri.path;
    final path = uri.path;
    final pattern = RegExp(
      '^${RegExp.escape(prefix)}'
      r'/api/docs/([1-9][0-9]*)(/content/raw)?$',
    );
    final match = pattern.firstMatch(path);
    if (match == null ||
        int.tryParse(match.group(1)!) == null ||
        maxWireBytes <= 0 ||
        maxWireBytes > 128 * 1024 * 1024 ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.toString() != baseUri.replace(path: path).toString()) {
      throw const FormatException('Invalid owned document wire request');
    }
    if (_rawClosed || (_cookies['token'] ?? '').isEmpty) {
      throw const ApiFailure(401, 'Document session unavailable');
    }
    final identity = _rawSessionIdentity();
    final stopped = Completer<void>();
    _rawDocumentStops.add(stopped);
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
      _rawDocumentStops.remove(stopped);
    }

    var cancelled = false;
    abortTrigger.then(
      (_) {
        cancelled = true;
        stop();
      },
      onError: (Object _, StackTrace _) {
        cancelled = true;
        stop();
      },
    );
    var expired = false;
    final timer = Timer(const Duration(seconds: 20), () {
      expired = true;
      stop();
    });
    void guard() {
      if (_rawClosed ||
          cancelled ||
          expired ||
          stopped.isCompleted ||
          _rawSessionIdentity() != identity) {
        throw const ApiFailure(499, 'Document read retired');
      }
    }

    http.StreamedResponse response;
    try {
      await Future<void>.value();
      guard();
      final transport = _rawDocumentTransport ??= createRawDocumentClient();
      final request = http.AbortableRequest(
        'GET',
        uri,
        abortTrigger: stopped.future,
      )..followRedirects = false;
      _authenticate(request);
      request.headers['accept'] =
          'application/json, text/html, application/octet-stream';
      request.headers['accept-encoding'] = 'gzip';
      request.headers['cache-control'] = 'no-store';
      final pending = transport.send(request);
      unawaited(
        pending.then<void>((lateResponse) async {
          if (stopped.isCompleted) {
            try {
              await lateResponse.stream
                  .listen((_) {}, onError: (Object _, StackTrace _) {})
                  .cancel();
            } catch (_) {}
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      response = await Future.any<http.StreamedResponse>([
        pending,
        stopped.future.then<http.StreamedResponse>(
          (_) => throw const ApiFailure(499, 'Document read retired'),
        ),
      ]).timeout(const Duration(seconds: 20));
      try {
        guard();
        if (response.statusCode != 200 ||
            response.isRedirect ||
            (response.request != null && response.request!.url != uri) ||
            (response.contentLength != null &&
                response.contentLength! > maxWireBytes)) {
          throw ApiFailure(
            response.statusCode,
            'Document wire response unavailable',
          );
        }
      } catch (_) {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        rethrow;
      }
    } catch (_) {
      timer.cancel();
      stop();
      rethrow;
    }
    Stream<List<int>> body() async* {
      var count = 0;
      final iterator = StreamIterator<List<int>>(response.stream);
      try {
        guard();
        while (await Future.any<bool>([
          iterator.moveNext(),
          stopped.future.then<bool>(
            (_) => throw const ApiFailure(499, 'Document read retired'),
          ),
        ])) {
          guard();
          final chunk = iterator.current;
          count += chunk.length;
          if (count > maxWireBytes) {
            throw const ApiFailure(413, 'Document wire response exceeds bound');
          }
          yield chunk;
        }
        guard();
      } finally {
        timer.cancel();
        stop();
        await iterator.cancel();
      }
    }

    return http.StreamedResponse(
      body(),
      response.statusCode,
      headers: response.headers,
      contentLength: response.contentLength,
      request: response.request,
      reasonPhrase: response.reasonPhrase,
      isRedirect: false,
      persistentConnection: response.persistentConnection,
    );
  }

  /// Original envelope; body projection validates the entire stream while
  /// discarding full note bodies before native list models are allocated.
  /// Fixed owned-summary endpoints only; bounded JSON, same origin, no redirect.
  Future<Map<String, Object?>> readTopicSummaryContent(
    int topicId,
    int summaryId, {
    required int expectedSessionRevision,
    required bool Function() isCurrent,
  }) => _topicSummaryContentJson(
    'GET',
    topicId,
    summaryId,
    expectedSessionRevision: expectedSessionRevision,
    isCurrent: isCurrent,
  );
  Future<Map<String, Object?>> updateTopicSummaryContent(
    int topicId,
    int summaryId, {
    required String content,
    required String expectedSourceSHA,
    required int expectedSessionRevision,
    required bool Function() isCurrent,
  }) {
    if (content.trim().isEmpty ||
        content.runes.length > 20000 ||
        utf8.encode(content).length > 80000 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedSourceSHA)) {
      throw const FormatException('Invalid summary content or baseline');
    }
    return _topicSummaryContentJson(
      'PUT',
      topicId,
      summaryId,
      body: {'content': content, 'expected_source_sha256': expectedSourceSHA},
      expectedSessionRevision: expectedSessionRevision,
      isCurrent: isCurrent,
    );
  }

  Future<Map<String, Object?>> _topicSummaryContentJson(
    String method,
    int topicId,
    int summaryId, {
    Map<String, Object?>? body,
    required int expectedSessionRevision,
    required bool Function() isCurrent,
  }) async {
    if (topicId <= 0 || summaryId <= 0 || !{'GET', 'PUT'}.contains(method)) {
      throw const FormatException('Invalid summary source identity');
    }
    void guard() {
      if (sessionRevision != expectedSessionRevision || !isCurrent()) {
        throw StateError('Summary source owner retired');
      }
    }

    guard();
    try {
      final actual = await _boundedSettingsJson(
        method,
        '/api/topics/$topicId/summaries/$summaryId/content',
        body: body,
        maxRequestBytes: 256 * 1024,
        maxResponseBytes: 256 * 1024,
        sanitizeApiErrors: true,
        requireSuccessCode: true,
        onSubmitted: guard,
      );
      guard();
      const keys = {
        'summary_id',
        'topic_id',
        'content',
        'summary_type',
        'order_sort',
        'comment_count',
        'create_time',
        'modify_time',
      };
      if (actual.length != keys.length ||
          !actual.keys.toSet().containsAll(keys) ||
          actual['summary_id'] != summaryId ||
          actual['topic_id'] != topicId ||
          actual['content'] is! String ||
          (actual['content'] as String).length > 80000 ||
          utf8.encode(actual['content'] as String).length > 80000 ||
          !{'manual', 'ai'}.contains(actual['summary_type']) ||
          actual['order_sort'] is! int ||
          actual['comment_count'] is! int ||
          (actual['comment_count'] as int) < 0) {
        throw const FormatException('Complete bounded summary source required');
      }
      for (final key in ['create_time', 'modify_time']) {
        if (actual[key] is! String ||
            DateTime.tryParse(actual[key] as String) == null) {
          throw const FormatException('Actual summary version required');
        }
      }
      _scopedText(actual['content'] as String);
      return actual;
    } on FormatException {
      throw const FormatException(
        'Summary source unavailable or exceeds read limits',
      );
    } on ApiFailure catch (error) {
      throw ApiFailure(
        error.status,
        'Summary source unavailable; draft retained',
      );
    }
  }

  Future<Map<String, Object?>> noteListPageMetadata(
    String path, {
    Future<void>? abortTrigger,
  }) {
    final uri = Uri.parse(path);
    if (uri.path != '/api/blogs' || uri.hasFragment) {
      throw const FormatException('Invalid note list endpoint');
    }
    return _noteBoundedJson(
      'GET',
      path,
      abortTrigger: abortTrigger,
      listProjection: true,
    );
  }

  /// One explicit create attempt. The callback marks the uncertainty boundary:
  /// CSRF has succeeded and the next operation is the sole transport send.
  Future<Map<String, Object?>> createMarkdownNoteJson(
    Map<String, Object?> body, {
    required void Function() onSubmit,
    Future<void>? abortTrigger,
  }) {
    if (!{'note', 'article'}.contains(body['blog_type']) ||
        body['editor_type'] != 'markdown' ||
        body['visibility'] != 0 ||
        body['blog_title'] is! String ||
        body['blog_content'] is! String) {
      throw const FormatException('Invalid ordinary Markdown creation');
    }
    return _noteBoundedJson(
      'POST',
      '/api/blogs',
      body: body,
      onSubmit: onSubmit,
      abortTrigger: abortTrigger,
      maxBytes: 26 * 1024 * 1024,
      maxRequestBytes: 26 * 1024 * 1024,
    );
  }

  /// Full bounded source for an explicitly opened ordinary owner note.
  /// Ownership/editor-kind must additionally be verified by the caller.
  Future<Map<String, Object?>> boundedOwnedMarkdownJson(
    int id, {
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Invalid note ID');
    return _noteBoundedJson(
      'GET',
      '/api/blogs/$id',
      abortTrigger: abortTrigger,
      maxBytes: 26 * 1024 * 1024,
    );
  }

  Future<Map<String, Object?>> boundedResourceLabelsJson(
    int id, {
    String? replacement,
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Invalid note ID');
    return _noteBoundedJson(
      replacement == null ? 'GET' : 'PUT',
      '/api/labels/resource/blog/$id',
      body: replacement == null ? null : {'labels': replacement},
      abortTrigger: abortTrigger,
    );
  }

  Future<Map<String, Object?>> _noteBoundedJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
    void Function()? onSubmit,
    bool listProjection = false,
    int maxBytes = 128 * 1024,
    int maxRequestBytes = 64 * 1024,
  }) {
    // Validate current-origin endpoint before CSRF or any other network work.
    final endpoint = _endpoint(path);
    final payload = body == null ? null : jsonEncode(body);
    if (payload != null && utf8.encode(payload).length > maxRequestBytes) {
      throw const FormatException('Note request exceeds read bound');
    }
    return _publicDeadline((abort) async {
      var stopped = false;
      abort.then((_) => stopped = true, onError: (Object _) => stopped = true);
      if (method != 'GET') await _ensureCsrf(abortTrigger: abort);
      await Future<void>.value();
      if (stopped) throw const ApiFailure(499, 'Note request cancelled');
      final request = http.AbortableRequest(
        method,
        endpoint,
        abortTrigger: abort,
      );
      _authenticate(request);
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      if (payload != null) {
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.body = payload;
      }
      if (method != 'GET') {
        request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      }
      onSubmit?.call();
      final response = await _transport.send(request);
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          media.split(';').first.trim() != 'application/json' ||
          (media.contains('charset=') &&
              !RegExp(
                r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
              ).hasMatch(media))) {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        throw ApiFailure(response.statusCode, 'Note response unavailable');
      }
      final Map<String, Object?> envelope;
      if (listProjection) {
        envelope = await readNotesListMetadataJson(response.stream);
      } else {
        final bytes = await readBoundedResponse(response, maxBytes: maxBytes);
        final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: false));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid note response envelope');
        }
        envelope = Map<String, Object?>.from(decoded);
      }
      if (envelope['code'] is! int || !{0, 200}.contains(envelope['code'])) {
        throw const FormatException('Invalid note response receipt');
      }
      return envelope;
    }, abortTrigger: abortTrigger);
  }

  /// Identity only: streamed Go bodies never enter the native article editor.
  Future<Map<String, Object?>> articleMetadata(
    int id, {
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Invalid article ID');
    return _publicDeadline((abort) async {
      final request = http.AbortableRequest(
        'GET',
        _endpoint('/api/blogs/$id'),
        abortTrigger: abort,
      )..followRedirects = false;
      _authenticate(request);
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      final response = await _transport.send(request);
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode != 200 ||
          media.split(';').first.trim() != 'application/json' ||
          (media.contains('charset=') &&
              !RegExp(
                r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
              ).hasMatch(media))) {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        throw ApiFailure(response.statusCode, 'Article metadata unavailable');
      }
      final envelope = await readArticleMetadataJson(response.stream);
      if (envelope['code'] is! int ||
          !{0, 200}.contains(envelope['code']) ||
          envelope['data'] is! Map<String, dynamic>) {
        throw const FormatException('Invalid article metadata receipt');
      }
      return Map<String, Object?>.from(envelope['data'] as Map);
    }, abortTrigger: abortTrigger);
  }

  Future<Map<String, Object?>> htmlNoteMetadata(
    int id, {
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Invalid HTML note ID');
    return _boundedSettingsJson(
      'GET',
      '/api/blogs/$id',
      abortTrigger: abortTrigger,
    );
  }

  /// One bounded owner-list page. Results are hints until full source review.
  Future<Map<String, Object?>> htmlCreationCandidates({
    required String collection,
    required int page,
    String keyword = '',
    Future<void>? abortTrigger,
  }) {
    if (!{'note', 'article'}.contains(collection) ||
        page < 1 ||
        page > 1000 ||
        utf8.encode(keyword).length > 200) {
      throw const FormatException('Invalid HTML candidate query');
    }
    final query = Uri(
      queryParameters: {
        'type': collection,
        'editor_type': 'html',
        'page': '$page',
        'keyword': keyword,
      },
    ).query;
    return _boundedSettingsJson(
      'GET',
      '/api/blogs?$query',
      abortTrigger: abortTrigger,
    );
  }

  Future<Map<String, Object?>> htmlNoteLabels(
    int id, {
    String? replacement,
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Invalid HTML note ID');
    return _boundedSettingsJson(
      replacement == null ? 'GET' : 'PUT',
      '/api/labels/resource/blog/$id',
      body: replacement == null ? null : {'labels': replacement},
      abortTrigger: abortTrigger,
    );
  }

  /// New ordinary owner HTML only. The legacy server echoes a full Blog,
  /// including gzip/base64 content, so a 5MiB source may exceed 128KiB in reply.
  /// No retry or server idempotency support is implied by this transport call.
  Future<int> createHtmlNote({
    required int memberId,
    required String collection,
    required String title,
    required String source,
    String labels = '',
    void Function()? onSubmit,
    Future<void>? abortTrigger,
  }) async {
    if (memberId <= 0 ||
        !{'note', 'article'}.contains(collection) ||
        title.trim().isEmpty ||
        utf8.encode(title).length > 200 ||
        utf8.encode(source).length > 5 * 1024 * 1024 ||
        utf8.encode(labels).length > 60 * 1024) {
      throw const FormatException('Invalid HTML creation bounds');
    }
    final payload = jsonEncode({
      'blog_title': title,
      'blog_content': source,
      'blog_type': collection,
      'editor_type': 'html',
      'labels': labels,
      'visibility': 0,
    });
    if (utf8.encode(payload).length > 32 * 1024 * 1024) {
      throw const FormatException('HTML creation request exceeds bound');
    }
    return _publicDeadline((stopped) async {
      await _ensureCsrf(abortTrigger: stopped);
      final request = http.AbortableRequest(
        'POST',
        _endpoint('/api/blogs'),
        abortTrigger: stopped,
      );
      _authenticate(request);
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.body = payload;
      onSubmit?.call();
      final response = await _transport.send(request);
      late Uint8List bytes;
      try {
        bytes = await readBoundedResponse(response, maxBytes: 8 * 1024 * 1024);
      } on ApiFailure catch (error) {
        if (error.status == 413) {
          throw const FormatException(
            'HTML creation receipt exceeds read bound',
          );
        }
        rethrow;
      }
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (media.split(';').first.trim() != 'application/json' ||
          media.contains('charset=') &&
              !RegExp(
                r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
              ).hasMatch(media)) {
        throw const FormatException('HTML creation receipt must be UTF8 JSON');
      }
      final text = utf8.decode(bytes, allowMalformed: false);
      final data = _decode(
        http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
        ),
      );
      final receipt = jsonDecode(text);
      final id = data['blog_id'];
      if (receipt is! Map ||
          receipt['code'] != 0 ||
          receipt['data'] is! Map ||
          id is! int ||
          id <= 0 ||
          data['member_id'] != memberId ||
          data['blog_type'] != collection ||
          data['editor_type'] != 'html' ||
          data['blog_title'] != title) {
        throw const FormatException(
          'Missing matching owned HTML creation receipt',
        );
      }
      return id;
    }, abortTrigger: abortTrigger);
  }

  /// Existing HTML note update only: never changes format, protection or ID.
  Future<void> updateHtmlNote(
    int id, {
    required String title,
    required String source,
    String? password,
    Future<void>? abortTrigger,
  }) async {
    if (id <= 0 ||
        utf8.encode(title).length > 200 ||
        utf8.encode(source).length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid HTML update bounds');
    }
    final payload = jsonEncode({
      'blog_title': title,
      'blog_content': source,
      'password': ?password,
    });
    // JSON escaping can expand each source byte to six bytes.
    if (utf8.encode(payload).length > 32 * 1024 * 1024) {
      throw const FormatException('HTML update request exceeds bound');
    }
    await _publicDeadline((stopped) async {
      await _ensureCsrf(abortTrigger: stopped);
      final request = http.AbortableRequest(
        'PUT',
        _endpoint('/api/blogs/$id'),
        abortTrigger: stopped,
      );
      _authenticate(request);
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.body = payload;
      final response = await _transport.send(request);
      late Uint8List bytes;
      try {
        bytes = await readBoundedResponse(response, maxBytes: 128 * 1024);
      } on ApiFailure catch (error) {
        // This is a local response-read limit after the PUT was issued, not
        // an HTTP413 refusal. Preserve the unknown mutation outcome.
        if (error.status == 413) {
          throw const FormatException('HTML update receipt exceeds read bound');
        }
        rethrow;
      }
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (media.split(';').first.trim() != 'application/json') {
        throw const FormatException('Missing HTML update JSON receipt');
      }
      final text = utf8.decode(bytes, allowMalformed: false);
      _decode(
        http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
        ),
      );
      final receipt = jsonDecode(text);
      if (receipt is! Map ||
          receipt['code'] != 0 ||
          receipt['message'] is! String) {
        throw const FormatException('Missing actual HTML update receipt');
      }
    }, abortTrigger: abortTrigger);
  }

  /// Exact HTML source, including protected notes, from the fixed owner API.
  /// IOClient and browser Fetch decode transfer gzip; never decode a second time
  /// based on a retained Content-Encoding header. The bound is decoded UTF-8.
  Future<String> blogHtmlSource(
    int id, {
    String? password,
    Future<void>? abortTrigger,
  }) async {
    if (id <= 0) throw const FormatException('Invalid HTML note ID');
    if (password != null &&
        (password.isEmpty || utf8.encode(password).length > 1024)) {
      throw const FormatException('Invalid HTML content password');
    }
    return _publicDeadline((stopped) async {
      if (password != null) await _ensureCsrf(abortTrigger: stopped);
      final request = http.AbortableRequest(
        password == null ? 'GET' : 'POST',
        _endpoint(
          '/api/blogs/$id/${password == null ? 'content/raw' : 'verify-password/raw'}',
        ),
        abortTrigger: stopped,
      );
      _authenticate(request);
      request.headers['accept'] = 'text/html';
      request.headers['cache-control'] = 'no-store';
      if (password != null) {
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.headers['x-csrf-token'] = _cookies['csrf_token']!;
        request.body = jsonEncode({'password': password});
      }
      final response = await _transport.send(request);
      final bytes = await readBoundedResponse(
        response,
        maxBytes: response.statusCode == 200 ? 5 * 1024 * 1024 : 64 * 1024,
      );
      if (response.statusCode != 200) {
        throw ApiFailure(
          response.statusCode,
          '无法读取HTML正文 / Unable to read HTML source',
        );
      }
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (type.split(';').first.trim() != 'text/html' ||
          type.contains('charset=') &&
              !RegExp(
                r'''charset=\s*["']?utf-8(?:["';\s]|$)''',
              ).hasMatch(type)) {
        throw const FormatException('HTML source must be UTF-8 text/html');
      }
      return _decodeExactHtml(bytes);
    }, abortTrigger: abortTrigger);
  }

  Future<String> publicShareHtmlSource(
    PublicShareReference reference, {
    String? chapterIdentify,
    String? password,
    Future<void>? abortTrigger,
  }) async {
    if (reference.server != baseUri ||
        chapterIdentify != null && password != null) {
      throw const FormatException('Invalid public HTML reading context');
    }
    final path = chapterIdentify == null
        ? '${reference.detailPath}/${password == null ? 'content/raw' : 'verify-password/raw'}'
        : '${reference.chapterPath(chapterIdentify)}/content/raw';
    if (password != null &&
        (password.isEmpty || utf8.encode(password).length > 4096)) {
      throw const FormatException('Invalid HTML content password');
    }
    return _publicDeadline((stopped) async {
      if (password != null) await _ensureCsrf(abortTrigger: stopped);
      final request = http.AbortableRequest(
        password == null ? 'GET' : 'POST',
        _endpoint(path),
        abortTrigger: stopped,
      );
      _authenticate(request);
      request.headers['accept'] = 'text/html';
      request.headers['cache-control'] = 'no-store';
      if (password != null) {
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.headers['x-csrf-token'] = _cookies['csrf_token']!;
        request.body = jsonEncode({'password': password});
      }
      final response = await _transport.send(request);
      final bytes = await readBoundedResponse(
        response,
        maxBytes: response.statusCode == 200 ? 5 * 1024 * 1024 : 64 * 1024,
      );
      if (response.statusCode != 200) {
        throw ApiFailure(
          response.statusCode,
          '无法读取HTML正文 / Unable to read HTML source',
        );
      }
      final type = response.headers['content-type']?.toLowerCase() ?? '';
      if (type.split(';').first.trim() != 'text/html' ||
          type.contains('charset=') &&
              !RegExp(
                r'''charset=\s*["']?utf-8(?:["';\s]|$)''',
              ).hasMatch(type)) {
        throw const FormatException('HTML source must be UTF-8 text/html');
      }
      return _decodeExactHtml(bytes);
    }, abortTrigger: abortTrigger);
  }

  /// Same-origin authenticated binary response. Caller owns stream cancellation.
  Future<http.StreamedResponse> downloadResponse(
    String path, {
    String? range,
    String? ifRange,
    Future<void>? abortTrigger,
  }) async {
    if (range != null &&
        !RegExp(r'^bytes=(?:[0-9]+-[0-9]*|-[0-9]+)$').hasMatch(range)) {
      throw const FormatException('Invalid byte range');
    }
    if (ifRange != null &&
        (ifRange.length > 512 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(ifRange))) {
      throw const FormatException('Invalid range validator');
    }
    final request = http.AbortableRequest(
      'GET',
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    if (range != null) request.headers['range'] = range;
    if (ifRange != null) request.headers['if-range'] = ifRange;
    _authenticate(request);
    final response = await _transport.send(request);
    if (response.statusCode != 200 && response.statusCode != 206) {
      final bytes = await readBoundedResponse(response, maxBytes: 64 * 1024);
      _decode(
        http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
        ),
      );
      throw ApiFailure(response.statusCode, '文件下载失败 / File download failed');
    }
    return response;
  }

  Future<Uint8List> download(
    String path, {
    int maxBytes = 64 * 1024 * 1024,
    Future<void>? abortTrigger,
  }) async => readBoundedResponse(
    await downloadResponse(path, abortTrigger: abortTrigger),
    maxBytes: maxBytes,
  );

  Future<T> _publicDeadline<T>(
    Future<T> Function(Future<void>) operation, {
    Future<void>? abortTrigger,
  }) async {
    final stopped = Completer<void>();
    var expired = false;
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    abortTrigger?.then(
      (_) => stop(),
      onError: (Object _, StackTrace stack) => stop(),
    );
    final timer = Timer(const Duration(seconds: 45), () {
      expired = true;
      stop();
    });
    try {
      // Transport cancellation may take time (or a test sender may ignore it).
      // End our own lifetime immediately; late completion cannot retain timers.
      return await Future.any<T>([
        Future<T>.sync(() => operation(stopped.future)),
        stopped.future.then<T>((_) {
          if (expired) throw TimeoutException('Request deadline exceeded');
          throw const ApiFailure(499, 'Request ended');
        }),
      ]);
    } finally {
      timer.cancel();
      stop();
    }
  }

  void _publicReference(PublicShareReference reference) {
    if (reference.server != baseUri) {
      throw const FormatException('Public reference belongs to another server');
    }
  }

  Future<Map<String, Object?>> _boundedSettingsJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool csrf = true,
    Future<void>? abortTrigger,
    int maxResponseBytes = 128 * 1024,
    int maxRequestBytes = 64 * 1024,
    bool sanitizeApiErrors = false,
    bool requireSuccessCode = false,
    void Function()? onSubmitted,
  }) => _publicDeadline((abortTrigger) async {
    final payload = body == null ? null : jsonEncode(body);
    if (payload != null && utf8.encode(payload).length > maxRequestBytes) {
      throw const FormatException('Settings request exceeds local bound');
    }
    if (method != 'GET' && csrf) {
      await _ensureCsrf(abortTrigger: abortTrigger);
    }
    final request = http.AbortableRequest(
      method,
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    if (sanitizeApiErrors) request.followRedirects = false;
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    request.headers['cache-control'] = 'no-store';
    if (payload != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = payload;
    }
    if (method != 'GET' && csrf) {
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
    }
    onSubmitted?.call();
    final response = await _transport.send(request);
    if (sanitizeApiErrors &&
        (response.statusCode < 200 || response.statusCode >= 300)) {
      final subscription = response.stream.listen(
        (_) {},
        onError: (Object _, StackTrace _) {},
      );
      try {
        await subscription.cancel();
      } catch (_) {}
      throw ApiFailure(
        response.statusCode,
        _adminBoundedError(response.statusCode),
      );
    }
    late Uint8List bytes;
    try {
      bytes = await readBoundedResponse(response, maxBytes: maxResponseBytes);
    } on ApiFailure catch (error) {
      if (error.status == 413) {
        throw FormatException(
          sanitizeApiErrors
              ? 'Administrator response exceeds read limit'
              : 'Settings receipt exceeds read bound',
        );
      }
      rethrow;
    }
    final media = (response.headers['content-type'] ?? '').toLowerCase();
    if (media.split(';').first.trim() != 'application/json' ||
        media.contains('charset=') &&
            !RegExp(
              r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
            ).hasMatch(media)) {
      throw const FormatException('Settings response must be UTF8 JSON');
    }
    try {
      final text = utf8.decode(bytes, allowMalformed: false);
      if (requireSuccessCode) {
        final envelope = jsonDecode(text);
        if (envelope is! Map<String, dynamic> ||
            envelope['code'] is! int ||
            !{0, 200}.contains(envelope['code'])) {
          throw const FormatException('Invalid administrator receipt');
        }
      }
    } on FormatException {
      if (requireSuccessCode) {
        throw const FormatException('Malformed administrator receipt');
      }
      rethrow;
    }
    try {
      return _decode(
        http.Response.bytes(
          bytes,
          response.statusCode,
          headers: response.headers,
        ),
      );
    } on ApiFailure catch (error) {
      if (!sanitizeApiErrors) rethrow;
      throw ApiFailure(error.status, _adminBoundedError(error.status));
    }
  }, abortTrigger: abortTrigger);

  String _adminBoundedError(int status) => switch (status) {
    401 => 'Administrator session expired',
    403 => 'Administrator access denied',
    429 => 'Administrator request rate limited',
    >= 500 => 'Administrator service temporarily unavailable',
    _ => 'Administrator request failed',
  };

  /// Administrator member list: fixed page size and no unsupported filters.
  Future<Map<String, Object?>> adminMembersPageJson(
    int page, {
    Future<void>? abortTrigger,
  }) {
    if (page < 1) throw const FormatException('Invalid member page');
    return _boundedSettingsJson(
      'GET',
      '/api/admin/members?page=$page&pageSize=20',
      abortTrigger: abortTrigger,
      maxResponseBytes: 256 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  /// Only the four existing Go mutations; no search, create, delete or lock API.
  Future<Map<String, Object?>> adminMemberActionJson(
    int id, {
    required String action,
    int? role,
    String? password,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (id <= 0 ||
        !{'approve', 'reject', 'role', 'reset-password'}.contains(action)) {
      throw const FormatException('Invalid member operation');
    }
    Map<String, Object?>? body;
    switch (action) {
      case 'role':
        if (!{0, 1}.contains(role) || password != null) {
          throw const FormatException('Invalid member role operation');
        }
        body = {'role': role};
      case 'reset-password':
        if (role != null ||
            password == null ||
            utf8.encode(password).length < 6 ||
            utf8.encode(password).length > 72) {
          throw const FormatException('Invalid member password bounds');
        }
        body = {'new_password': password};
      default:
        if (role != null || password != null) {
          throw const FormatException('Unexpected member operation data');
        }
    }
    return _boundedSettingsJson(
      'PUT',
      '/api/admin/members/$id/$action',
      body: body,
      abortTrigger: abortTrigger,
      maxResponseBytes: 64 * 1024,
      maxRequestBytes: 8 * 1024,
      onSubmitted: onSubmitted,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> adminFriendLinksJson({
    Map<String, Object?>? replacement,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (replacement != null &&
        (replacement.length != 2 ||
            replacement.keys.toSet().difference({
              'items',
              'simple_mode',
            }).isNotEmpty ||
            replacement['simple_mode'] is! bool ||
            replacement['items'] is! List ||
            (replacement['items'] as List).length > 200)) {
      throw const FormatException('Invalid full friend link replacement');
    }
    return _boundedSettingsJson(
      replacement == null ? 'GET' : 'PUT',
      '/api/admin/friend-links',
      body: replacement,
      abortTrigger: abortTrigger,
      maxResponseBytes: 2 * 1024 * 1024,
      maxRequestBytes: 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: replacement == null ? null : onSubmitted,
    );
  }

  Future<Map<String, Object?>> adminShareCommentsJson(
    int page, {
    String keyword = '',
    String? status,
    String? targetType,
    Future<void>? abortTrigger,
  }) {
    if (page < 1 ||
        page > 9007199254740991 ||
        status != null && !{'visible', 'deleted'}.contains(status) ||
        targetType != null &&
            !{'blog', 'book', 'document'}.contains(targetType)) {
      throw const FormatException('Invalid comment list filters');
    }
    final query = Uri(
      queryParameters: {
        'page': '$page',
        'page_size': '20',
        if (keyword.isNotEmpty) 'keyword': keyword,
        'status': ?status,
        'target_type': ?targetType,
      },
    ).query;
    if (utf8.encode(query).length > 64 * 1024) {
      throw const FormatException('Comment search exceeds request read bound');
    }
    return _boundedSettingsJson(
      'GET',
      '/api/admin/share-comments?$query',
      abortTrigger: abortTrigger,
      maxResponseBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> adminDeleteShareCommentsJson(
    List<int> ids, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (ids.isEmpty ||
        ids.length > 20 ||
        ids.toSet().length != ids.length ||
        ids.any((id) => id <= 0 || id > 9007199254740991)) {
      throw const FormatException('Invalid current-page comment selection');
    }
    return _boundedSettingsJson(
      'POST',
      '/api/admin/share-comments/delete',
      body: {'comment_ids': ids},
      abortTrigger: abortTrigger,
      maxResponseBytes: 64 * 1024,
      maxRequestBytes: 8 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: onSubmitted,
    );
  }

  /// Fresh administrator identity check for sensitive asset operations.
  Future<Map<String, Object?>> adminAssetPrincipalJson({
    Future<void>? abortTrigger,
  }) => _boundedSettingsJson(
    'GET',
    '/api/profile',
    abortTrigger: abortTrigger,
    maxResponseBytes: 128 * 1024,
    sanitizeApiErrors: true,
    requireSuccessCode: true,
  );

  bool _adminAssetId(Object? value, {bool allowZero = false}) =>
      value is int && value >= (allowZero ? 0 : 1) && value <= 9007199254740991;

  void _adminAssetFields(
    Map<String, Object?> value,
    Set<String> mandatory,
    Set<String> allowed,
  ) {
    if (!value.keys.toSet().containsAll(mandatory) ||
        value.keys.any((key) => !allowed.contains(key))) {
      throw const FormatException('Invalid administrator asset request');
    }
  }

  Future<Map<String, Object?>> adminAssetHostsJson({
    String query = '',
    String? status,
    Future<void>? abortTrigger,
  }) {
    if (status != null && !{'unknown', 'online', 'offline'}.contains(status)) {
      throw const FormatException('Invalid asset host filter');
    }
    final encoded = Uri(
      queryParameters: {if (query.isNotEmpty) 'q': query, 'status': ?status},
    ).query;
    if (utf8.encode(encoded).length > 64 * 1024) {
      throw const FormatException('Asset search exceeds request bound');
    }
    return _boundedSettingsJson(
      'GET',
      '/api/admin/assets/ssh-hosts${encoded.isEmpty ? '' : '?$encoded'}',
      abortTrigger: abortTrigger,
      maxResponseBytes: 16 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> adminAssetCredentialsJson({
    Future<void>? abortTrigger,
  }) => _boundedSettingsJson(
    'GET',
    '/api/admin/assets/credentials',
    abortTrigger: abortTrigger,
    maxResponseBytes: 16 * 1024 * 1024,
    sanitizeApiErrors: true,
    requireSuccessCode: true,
  );

  Future<Map<String, Object?>> adminSaveAssetHostJson(
    Map<String, Object?> value, {
    int? id,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    const mandatory = {
      'name',
      'host',
      'port',
      'shell',
      'cwd',
      'docker_socket_path',
      'credential_id',
      'username',
      'auth_type',
    };
    // Never replace a shared credential implicitly from a host edit.
    _adminAssetFields(value, mandatory, mandatory);
    if (id != null && !_adminAssetId(id) ||
        !_adminAssetId(value['credential_id'], allowZero: id != null) ||
        mandatory
            .difference({'port', 'credential_id'})
            .any((key) => value[key] is! String) ||
        value['port'] is! int ||
        (value['port'] as int) < 1 ||
        (value['port'] as int) > 65535) {
      throw const FormatException('Invalid asset host values');
    }
    final socket = trimGoSpace(value['docker_socket_path'] as String);
    if (trimGoSpace(value['name'] as String).isEmpty ||
        trimGoSpace(value['host'] as String).isEmpty ||
        {
          'shell',
          'cwd',
          'docker_socket_path',
        }.any((key) => RegExp(r'[\r\n]').hasMatch(value[key] as String)) ||
        socket.isNotEmpty && !socket.startsWith('/') ||
        value['credential_id'] == 0 &&
            (trimGoSpace(value['username'] as String).isEmpty ||
                !{'password', 'key'}.contains(value['auth_type']))) {
      throw const FormatException('Invalid asset host configuration');
    }
    return _boundedSettingsJson(
      id == null ? 'POST' : 'PUT',
      '/api/admin/assets/ssh-hosts${id == null ? '' : '/$id'}',
      body: Map.unmodifiable(value),
      abortTrigger: abortTrigger,
      maxRequestBytes: 1024 * 1024,
      maxResponseBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: onSubmitted,
    );
  }

  Future<Map<String, Object?>> adminSaveAssetCredentialJson(
    Map<String, Object?> value, {
    int? id,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    const fields = {'name', 'username', 'auth_type', 'credential'};
    _adminAssetFields(value, fields, fields);
    if (id != null && !_adminAssetId(id) ||
        fields.any((key) => value[key] is! String) ||
        trimGoSpace(value['name'] as String).isEmpty ||
        trimGoSpace(value['username'] as String).isEmpty ||
        !{'password', 'key'}.contains(value['auth_type']) ||
        id == null && trimGoSpace(value['credential'] as String).isEmpty) {
      throw const FormatException('Invalid asset credential configuration');
    }
    return _boundedSettingsJson(
      id == null ? 'POST' : 'PUT',
      '/api/admin/assets/credentials${id == null ? '' : '/$id'}',
      body: Map.unmodifiable(value),
      abortTrigger: abortTrigger,
      maxRequestBytes: 1024 * 1024,
      maxResponseBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: onSubmitted,
    );
  }

  Future<Map<String, Object?>> adminDeleteAssetRecordJson(
    String resource,
    int id, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (!{'ssh-hosts', 'credentials'}.contains(resource) ||
        !_adminAssetId(id)) {
      throw const FormatException('Invalid asset delete target');
    }
    return _boundedSettingsJson(
      'DELETE',
      '/api/admin/assets/$resource/$id',
      abortTrigger: abortTrigger,
      maxResponseBytes: 64 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: onSubmitted,
    );
  }

  Future<Map<String, Object?>> adminTestAssetHostJson(
    int id, {
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (!_adminAssetId(id)) {
      throw const FormatException('Invalid asset connection test target');
    }
    return _boundedSettingsJson(
      'POST',
      '/api/admin/assets/ssh-hosts/$id/test',
      abortTrigger: abortTrigger,
      maxResponseBytes: 64 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: onSubmitted,
    );
  }

  Future<Map<String, Object?>> adminAssetSettingsJson({
    Map<String, Object?>? update,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (update != null) {
      const fields = {
        'terminal_idle_timeout_seconds',
        'terminal_scrollback_lines',
        'credential_secret',
      };
      _adminAssetFields(update, fields, fields);
      final idle = update['terminal_idle_timeout_seconds'];
      final scrollback = update['terminal_scrollback_lines'];
      if (idle is! int ||
          idle < 1 ||
          idle > 86400 ||
          scrollback is! int ||
          scrollback < 500 ||
          scrollback > 50000 ||
          update['credential_secret'] is! String) {
        throw const FormatException('Invalid asset settings configuration');
      }
    }
    return _boundedSettingsJson(
      update == null ? 'GET' : 'PUT',
      '/api/admin/assets/settings',
      body: update == null ? null : Map.unmodifiable(update),
      abortTrigger: abortTrigger,
      maxRequestBytes: 1024 * 1024,
      maxResponseBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: update == null ? null : onSubmitted,
    );
  }

  /// The consumer drains the response inside the abortable deadline.
  /// Same-origin administrator API. Never contacts a caller-supplied DAV URL.
  Future<Map<String, Object?>> adminDavServersJson({
    String operation = 'list',
    int? id,
    String query = '',
    String? status,
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (id != null && !_adminAssetId(id) ||
        status != null && !{'unknown', 'online', 'offline'}.contains(status)) {
      throw const FormatException('Invalid WebDAV connection target');
    }
    final method = switch (operation) {
      'list' => 'GET',
      'save' => id == null ? 'POST' : 'PUT',
      'test' => 'POST',
      'delete' => 'DELETE',
      _ => throw const FormatException('Invalid WebDAV connection operation'),
    };
    if (operation == 'list' && id != null ||
        {'test', 'delete'}.contains(operation) && id == null ||
        operation != 'list' && (query.isNotEmpty || status != null)) {
      throw const FormatException('Invalid WebDAV connection request');
    }
    if (operation == 'save') {
      const fields = {'name', 'url', 'root_path', 'credential_id'};
      if (body == null) throw const FormatException('Missing WebDAV draft');
      _adminAssetFields(body, fields, fields);
      if (!_adminAssetId(body['credential_id']) ||
          fields
              .difference({'credential_id'})
              .any((key) => body[key] is! String)) {
        throw const FormatException('Invalid WebDAV draft');
      }
    } else if (body != null) {
      throw const FormatException('Unexpected WebDAV connection body');
    }
    final encoded = operation == 'list'
        ? Uri(
            queryParameters: {
              if (query.isNotEmpty) 'q': query,
              'status': ?status,
            },
          ).query
        : '';
    if (utf8.encode(encoded).length > 64 * 1024) {
      throw const FormatException('WebDAV search exceeds request bound');
    }
    final suffix = id == null ? '' : '/$id';
    return _boundedSettingsJson(
      method,
      '/api/admin/assets/webdav-servers$suffix${operation == 'test' ? '/test' : ''}${encoded.isEmpty ? '' : '?$encoded'}',
      body: body == null ? null : Map.unmodifiable(body),
      abortTrigger: abortTrigger,
      maxResponseBytes: operation == 'list' ? 16 * 1024 * 1024 : 128 * 1024,
      maxRequestBytes: 64 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: method == 'GET' ? null : onSubmitted,
    );
  }

  Future<T> adminDownloadDavFile<T>(
    int hostId,
    String remotePath, {
    required Future<T> Function(http.StreamedResponse, Future<void>) consume,
    Future<void>? abortTrigger,
  }) {
    if (!_adminAssetId(hostId) ||
        remotePath.isEmpty ||
        utf8.encode(remotePath).length > 16384) {
      throw const FormatException('Invalid remote download target');
    }
    return _publicDeadline((abort) async {
      final query = Uri(queryParameters: {'path': remotePath}).query;
      final request = http.AbortableRequest(
        'GET',
        _endpoint(
          '/api/admin/assets/webdav-servers/$hostId/files/download?$query',
        ),
        abortTrigger: abort,
      );
      _authenticate(request);
      request.headers['accept'] = 'application/octet-stream';
      request.headers['cache-control'] = 'no-store';
      final response = await _transport.send(request);
      if (response.statusCode != 200 ||
          (response.headers['content-type'] ?? '')
                  .split(';')
                  .first
                  .trim()
                  .toLowerCase() !=
              'application/octet-stream') {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        throw ApiFailure(
          response.statusCode == 200 ? 502 : response.statusCode,
          'Remote file download refused',
        );
      }
      return consume(response, abort);
    }, abortTrigger: abortTrigger);
  }

  Future<Map<String, Object?>> adminUploadDavFile(
    int hostId,
    String directory, {
    required String filename,
    required int length,
    required Stream<List<int>> bytes,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
    void Function(int, int)? onSent,
  }) {
    if (!_adminAssetId(hostId) ||
        directory.isEmpty ||
        utf8.encode(directory).length > 16384 ||
        length < 0 ||
        length > 64 * 1024 * 1024 ||
        filename.isEmpty ||
        filename.contains('/') ||
        filename.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(filename)) {
      throw const FormatException('Invalid remote upload');
    }
    return _publicDeadline((abort) async {
      await _ensureCsrf(abortTrigger: abort);
      final query = Uri(queryParameters: {'path': directory}).query;
      final request = http.AbortableMultipartRequest(
        'POST',
        _endpoint(
          '/api/admin/assets/webdav-servers/$hostId/files/upload?$query',
        ),
        abortTrigger: abort,
      );
      _authenticate(request);
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      Stream<List<int>> counted() async* {
        var sent = 0;
        await for (final chunk in bytes) {
          sent += chunk.length;
          if (sent > length) {
            throw const FormatException('Upload source changed');
          }
          yield chunk;
          onSent?.call(sent, length);
        }
        if (sent != length) {
          throw const FormatException('Upload source incomplete');
        }
      }

      request.files.add(
        http.MultipartFile('file', counted(), length, filename: filename),
      );
      onSubmitted?.call();
      final response = await _transport.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        throw ApiFailure(response.statusCode, 'Remote upload refused');
      }
      final receipt = await readBoundedResponse(response, maxBytes: 128 * 1024);
      if ((response.headers['content-type'] ?? '')
              .split(';')
              .first
              .trim()
              .toLowerCase() !=
          'application/json') {
        throw const FormatException('Remote upload receipt is not JSON');
      }
      final decoded = jsonDecode(utf8.decode(receipt, allowMalformed: false));
      if (decoded is! Map<String, dynamic> ||
          decoded['code'] is! int ||
          !{0, 200}.contains(decoded['code'])) {
        throw const FormatException('Remote upload receipt invalid');
      }
      try {
        return _decode(
          http.Response.bytes(
            receipt,
            response.statusCode,
            headers: response.headers,
          ),
        );
      } on ApiFailure catch (error) {
        throw ApiFailure(error.status, 'Remote upload refused');
      }
    }, abortTrigger: abortTrigger);
  }

  /// Bounded, same-origin remote-file API. No absolute caller-provided endpoint.
  Future<Map<String, Object?>> adminDavFilesJson(
    int hostId, {
    String operation = 'list',
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (!_adminAssetId(hostId)) {
      throw const FormatException('Invalid remote file host');
    }
    const methods = {
      'list': 'GET',
      'read': 'GET',
      'save': 'PUT',
      'mkdir': 'POST',
      'rename': 'POST',
      'copy': 'POST',
      'delete': 'DELETE',
    };
    const suffixes = {
      'list': '',
      'read': '/content',
      'save': '/content',
      'mkdir': '/mkdir',
      'rename': '/rename',
      'copy': '/copy',
      'delete': '',
    };
    const fields = {
      'save': {'path', 'content'},
      'mkdir': {'path'},
      'rename': {'old_path', 'new_path'},
      'copy': {'source_path', 'target_path'},
    };
    final method = methods[operation];
    if (method == null) {
      throw const FormatException('Invalid remote file operation');
    }
    final expected = fields[operation];
    if (expected == null
        ? body != null
        : body == null ||
              body.length != expected.length ||
              !body.keys.toSet().containsAll(expected) ||
              body.values.any((value) => value is! String)) {
      throw const FormatException('Invalid remote file request');
    }
    final allowedQuery = operation == 'delete'
        ? {'path', 'recursive'}
        : {'path'};
    if (query.keys.any((key) => !allowedQuery.contains(key)) ||
        body == null &&
            (!query.containsKey('path') || query['path']!.isEmpty) ||
        query['recursive'] != null &&
            !{'true', 'false'}.contains(query['recursive'])) {
      throw const FormatException('Invalid remote file query');
    }
    // Writes carry their path in JSON; read/list/delete carry it in the query.
    if (body != null && query.isNotEmpty) {
      throw const FormatException('Invalid remote file mutation query');
    }
    final encoded = Uri(queryParameters: body == null ? query : null).query;
    if (utf8.encode(encoded).length > 64 * 1024) {
      throw const FormatException('Remote file path exceeds local limit');
    }
    return _boundedSettingsJson(
      method,
      '/api/admin/assets/webdav-servers/$hostId/files${suffixes[operation]}${encoded.isEmpty ? '' : '?$encoded'}',
      body: body == null ? null : Map.unmodifiable(body),
      abortTrigger: abortTrigger,
      maxResponseBytes: operation == 'read'
          ? 16 * 1024 * 1024
          : 8 * 1024 * 1024,
      // JSON escaping may expand each control character to six bytes.
      maxRequestBytes: 13 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: method == 'GET' ? null : onSubmitted,
    );
  }

  Future<T> adminDownloadRemoteFile<T>(
    int hostId,
    String remotePath, {
    required Future<T> Function(http.StreamedResponse, Future<void>) consume,
    Future<void>? abortTrigger,
  }) {
    if (!_adminAssetId(hostId) ||
        remotePath.isEmpty ||
        utf8.encode(remotePath).length > 16384) {
      throw const FormatException('Invalid remote download target');
    }
    return _publicDeadline((abort) async {
      final query = Uri(queryParameters: {'path': remotePath}).query;
      final request = http.AbortableRequest(
        'GET',
        _endpoint('/api/admin/assets/ssh-hosts/$hostId/files/download?$query'),
        abortTrigger: abort,
      );
      _authenticate(request);
      request.headers['accept'] = 'application/octet-stream';
      request.headers['cache-control'] = 'no-store';
      final response = await _transport.send(request);
      if (response.statusCode != 200 ||
          (response.headers['content-type'] ?? '')
                  .split(';')
                  .first
                  .trim()
                  .toLowerCase() !=
              'application/octet-stream') {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        throw ApiFailure(
          response.statusCode == 200 ? 502 : response.statusCode,
          'Remote file download refused',
        );
      }
      return consume(response, abort);
    }, abortTrigger: abortTrigger);
  }

  Future<Map<String, Object?>> adminUploadRemoteFile(
    int hostId,
    String directory, {
    required String filename,
    required int length,
    required Stream<List<int>> bytes,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
    void Function(int, int)? onSent,
  }) {
    if (!_adminAssetId(hostId) ||
        directory.isEmpty ||
        utf8.encode(directory).length > 16384 ||
        length < 0 ||
        length > 64 * 1024 * 1024 ||
        filename.isEmpty ||
        filename.contains('/') ||
        filename.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(filename)) {
      throw const FormatException('Invalid remote upload');
    }
    return _publicDeadline((abort) async {
      await _ensureCsrf(abortTrigger: abort);
      final query = Uri(queryParameters: {'path': directory}).query;
      final request = http.AbortableMultipartRequest(
        'POST',
        _endpoint('/api/admin/assets/ssh-hosts/$hostId/files/upload?$query'),
        abortTrigger: abort,
      );
      _authenticate(request);
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.headers['accept'] = 'application/json';
      request.headers['cache-control'] = 'no-store';
      Stream<List<int>> counted() async* {
        var sent = 0;
        await for (final chunk in bytes) {
          sent += chunk.length;
          if (sent > length) {
            throw const FormatException('Upload source changed');
          }
          yield chunk;
          onSent?.call(sent, length);
        }
        if (sent != length) {
          throw const FormatException('Upload source incomplete');
        }
      }

      request.files.add(
        http.MultipartFile('file', counted(), length, filename: filename),
      );
      onSubmitted?.call();
      final response = await _transport.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final subscription = response.stream.listen(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        await subscription.cancel();
        throw ApiFailure(response.statusCode, 'Remote upload refused');
      }
      final receipt = await readBoundedResponse(response, maxBytes: 128 * 1024);
      if ((response.headers['content-type'] ?? '')
              .split(';')
              .first
              .trim()
              .toLowerCase() !=
          'application/json') {
        throw const FormatException('Remote upload receipt is not JSON');
      }
      final decoded = jsonDecode(utf8.decode(receipt, allowMalformed: false));
      if (decoded is! Map<String, dynamic> ||
          decoded['code'] is! int ||
          !{0, 200}.contains(decoded['code'])) {
        throw const FormatException('Remote upload receipt invalid');
      }
      try {
        return _decode(
          http.Response.bytes(
            receipt,
            response.statusCode,
            headers: response.headers,
          ),
        );
      } on ApiFailure catch (error) {
        throw ApiFailure(error.status, 'Remote upload refused');
      }
    }, abortTrigger: abortTrigger);
  }

  /// Bounded, same-origin remote-file API. No absolute caller-provided endpoint.
  Future<Map<String, Object?>> adminRemoteFilesJson(
    int hostId, {
    String operation = 'list',
    Map<String, String> query = const {},
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (!_adminAssetId(hostId)) {
      throw const FormatException('Invalid remote file host');
    }
    const methods = {
      'list': 'GET',
      'read': 'GET',
      'save': 'PUT',
      'mkdir': 'POST',
      'rename': 'POST',
      'copy': 'POST',
      'chmod': 'POST',
      'delete': 'DELETE',
    };
    const suffixes = {
      'list': '',
      'read': '/content',
      'save': '/content',
      'mkdir': '/mkdir',
      'rename': '/rename',
      'copy': '/copy',
      'chmod': '/chmod',
      'delete': '',
    };
    const fields = {
      'save': {'path', 'content'},
      'mkdir': {'path'},
      'rename': {'old_path', 'new_path'},
      'copy': {'source_path', 'target_path'},
      'chmod': {'path', 'mode'},
    };
    final method = methods[operation];
    if (method == null) {
      throw const FormatException('Invalid remote file operation');
    }
    final expected = fields[operation];
    if (expected == null
        ? body != null
        : body == null ||
              body.length != expected.length ||
              !body.keys.toSet().containsAll(expected) ||
              body.values.any((value) => value is! String)) {
      throw const FormatException('Invalid remote file request');
    }
    final allowedQuery = operation == 'delete'
        ? {'path', 'recursive'}
        : {'path'};
    if (query.keys.any((key) => !allowedQuery.contains(key)) ||
        body == null &&
            (!query.containsKey('path') || query['path']!.isEmpty) ||
        query['recursive'] != null &&
            !{'true', 'false'}.contains(query['recursive'])) {
      throw const FormatException('Invalid remote file query');
    }
    // Writes carry their path in JSON; read/list/delete carry it in the query.
    if (body != null && query.isNotEmpty) {
      throw const FormatException('Invalid remote file mutation query');
    }
    final encoded = Uri(queryParameters: body == null ? query : null).query;
    if (utf8.encode(encoded).length > 64 * 1024) {
      throw const FormatException('Remote file path exceeds local limit');
    }
    return _boundedSettingsJson(
      method,
      '/api/admin/assets/ssh-hosts/$hostId/files${suffixes[operation]}${encoded.isEmpty ? '' : '?$encoded'}',
      body: body == null ? null : Map.unmodifiable(body),
      abortTrigger: abortTrigger,
      maxResponseBytes: operation == 'read'
          ? 16 * 1024 * 1024
          : 8 * 1024 * 1024,
      // JSON escaping may expand each control character to six bytes.
      maxRequestBytes: 13 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: method == 'GET' ? null : onSubmitted,
    );
  }

  /// Administrator Docker API, bounded and restricted to the selected SSH host.
  Future<Map<String, Object?>> adminDockerJson(
    int hostId, {
    required String resource,
    String operation = 'list',
    String? target,
    int tail = 200,
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (!_adminAssetId(hostId) ||
        !{'containers', 'networks', 'volumes', 'images'}.contains(resource)) {
      throw const FormatException('Invalid Docker host/resource');
    }
    var method = 'GET';
    var suffix = '/api/admin/assets/ssh-hosts/$hostId/docker-$resource';
    var mutation = false;
    if (operation == 'prune') {
      if (target != null || body != null) {
        throw const FormatException('Invalid Docker prune');
      }
      method = 'POST';
      mutation = true;
      suffix = '/api/admin/assets/ssh-hosts/$hostId/docker/$resource/prune';
    } else if (operation == 'create') {
      if (target != null || body == null) {
        throw const FormatException('Invalid Docker create');
      }
      final keys = switch (resource) {
        'containers' => {
          'image',
          'name',
          'command',
          'start_after_create',
          'restart_policy',
          'ports',
          'volumes',
          'env',
          'network',
          'privileged',
          'memory',
          'cpus',
        },
        'networks' || 'volumes' => {'name', 'driver'},
        _ => {'image'},
      };
      if (body.length != keys.length || !body.keys.toSet().containsAll(keys)) {
        throw const FormatException('Invalid Docker create fields');
      }
      method = 'POST';
      mutation = true;
    } else if (operation != 'list') {
      if (target == null ||
          target.isEmpty ||
          target.length > 1024 ||
          target.startsWith('-') ||
          RegExp(r'[\u0000-\u001f\u007f]').hasMatch(target)) {
        throw const FormatException('Invalid Docker target');
      }
      suffix += '/${Uri.encodeComponent(target)}';
      if (resource == 'containers') {
        if (!RegExp(r'^[a-f0-9]{12,64}$').hasMatch(target)) {
          throw const FormatException('Invalid Docker container identity');
        }
        if (operation == 'inspect') {
          if (body != null) throw const FormatException('Invalid inspect body');
          method = 'POST';
          suffix += '/inspect';
        } else if (operation == 'logs') {
          if (body != null || tail < 1 || tail > 10000) {
            throw const FormatException('Invalid Docker log tail');
          }
          suffix += '/logs?tail=$tail';
        } else if ({
          'start',
          'stop',
          'restart',
          'delete',
          'restart-policy',
        }.contains(operation)) {
          if (target.length != 64) {
            throw const FormatException('Reviewed full Docker ID required');
          }
          if (operation == 'restart-policy') {
            if (body?.length != 1 ||
                !{
                  'no',
                  'always',
                  'unless-stopped',
                  'on-failure',
                }.contains(body?['policy'])) {
              throw const FormatException('Invalid restart policy');
            }
          } else if (body != null) {
            throw const FormatException('Unexpected Docker action body');
          }
          method = 'POST';
          mutation = true;
          suffix += '/$operation';
        } else {
          throw const FormatException('Invalid Docker action');
        }
      } else {
        if (operation != 'delete' || body != null) {
          throw const FormatException('Invalid Docker resource action');
        }
        method = 'DELETE';
        mutation = true;
      }
    } else if (target != null || body != null) {
      throw const FormatException('Unexpected Docker list parameters');
    }
    return _boundedSettingsJson(
      method,
      suffix,
      body: body,
      abortTrigger: abortTrigger,
      maxRequestBytes: 64 * 1024,
      maxResponseBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: mutation ? onSubmitted : null,
    );
  }

  /// GET SSE, with independent cancellation; never reused as a terminal socket.
  Stream<ServerEvent> adminDockerLogEvents(
    int hostId,
    String containerId, {
    int tail = 200,
    Future<void>? abortTrigger,
  }) async* {
    if (!_adminAssetId(hostId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(containerId) ||
        tail < 1 ||
        tail > 10000) {
      throw const FormatException('Invalid Docker log stream');
    }
    final stopped = Completer<void>();
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
    }

    abortTrigger?.then(
      (_) => stop(),
      onError: (Object e, StackTrace s) => stop(),
    );
    try {
      final request = http.AbortableRequest(
        'GET',
        _endpoint(
          '/api/admin/assets/ssh-hosts/$hostId/docker-containers/$containerId/logs/stream?tail=$tail',
        ),
        abortTrigger: stopped.future,
      );
      _authenticate(request);
      request.headers['accept'] = 'text/event-stream';
      final response = await _transport
          .send(request)
          .timeout(const Duration(seconds: 45));
      final type = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode != 200 || type != 'text/event-stream') {
        await readBoundedResponse(response, maxBytes: 64 * 1024);
        throw ApiFailure(
          response.statusCode >= 400 ? response.statusCode : 502,
          '日志流不可用 / Log stream unavailable',
        );
      }
      yield* decodeServerEvents(
        response.stream.timeout(const Duration(seconds: 45)),
        maxEventBytes: 32 * 1024,
        maxTotalBytes: 64 * 1024 * 1024,
      );
    } finally {
      stop();
    }
  }

  /// Saves only terminal policy, preserving absent secret rows and config fallback.
  Future<Map<String, Object?>> adminAssetTerminalPolicyJson({
    required int idleSeconds,
    required int scrollbackLines,
    Future<void>? abortTrigger,
    void Function()? onSubmitted,
  }) {
    if (idleSeconds < 1 ||
        idleSeconds > 86400 ||
        scrollbackLines < 500 ||
        scrollbackLines > 50000) {
      throw const FormatException('Invalid asset terminal policy');
    }
    return _boundedSettingsJson(
      'PUT',
      '/api/admin/settings',
      body: {
        'asset_terminal_idle_timeout_seconds': '$idleSeconds',
        'asset_terminal_scrollback_lines': '$scrollbackLines',
      },
      abortTrigger: abortTrigger,
      maxRequestBytes: 4096,
      maxResponseBytes: 64 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
      onSubmitted: onSubmitted,
    );
  }

  Future<Map<String, Object?>> adminSettingsJson({
    Map<String, String>? update,
    Future<void>? abortTrigger,
  }) {
    if (update != null && update.keys.any((key) => key.isEmpty)) {
      throw const FormatException('Invalid admin setting key');
    }
    return _boundedSettingsJson(
      update == null ? 'GET' : 'PUT',
      '/api/admin/settings',
      body: update,
      abortTrigger: abortTrigger,
      maxResponseBytes: 2 * 1024 * 1024,
      maxRequestBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> adminRecommendationsJson({
    Map<String, Object?>? update,
    Future<void>? abortTrigger,
  }) {
    if (update != null &&
        (update.length != 3 ||
            update.keys.toSet().difference({
              'strategy',
              'manual_labels',
              'page_size',
            }).isNotEmpty)) {
      throw const FormatException('Invalid recommendation configuration');
    }
    return _boundedSettingsJson(
      update == null ? 'GET' : 'PUT',
      '/api/labels/recommendation-settings',
      body: update,
      abortTrigger: abortTrigger,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> adminAiTestJson(
    Map<String, Object?> body, {
    Future<void>? abortTrigger,
  }) => _boundedSettingsJson(
    'POST',
    '/api/admin/settings/ai/test',
    body: body,
    abortTrigger: abortTrigger,
    maxResponseBytes: 256 * 1024,
    sanitizeApiErrors: true,
    requireSuccessCode: true,
  );

  Future<Map<String, Object?>> adminMailStatusJson({
    Future<void>? abortTrigger,
  }) => _boundedSettingsJson(
    'GET',
    '/api/admin/mail/status',
    abortTrigger: abortTrigger,
    maxResponseBytes: 256 * 1024,
    sanitizeApiErrors: true,
    requireSuccessCode: true,
  );

  Future<Map<String, Object?>> adminMailTestJson(
    String email, {
    Future<void>? abortTrigger,
  }) {
    if (email.trim().isEmpty) {
      throw const FormatException('A test recipient is required');
    }
    return _boundedSettingsJson(
      'POST',
      '/api/admin/settings/mail/test',
      body: {'email': email},
      abortTrigger: abortTrigger,
      maxResponseBytes: 256 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> adminAiResetJson(
    String key, {
    Future<void>? abortTrigger,
  }) {
    const allowed = {
      'ai_system_prompt_md',
      'ai_system_prompt_html',
      'ai_system_prompt_drawing',
      'ai_actions_selection',
      'ai_actions_html',
      'ai_actions_book',
      'ai_actions_article',
      'ai_actions_note',
      'ai_actions_task',
      'ai_actions_empty',
    };
    if (!allowed.contains(key)) {
      throw const FormatException('Unsupported AI reset field');
    }
    return _boundedSettingsJson(
      'POST',
      '/api/admin/settings/ai/reset',
      body: {'key': key},
      abortTrigger: abortTrigger,
      maxResponseBytes: 2 * 1024 * 1024,
      sanitizeApiErrors: true,
      requireSuccessCode: true,
    );
  }

  Future<Map<String, Object?>> profileSettingsJson({
    bool update = false,
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
  }) {
    if (update
        ? body == null ||
              body.keys.toSet().difference({
                'email',
                'default_home',
              }).isNotEmpty ||
              body.length != 2
        : body != null) {
      throw const FormatException('Invalid profile operation');
    }
    return _boundedSettingsJson(
      update ? 'PUT' : 'GET',
      '/api/profile',
      body: body,
      abortTrigger: abortTrigger,
    );
  }

  Future<Map<String, Object?>> trashListJson({
    required String type,
    required int page,
  }) {
    if (!{
          '',
          'book',
          'blog',
          'bookmark',
          'document',
          'task',
          'topic',
        }.contains(type) ||
        page < 1 ||
        page > 1000000) {
      throw const FormatException('Invalid trash query');
    }
    return _boundedSettingsJson(
      'GET',
      Uri(
        path: '/api/trash',
        queryParameters: {'type': type, 'page': '$page', 'page_size': '20'},
      ).toString(),
    );
  }

  Future<Map<String, Object?>> trashMutationJson(
    int id, {
    required bool restore,
  }) {
    if (id <= 0) {
      throw const FormatException('Invalid trash ID');
    }
    return _boundedSettingsJson(
      restore ? 'POST' : 'DELETE',
      restore ? '/api/trash/$id/restore' : '/api/trash/$id',
    );
  }

  Future<Map<String, Object?>> listApiTokensJson() =>
      _boundedSettingsJson('GET', '/api/api-tokens');
  Future<Map<String, Object?>> createApiTokenJson(String name) =>
      _boundedSettingsJson('POST', '/api/api-tokens', body: {'name': name});
  Future<Map<String, Object?>> deleteApiTokenJson(int id) {
    if (id <= 0) {
      throw const FormatException('Actual token identity required');
    }
    return _boundedSettingsJson('DELETE', '/api/api-tokens/$id');
  }

  Future<String> probeWebdavAppPassword(
    String account,
    String password,
  ) => _publicDeadline((abort) async {
    if (account.isEmpty || account.contains(':') || password.isEmpty) {
      throw const FormatException('DAV credentials required');
    }
    final request = http.AbortableRequest(
      'PROPFIND',
      baseUri.replace(path: '${baseUri.path}/dav'),
      abortTrigger: abort,
    );
    // The DAV handler authenticates Basic credentials directly. Do not adopt
    // or supply the owner's session cookies to this separate credential probe.
    request.followRedirects = false;
    request.headers.addAll({
      'authorization':
          'Basic ${base64Encode(utf8.encode('$account:$password'))}',
      'depth': '0',
      'accept': 'text/xml, application/xml',
      'content-type': 'application/xml; charset=utf-8',
      'cache-control': 'no-store',
    });
    request.body =
        '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/></d:prop></d:propfind>';
    final response = await _transport.send(request);
    final bytes = await readBoundedResponse(response, maxBytes: 128 * 1024);
    if (response.statusCode != 207) {
      throw ApiFailure(
        response.statusCode,
        'DAV credential verification incomplete',
      );
    }
    final media = (response.headers['content-type'] ?? '')
        .split(';')
        .first
        .trim()
        .toLowerCase();
    if (!{'text/xml', 'application/xml'}.contains(media)) {
      throw const FormatException('DAV verification requires actual XML');
    }
    return utf8.decode(bytes, allowMalformed: false);
  });

  Future<Map<String, Object?>> webdavCredentialsProfileJson() =>
      _boundedSettingsJson('GET', '/api/webdav/profile');
  Future<Map<String, Object?>> resetWebdavAppPasswordJson({String? password}) =>
      _boundedSettingsJson(
        'POST',
        '/api/webdav/app-password/reset',
        body: password == null ? null : {'password': password},
      );
  Future<Map<String, Object?>> revokeWebdavAppPasswordJson() =>
      _boundedSettingsJson('DELETE', '/api/webdav/app-password');

  Future<Map<String, Object?>> backgroundSettingsJson() =>
      _boundedSettingsJson('GET', '/api/profile/background');
  Future<Map<String, Object?>> updateBackgroundJson(
    Map<String, String> fields, {
    Uint8List? image,
  }) => _publicDeadline((abort) async {
    if (fields.keys.toSet().difference({
          'mode',
          'animated',
          'fade',
          'remove',
        }).isNotEmpty ||
        fields.length != 4 ||
        image != null && image.length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid background request');
    }
    await _ensureCsrf(abortTrigger: abort);
    final request = http.AbortableMultipartRequest(
      'PUT',
      _endpoint('/api/profile/background'),
      abortTrigger: abort,
    )..fields.addAll(fields);
    if (image != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          image,
          filename: 'background-image',
        ),
      );
    }
    _authenticate(request);
    request.headers['x-csrf-token'] = _cookies['csrf_token']!;
    request.headers['cache-control'] = 'no-store';
    request.headers['accept'] = 'application/json';
    final response = await _transport.send(request);
    late Uint8List bytes;
    try {
      bytes = await readBoundedResponse(response, maxBytes: 128 * 1024);
    } on ApiFailure catch (e) {
      if (e.status == 413) {
        throw const FormatException('Background receipt exceeds bound');
      }
      rethrow;
    }
    if ((response.headers['content-type'] ?? '')
            .split(';')
            .first
            .trim()
            .toLowerCase() !=
        'application/json') {
      throw const FormatException('Expected background JSON');
    }
    utf8.decode(bytes, allowMalformed: false);
    return _decode(
      http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      ),
    );
  });
  Future<Uint8List> backgroundImageBytes(String hash) =>
      _publicDeadline((abort) async {
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
          throw const FormatException('Actual image hash required');
        }
        final request = http.AbortableRequest(
          'GET',
          _endpoint('/api/profile/background/image'),
          abortTrigger: abort,
        );
        _authenticate(request);
        request.headers['cache-control'] = 'no-store';
        final response = await _transport.send(request);
        if (response.statusCode != 200) {
          await readBoundedResponse(response, maxBytes: 64 * 1024);
          throw ApiFailure(
            response.statusCode,
            'Private background image unavailable',
          );
        }
        if ((response.headers['content-type'] ?? '')
                    .split(';')
                    .first
                    .trim()
                    .toLowerCase() !=
                'image/jpeg' ||
            response.headers['etag'] != '"$hash"') {
          await readBoundedResponse(response, maxBytes: 64 * 1024);
          throw const FormatException('Unexpected private background image');
        }
        return readBoundedResponse(response, maxBytes: 16 * 1024 * 1024);
      });

  Future<Map<String, Object?>> reminderSettingsJson({
    Map<String, Object?>? body,
  }) => _boundedSettingsJson(
    body == null ? 'GET' : 'PUT',
    '/api/profile/task-reminder',
    body: body,
  );
  Future<Map<String, Object?>> reminderTestJson() => _boundedSettingsJson(
    'POST',
    '/api/profile/task-reminder/test',
    body: const {},
  );

  Future<Map<String, Object?>> accountPasswordJson(
    String current,
    String next,
  ) => _boundedSettingsJson(
    'PUT',
    '/api/password',
    body: {'old_password': current, 'new_password': next},
  );
  Future<Map<String, Object?>> credentialLoginJson(
    String account,
    String password,
  ) => _boundedSettingsJson(
    'POST',
    '/api/login',
    body: {'account': account, 'password': password},
    csrf: false,
  );

  Future<String> publicNotesHtml(int page, {Future<void>? abortTrigger}) =>
      _publicDeadline((abortTrigger) async {
        if (page < 1 || page > 100000) {
          throw const FormatException('Invalid public notes page');
        }
        final request = http.AbortableRequest(
          'GET',
          baseUri.replace(
            path: '${baseUri.path}/notes/public',
            queryParameters: {'page': '$page', 'page_size': '20'},
          ),
          abortTrigger: abortTrigger,
        );
        _authenticate(request);
        request.headers['accept'] = 'text/html';
        final response = await _transport.send(request);
        final bytes = await readBoundedResponse(
          response,
          maxBytes: 26 * 1024 * 1024,
        );
        if (response.statusCode != 200) {
          throw ApiFailure(response.statusCode, 'Public notes unavailable');
        }
        final media = (response.headers['content-type'] ?? '').toLowerCase();
        if (media.split(';').first.trim() != 'text/html' ||
            media.contains('charset=') &&
                !RegExp(
                  r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
                ).hasMatch(media)) {
          throw const FormatException('Public notes require UTF8 HTML');
        }
        return utf8.decode(bytes, allowMalformed: false);
      }, abortTrigger: abortTrigger);

  Future<Map<String, Object?>> contentPasswordJson(
    int id, {
    String? newPassword,
    String? currentPassword,
    String? verifyPassword,
    Future<void>? abortTrigger,
  }) => _publicDeadline((abortTrigger) async {
    if (id <= 0 ||
        id > 9007199254740991 ||
        verifyPassword != null && newPassword != null) {
      throw const FormatException('Invalid content password operation');
    }
    for (final value in [newPassword, currentPassword, verifyPassword]) {
      if (value != null && utf8.encode(value).length > 1024) {
        throw const FormatException('Password request exceeds local limit');
      }
    }
    final method = verifyPassword != null
        ? 'POST'
        : newPassword != null
        ? 'PUT'
        : 'GET';
    final path =
        '/api/blogs/$id${verifyPassword != null ? '/verify-password' : ''}';
    if (method != 'GET') {
      await _ensureCsrf(abortTrigger: abortTrigger);
    }
    final request = http.AbortableRequest(
      method,
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    request.headers['cache-control'] = 'no-store';
    if (method != 'GET') {
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(
        verifyPassword != null
            ? {'password': verifyPassword}
            : {
                'new_password': newPassword,
                'current_password': ?currentPassword,
              },
      );
    }
    final response = await _transport.send(request);
    late Uint8List bytes;
    try {
      bytes = await readBoundedResponse(
        response,
        maxBytes: method == 'PUT' ? 128 * 1024 : 26 * 1024 * 1024,
      );
    } on ApiFailure catch (error) {
      if (error.status == 413) {
        throw const FormatException(
          'Password response exceeds local read bound',
        );
      }
      rethrow;
    }
    if ((response.headers['content-type'] ?? '')
            .toLowerCase()
            .split(';')
            .first
            .trim() !=
        'application/json') {
      throw const FormatException('Content password operation requires JSON');
    }
    utf8.decode(bytes, allowMalformed: false);
    return _decode(
      http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      ),
    );
  }, abortTrigger: abortTrigger);

  /// Fixed owner sharing operations, bounded and cancelled independently.
  Future<Map<String, Object?>> shareSettingsJson(
    PublicShareKind kind,
    int targetId, {
    String action = 'status',
    Future<void>? abortTrigger,
  }) => _publicDeadline((abortTrigger) async {
    if (targetId <= 0 ||
        targetId > 9007199254740991 ||
        !{
          'status',
          'publish',
          'enable',
          'reset',
          'disable',
          'unpublish',
        }.contains(action)) {
      throw const FormatException('Invalid owner sharing operation');
    }
    final method = switch (action) {
      'status' => 'GET',
      'publish' => 'POST',
      'unpublish' => 'DELETE',
      _ => 'PATCH',
    };
    final path = switch (action) {
      'status' => '/api/shares/status?type=${kind.name}&ids=$targetId',
      'publish' => '/api/shares',
      'unpublish' => '/api/shares/${kind.name}/$targetId',
      _ => '/api/shares/${kind.name}/$targetId/edit-token',
    };
    if (method != 'GET') {
      await _ensureCsrf(abortTrigger: abortTrigger);
    }
    final request = http.AbortableRequest(
      method,
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    request.headers['cache-control'] = 'no-store';
    if (method != 'GET') {
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(
        action == 'publish'
            ? {
                'share_type': kind.name,
                'target_id': targetId,
                'enable_edit': false,
              }
            : action == 'unpublish'
            ? <String, Object?>{}
            : {'action': action},
      );
    }
    final response = await _transport.send(request);
    late Uint8List bytes;
    try {
      bytes = await readBoundedResponse(response, maxBytes: 128 * 1024);
    } on ApiFailure catch (error) {
      if (error.status == 413) {
        throw const FormatException('Sharing receipt exceeds the read bound');
      }
      rethrow;
    }
    final media = (response.headers['content-type'] ?? '').toLowerCase();
    if (media.split(';').first.trim() != 'application/json') {
      throw const FormatException('Sharing settings require a JSON response');
    }
    utf8.decode(bytes, allowMalformed: false);
    return _decode(
      http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      ),
    );
  }, abortTrigger: abortTrigger);

  Future<String> publicSharePageHtml(
    PublicShareReference reference, {
    Future<void>? abortTrigger,
  }) => _publicDeadline((abortTrigger) async {
    _publicReference(reference);
    final request = http.AbortableRequest(
      'GET',
      reference.canonicalUri,
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'text/html';
    final response = await _transport.send(request);
    final bytes = await readBoundedResponse(
      response,
      maxBytes: 26 * 1024 * 1024,
    );
    if (response.statusCode != 200) {
      throw ApiFailure(response.statusCode, 'Public share page unavailable');
    }
    final media = (response.headers['content-type'] ?? '').toLowerCase();
    if (media.split(';').first.trim() != 'text/html' ||
        media.contains('charset=') &&
            !RegExp(
              r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
            ).hasMatch(media)) {
      throw const FormatException('Public share page must be UTF-8 HTML');
    }
    return utf8.decode(bytes, allowMalformed: false);
  }, abortTrigger: abortTrigger);

  Future<Map<String, Object?>> publicCommentsJson(
    PublicShareReference reference, {
    int page = 1,
    Map<String, Object?>? body,
    int? deleteId,
    Future<void>? abortTrigger,
  }) => _publicDeadline((abortTrigger) async {
    _publicReference(reference);
    if (page < 1 ||
        page > 100000 ||
        deleteId != null && deleteId <= 0 ||
        body != null && deleteId != null) {
      throw const FormatException('Invalid public comment operation');
    }
    final write = body != null || deleteId != null;
    if (write) await _ensureCsrf(abortTrigger: abortTrigger);
    final path = deleteId != null
        ? '/api/share-comments/$deleteId?identify=${Uri.encodeQueryComponent(reference.identify)}'
        : '${reference.detailPath}/comments${body == null ? '?page=$page&page_size=20' : ''}';
    final request = http.AbortableRequest(
      deleteId != null
          ? 'DELETE'
          : body == null
          ? 'GET'
          : 'POST',
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    if (write) request.headers['x-csrf-token'] = _cookies['csrf_token']!;
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.body = jsonEncode(body);
    }
    final response = await _transport.send(request);
    final bytes = await readBoundedResponse(
      response,
      maxBytes: body == null && deleteId == null ? 8 * 1024 * 1024 : 128 * 1024,
    );
    final media = (response.headers['content-type'] ?? '').toLowerCase();
    if (media.split(';').first.trim() != 'application/json' ||
        media.contains('charset=') &&
            !RegExp(
              r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
            ).hasMatch(media)) {
      throw const FormatException('Public comments require UTF-8 JSON');
    }
    return _decode(
      http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      ),
    );
  }, abortTrigger: abortTrigger);

  /// Token capabilities stay on a fixed same-origin edit endpoint. Other
  /// formats are not writable through this Markdown-sized request channel.
  Future<Map<String, Object?>> publicEditJson(
    PublicEditLink link, {
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
  }) => _publicDeadline((abortTrigger) async {
    _publicReference(link.reference);
    if (body != null) {
      if (body['content'] is! String ||
          body.keys.any((key) => !{'content', 'password'}.contains(key)) ||
          body.containsKey('password') && body['password'] is! String ||
          utf8.encode(body['content'] as String).length > 500 * 1024) {
        throw const FormatException('Invalid shared Markdown request');
      }
      await _ensureCsrf(abortTrigger: abortTrigger);
    }
    final request = http.AbortableRequest(
      body == null ? 'GET' : 'PUT',
      _endpoint(link.requestPath),
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    request.headers['cache-control'] = 'no-store';
    if (body != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.body = jsonEncode(body);
    }
    final response = await _transport.send(request);
    final bytes = await readBoundedResponse(
      response,
      maxBytes: body == null ? 26 * 1024 * 1024 : 128 * 1024,
    );
    final media = (response.headers['content-type'] ?? '').toLowerCase();
    if (media.split(';').first.trim() != 'application/json' ||
        media.contains('charset=') &&
            !RegExp(
              r"""charset=\s*["']?utf-8(?:["';\s]|$)""",
            ).hasMatch(media)) {
      throw const FormatException('Shared editing requires UTF-8 JSON');
    }
    return _decode(
      http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      ),
    );
  }, abortTrigger: abortTrigger);

  /// Fixed public reading endpoints with bounded JSON and no redirects.
  Future<Map<String, Object?>> publicShareJson(
    String path, {
    Map<String, Object?>? passwordBody,
    Future<void>? abortTrigger,
  }) => _publicDeadline((abortTrigger) async {
    final route = Uri.parse(path);
    if (!RegExp(
          r'^/api/shares/[^/]+(?:/docs/[^/]+|/verify-password)?$',
        ).hasMatch(route.path) ||
        route.hasQuery ||
        route.hasFragment ||
        (passwordBody != null && !route.path.endsWith('/verify-password')) ||
        (passwordBody == null && route.path.endsWith('/verify-password'))) {
      throw const FormatException('Invalid public reading endpoint');
    }
    if (passwordBody != null) {
      if (passwordBody.length != 1 || passwordBody['password'] is! String) {
        throw const FormatException('Invalid unlock body');
      }
      await _ensureCsrf(abortTrigger: abortTrigger);
    }
    final request = http.AbortableRequest(
      passwordBody == null ? 'GET' : 'POST',
      _endpoint(path),
      abortTrigger: abortTrigger,
    );
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    if (passwordBody != null) {
      request.headers['content-type'] = 'application/json; charset=utf-8';
      request.headers['x-csrf-token'] = _cookies['csrf_token']!;
      request.body = jsonEncode(passwordBody);
    }
    final response = await _transport.send(request);
    // JSON escaping can expand a valid 4 MiB Markdown body sixfold.
    final bytes = await readBoundedResponse(
      response,
      maxBytes: 26 * 1024 * 1024,
    );
    final media = (response.headers['content-type'] ?? '').toLowerCase();
    if (media.split(';').first.trim() != 'application/json' ||
        media.contains('charset=') &&
            !RegExp(
              r'''charset=\s*["']?utf-8(?:["';\s]|$)''',
            ).hasMatch(media)) {
      throw const FormatException('Public reading requires UTF-8 JSON');
    }
    return _decode(
      http.Response.bytes(
        bytes,
        response.statusCode,
        headers: response.headers,
      ),
    );
  }, abortTrigger: abortTrigger);

  Future<Map<String, Object?>> _sendJson(
    http.BaseRequest request, {
    bool csrf = false,
    void Function()? beforeSubmit,
    void Function()? sessionGuard,
  }) async {
    final guard = sessionGuard ?? _legacySessionGuard();
    guard();
    _authenticate(request);
    request.headers['accept'] = 'application/json';
    if (csrf) request.headers['x-csrf-token'] = _cookies['csrf_token']!;
    beforeSubmit?.call();
    guard();
    final response = await http.Response.fromStream(
      await _transport.send(request),
    );
    // _decode may merge Set-Cookie. Reject stale identity before that side effect.
    guard();
    return _decode(response);
  }

  Map<String, Object?> _decode(http.Response response) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiFailure(response.statusCode, '服务器没有返回有效的 JSON 响应');
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiFailure(response.statusCode, '服务器响应格式不正确');
    }
    final code = decoded['code'];
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        (code is int && code != 0 && code != 200)) {
      throw ApiFailure(
        response.statusCode,
        decoded['message'] is String ? decoded['message'] as String : '请求失败',
      );
    }
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      for (final cookie in setCookie.split(RegExp(r',(?=\s*[^;,=\s]+=)'))) {
        final pair = cookie.split(';').first.trim();
        final equal = pair.indexOf('=');
        if (equal < 1) continue;
        final name = pair.substring(0, equal);
        if (!['token', 'csrf_token'].contains(name)) continue;
        final value = pair.substring(equal + 1);
        if (value.isEmpty || cookie.toLowerCase().contains('max-age=0')) {
          _cookies.remove(name);
        } else {
          _cookies[name] = value;
        }
      }
    }
    final data = decoded['data'];
    return data is Map<String, dynamic>
        ? Map<String, Object?>.from(data)
        : Map<String, Object?>.from(decoded);
  }

  /// These narrow methods return the original success envelope. Never _decode:
  /// raw server messages/error bodies must not leak into recovery UI.
  Future<Map<String, Object?>> boundedDriveListJson(
    String path, {
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    final fixed = drivePath(path);
    if (fixed != path) {
      throw const FormatException('Canonical drive path required');
    }
    return _scopedReadJson(
      '/api/webdav/files?${Uri(queryParameters: {'path': fixed}).query}',
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxBytes: 1024 * 1024,
    );
  }

  /// Authenticated visible server media, not proof that the current member owns
  /// every item: the existing Go list is global to authenticated users.
  Future<Map<String, Object?>> boundedOwnedImageChoicesJson(
    int page, {
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    if (page < 1 || page > 1000000) {
      throw const FormatException('Invalid image page');
    }
    return _scopedReadJson(
      '/api/uploads?${Uri(queryParameters: {'page': page.toString(), 'page_size': '20'}).query}',
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxBytes: 128 * 1024,
    );
  }

  Future<Map<String, Object?>> boundedCurrentOwnerJson({
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) => _scopedReadJson(
    '/api/profile',
    expectedSessionRevision: expectedSessionRevision,
    abortTrigger: abortTrigger,
    maxBytes: 128 * 1024,
  );
  Future<Map<String, Object?>> boundedBookDetailJson(
    int id, {
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Positive book ID required');
    return _scopedReadJson(
      '/api/books/$id',
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxBytes: 256 * 1024,
    );
  }

  Future<Map<String, Object?>> boundedBookLabelsJson(
    int id, {
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    if (id <= 0) throw const FormatException('Positive book ID required');
    return _scopedReadJson(
      '/api/labels/resource/book/$id',
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxBytes: 128 * 1024,
    );
  }

  Future<PreparedAuthenticatedJsonRequest> prepareDriveMutationJson(
    DriveMutationAction action, {
    required String sourcePath,
    String? destinationPath,
    String? name,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    if (drivePath(sourcePath) != sourcePath) {
      throw const FormatException('Canonical source required');
    }
    late String method, path;
    Map<String, Object?>? body;
    if (action == DriveMutationAction.mkdir) {
      if (name == null || driveName(name) != name || destinationPath != null) {
        throw const FormatException('Mkdir input');
      }
      method = 'POST';
      path = '/api/webdav/files/mkdir';
      body = {'path': sourcePath, 'name': name};
    } else if (action == DriveMutationAction.remove) {
      if (sourcePath.isEmpty || destinationPath != null || name != null) {
        throw const FormatException('Delete input');
      }
      method = 'DELETE';
      path =
          '/api/webdav/files?${Uri(queryParameters: {'path': sourcePath}).query}';
      body = <String, Object?>{};
    } else {
      if (sourcePath.isEmpty ||
          destinationPath == null ||
          name != null ||
          drivePath(destinationPath) != destinationPath ||
          destinationPath.isEmpty ||
          destinationPath == sourcePath ||
          destinationPath.startsWith('$sourcePath/')) {
        throw const FormatException('Relocate input');
      }
      method = 'POST';
      path =
          '/api/webdav/files/${action == DriveMutationAction.rename ? 'rename' : 'copy'}';
      body = {'path': sourcePath, 'new_path': destinationPath};
    }
    return _prepareScopedJson(
      method,
      path,
      body: body,
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
    );
  }

  Future<Map<String, Object?>> readTopicCreationReviewJson(
    String kind,
    int id, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) async {
    if (!{'topic', 'summary', 'comment'}.contains(kind) || id <= 0) {
      throw const FormatException('Invalid creation review identity');
    }
    final request = await _prepareScopedJson(
      'GET',
      '/api/topic-creation-review/$kind/$id',
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxBytes: 512 * 1024,
    );
    try {
      return await request.sendOnce();
    } finally {
      request.retire();
    }
  }

  /// Exact topic-family create paths. Auth/CSRF completes before sendAfter claim.
  Future<PreparedAuthenticatedJsonRequest> prepareTopicCreationJson(
    String kind,
    int topicId,
    Map<String, Object?> body, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) {
    Set<String> keys;
    String path;
    if (kind == 'topic' && topicId == 0) {
      keys = {'title', 'question', 'is_pinned'};
      path = '/api/topics';
      if (body['title'] is! String ||
          body['question'] is! String ||
          body['is_pinned'] is! bool ||
          (body['title'] as String).trim().isEmpty ||
          (body['title'] as String).runes.length > 200 ||
          (body['question'] as String).runes.length > 2000) {
        throw const FormatException('Invalid topic creation');
      }
    } else if (kind == 'summary' && topicId > 0) {
      keys = {'content', 'summary_type', 'order_sort'};
      path = '/api/topics/$topicId/summaries';
      if (!{'manual', 'ai'}.contains(body['summary_type']) ||
          body['order_sort'] is! int) {
        throw const FormatException('Invalid summary creation');
      }
    } else if (kind == 'comment' && topicId > 0) {
      keys = {'content', 'target_type', 'target_id', 'parent_comment_id'};
      path = '/api/topics/$topicId/comments';
      if (!{'summary', 'resource', 'task'}.contains(body['target_type']) ||
          body['target_id'] is! int ||
          (body['target_id'] as int) <= 0 ||
          body['parent_comment_id'] != 0) {
        throw const FormatException('Invalid comment creation');
      }
    } else {
      throw const FormatException('Invalid topic creation route');
    }
    if (body.length != keys.length || !body.keys.toSet().containsAll(keys)) {
      throw const FormatException('Unexpected creation fields');
    }
    if (kind != 'topic' &&
        (body['content'] is! String ||
            (body['content'] as String).trim().isEmpty ||
            (body['content'] as String).runes.length > 20000)) {
      throw const FormatException('Invalid creation content');
    }
    return _prepareScopedJson(
      'POST',
      path,
      body: Map.of(body),
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxRequestBytes: 256 * 1024,
      maxBytes: 512 * 1024,
    );
  }

  Future<PreparedAuthenticatedJsonRequest> prepareBookCreateJson(
    Map<String, Object?> body, {
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    if (body.length != 3 ||
        !body.keys.toSet().containsAll({
          'book_name',
          'description',
          'labels',
        }) ||
        body['book_name'] is! String ||
        body['description'] is! String ||
        body['labels'] is! String ||
        (body['book_name'] as String).trim().isEmpty ||
        utf8.encode(body['book_name'] as String).length > 200 ||
        utf8.encode(body['description'] as String).length > 2000) {
      throw const FormatException('Book creation input');
    }
    return _prepareScopedJson(
      'POST',
      '/api/books',
      body: Map.of(body),
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
    );
  }

  Future<Map<String, Object?>> readOwnedProtectedRecoveryJson(
    int id, {
    required String password,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) async {
    if (id <= 0) throw const FormatException('Owned recovery ID required');
    _scopedText(password);
    if (utf8.encode(password).length > 4096) {
      throw const FormatException('Bounded recovery credential required');
    }
    final prepared = await _prepareScopedJson(
      'POST',
      '/api/owned-complex/notes/$id/protected-review',
      body: {'password': password},
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxRequestBytes: 8192,
      maxBytes: 28 * 1024 * 1024 + 128 * 1024,
    );
    try {
      return await prepared.sendOnce();
    } finally {
      prepared.retire();
    }
  }

  void _protectedOwnedIdentity(int id, String kind, String password) {
    if (id <= 0 ||
        !const {
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(kind)) {
      throw const FormatException('Protected owned note identity required');
    }
    _scopedText(password);
    if (password.isEmpty || utf8.encode(password).length > 4096) {
      throw const FormatException('Invalid bounded protected credential');
    }
  }

  Future<Map<String, Object?>> unlockProtectedOwnedComplexJson(
    int id, {
    required String kind,
    required String password,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) async {
    _protectedOwnedIdentity(id, kind, password);
    final prepared = await _prepareScopedJson(
      'POST',
      '/api/owned-complex/notes/$id/unlock?kind=$kind',
      body: {'password': password},
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxRequestBytes: 8192,
      maxBytes: 28 * 1024 * 1024 + 128 * 1024,
    );
    try {
      return await prepared.sendOnce();
    } finally {
      prepared.retire();
    }
  }

  Future<PreparedAuthenticatedJsonRequest>
  prepareProtectedOwnedComplexSourcePut(
    int id, {
    required String kind,
    required String password,
    required String expectedFingerprint,
    required List<int> sourceBytes,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    _protectedOwnedIdentity(id, kind, password);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedFingerprint) ||
        sourceBytes.length > (kind == 'presentation' ? 20 : 5) * 1024 * 1024) {
      throw const FormatException('Protected source exceeds bound');
    }
    return _prepareScopedJson(
      'PUT',
      '/api/owned-complex/notes/$id/protected?kind=$kind',
      body: {
        'password': password,
        'expected_fp': expectedFingerprint,
        'source_base64': base64Encode(sourceBytes),
      },
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxRequestBytes: 28 * 1024 * 1024 + 128 * 1024,
      maxBytes: 28 * 1024 * 1024 + 128 * 1024,
    );
  }

  String _ownedComplexPath(
    int id, {
    required int bookId,
    required bool note,
    required String kind,
  }) {
    if (id <= 0 ||
        (note ? bookId != 0 : bookId <= 0) ||
        !const {
          'html',
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(kind)) {
      throw const FormatException('Owned complex identity required');
    }
    return '${note ? '/api/owned-complex/notes/$id' : '/api/owned-complex/books/$bookId/docs/$id'}?kind=$kind';
  }

  Future<Map<String, Object?>> ownedComplexSourceJson(
    int id, {
    required int bookId,
    required bool note,
    required String kind,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) => _scopedReadJson(
    _ownedComplexPath(id, bookId: bookId, note: note, kind: kind),
    expectedSessionRevision: expectedSessionRevision,
    abortTrigger: abortTrigger,
    maxBytes: 28 * 1024 * 1024 + 128 * 1024,
  );
  Future<PreparedAuthenticatedJsonRequest> prepareOwnedComplexSourcePut(
    int id, {
    required int bookId,
    required bool note,
    required String kind,
    required String expectedFingerprint,
    required List<int> sourceBytes,
    String? title,
    List<String>? labels,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
  }) {
    final path = _ownedComplexPath(id, bookId: bookId, note: note, kind: kind);
    final limit = (kind == 'presentation' ? 20 : 5) * 1024 * 1024;
    if (sourceBytes.length > limit ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedFingerprint)) {
      throw const FormatException('Owned complex source exceeds bound');
    }
    if ((title == null) != (labels == null) || !note && title != null) {
      throw const FormatException(
        'Only note metadata may be edited explicitly',
      );
    }
    if (title != null) {
      _scopedText(title);
      final editedLabels = labels!;
      if (title.trim().isEmpty ||
          utf8.encode(title).length > 200 ||
          editedLabels.length > 100 ||
          editedLabels.toSet().length != editedLabels.length ||
          editedLabels.any((v) => v.isEmpty) ||
          utf8.encode(jsonEncode(editedLabels)).length > 60 * 1024) {
        throw const FormatException('Invalid explicit note metadata');
      }
      for (final label in editedLabels) {
        _scopedText(label);
      }
    }
    final body = <String, Object?>{
      'expected_fp': expectedFingerprint,
      'source_base64': base64Encode(sourceBytes),
      'title': ?title,
      if (labels != null) 'labels': List<String>.of(labels),
    };
    return _prepareScopedJson(
      'PUT',
      path,
      body: body,
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxBytes: 28 * 1024 * 1024 + 128 * 1024,
      maxRequestBytes: 28 * 1024 * 1024 + 128 * 1024,
    );
  }

  void _scopedText(String text) {
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        if (++i >= text.length ||
            text.codeUnitAt(i) < 0xdc00 ||
            text.codeUnitAt(i) > 0xdfff) {
          throw const FormatException('Invalid request text');
        }
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        throw const FormatException('Invalid request text');
      }
    }
  }

  Future<Map<String, Object?>> _scopedReadJson(
    String path, {
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
    int maxBytes = 128 * 1024,
  }) async {
    final request = await _prepareScopedJson(
      'GET',
      path,
      expectedSessionRevision: expectedSessionRevision,
      abortTrigger: abortTrigger,
      maxBytes: maxBytes,
    );
    return request.sendOnce();
  }

  /// Bookmark-only creation transport; no legacy URL upsert.
  Future<PreparedAuthenticatedJsonRequest> prepareBookmarkCreationJson(
    Map<String, Object?> body, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) {
    const fields = {
      'title',
      'url',
      'description',
      'favicon',
      'is_public',
      'labels',
    };
    if (body.length != fields.length ||
        !body.keys.toSet().containsAll(fields) ||
        body['is_public'] is! bool ||
        body['labels'] is! List) {
      throw const FormatException('Invalid bookmark creation input');
    }
    for (final key in ['title', 'url', 'description', 'favicon']) {
      if (body[key] is! String) {
        throw const FormatException('Bookmark string required');
      }
      _scopedText(body[key] as String);
    }
    final labels = body['labels'] as List;
    if (labels.length > 100 || labels.any((e) => e is! String)) {
      throw const FormatException('Invalid exact bookmark labels');
    }
    var total = 0;
    for (final label in labels.cast<String>()) {
      _scopedText(label);
      final n = utf8.encode(label).length;
      total += n;
      if (n > 4096 || total > 65536) {
        throw const FormatException('Bookmark label budget');
      }
    }
    return _prepareScopedJson(
      'POST',
      '/api/bookmarks/create-owned',
      body: Map.of(body),
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxRequestBytes: 512 * 1024,
      maxBytes: 1024 * 1024,
    );
  }

  Future<Map<String, Object?>> checkBookmarkCreationURLJson(
    String url, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) async {
    _scopedText(url);
    if (utf8.encode(url).length > 2048) {
      throw const FormatException('Bookmark URL budget');
    }
    final request = await _prepareScopedJson(
      'POST',
      '/api/bookmarks/creation-check',
      body: {'url': url},
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxRequestBytes: 16 * 1024,
      maxBytes: 1024 * 1024,
    );
    return request.sendOnce();
  }

  Future<Map<String, Object?>> readBookmarkCreationReviewJson(
    int id, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) async {
    if (id <= 0) throw const FormatException('Actual bookmark ID required');
    final request = await _prepareScopedJson(
      'GET',
      '/api/bookmarks/$id/creation-review',
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxBytes: 1024 * 1024,
    );
    return request.sendOnce();
  }

  /// Global label INSERT only. Auth/CSRF precedes the durable single claim.
  /// Exact ordinary task creation only. Auth/CSRF preparation sends no mutation.
  Future<PreparedAuthenticatedJsonRequest> prepareTaskCreationJson(
    Map<String, Object?> body, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) {
    const fields = {'content', 'due_date', 'done', 'parent_id', 'topic_id'};
    if (body.length != fields.length ||
        !body.keys.toSet().containsAll(fields) ||
        body['content'] is! String ||
        body['due_date'] is! String ||
        body['done'] is! bool ||
        body['parent_id'] is! int ||
        body['topic_id'] is! int) {
      throw const FormatException('Exact task input required');
    }
    final content = body['content'] as String,
        date = body['due_date'] as String;
    _scopedText(content);
    _scopedText(date);
    final parsed = DateTime.tryParse(date);
    if (content.isEmpty ||
        content != content.trim() ||
        content.runes.length > 1000 ||
        (body['parent_id'] as int) < 0 ||
        (body['topic_id'] as int) < 0 ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        parsed == null ||
        parsed.year < 1 ||
        parsed.toIso8601String().substring(0, 10) != date) {
      throw const FormatException('Invalid task input');
    }
    return _prepareScopedJson(
      'POST',
      '/api/tasks',
      body: Map.of(body),
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxRequestBytes: 16 * 1024,
      maxBytes: 32 * 1024,
    );
  }

  Future<Map<String, Object?>> readTaskCreationReviewJson(
    int id, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) async {
    if (id <= 0)
      throw const FormatException('Positive actual task ID required');
    final request = await _prepareScopedJson(
      'GET',
      '/api/tasks/$id',
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxBytes: 32 * 1024,
    );
    try {
      return await request.sendOnce();
    } finally {
      request.retire();
    }
  }

  Future<PreparedAuthenticatedJsonRequest> prepareLabelCreationJson(
    Map<String, Object?> body, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) {
    if (body.length != 1 || body['label_name'] is! String) {
      throw const FormatException('Exact label name required');
    }
    final name = body['label_name'] as String;
    _scopedText(name);
    if (name.trim().isEmpty || utf8.encode(name).length > 100) {
      throw const FormatException('Label name exceeds UTF-8 budget');
    }
    return _prepareScopedJson(
      'POST',
      '/api/labels',
      body: Map.of(body),
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxRequestBytes: 16 * 1024,
      maxBytes: 32 * 1024,
    );
  }

  Future<Map<String, Object?>> readLabelCreationReviewJson(
    int id, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) async {
    if (id <= 0) throw const FormatException('Actual global label ID required');
    final request = await _prepareScopedJson(
      'GET',
      '/api/label-creation-review/$id',
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxBytes: 256 * 1024,
    );
    try {
      return await request.sendOnce();
    } finally {
      request.retire();
    }
  }

  /// Owned search only; bounded JSON, original seven-type response semantics.
  Future<Map<String, Object?>> readSearchJson(
    String query, {
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    Future<void>? abortTrigger,
  }) async {
    _scopedText(query);
    if (query.trim().isEmpty ||
        query != query.trim() ||
        utf8.encode(query).length > 100) {
      throw const FormatException('Invalid exact search query');
    }
    final path = '/api/search?${Uri(queryParameters: {'q': query}).query}';
    final request = await _prepareScopedJson(
      'GET',
      path,
      expectedSessionRevision: expectedSessionRevision,
      ownerGuard: ownerGuard,
      abortTrigger: abortTrigger,
      maxBytes: 2 * 1024 * 1024,
      responseLimits: const LegacyJsonLimits(
        maxBytes: 2 * 1024 * 1024,
        maxStringBytes: 64 * 1024,
        maxEncodedStringCharacters: 2 * 1024 * 1024,
        maxDepth: 8,
        maxNodes: 10000,
        maxObjectMembers: 32,
        maxArrayLength: 20,
      ),
    );
    try {
      final reply = await request.sendOnce();
      final data = reply['data'];
      if (data is! Map<String, Object?>)
        throw const ApiFailure(502, 'Search metadata unavailable');
      return Map.of(data);
    } finally {
      request.retire();
    }
  }

  Future<PreparedAuthenticatedJsonRequest> _prepareScopedJson(
    String method,
    String path, {
    Map<String, Object?>? body,
    required int expectedSessionRevision,
    Future<void>? abortTrigger,
    int maxBytes = 128 * 1024,
    int maxRequestBytes = 128 * 1024,
    void Function()? ownerGuard,
    LegacyJsonLimits? responseLimits,
  }) async {
    if (maxRequestBytes < 0 ||
        maxRequestBytes > 28 * 1024 * 1024 + 128 * 1024) {
      throw const FormatException('Invalid prepared request bound');
    }
    final endpoint = _endpoint(path),
        token = _cookies['token'],
        language = _language;
    if (token == null ||
        token.isEmpty ||
        _rawClosed ||
        sessionRevision != expectedSessionRevision) {
      throw const ApiFailure(499, 'Authenticated scope unavailable');
    }
    final payload = body == null ? null : jsonEncode(body);
    if (body != null) {
      for (final value in body.values) {
        if (value is String) {
          _scopedText(value);
        }
      }
    }
    if (payload != null && utf8.encode(payload).length > maxRequestBytes) {
      throw const FormatException('Request exceeds bound');
    }
    final stopped = Completer<void>();
    _rawDocumentStops.add(stopped);
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
      _rawDocumentStops.remove(stopped);
    }

    final timer = Timer(const Duration(seconds: 20), stop);
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) => stop(), onError: (Object _) => stop()),
      );
    }
    void guard() {
      ownerGuard?.call();
      if (stopped.isCompleted ||
          _rawClosed ||
          sessionRevision != expectedSessionRevision ||
          _cookies['token'] != token ||
          _language != language) {
        throw const ApiFailure(499, 'Authenticated scope retired');
      }
    }

    Future<T> wait<T>(Future<T> work) => Future.any<T>([
      work,
      stopped.future.then<T>(
        (_) => throw const ApiFailure(499, 'Authenticated request retired'),
      ),
    ]);
    Future<Map<String, Object?>> exchange(
      http.AbortableRequest request,
      int limit,
    ) async {
      guard();
      var responseClaimed = false, lateDrained = false;
      final pending = _transport.send(request);
      unawaited(
        pending.then<void>((response) async {
          if (stopped.isCompleted && !responseClaimed) {
            lateDrained = true;
            try {
              await response.stream
                  .listen((_) {}, onError: (Object _, StackTrace _) {})
                  .cancel();
            } catch (_) {}
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final response = await wait(pending);
      responseClaimed = true;
      try {
        guard();
      } catch (_) {
        if (!lateDrained) {
          await response.stream
              .listen((_) {}, onError: (Object _, StackTrace _) {})
              .cancel();
        }
        rethrow;
      }
      final media = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode != 200 ||
          response.isRedirect ||
          response.request != null && response.request!.url != request.url ||
          media.split(';').first.trim() != 'application/json' ||
          media.contains('charset=') &&
              !RegExp(
                r'''charset=\s*["]?utf-8(?:[";\s]|$)''',
              ).hasMatch(media) ||
          !{'', 'identity'}.contains(
            (response.headers['content-encoding'] ?? '').toLowerCase(),
          ) ||
          response.contentLength != null && response.contentLength! > limit) {
        await response.stream
            .listen((_) {}, onError: (Object _, StackTrace _) {})
            .cancel();
        throw ApiFailure(
          response.statusCode,
          'Authenticated response unavailable',
        );
      }
      final iterator = StreamIterator<List<int>>(response.stream),
          bytes = BytesBuilder(copy: false);
      var count = 0;
      try {
        while (await wait(iterator.moveNext())) {
          guard();
          count += iterator.current.length;
          if (count > limit) {
            throw const ApiFailure(413, 'Authenticated response exceeds bound');
          }
          bytes.add(iterator.current);
        }
      } finally {
        await iterator.cancel();
      }
      guard();
      final Object? decoded;
      try {
        final raw = bytes.takeBytes();
        decoded = responseLimits == null
            ? jsonDecode(utf8.decode(raw, allowMalformed: false))
            : decodeLegacyJson(raw, limits: responseLimits);
      } catch (_) {
        throw const ApiFailure(502, 'Authenticated response unavailable');
      }
      if (decoded is! Map<String, dynamic> ||
          decoded['code'] is! int ||
          decoded['code'] != 0) {
        throw const ApiFailure(502, 'Authenticated response unavailable');
      }
      return Map<String, Object?>.from(decoded);
    }

    http.AbortableRequest make(
      String verb,
      Uri uri, {
      String? encoded,
      String? csrf,
    }) {
      final request = http.AbortableRequest(
        verb,
        uri,
        abortTrigger: stopped.future,
      )..followRedirects = false;
      _authenticate(request);
      request.headers.addAll({
        'accept': 'application/json',
        'accept-encoding': 'identity',
        'cache-control': 'no-store',
      });
      if (encoded != null) {
        request.headers['content-type'] = 'application/json; charset=utf-8';
        request.body = encoded;
      }
      if (csrf != null) request.headers['x-csrf-token'] = csrf;
      return request;
    }

    try {
      guard();
      if (method != 'GET' && (_cookies['csrf_token'] ?? '').isEmpty) {
        final csrfEnvelope = await exchange(
          make('GET', _endpoint('/api/csrf-token')),
          16 * 1024,
        );
        guard();
        final csrf = csrfEnvelope['csrf_token'];
        if (csrf is! String ||
            csrf.isEmpty ||
            csrf.length > 4096 ||
            RegExp(r'[\r\n;]').hasMatch(csrf)) {
          throw const ApiFailure(403, 'CSRF preparation unavailable');
        }
        _cookies['csrf_token'] = csrf;
      }
      guard();
      final csrf = method == 'GET' ? null : _cookies['csrf_token'];
      final request = make(method, endpoint, encoded: payload, csrf: csrf);
      final cookieIdentity = jsonEncode(_cookies);
      return PreparedAuthenticatedJsonRequest._(
        endpoint,
        payload ?? '',
        () async {
          try {
            guard();
            if (jsonEncode(_cookies) != cookieIdentity) {
              throw const ApiFailure(499, 'Prepared session changed');
            }
            return await exchange(request, maxBytes);
          } finally {
            timer.cancel();
            stop();
          }
        },
        () {
          timer.cancel();
          stop();
        },
      );
    } catch (_) {
      timer.cancel();
      stop();
      rethrow;
    }
  }

  /// Existing owned-document image upload. Legal account/CSRF and the complete
  /// multipart bytes are fixed before the caller's durable send boundary.
  Future<PreparedOwnedImageUpload> prepareOwnedImageUpload({
    required Uint8List imageBytes,
    required String fileName,
    required String inputSHA256,
    required int expectedMemberId,
    required int expectedSessionRevision,
    required void Function() ownerGuard,
    String category = 'editor',
    Future<void>? abortTrigger,
  }) async {
    if (expectedMemberId <= 0 ||
        imageBytes.isEmpty ||
        imageBytes.length > 5 * 1024 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(inputSHA256) ||
        crypto.sha256.convert(imageBytes).toString() != inputSHA256 ||
        fileName.isEmpty ||
        fileName.length > 255 ||
        fileName == '.' ||
        fileName == '..' ||
        fileName.contains('/') ||
        fileName.contains('\\') ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(fileName) ||
        !{'editor', 'note', 'drawing'}.contains(category)) {
      throw const FormatException('Invalid owned image upload');
    }
    _scopedText(fileName);
    bool at(int offset, List<int> signature) =>
        imageBytes.length >= offset + signature.length &&
        List.generate(
          signature.length,
          (index) => imageBytes[offset + index] == signature[index],
        ).every((v) => v);
    if (!(at(0, [137, 80, 78, 71, 13, 10, 26, 10]) ||
        at(0, [255, 216, 255]) ||
        at(0, [71, 73, 70, 56, 55, 97]) ||
        at(0, [71, 73, 70, 56, 57, 97]) ||
        at(0, [82, 73, 70, 70]) && at(8, [87, 69, 66, 80]))) {
      throw const FormatException('Supported raster image required');
    }
    final (width, height) = encodedImageDimensions(imageBytes);
    if (width > 8192 || height > 8192 || width * height > 16 * 1024 * 1024) {
      throw const FormatException('Image dimensions exceeded');
    }
    final bytes = Uint8List.fromList(imageBytes);
    final token = _cookies['token'];
    final stopped = Completer<void>();
    _rawDocumentStops.add(stopped);
    void stop() {
      if (!stopped.isCompleted) stopped.complete();
      _rawDocumentStops.remove(stopped);
    }

    final timer = Timer(const Duration(seconds: 20), stop);
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then((_) => stop(), onError: (Object _) => stop()),
      );
    }
    void guard() {
      ownerGuard();
      if (stopped.isCompleted ||
          _rawClosed ||
          token == null ||
          token.isEmpty ||
          sessionRevision != expectedSessionRevision ||
          _cookies['token'] != token) {
        throw const ApiFailure(499, 'Image upload scope retired');
      }
    }

    Future<T> wait<T>(Future<T> work) => Future.any<T>([
      work,
      stopped.future.then<T>(
        (_) => throw const ApiFailure(499, 'Image upload ended'),
      ),
    ]);
    try {
      guard();
      final owner = await wait(
        boundedCurrentOwnerJson(
          expectedSessionRevision: expectedSessionRevision,
          abortTrigger: stopped.future,
        ),
      );
      guard();
      if (owner['code'] != 0 ||
          owner['data'] is! Map ||
          (owner['data'] as Map)['member_id'] is! int ||
          (owner['data'] as Map)['member_id'] != expectedMemberId) {
        throw const ApiFailure(403, 'Image upload owner mismatch');
      }
      if ((_cookies['csrf_token'] ?? '').isEmpty) {
        final beforeBootstrap = jsonEncode(_cookies);
        final envelope = await wait(
          _scopedReadJson(
            '/api/csrf-token',
            expectedSessionRevision: expectedSessionRevision,
            abortTrigger: stopped.future,
            maxBytes: 16 * 1024,
          ),
        );
        guard();
        if (jsonEncode(_cookies) != beforeBootstrap) {
          throw const ApiFailure(499, 'Image upload session changed');
        }
        final csrf = envelope['csrf_token'];
        if (csrf is! String ||
            csrf.isEmpty ||
            csrf.length > 4096 ||
            RegExp(r'[\r\n;]').hasMatch(csrf)) {
          throw const ApiFailure(403, 'Image upload CSRF unavailable');
        }
        // Go explicitly exposes this token in its bounded JSON endpoint.
        // Never merge a late response Set-Cookie into another client session.
        _cookies['csrf_token'] = csrf;
      }
      guard();
      final form = http.MultipartRequest('POST', _endpoint('/api/uploads'))
        ..fields['category'] = category
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
      if (form.contentLength > 5 * 1024 * 1024 + 16384) {
        throw const FormatException('Image multipart exceeds bound');
      }
      final encoded = await wait(form.finalize().toBytes());
      guard();
      if (encoded.length > 5 * 1024 * 1024 + 16384) {
        throw const FormatException('Image multipart exceeds bound');
      }
      final request =
          http.AbortableRequest(
              'POST',
              _endpoint('/api/uploads'),
              abortTrigger: stopped.future,
            )
            ..followRedirects = false
            ..bodyBytes = encoded;
      _authenticate(request);
      request.headers.addAll({
        'accept': 'application/json',
        'cache-control': 'no-store',
        'content-type': form.headers['content-type']!,
        'x-csrf-token': _cookies['csrf_token']!,
      });
      final cookies = jsonEncode(_cookies);
      void ready() {
        guard();
        if (jsonEncode(_cookies) != cookies) {
          throw const ApiFailure(499, 'Prepared upload session changed');
        }
      }

      return PreparedOwnedImageUpload(
        uri: request.url,
        inputSHA256: inputSHA256,
        beforeSubmit: ready,
        abort: () {
          timer.cancel();
          stop();
        },
        send: () async {
          ready();
          var claimed = false;
          final pending = _transport.send(request);
          unawaited(
            pending.then<void>((response) async {
              if (stopped.isCompleted && !claimed) {
                try {
                  await response.stream
                      .listen((_) {}, onError: (Object _, StackTrace _) {})
                      .cancel();
                } catch (_) {}
              }
            }, onError: (Object _, StackTrace _) {}),
          );
          try {
            final response = await wait(pending);
            claimed = true;
            try {
              ready();
            } catch (_) {
              await wait(
                response.stream
                    .listen((_) {}, onError: (Object _, StackTrace _) {})
                    .cancel(),
              );
              rethrow;
            }
            final media = (response.headers['content-type'] ?? '')
                .toLowerCase();
            if (response.statusCode != 200 ||
                response.isRedirect ||
                response.request != null &&
                    response.request!.url != request.url ||
                media.split(';').first.trim() != 'application/json' ||
                media.contains('charset=') &&
                    !RegExp(
                      r'charset=\s*"?utf-8(?:[";\s]|$)',
                    ).hasMatch(media) ||
                response.contentLength != null &&
                    response.contentLength! > 64 * 1024) {
              await wait(
                response.stream
                    .listen((_) {}, onError: (Object _, StackTrace _) {})
                    .cancel(),
              );
              throw ApiFailure(
                response.statusCode,
                'Image upload result unavailable',
              );
            }
            final responseBytes = await wait(
              readBoundedResponse(response, maxBytes: 64 * 1024),
            );
            ready();
            final Object? decoded;
            try {
              decoded = jsonDecode(
                utf8.decode(responseBytes, allowMalformed: false),
              );
            } catch (_) {
              throw const FormatException('Image upload result unavailable');
            }
            if (decoded is! Map<String, dynamic> ||
                decoded['code'] is! int ||
                decoded['code'] != 0 ||
                decoded['data'] is! Map) {
              throw const FormatException('Image upload result unavailable');
            }
            return Map<String, Object?>.from(decoded);
          } finally {
            timer.cancel();
            stop();
          }
        },
      );
    } catch (_) {
      timer.cancel();
      stop();
      rethrow;
    }
  }

  void close() {
    _rawClosed = true;
    _retireRawDocumentReads();
    if (_ownsRawDocumentTransport) _rawDocumentTransport?.close();
    _transport.close();
  }
}

Future<Uint8List> readBoundedResponse(
  http.StreamedResponse response, {
  required int maxBytes,
}) async {
  if (maxBytes < 0) throw ArgumentError.value(maxBytes);
  if (response.contentLength != null && response.contentLength! > maxBytes) {
    await response.stream.listen((_) {}).cancel();
    throw const ApiFailure(413, '文件超过读取上限 / File exceeds the read limit');
  }
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in response.stream) {
    if (buffer.length + chunk.length > maxBytes) {
      throw const ApiFailure(413, '文件超过读取上限 / File exceeds the read limit');
    }
    buffer.add(chunk);
  }
  return buffer.takeBytes();
}

// Utf8Decoder consumes the transport BOM. HTML source is an editable document,
// so restore that original codepoint instead of silently normalizing the file.
String _decodeExactHtml(List<int> bytes) {
  final decoded = utf8.decode(bytes, allowMalformed: false);
  return bytes.length >= 3 &&
          bytes[0] == 0xef &&
          bytes[1] == 0xbb &&
          bytes[2] == 0xbf
      ? '\ufeff$decoded'
      : decoded;
}
