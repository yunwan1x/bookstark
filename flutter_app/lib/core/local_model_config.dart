import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// One explicitly configured, device-owned compatible model endpoint.
final class LocalModelConfig {
  LocalModelConfig({
    required String endpoint,
    required String model,
    this.apiKey = '',
    this.allowKnowledge = false,
  }) : endpoint = _endpoint(endpoint),
       model = model.trim() {
    if (this.model.isEmpty ||
        utf8.encode(this.model).length > 256 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(this.model)) {
      throw const FormatException('Invalid model identifier');
    }
    if (utf8.encode(apiKey).length > 8192 ||
        RegExp(r'[^\x21-\x7e]').hasMatch(apiKey)) {
      throw const FormatException('Invalid model credential');
    }
  }
  final Uri endpoint;
  final String model, apiKey;
  final bool allowKnowledge;
  static Uri _endpoint(String value) {
    final text = value.trim();
    if (text.isEmpty ||
        utf8.encode(text).length > 2048 ||
        RegExp(r'[\x00-\x20\x7f]').hasMatch(text)) {
      throw const FormatException('Invalid model endpoint');
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.port < 1 ||
        uri.port > 65535) {
      throw const FormatException('Invalid model endpoint');
    }
    return uri;
  }

  Uri get chatUri => Uri.parse(
    '${endpoint.toString().replaceFirst(RegExp(r'/+$'), '')}/chat/completions',
  );
  Map<String, Object> toRecord() => {
    'endpoint': endpoint.toString(),
    'model': model,
    'apiKey': apiKey,
    'allowKnowledge': allowKnowledge,
  };
  factory LocalModelConfig.fromRecord(Object? raw) {
    if (raw is! Map ||
        raw['endpoint'] is! String ||
        raw['model'] is! String ||
        raw['apiKey'] is! String ||
        raw['allowKnowledge'] is! bool) {
      throw const FormatException('Invalid model configuration');
    }
    return LocalModelConfig(
      endpoint: raw['endpoint'] as String,
      model: raw['model'] as String,
      apiKey: raw['apiKey'] as String,
      allowKnowledge: raw['allowKnowledge'] as bool,
    );
  }
  bool same(LocalModelConfig? other) =>
      other != null &&
      endpoint == other.endpoint &&
      model == other.model &&
      apiKey == other.apiKey &&
      allowKnowledge == other.allowKnowledge;
}

final class LocalModelConfigCorrupt extends FormatException {
  const LocalModelConfigCorrupt() : super('Invalid stored model configuration');
}

final class LocalModelSaveUnknown implements Exception {
  const LocalModelSaveUnknown();
}

final class LocalModelScopeRetired implements Exception {
  const LocalModelScopeRetired();
}

/// Own small encrypted metadata record; never joins local content exports.
final class LocalModelConfigVault {
  LocalModelConfigVault({
    required String namespace,
    required this.readValue,
    required this.writeValue,
    this.isCurrent,
  }) : key = jsonEncode(['bookstark.model-v1', namespace]);
  final String key;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final bool Function()? isCurrent;
  static final Map<String, Future<void>> _pending = {};
  void _current() {
    if (isCurrent?.call() == false) throw const LocalModelScopeRetired();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = Completer<T>();
    final next = (_pending[key] ?? Future<void>.value()).then((_) async {
      try {
        _current();
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    _pending[key] = next;
    unawaited(
      next.then((_) {
        if (identical(_pending[key], next)) _pending.remove(key);
      }),
    );
    return result.future;
  }

  Future<LocalModelConfig?> _read() async {
    _current();
    final text = await readValue(key);
    _current();
    if (text == null) return null;
    try {
      if (utf8.encode(text).length > 32768) {
        throw const FormatException('Oversized model configuration');
      }
      final raw = jsonDecode(text);
      if (raw is! Map || raw['format'] != 1 || !raw.containsKey('config')) {
        throw const FormatException('Invalid model configuration format');
      }
      return raw['config'] == null
          ? null
          : LocalModelConfig.fromRecord(raw['config']);
    } on FormatException {
      throw const LocalModelConfigCorrupt();
    }
  }

  Future<LocalModelConfig?> read() => _serial(_read);
  Future<void> _write(LocalModelConfig? config) async {
    _current();
    try {
      await writeValue(
        key,
        jsonEncode({'format': 1, 'config': config?.toRecord()}),
      );
      _current();
      final actual = await _read();
      if (!(config == null ? actual == null : config.same(actual))) {
        throw const LocalModelSaveUnknown();
      }
    } on LocalModelScopeRetired {
      rethrow;
    } catch (_) {
      throw const LocalModelSaveUnknown();
    }
  }

  Future<void> save(LocalModelConfig config) => _serial(() async {
    // A corrupt old record cannot be silently overwritten by an ordinary save.
    await _read();
    await _write(config);
  });
  Future<void> reset() => _serial(() => _write(null));
}

enum LocalModelProbeIssue {
  authentication,
  busy,
  redirect,
  protocol,
  network,
  timeout,
}

final class LocalModelProbeFailure implements Exception {
  const LocalModelProbeFailure(this.issue);
  final LocalModelProbeIssue issue;
}

/// Same small compatible probe as Go testOpenAIConnection. A separate client
/// owns cancellation; no account cookies, CSRF, redirects or response snippets.
final class LocalModelProbe {
  LocalModelProbe({
    http.Client Function()? createClient,
    this.deadline = const Duration(seconds: 20),
  }) : createClient = createClient ?? http.Client.new;
  final http.Client Function() createClient;
  final Duration deadline;
  Future<void> test(
    LocalModelConfig config, {
    Future<void>? abortTrigger,
  }) async {
    final client = createClient(), abort = Completer<void>();
    void stop() {
      if (abort.isCompleted) return;
      abort.complete();
      client.close();
    }

    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then(
          (_) => stop(),
          onError: (Object _, StackTrace _) => stop(),
        ),
      );
    }
    try {
      await _test(client, config, abort.future).timeout(
        deadline,
        onTimeout: () {
          stop();
          throw const LocalModelProbeFailure(LocalModelProbeIssue.timeout);
        },
      );
    } on LocalModelProbeFailure {
      rethrow;
    } catch (_) {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.network);
    } finally {
      stop();
    }
  }

  Future<void> _test(
    http.Client client,
    LocalModelConfig config,
    Future<void> abort,
  ) async {
    final request =
        http.AbortableRequest('POST', config.chatUri, abortTrigger: abort)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers.addAll({
            'Content-Type': 'application/json; charset=utf-8',
            'Accept': 'application/json',
            if (config.apiKey.isNotEmpty)
              'Authorization': 'Bearer ${config.apiKey}',
          })
          ..bodyBytes = utf8.encode(
            jsonEncode({
              'model': config.model,
              'messages': [
                {'role': 'user', 'content': 'ping'},
              ],
              'max_tokens': 16,
              'stream': false,
            }),
          );
    final response = await client.send(request);
    if ([401, 403].contains(response.statusCode)) {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.authentication);
    }
    if (response.statusCode == 429) {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.busy);
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.redirect);
    }
    if (response.statusCode != 200) {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.network);
    }
    final type = response.headers['content-type']
        ?.split(';')
        .first
        .trim()
        .toLowerCase();
    if (type != 'application/json') {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.protocol);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 65536) {
        throw const LocalModelProbeFailure(LocalModelProbeIssue.protocol);
      }
      bytes.add(chunk);
    }
    try {
      final raw = jsonDecode(utf8.decode(bytes.takeBytes()));
      final choices = raw is Map ? raw['choices'] : null;
      if (choices is! List || choices.isEmpty || choices.first is! Map) {
        throw const FormatException('Invalid compatible response');
      }
      final message = (choices.first as Map)['message'];
      if (message is! Map ||
          message['content'] is! String ||
          (message['content'] as String).trim().isEmpty) {
        throw const FormatException('Invalid compatible message');
      }
    } on FormatException {
      throw const LocalModelProbeFailure(LocalModelProbeIssue.protocol);
    }
  }
}
