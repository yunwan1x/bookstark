import 'dart:convert';
import 'api_client.dart';

enum CompletionScene { topicSummary, topicComment }

abstract interface class CompletionRepository {
  Stream<String> complete({
    required String context,
    required String instruction,
    required CompletionScene scene,
    Future<void>? abortTrigger,
  });
}

/// Existing /api/ai/complete protocol, separate from tool-capable assistant chat.
/// This only produces reviewable text; it never saves any user resource.
class RemoteCompletionRepository implements CompletionRepository {
  RemoteCompletionRepository(this.client);
  final BookstarkClient client;
  @override
  Stream<String> complete({
    required String context,
    required String instruction,
    required CompletionScene scene,
    Future<void>? abortTrigger,
  }) async* {
    if (context.runes.length > 20000 ||
        instruction.trim().isEmpty ||
        instruction.runes.length > 2000) {
      throw const FormatException(
        '上下文最多20000字，指令1—2000字 / Context up to 20000 characters; instruction 1–2000',
      );
    }
    final body = <String, Object?>{
      'scene': scene == CompletionScene.topicSummary
          ? 'topic-summary'
          : 'topic-comment',
      'messages': [
        {
          'role': 'system',
          'content':
              '你是Bookstark知识整理助手。根据用户提供的上下文和指令生成可审核的Markdown正文。只返回正文，不执行保存、不声称已写入任何资源。',
        },
        {
          'role': 'user',
          'content':
              '${context.trim().isEmpty ? '' : '【上下文】\n${context.trim()}\n\n'}【指令】\n${instruction.trim()}\n\n请只返回Markdown正文，不要解释。',
        },
      ],
    };
    if (utf8.encode(jsonEncode(body)).length > 192 * 1024) {
      throw const FormatException('AI request exceeds limit');
    }
    final answer = StringBuffer();
    var characters = 0, truncated = false;
    await for (final event in client.postEvents(
      '/api/ai/complete',
      body,
      abortTrigger: abortTrigger,
    )) {
      if (event.data == '[DONE]') {
        if (answer.toString().trim().isEmpty) {
          throw const FormatException('AI返回空正文 / AI returned no content');
        }
        if (truncated) {
          throw const FormatException(
            'AI回复达到长度上限，正文尚不完整 / AI response reached its token limit; content is incomplete',
          );
        }
        return;
      }
      final value = jsonDecode(event.data);
      if (value is! Map) {
        throw const FormatException('Invalid completion frame');
      }
      if (value['error'] != null) {
        final error = value['error'];
        throw ApiFailure(
          502,
          error is Map
              ? error['message'] as String? ?? 'AI completion failed'
              : 'AI completion failed',
        );
      }
      final choices = value['choices'];
      if (choices is! List) {
        if (value['usage'] is Map) continue;
        throw const FormatException('Invalid completion choices');
      }
      if (choices.isEmpty) continue; // OpenAI usage-only trailer.
      final choice = choices.first;
      if (choice is! Map) {
        throw const FormatException('Invalid completion choice');
      }
      if (choice['finish_reason'] == 'length') truncated = true;
      final delta = choice['delta'];
      if (delta == null) continue;
      if (delta is! Map ||
          (delta['content'] != null && delta['content'] is! String)) {
        throw const FormatException('Invalid completion delta');
      }
      final text = delta['content'] as String? ?? '';
      if (text.isEmpty) continue;
      characters += text.runes.length;
      if (characters > 20000) {
        throw const FormatException(
          'AI正文超过20000字，请缩小范围 / AI content exceeds 20000 characters; narrow the request',
        );
      }
      answer.write(text);
      yield text;
    }
    throw const FormatException(
      'AI回复中断，未收到完成标记 / AI stream ended without completion',
    );
  }
}
