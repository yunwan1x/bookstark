// Synthetic browser-only UI fixture. No SQLite, model API, credentials or real
// resources. Production widgets are exercised; callbacks deliberately stay fake.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';
import 'package:bookstark_flutter/core/local_assistant_creation_receipts.dart';
import 'package:bookstark_flutter/core/local_assistant_draft_payload.dart';
import 'package:bookstark_flutter/core/local_assistant_retained_draft.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';
import 'package:bookstark_flutter/features/assistant/local_assistant_save_review_page.dart';
import 'package:bookstark_flutter/features/assistant/local_assistant_retained_draft_page.dart';

const fixtureId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const pendingId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const unknownId = 'cccccccccccccccccccccccccccccccc';

class FixtureAssistant implements AssistantDataSource {
  int chats = 0;
  final Set<String> discarded = {};
  @override
  Future<AssistantSession> open() async => AssistantSession.fromJson({
    'id': fixtureId,
    'drafts': [
      {
        'id': pendingId,
        'status': discarded.contains(pendingId) ? 'cancelled' : 'pending',
        'payload': {
          'kind': 'note',
          'title': '冬日阅读清单',
          'content': '## 阅读安排\n\n- 阅读一章\n- 记录问题',
        },
      },
      {
        'id': unknownId,
        'status': 'unknown',
        'payload': {
          'kind': 'task',
          'content': 'Review the reading notes',
          'due_date': '2026-11-20',
        },
      },
    ],
  });
  @override
  Future<AssistantSession> reset(String id) => open();
  @override
  Future<AssistantResourceDetail> readSource(
    Map<String, Object?> source,
  ) async => const AssistantResourceDetail('Synthetic source', 'Fixture only');
  @override
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  }) async {
    if (confirm) throw StateError('Synthetic fixture never creates resources');
    discarded.add(id);
    return (await open()).drafts.firstWhere((draft) => draft.id == id);
  }

  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    chats++;
    yield AssistantUpdate(
      'done',
      messages: [
        AssistantMessage(role: 'user', content: message),
        const AssistantMessage(
          role: 'assistant',
          content: '## Fixture reply\n\n**Rendered Markdown** with no network.',
        ),
      ],
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized().ensureSemantics();
  final english = Uri.base.queryParameters['lang'] == 'en';
  final large = Uri.base.queryParameters['large'] == '1';
  runApp(
    MaterialApp(
      title: 'Synthetic assistant creation fixture',
      theme: bookstarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(large ? 2 : 1),
          viewInsets: large
              ? const EdgeInsets.only(bottom: 180)
              : EdgeInsets.zero,
        ),
        child: child!,
      ),
      home: FixtureHome(english: english),
    ),
  );
}

class FixtureHome extends StatefulWidget {
  const FixtureHome({super.key, required this.english});
  final bool english;
  @override
  State<FixtureHome> createState() => _FixtureHomeState();
}

class _FixtureHomeState extends State<FixtureHome> {
  final repository = FixtureAssistant();
  int resolutions = 0, opens = 0, clears = 0;
  bool _started = false;
  String? _contextValue;
  String get view => Uri.base.queryParameters['view'] ?? 'assistant';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _launch());
    }
  }

  Future<void> _callback(String label) async {
    opens++;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Synthetic callback')),
          body: Center(child: Text(label)),
        ),
      ),
    );
  }

  LocalAssistantCreationInspection _inspection(String kind, int revision) {
    final state = kind == 'review-absent'
        ? LocalAssistantCreationResourceState.absent
        : kind == 'review-protected'
        ? LocalAssistantCreationResourceState.protected
        : revision > 0
        ? LocalAssistantCreationResourceState.changed
        : LocalAssistantCreationResourceState.matching;
    final task = kind == 'review-task';
    final receipt = state == LocalAssistantCreationResourceState.absent
        ? null
        : LocalAssistantCreationReceipt(
            key: unknownId,
            kind: task
                ? LocalAssistantDraftKind.task
                : LocalAssistantDraftKind.note,
            resourceId: 42,
            inputHash: 'd' * 64,
            createdAt: 123,
          );
    return LocalAssistantCreationInspection(
      key: unknownId,
      receipt: receipt,
      state: state,
      fingerprint: '$kind-$revision',
      note: kind == 'review-note'
          ? Note(
              id: 42,
              title: widget.english ? 'Winter reading list' : '冬日阅读清单',
              content: widget.english
                  ? '## Read and reflect\n\n- Read one chapter\n- Record a question\n\n> Keep the original source.'
                  : '## 阅读与思考\n\n- 阅读一个章节\n- 记录一个问题\n\n> 保留原始资料。',
            )
          : null,
      task: task
          ? const TaskItem(
              id: 42,
              content: 'Review the reading notes and record the next question',
              dueDate: '2026-11-20',
            )
          : null,
    );
  }

  Widget _review(String kind) {
    var calls = 0;
    final changing = Uri.base.queryParameters['changing'] == '1';
    return LocalAssistantSaveReviewPage(
      english: widget.english,
      inspect: () async => _inspection(kind, changing && calls++ > 0 ? 1 : 0),
      resolve: (_) async {
        resolutions++;
      },
      onOpenResource: (_) async => _callback('Synthetic resource opened'),
    );
  }

  Future<void> _launch() async {
    final Widget page;
    if (view.startsWith('review-')) {
      page = _review(view);
    } else if (view.startsWith('retained')) {
      final snapshot = LocalAssistantRetainedDraftSnapshot(
        fingerprint: 'fixture-retained',
        note: Note(
          title: widget.english ? 'Retained reading draft' : '保留的阅读草稿',
          content: widget.english
              ? '## Notes to keep\n\nThis **edited draft** is retained until explicit clearing.'
              : '## 保留的笔记\n\n这份**实际编辑草稿**会保留到明确清除。',
        ),
        task: null,
        raw: 'synthetic fixture only',
      );
      page = LocalAssistantRetainedDraftPage(
        english: widget.english,
        initialSnapshot: view == 'retained-empty' ? null : snapshot,
        inspect: () async => view == 'retained-empty' ? null : snapshot,
        clear: (_) async {
          clears++;
        },
      );
    } else {
      final partial = view == 'assistant-partial';
      _contextValue = jsonEncode({
        'version': 2,
        'session': fixtureId,
        'input': partial ? 'New question' : '',
        'pending_question': partial ? 'Earlier question' : null,
        'partial': partial
            ? '## Unfinished reading plan\n\nKeep this **partial reply** until you explicitly replace it.'
            : '',
        'messages': partial
            ? []
            : [
                {
                  'role': 'user',
                  'content': widget.english ? 'Organize my reading' : '整理阅读思路',
                },
                {
                  'role': 'assistant',
                  'content': widget.english
                      ? '## Reading plan\n\nUse **Markdown** to organize ideas.\n\n- Read one chapter\n- Record a question'
                      : '## 阅读计划\n\n用 **Markdown** 整理思路。\n\n- 阅读一个章节\n- 记录一个问题',
                },
              ],
      });
      page = AssistantPage(
        repository: repository,
        local: true,
        modelLabel: 'visual-model',
        knowledgeGranted: true,
        english: widget.english,
        vault: AssistantConversationVault(
          namespace: 'synthetic-c-fixture',
          readValue: (_) async => _contextValue,
          writeValue: (_, value) async {
            _contextValue = value;
          },
          deleteValue: (_) async {
            _contextValue = null;
          },
        ),
        onEditLocalDraft: (id) async {
          if (id == unknownId) {
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => _review('review-task')),
            );
          } else {
            await _callback('Synthetic editor opened; no resource was created');
          }
        },
      );
    }
    if (!mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => Banner(
          message: 'FIXTURE',
          location: BannerLocation.topEnd,
          child: page,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Synthetic fixture result')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Browser fixture only. No database, model API or actual resource changes.',
        ),
        Text('Resolved: $resolutions'),
        Text('Opened: $opens'),
        Text('Cleared: $clears'),
        Text('Chats: ${repository.chats}'),
        FilledButton(
          onPressed: _launch,
          child: const Text('Open fixture again'),
        ),
      ],
    ),
  );
}
