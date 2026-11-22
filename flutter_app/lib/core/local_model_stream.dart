import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'local_model_config.dart';
import 'server_events.dart';

enum LocalModelStreamIssue {
  authentication,
  busy,
  redirect,
  protocol,
  truncated,
  outputLimit,
  filtered,
  network,
  timeout,
  cancelled,
  retired,
}

final class LocalModelStreamFailure implements Exception {
  const LocalModelStreamFailure(this.issue);
  final LocalModelStreamIssue issue;
}

final class LocalModelToolDefinition {
  LocalModelToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
  }) {
    if (!_functionName(name) ||
        utf8.encode(description).length > 2048 ||
        parameters['type'] != 'object' ||
        utf8.encode(jsonEncode(parameters)).length > 16384) {
      throw const FormatException('Invalid local model tool definition');
    }
  }
  final String name, description;
  final Map<String, Object?> parameters;
  Map<String, Object?> toJson() => {
    'type': 'function',
    'function': {
      'name': name,
      'description': description,
      'parameters': parameters,
    },
  };
}

bool _functionName(String name) =>
    RegExp(r'^[A-Za-z_][A-Za-z0-9_-]{0,63}$').hasMatch(name);
bool _callId(String id) => RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(id);

final class LocalModelToolCall {
  const LocalModelToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });
  final String id, name, arguments;
  Map<String, Object?> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': arguments},
  };
}

final class LocalModelTurn {
  const LocalModelTurn({required this.text, required this.toolCalls});
  final String text;
  final List<LocalModelToolCall> toolCalls;
}

final class LocalModelStreamUpdate {
  const LocalModelStreamUpdate.delta(this.text) : turn = null;
  const LocalModelStreamUpdate.complete(this.turn) : text = '';
  final String text;
  final LocalModelTurn? turn;
}

final class _PendingCall {
  String id = '', name = '';
  final arguments = StringBuffer();
  int bytes = 0;
}

/// Owns every model connection. Retiring the owner closes active HTTP bodies;
/// account clients/cookies and arbitrary redirects never enter this transport.
final class LocalModelStreamTransport {
  LocalModelStreamTransport(
    this.config, {
    http.Client Function()? createClient,
    this.isCurrent,
    this.connectDeadline = const Duration(seconds: 20),
    this.idleDeadline = const Duration(seconds: 45),
    this.turnDeadline = const Duration(minutes: 3),
  }) : createClient = createClient ?? http.Client.new;
  final LocalModelConfig config;
  final http.Client Function() createClient;
  final bool Function()? isCurrent;
  final Duration connectDeadline, idleDeadline, turnDeadline;
  final _stops = <void Function()>{};
  bool _closed = false;
  bool get _current => !_closed && isCurrent?.call() != false;
  void close() {
    if (_closed) return;
    _closed = true;
    for (final stop in _stops.toList()) {
      stop();
    }
  }

  List<Map<String, Object?>> _messages(List<Map<String, Object?>> messages) {
    if (messages.isEmpty || messages.length > 64) {
      throw const FormatException('Invalid model message count');
    }
    final result = <Map<String, Object?>>[];
    for (final message in messages) {
      if (message.keys.any(
        (key) =>
            !{'role', 'content', 'tool_call_id', 'tool_calls'}.contains(key),
      )) {
        throw const FormatException('Unexpected model message fields');
      }
      final role = message['role'], content = message['content'];
      if (!{'system', 'user', 'assistant', 'tool'}.contains(role) ||
          (content != null && content is! String)) {
        throw const FormatException('Invalid model message');
      }
      final calls = message['tool_calls'];
      if (content == null &&
          !(role == 'assistant' && calls is List && calls.isNotEmpty)) {
        throw const FormatException('Missing model message content');
      }
      if (content is String) {
        final bytes = utf8.encode(content);
        final limit = role == 'user'
            ? 8000
            : role == 'assistant'
            ? 24000
            : 32768;
        if (bytes.length > limit || utf8.decode(bytes) != content) {
          throw const FormatException('Model message exceeds its bound');
        }
      }
      if (role == 'tool' &&
          (message['tool_call_id'] is! String ||
              !_callId(message['tool_call_id'] as String))) {
        throw const FormatException('Invalid tool result binding');
      }
      if (role != 'tool' && message.containsKey('tool_call_id')) {
        throw const FormatException('Unexpected tool result binding');
      }
      if (calls != null) {
        if (role != 'assistant' ||
            calls is! List ||
            calls.isEmpty ||
            calls.length > 8) {
          throw const FormatException('Invalid assistant tool history');
        }
        final ids = <String>{};
        for (final call in calls) {
          if (call is! Map ||
              call['id'] is! String ||
              !_callId(call['id'] as String) ||
              !ids.add(call['id'] as String) ||
              call['type'] != 'function') {
            throw const FormatException('Invalid historical model tool');
          }
          final function = call['function'];
          if (function is! Map ||
              function['name'] is! String ||
              !_functionName(function['name'] as String) ||
              function['arguments'] is! String ||
              utf8.encode(function['arguments'] as String).length > 32768 ||
              jsonDecode(function['arguments'] as String) is! Map) {
            throw const FormatException('Invalid historical tool arguments');
          }
        }
      }
      result.add(Map<String, Object?>.from(message));
    }
    return result;
  }

  Stream<LocalModelStreamUpdate> chat({
    required List<Map<String, Object?>> messages,
    List<LocalModelToolDefinition> tools = const [],
    Future<void>? abortTrigger,
  }) async* {
    if (!_current) {
      throw const LocalModelStreamFailure(LocalModelStreamIssue.retired);
    }
    if (abortTrigger != null) {
      var alreadyAborted = false;
      unawaited(
        abortTrigger.then(
          (_) {
            alreadyAborted = true;
          },
          onError: (Object _, StackTrace _) {
            alreadyAborted = true;
          },
        ),
      );
      await Future<void>.value();
      if (alreadyAborted) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.cancelled);
      }
      if (!_current) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.retired);
      }
    }
    final names = tools.map((tool) => tool.name).toSet();
    if (tools.length > 8 || names.length != tools.length) {
      throw const FormatException('Invalid model tool count');
    }
    final payload = utf8.encode(
      jsonEncode({
        'model': config.model,
        'messages': _messages(messages),
        'max_tokens': 2048,
        'stream': true,
        if (tools.isNotEmpty)
          'tools': tools.map((tool) => tool.toJson()).toList(),
      }),
    );
    if (payload.length > 192 * 1024) {
      throw const FormatException('Model request exceeds context limit');
    }
    final client = createClient(), abort = Completer<void>();
    var stopped = false, deadlineReached = false;
    void stop() {
      if (stopped) return;
      stopped = true;
      if (!abort.isCompleted) abort.complete();
      client.close();
    }

    _stops.add(stop);
    final timer = Timer(turnDeadline, () {
      deadlineReached = true;
      stop();
    });
    if (abortTrigger != null) {
      unawaited(
        abortTrigger.then(
          (_) => stop(),
          onError: (Object _, StackTrace _) => stop(),
        ),
      );
    }
    try {
      final request =
          http.AbortableRequest(
              'POST',
              config.chatUri,
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers.addAll({
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'text/event-stream',
              if (config.apiKey.isNotEmpty)
                'Authorization': 'Bearer ${config.apiKey}',
            })
            ..bodyBytes = payload;
      final response = await client
          .send(request)
          .timeout(
            connectDeadline,
            onTimeout: () {
              stop();
              throw const LocalModelStreamFailure(
                LocalModelStreamIssue.timeout,
              );
            },
          );
      if (!_current) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.retired);
      }
      if ([401, 403].contains(response.statusCode)) {
        throw const LocalModelStreamFailure(
          LocalModelStreamIssue.authentication,
        );
      }
      if (response.statusCode == 429) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.busy);
      }
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.redirect);
      }
      final mime = response.headers['content-type']
          ?.split(';')
          .first
          .trim()
          .toLowerCase();
      if (response.statusCode != 200) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.network);
      }
      if (mime != 'text/event-stream') {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
      }
      final text = StringBuffer(), calls = <int, _PendingCall>{};
      var textBytes = 0, argumentBytes = 0;
      String? finish;
      await for (final event in decodeServerEvents(
        response.stream.timeout(idleDeadline),
        maxEventBytes: 256 * 1024,
        maxTotalBytes: 2 * 1024 * 1024,
      )) {
        if (!_current) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.retired);
        }
        if (stopped) {
          throw LocalModelStreamFailure(
            deadlineReached
                ? LocalModelStreamIssue.timeout
                : LocalModelStreamIssue.cancelled,
          );
        }
        if (event.type == 'ping' || event.data.trim().isEmpty) continue;
        if (event.type == 'error') {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.network);
        }
        if (event.data.trim() == '[DONE]') {
          if (finish == 'length') {
            throw const LocalModelStreamFailure(
              LocalModelStreamIssue.outputLimit,
            );
          }
          if (finish == 'content_filter') {
            throw const LocalModelStreamFailure(LocalModelStreamIssue.filtered);
          }
          if (finish == null || !{'stop', 'tool_calls'}.contains(finish)) {
            throw const LocalModelStreamFailure(
              LocalModelStreamIssue.truncated,
            );
          }
          final completed = <LocalModelToolCall>[], ids = <String>{};
          for (var i = 0; i < calls.length; i++) {
            final call = calls[i];
            if (call == null ||
                !_callId(call.id) ||
                !ids.add(call.id) ||
                !names.contains(call.name) ||
                jsonDecode(call.arguments.toString()) is! Map) {
              throw const LocalModelStreamFailure(
                LocalModelStreamIssue.protocol,
              );
            }
            completed.add(
              LocalModelToolCall(
                id: call.id,
                name: call.name,
                arguments: call.arguments.toString(),
              ),
            );
          }
          if (finish == 'tool_calls'
              ? completed.isEmpty
              : completed.isNotEmpty || text.toString().trim().isEmpty) {
            throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
          }
          yield LocalModelStreamUpdate.complete(
            LocalModelTurn(
              text: text.toString(),
              toolCalls: List.unmodifiable(completed),
            ),
          );
          return;
        }
        final raw = jsonDecode(event.data);
        if (raw is! Map || raw['error'] != null) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
        }
        final choices = raw['choices'];
        if (choices is List && choices.isEmpty && raw['usage'] is Map) continue;
        if (choices is! List || choices.length != 1 || choices.single is! Map) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
        }
        final choice = choices.single as Map;
        if (choice['index'] != null && choice['index'] != 0) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
        }
        final delta = choice['delta'];
        if (delta is! Map ||
            delta.containsKey('function_call') ||
            (delta['role'] != null && delta['role'] != 'assistant')) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
        }
        final fragment = delta['content'], incoming = delta['tool_calls'];
        if (finish != null &&
            ((fragment is String && fragment.isNotEmpty) ||
                (incoming is List && incoming.isNotEmpty))) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
        }
        if (fragment != null && fragment is! String) {
          throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
        }
        if (fragment is String && fragment.isNotEmpty) {
          final bytes = utf8.encode(fragment);
          if (utf8.decode(bytes) != fragment ||
              textBytes + bytes.length > 24000) {
            throw const LocalModelStreamFailure(
              LocalModelStreamIssue.outputLimit,
            );
          }
          textBytes += bytes.length;
          text.write(fragment);
          yield LocalModelStreamUpdate.delta(fragment);
        }
        if (incoming != null) {
          if (incoming is! List) {
            throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
          }
          for (final item in incoming) {
            if (item is! Map ||
                item['index'] is! int ||
                (item['index'] as int) < 0 ||
                (item['index'] as int) >= 8 ||
                (item['type'] != null && item['type'] != 'function')) {
              throw const LocalModelStreamFailure(
                LocalModelStreamIssue.protocol,
              );
            }
            final call = calls.putIfAbsent(
              item['index'] as int,
              () => _PendingCall(),
            );
            final id = item['id'];
            if (id != null) {
              if (id is! String) {
                throw const LocalModelStreamFailure(
                  LocalModelStreamIssue.protocol,
                );
              }
              if (call.id != id) call.id += id;
              if (utf8.encode(call.id).length > 128) {
                throw const LocalModelStreamFailure(
                  LocalModelStreamIssue.protocol,
                );
              }
            }
            final function = item['function'];
            if (function != null) {
              if (function is! Map) {
                throw const LocalModelStreamFailure(
                  LocalModelStreamIssue.protocol,
                );
              }
              final name = function['name'], args = function['arguments'];
              if (name != null) {
                if (name is! String) {
                  throw const LocalModelStreamFailure(
                    LocalModelStreamIssue.protocol,
                  );
                }
                if (call.name != name) call.name += name;
                if (utf8.encode(call.name).length > 64) {
                  throw const LocalModelStreamFailure(
                    LocalModelStreamIssue.protocol,
                  );
                }
              }
              if (args != null) {
                if (args is! String) {
                  throw const LocalModelStreamFailure(
                    LocalModelStreamIssue.protocol,
                  );
                }
                final count = utf8.encode(args).length;
                call.bytes += count;
                argumentBytes += count;
                if (call.bytes > 32768 || argumentBytes > 65536) {
                  throw const LocalModelStreamFailure(
                    LocalModelStreamIssue.outputLimit,
                  );
                }
                call.arguments.write(args);
              }
            }
          }
        }
        final reason = choice['finish_reason'];
        if (reason != null) {
          if (reason is! String || (finish != null && finish != reason)) {
            throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
          }
          finish = reason;
        }
      }
      if (!_current) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.retired);
      }
      if (deadlineReached) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.timeout);
      }
      if (stopped) {
        throw const LocalModelStreamFailure(LocalModelStreamIssue.cancelled);
      }
      throw LocalModelStreamFailure(
        finish == 'length'
            ? LocalModelStreamIssue.outputLimit
            : LocalModelStreamIssue.truncated,
      );
    } on LocalModelStreamFailure {
      rethrow;
    } on TimeoutException {
      throw const LocalModelStreamFailure(LocalModelStreamIssue.timeout);
    } on FormatException {
      throw const LocalModelStreamFailure(LocalModelStreamIssue.protocol);
    } catch (_) {
      throw LocalModelStreamFailure(
        !_current
            ? LocalModelStreamIssue.retired
            : deadlineReached
            ? LocalModelStreamIssue.timeout
            : stopped
            ? LocalModelStreamIssue.cancelled
            : LocalModelStreamIssue.network,
      );
    } finally {
      timer.cancel();
      _stops.remove(stop);
      stop();
    }
  }
}
