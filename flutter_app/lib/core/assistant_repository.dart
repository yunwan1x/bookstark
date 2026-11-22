import 'dart:convert';
import 'api_client.dart';
import 'secure_record_store.dart';

String _assistantId(Object? value) {
  if (value is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) {
    throw const FormatException('Invalid assistant identity');
  }
  return value;
}

class AssistantMessage {
  const AssistantMessage({
    required this.role,
    required this.content,
    this.sources = const [],
    this.createdAt = 0,
  });
  factory AssistantMessage.fromJson(Map data) {
    final role = data['role'];
    final content = data['content'];
    if (!['user', 'assistant'].contains(role) || content is! String) {
      throw const FormatException('Invalid assistant message');
    }
    return AssistantMessage(
      role: role as String,
      content: content,
      createdAt: data['created_at'] as int? ?? 0,
      sources: [
        for (final row in data['sources'] as List? ?? [])
          Map<String, Object?>.from(row as Map),
      ],
    );
  }
  final String role, content;
  final int createdAt;
  final List<Map<String, Object?>> sources;
  Map<String, Object?> toJson({bool contextOnly = false}) => {
    'role': role,
    'content': content,
    if (!contextOnly) 'sources': sources,
    if (!contextOnly) 'created_at': createdAt,
  };
}

class AssistantDraft {
  AssistantDraft.fromJson(Map data)
    : id = _assistantId(data['id']),
      payload = Map<String, Object?>.from(data['payload'] as Map),
      status = data['status'] as String,
      url = data['url'] as String? ?? '';
  final String id, status, url;
  final Map<String, Object?> payload;
}

class AssistantSession {
  AssistantSession.fromJson(Map data)
    : id = _assistantId(data['id']),
      busy = data['busy'] == true,
      drafts = [
        for (final row in data['drafts'] as List? ?? [])
          AssistantDraft.fromJson(row as Map),
      ];
  final String id;
  final bool busy;
  final List<AssistantDraft> drafts;
}

class AssistantUpdate {
  const AssistantUpdate(
    this.type, {
    this.text = '',
    this.round = 0,
    this.messages = const [],
    this.drafts = const [],
  });
  final String type, text;
  final int round;
  final List<AssistantMessage> messages;
  final List<AssistantDraft> drafts;
}

class AssistantResourceDetail {
  const AssistantResourceDetail(
    this.title,
    this.content, {
    this.metadata = const {},
  });
  final String title, content;
  final Map<String, Object?> metadata;
}

/// Keeps whole recent turns within the server's context and encrypted-record limits.
List<AssistantMessage> boundedAssistantHistory(
  List<AssistantMessage> messages,
) {
  final result = <AssistantMessage>[];
  for (var i = messages.length - 2; i >= 0; i -= 2) {
    final pair = messages.sublist(i, i + 2);
    if (pair[0].role != 'user' || pair[1].role != 'assistant') {
      throw const FormatException('Invalid conversation order');
    }
    if (pair.any(
      (item) =>
          item.content.trim().isEmpty ||
          utf8.encode(item.content).length > 24000,
    )) {
      continue;
    }
    final next = [...pair, ...result];
    if (next.length > 38 ||
        utf8
                .encode(jsonEncode(next.map((item) => item.toJson()).toList()))
                .length >
            140 * 1024) {
      break;
    }
    result.insertAll(0, pair);
  }
  return result;
}

Map<String, Object?>? assistantCreatedResource(AssistantDraft draft) {
  if (draft.status != 'done') {
    return null;
  }
  final uri = Uri.tryParse(draft.url);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      uri.path != '/notes') {
    return null;
  }
  final kind = draft.payload['kind'];
  final tab = kind == 'note'
      ? 'notes'
      : kind == 'task'
      ? 'tasks'
      : null;
  if (tab == null || uri.queryParameters['tab'] != tab) {
    return null;
  }
  final id = int.tryParse(
    uri.queryParameters[kind == 'note' ? 'id' : 'task_id'] ?? '',
  );
  if (id == null || id <= 0) {
    return null;
  }
  return {
    'kind': kind,
    'id': id,
    'title': kind == 'note' ? draft.payload['title'] : draft.payload['content'],
  };
}

/// UI contract shared by the authenticated server and device-owned models.
abstract interface class AssistantDataSource {
  Future<AssistantResourceDetail> readSource(Map<String, Object?> source);
  Future<AssistantSession> open();
  Future<AssistantSession> reset(String id);
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  });
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  });
}

class AssistantRepository implements AssistantDataSource {
  AssistantRepository(this.client);
  final BookstarkClient client;
  @override
  Future<AssistantResourceDetail> readSource(
    Map<String, Object?> source,
  ) async {
    final kind = source['kind'], id = source['id'];
    if (id is! int || id <= 0) {
      throw const FormatException('Invalid source identity');
    }
    final routes = {
      'note': '/api/blogs/$id',
      'article': '/api/blogs/$id',
      'task': '/api/tasks/$id',
      'bookmark': '/api/bookmarks/$id/',
      'book': '/api/books/$id',
      'document': '/api/docs/$id',
      'topic': '/api/topics/$id',
    };
    final path = routes[kind];
    if (path == null) {
      throw const FormatException('Unsupported source kind');
    }
    final row = await client.get(path);
    if (row['has_password'] == true) {
      throw const ApiFailure(
        403,
        '资料已受密码保护 / Resource is now password protected',
      );
    }
    if (['note', 'article'].contains(kind)) {
      return AssistantResourceDetail(
        row['blog_title'] as String,
        row['blog_content'] as String,
      );
    }
    if (kind == 'document') {
      return AssistantResourceDetail(
        row['document_name'] as String,
        row['markdown'] as String? ?? '',
      );
    }
    if (kind == 'book') {
      return AssistantResourceDetail(
        row['book_name'] as String,
        row['description'] as String? ?? '',
      );
    }
    if (kind == 'task') {
      return AssistantResourceDetail(
        row['content'] as String,
        row['content'] as String,
        metadata: {'due_date': row['due_date'], 'done': row['done']},
      );
    }
    if (kind == 'topic') {
      return AssistantResourceDetail(
        row['title'] as String,
        row['question'] as String? ?? '',
      );
    }
    return AssistantResourceDetail(
      row['title'] as String,
      row['description'] as String? ?? '',
      metadata: {'url': row['url']},
    );
  }

  @override
  Future<AssistantSession> open() async => AssistantSession.fromJson(
    (await client.get('/api/ai/assistant'))['session'] as Map,
  );
  @override
  Future<AssistantSession> reset(String id) async {
    _assistantId(id);
    return AssistantSession.fromJson(
      (await client.post('/api/ai/assistant/reset', {
            'session_id': id,
          }))['session']
          as Map,
    );
  }

  @override
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  }) async {
    _assistantId(session);
    _assistantId(id);
    final result = await client.post('/api/ai/assistant/drafts/$id', {
      'session_id': session,
      'action': confirm ? 'confirm' : 'cancel',
    });
    final draft = AssistantDraft.fromJson(result['draft'] as Map);
    if (draft.id != id) {
      throw const FormatException('Mismatched assistant draft');
    }
    return draft;
  }

  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    _assistantId(session);
    final question = message.trim();
    if (question.isEmpty ||
        utf8.encode(question).length > 8000 ||
        history.length > 38 ||
        history.length.isOdd) {
      throw const FormatException(
        'Invalid assistant context or question length',
      );
    }
    for (var i = 0; i < history.length; i++) {
      final item = history[i];
      if (item.role != (i.isEven ? 'user' : 'assistant') ||
          item.content.trim().isEmpty ||
          utf8.encode(item.content).length > 24000) {
        throw const FormatException('Invalid assistant conversation order');
      }
    }
    final body = <String, Object?>{
      'session_id': session,
      'message': question,
      'history': [for (final item in history) item.toJson(contextOnly: true)],
    };
    if (utf8.encode(jsonEncode(body)).length > 192 * 1024) {
      throw const FormatException('Assistant context exceeds limit');
    }
    var done = false;
    await for (final event in client.postEvents(
      '/api/ai/assistant/chat',
      body,
      abortTrigger: abortTrigger,
    )) {
      if (![
        'delta',
        'round',
        'progress',
        'done',
        'error',
      ].contains(event.type)) {
        continue;
      }
      final data = jsonDecode(event.data) as Map<String, dynamic>;
      if (event.type == 'error') {
        throw ApiFailure(
          data['code'] as int? ?? 502,
          data['message'] as String? ?? 'AI request failed',
        );
      }
      if (event.type == 'delta') {
        if (data['text'] is! String) {
          throw const FormatException('Invalid assistant delta');
        }
        yield AssistantUpdate('delta', text: data['text'] as String);
      } else if (event.type == 'round') {
        final round = data['round'];
        if (round is! int || round < 1 || round > 7) {
          throw const FormatException('Invalid assistant round');
        }
        yield AssistantUpdate('round', round: round);
      } else if (event.type == 'progress') {
        final tool = data['tool'];
        yield AssistantUpdate(
          'progress',
          text:
              [
                'search',
                'read',
                'draft_note',
                'draft_task',
                'validation',
              ].contains(tool)
              ? tool as String
              : 'validation',
        );
      } else if (event.type == 'done') {
        if (data['session_id'] != session || data['code'] != 0) {
          throw const FormatException('Mismatched assistant session');
        }
        final messages = [
          for (final row in data['messages'] as List)
            AssistantMessage.fromJson(row as Map),
        ];
        if (messages.length != 2 ||
            messages[0].role != 'user' ||
            messages[1].role != 'assistant' ||
            messages[0].content != question ||
            messages[1].content.trim().isEmpty) {
          throw const FormatException('Invalid completed assistant turn');
        }
        final drafts = [
          for (final row in data['drafts'] as List? ?? [])
            AssistantDraft.fromJson(row as Map),
        ];
        done = true;
        yield AssistantUpdate('done', messages: messages, drafts: drafts);
        break;
      }
    }
    if (!done) {
      throw const ApiFailure(502, '回答连接已中断 / Response ended before completion');
    }
  }
}

class AssistantConversation {
  const AssistantConversation(
    this.session,
    this.messages, {
    this.input = '',
    this.pendingQuestion,
    this.partial = '',
  });
  final String session;
  final List<AssistantMessage> messages;
  final String input;
  final String? pendingQuestion;
  final String partial;
}

void _validatePartial(Object? question, Object? partial) {
  if ((question != null &&
          (question is! String ||
              question.trim().isEmpty ||
              utf8.encode(question).length > 8000)) ||
      partial is! String ||
      utf8.encode(partial).length > 24000 ||
      (question == null && partial.isNotEmpty)) {
    throw const FormatException('Invalid interrupted assistant reply');
  }
}

class AssistantConversationVault extends SecureRecordStore {
  AssistantConversationVault({
    required super.namespace,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
  }) : super(prefix: 'bookstark.assistant.v1');
  Future<AssistantConversation?> load() async {
    final value = await readRecord('current');
    if (value == null) {
      return null;
    }
    if (utf8.encode(value).length > 192 * 1024) {
      throw const FormatException('Stored assistant context exceeds limit');
    }
    final data = jsonDecode(value) as Map;
    if (data['version'] != 1 && data['version'] != 2) {
      throw const FormatException('Invalid assistant context version');
    }
    final session = _assistantId(data['session']);
    final messages = [
      for (final row in data['messages'] as List)
        AssistantMessage.fromJson(row as Map),
    ];
    if (messages.length.isOdd || messages.length > 38) {
      throw const FormatException('Invalid stored assistant context');
    }
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].role != (i.isEven ? 'user' : 'assistant')) {
        throw const FormatException('Invalid stored assistant order');
      }
    }
    _validatePartial(data['pending_question'], data['partial'] ?? '');
    return AssistantConversation(
      session,
      messages,
      input: data['input'] as String? ?? '',
      pendingQuestion: data['pending_question'] as String?,
      partial: data['partial'] as String? ?? '',
    );
  }

  Future<void> save(
    String session,
    List<AssistantMessage> messages, {
    String input = '',
    String? pendingQuestion,
    String partial = '',
  }) {
    _assistantId(session);
    _validatePartial(pendingQuestion, partial);
    if (messages.length > 38 || messages.length.isOdd) {
      throw const FormatException('Invalid assistant conversation length');
    }
    final value = jsonEncode({
      'version': 2,
      'pending_question': pendingQuestion,
      'partial': partial,
      'input': input,
      'session': session,
      'messages': [for (final item in messages) item.toJson()],
    });
    if (utf8.encode(value).length > 192 * 1024) {
      throw const FormatException('Stored assistant context exceeds limit');
    }
    return writeRecord('current', value);
  }

  Future<void> clear() => removeRecord('current');
}
