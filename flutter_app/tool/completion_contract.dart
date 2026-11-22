import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/completion_repository.dart';

Future<void> runCompletionContract(BookstarkClient client, Uri provider) async {
  final repository = RemoteCompletionRepository(client);
  final chunks = await repository
      .complete(
        context: '主题资料上下文',
        instruction: 'COMPLETE_FIXTURE',
        scene: CompletionScene.topicSummary,
      )
      .toList();
  if (chunks.join() != '## 主题小结\n\n真实接口生成的可审核草稿。' || chunks.length < 2) {
    throw StateError('Generic completion did not stream actual Go content');
  }
  final stopped = await repository
      .complete(
        context: '',
        instruction: 'COMPLETE_STOP_FIXTURE',
        scene: CompletionScene.topicComment,
      )
      .take(1)
      .toList();
  if (stopped.single != '小结流式片段 ') {
    throw StateError('Generic completion first chunk');
  }
  final monitor = provider.resolve('/active-completions');
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  var released = false;
  do {
    final response = await http
        .get(monitor)
        .timeout(const Duration(seconds: 1));
    if (response.statusCode != 200) {
      throw StateError('Provider monitor HTTP ${response.statusCode}');
    }
    if ((jsonDecode(response.body) as Map)['count'] == 0) {
      released = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  } while (DateTime.now().isBefore(deadline));
  if (!released) {
    throw StateError(
      'Cancelled completion kept the fixture provider streaming',
    );
  }
}
