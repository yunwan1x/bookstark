import 'fixtures/spreadsheet.dart';
import 'fixtures/trash.dart';
import 'package:bookstark_flutter/features/trash/trash_page.dart';
import 'fixtures/credentials.dart';
import 'package:bookstark_flutter/features/credentials/api_tokens_page.dart';
import 'package:bookstark_flutter/features/credentials/webdav_password_page.dart';
import 'fixtures/backgrounds.dart';
import 'package:bookstark_flutter/core/background_repository.dart';
import 'package:bookstark_flutter/features/profile/background_page.dart';
import 'fixtures/reminders.dart';
import 'package:bookstark_flutter/core/reminder_repository.dart';
import 'package:bookstark_flutter/features/profile/reminder_page.dart';
import 'fixtures/account_security.dart';
import 'package:bookstark_flutter/features/profile/account_security_page.dart';
import 'fixtures/profile.dart';
import 'package:bookstark_flutter/features/profile/profile_edit_page.dart';
import 'fixtures/public_notes.dart';
import 'package:bookstark_flutter/features/public_notes/public_notes_page.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'fixtures/sharing.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';
import 'package:bookstark_flutter/features/sharing/share_settings_page.dart';
import 'package:bookstark_flutter/features/sharing/content_password_page.dart';
import 'fixtures/public_edit.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_link_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_page.dart';
import 'fixtures/share_comments.dart';
import 'package:bookstark_flutter/features/public_shares/share_comments_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_book_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_chapter_page.dart';
import 'fixtures/public_shares.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/features/public_shares/share_reader_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_unlock_page.dart';
import 'package:bookstark_flutter/core/document_creation.dart';
import 'package:bookstark_flutter/features/public_feed/document_create_page.dart';
import 'package:bookstark_flutter/features/public_feed/document_location_page.dart';
import 'fixtures/public_feed.dart';
import 'package:bookstark_flutter/features/public_feed/public_feed_page.dart';
import 'package:bookstark_flutter/features/public_feed/resource_create_page.dart';
import 'fixtures/drive.dart';
import 'package:bookstark_flutter/core/file_draft_vault.dart';
import 'package:bookstark_flutter/features/drive/drive_page.dart';
import 'package:bookstark_flutter/features/drive/file_editor_page.dart';
import 'package:bookstark_flutter/features/drive/file_upload_page.dart';
import 'package:bookstark_flutter/features/drive/file_preview_page.dart';
import 'package:bookstark_flutter/features/drive/file_public_page.dart';
import 'dart:convert';
import 'fixtures/images.dart';
import 'package:bookstark_flutter/core/images_repository.dart';
import 'package:bookstark_flutter/features/images/images_page.dart';
import 'package:bookstark_flutter/features/images/image_preview_page.dart';
import 'package:bookstark_flutter/features/images/image_upload_page.dart';
import 'fixtures/search.dart';
import 'package:bookstark_flutter/features/search/search_page.dart';
import 'fixtures/label_management.dart';
import 'package:bookstark_flutter/features/labels/labels_feature.dart';
import 'package:bookstark_flutter/features/labels/label_editor_page.dart';
import 'package:bookstark_flutter/features/labels/label_detail_page.dart';
import 'package:bookstark_flutter/features/labels/label_merge_page.dart';
import 'package:bookstark_flutter/features/labels/label_recommendations_page.dart';
import 'package:bookstark_flutter/core/completion_repository.dart';
import 'package:bookstark_flutter/core/summary_editor_repository.dart';
import 'package:bookstark_flutter/core/comment_editor_repository.dart';
import 'package:bookstark_flutter/features/topics/ai_draft_page.dart';
import 'fixtures/topics.dart';
import 'fixtures/topic_picker.dart';
import 'package:bookstark_flutter/features/topics/topics_feature.dart';
import 'package:bookstark_flutter/features/topics/topic_detail_page.dart';
import 'package:bookstark_flutter/features/topics/topic_editor_page.dart';
import 'package:bookstark_flutter/features/topics/topic_calendar_page.dart';
import 'package:bookstark_flutter/features/topics/topic_comments_page.dart';
import 'package:bookstark_flutter/features/topics/topic_resource_picker_page.dart';
import 'fixtures/navigation.dart';
import 'package:bookstark_flutter/features/navigation/navigation_page.dart';
import 'fixtures/bookmarks.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmark_editor_page.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/task_draft_vault.dart';
import 'package:bookstark_flutter/features/tasks/tasks_page.dart';
import 'package:bookstark_flutter/features/tasks/task_editor_page.dart';
import 'fixtures/tasks.dart';
import 'fixtures/books.dart';
import 'fixtures/speech.dart';
import 'package:bookstark_flutter/core/speech_controller.dart';
import 'package:bookstark_flutter/features/speech/speech_player_page.dart';
import 'package:bookstark_flutter/core/book_draft_vault.dart';
import 'package:bookstark_flutter/core/document_editor_repository.dart';
import 'package:bookstark_flutter/features/books/books_feature.dart';
import 'package:bookstark_flutter/features/books/book_editor_page.dart';
import 'package:bookstark_flutter/features/books/chapters_page.dart';
import 'package:bookstark_flutter/features/books/document_reader_page.dart';
// Visual-regression fixture target only. Never imported by lib/main.dart.
import 'dart:typed_data';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';
import 'package:bookstark_flutter/features/assistant/assistant_page.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/draft_vault.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class FixtureCompletion implements CompletionRepository {
  @override
  Stream<String> complete({
    required String context,
    required String instruction,
    required CompletionScene scene,
    Future<void>? abortTrigger,
  }) async* {
    yield '# 三个可执行的行动\n\n';
    await Future<void>.delayed(const Duration(milliseconds: 150));
    yield '1. 每次阅读后写下一个观点。\n2. 关联已有笔记。\n3. 每周回顾，并选择下一步行动。';
  }
}

class FixtureRepository extends RemoteNotesRepository {
  FixtureRepository({bool articles = false})
    : super(
        BookstarkClient('https://fixture.invalid'),
        collection: articles ? NoteCollection.article : NoteCollection.note,
      ) {
    if (articles) {
      notes.clear();
      final titles = ['如何建立自己的知识体系', '阅读之后，如何留下思考', '写给未来自己的记录'];
      final content = [
        '让零散的信息建立关联，在阅读、记录与实践之间形成闭环。',
        '从摘录走向表达，用自己的语言重新组织观点。',
        '好的文章不是信息堆积，而是清晰的思考路径。',
      ];
      final labels = ['学习方法', '阅读', '写作'];
      for (var i = 0; i < 3; i++) {
        notes[i + 1] = Note(
          id: i + 1,
          title: titles[i],
          content: content[i],
          labels: [labels[i]],
          updatedAt: DateTime(2026, 11, 4 - i),
        );
      }
    }
  }
  final notes = <int, Note>{
    1: const Note(
      id: 1,
      title: '阅读的意义',
      content:
          '# 阅读的意义\n\n把阅读变成理解，再把理解变成行动。\n\n## 三个行动\n- 记录一个观点\n- 关联已有笔记\n- [ ] 写下自己的思考',
      labels: ['阅读'],
    ),
    2: const Note(
      id: 2,
      title: '私密阅读摘录',
      content: '',
      labels: ['私密'],
      isProtected: true,
    ),
  };
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) =>
      listFiltered(keyword: keyword, page: page);
  @override
  Future<List<Note>> listFiltered({
    String keyword = '',
    int page = 1,
    String label = '',
    String pinned = '',
  }) async => page == 1 && pinned != '1'
      ? notes.values
            .where(
              (note) =>
                  note.title.contains(keyword) &&
                  (label.isEmpty || note.labels.contains(label)),
            )
            .toList()
      : [];
  @override
  Future<Note> read(int id) async {
    if (notes[id]!.isProtected) throw NoteLocked(id);
    return notes[id]!;
  }

  @override
  Future<Note> unlock(int id, String password) async {
    if (password != 'test') throw StateError('测试密码不正确');
    return Note(
      id: id,
      title: notes[id]!.title,
      content: '# 私密阅读摘录\n\n仅供视觉回归的测试正文。',
      labels: ['私密'],
      isProtected: true,
      unlockPassword: password,
    );
  }

  @override
  Future<int> save(Note note) async {
    final id = note.id ?? notes.length + 1;
    notes[id] = note.copyWith(id: id);
    return id;
  }

  @override
  Future<void> remove(int id) async {
    notes.remove(id);
  }
}

class FixtureAttachments extends AttachmentRepository {
  final values = <Uri, Uint8List>{};
  @override
  bool owns(Uri uri) => uri.scheme == 'bookstark-attachment';
  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async {
    cancellation?.check();
    final uri = Uri.parse(
      'bookstark-attachment:///${attachmentId()}/${Uri.encodeComponent(file.name)}',
    );
    final bytes = await file.readAsBytes();
    cancellation?.check();
    values[uri] = bytes;
    return Attachment(
      uri: uri,
      name: file.name,
      image: rasterImage(file.name),
      size: bytes.length,
    );
  }

  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) async {
    final bytes = values[uri];
    if (bytes == null || bytes.length > maxBytes) {
      throw StateError('Fixture attachment unavailable');
    }
    return bytes;
  }
}

class FixtureAssistant extends AssistantRepository {
  FixtureAssistant() : super(BookstarkClient('https://fixture.invalid'));
  String session = '0123456789abcdef0123456789abcdef';
  String status = 'pending';
  static const draftId = 'abcdef0123456789abcdef0123456789';
  static const answer =
      '## 本周阅读收获\n\n- 把阅读变成理解\n- 将观点关联已有笔记\n- 用行动验证收获\n\n> 每天阅读20分钟，记录一个可执行的观点。';
  static const sources = <Map<String, Object?>>[
    {'kind': 'note', 'id': 1, 'title': '阅读的意义'},
    {'kind': 'topic', 'id': 2, 'title': '学习方法'},
  ];
  AssistantDraft get draft => AssistantDraft.fromJson({
    'id': draftId,
    'payload': {
      'kind': 'task',
      'title': '',
      'content': '每日阅读20分钟',
      'due_date': '2026-11-04',
    },
    'status': status,
    'url': status == 'done' ? '/notes?tab=tasks&task_id=9' : '',
  });
  @override
  Future<AssistantSession> open() async => AssistantSession.fromJson({
    'id': session,
    'busy': false,
    'drafts': [
      {
        'id': draft.id,
        'payload': draft.payload,
        'status': draft.status,
        'url': draft.url,
      },
    ],
  });
  @override
  Stream<AssistantUpdate> chat({
    required String session,
    required String message,
    required List<AssistantMessage> history,
    Future<void>? abortTrigger,
  }) async* {
    var cancelled = false;
    abortTrigger?.then((_) {
      cancelled = true;
    });
    yield const AssistantUpdate('round', round: 1);
    for (final rune in answer.runes) {
      await Future<void>.delayed(
        Duration(milliseconds: message == '停止测试' ? 120 : 15),
      );
      if (cancelled) {
        throw StateError('Fixture request aborted');
      }
      yield AssistantUpdate('delta', text: String.fromCharCode(rune));
    }
    yield AssistantUpdate(
      'done',
      messages: [
        AssistantMessage(role: 'user', content: message),
        const AssistantMessage(
          role: 'assistant',
          content: answer,
          sources: sources,
        ),
      ],
      drafts: [draft],
    );
  }

  @override
  Future<AssistantDraft> resolve(
    String session,
    String id, {
    required bool confirm,
  }) async {
    status = confirm ? 'done' : 'cancelled';
    return draft;
  }

  @override
  Future<AssistantSession> reset(String id) async {
    session = attachmentId();
    status = 'cancelled';
    return open();
  }

  @override
  Future<AssistantResourceDetail> readSource(
    Map<String, Object?> source,
  ) async => AssistantResourceDetail(
    source['title'] as String? ?? '来源资料',
    '# 来源资料\n\n这是独立视觉回归中的测试内容。',
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final values = <String, String>{};
  final drafts = DraftVault(
    namespace: 'visual-test-only',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
  final assistant = FixtureAssistant();
  final assistantVault = AssistantConversationVault(
    namespace: 'visual-test-only',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
  await assistantVault.save(assistant.session, [
    const AssistantMessage(role: 'user', content: '帮我总结最近的阅读笔记，并整理一条待办。'),
    const AssistantMessage(
      role: 'assistant',
      content: FixtureAssistant.answer,
      sources: FixtureAssistant.sources,
    ),
  ]);
  final articles = Uri.base.queryParameters['page'] == 'articles';
  final repository = FixtureRepository(articles: articles);
  if (!articles) {
    await drafts.write(
      repository.notes[1]!.copyWith(
        content:
            '# 阅读的意义\n\n这是待恢复的草稿，用于视觉回归。\n\n## 三个行动\n- 记录一个观点\n- 关联已有笔记\n- [ ] 写下自己的思考',
      ),
    );
  }
  final page = Uri.base.queryParameters['page'];
  final english = Uri.base.queryParameters['lang'] == 'en';
  final requestedScale =
      double.tryParse(Uri.base.queryParameters['scale'] ?? '1') ?? 1;
  final textScale = requestedScale.isFinite
      ? requestedScale.clamp(1.0, 3.0)
      : 1.0;
  final tasks = TaskFixture(today: DateTime(2026, 11, 4, 12));
  final taskVault = TaskDraftVault(
    namespace: 'visual-test-only',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
  if (page == 'task-editor') {
    tasks.records[1] = const TaskItem(
      id: 1,
      content: '每天阅读20分钟\n\n- 选择一本正在阅读的书\n- 记录一个可执行的观点',
      dueDate: '2026-11-04',
    );
  }
  if (page == 'task-calendar') {
    tasks.records.remove(2);
    final older = tasks.records[3]!;
    tasks.records[3] = TaskItem(
      id: older.id,
      content: older.content,
      dueDate: older.dueDate,
      modifiedAt: '2026-11-03T12:00:00',
    );
  }
  final media = FixtureAttachments();
  final bookmarks = BookmarksFixture();
  final navigationBookmarks = navigationBookmarksFixture();
  final books = BooksFixture(),
      documents = DocumentsFixture(),
      labels = LabelsFixture();
  final bookVault = BookDraftVault(
    namespace: 'visual-books',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
  final documentVault = DraftVault(
    namespace: 'visual-documents',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
  Future<void> speakPublicFixture(
    BuildContext context,
    String markdown,
    String title,
    String source,
  ) async {
    final speech = SpeechController(
      repository: SpeechFixtureRepository(),
      player: SpeechFixturePlayback(),
    );
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => SpeechPlayerPage(
            controller: speech,
            english: english,
            request: SpeechRequest(markdown, title: title, context: source),
          ),
        ),
      );
    } finally {
      await speech.close();
    }
  }

  Future<void> openDocument(BuildContext context, int id) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentReaderPage(
          bookId: 1,
          documentId: id,
          books: books,
          documents: documents,
          drafts: documentVault,
          attachments: media,
          english: english,
        ),
      ),
    );
  }

  Future<void> openExcerpt(
    BuildContext context,
    Note note,
    int documentId,
  ) async {
    final vault = DraftVault(
      namespace: 'visual-excerpt-$documentId',
      readValue: (key) async => values[key],
      writeValue: (key, value) async {
        values[key] = value;
      },
      deleteValue: (key) async {
        values.remove(key);
      },
    );
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(
          repository: repository,
          note: note,
          drafts: vault,
          attachments: media,
          english: english,
        ),
      ),
    );
  }

  Future<void> openSettings(BuildContext context, dynamic book) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BookEditorPage(
          repository: books,
          book: book,
          labelsRepository: labels,
          vault: bookVault,
          english: english,
        ),
      ),
    );
  }

  final images = ImagesFixture();
  if (['images', 'image-preview', 'image-upload'].contains(page)) {
    final names = ['阅读与自然.svg', '产品交互草图.svg', '知识网络.svg', '山间阅读.svg'];
    for (var n = 0; n < names.length; n++) {
      final colors = ['#dbeafe', '#fef3c7', '#dcfce7', '#ede9fe'];
      final content =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 480 300"><rect width="480" height="300" fill="${colors[n]}"/><circle cx="360" cy="70" r="35" fill="#fbbf24"/><path d="M0 280L140 90L260 240L350 150L480 300H0Z" fill="#64748b"/><rect x="170" y="175" width="125" height="85" rx="8" fill="#fff"/><path d="M232 180V250M180 195H220M245 195H292M180 215H220M245 215H292" stroke="#2563eb" stroke-width="5"/></svg>';
      images.recordPayload(
        ImageUploadPayload.fromBytes(
          name: names[n],
          bytes: Uint8List.fromList(utf8.encode(content)),
          category: ImageCategory.values[n % 3],
        ),
      );
    }
  }
  final drive = DriveFixture();
  final fileVault = FileDraftVault(
    namespace: 'visual-drive-only',
    readValue: (key) async => values[key],
    writeValue: (key, value) async {
      values[key] = value;
    },
    deleteValue: (key) async {
      values.remove(key);
    },
  );
  final managedLabels = LabelManagementFixture();
  final topics = TopicsFixture();
  final topicPicker = TopicPickerFixture();
  final Widget? bookPreview = switch (page) {
    'spreadsheet' => const SpreadsheetVisualFixture(),
    'drive' => DrivePage(repository: drive, vault: fileVault),
    'drive-editor' => FileEditorPage(
      repository: drive,
      file: drive.nodes['阅读清单.md']!,
      vault: fileVault,
    ),
    'drive-upload' => FileUploadPage(repository: drive, directory: ''),
    'drive-public' => FilePublicPage(
      repository: drive,
      file: drive.nodes['阅读清单.md']!,
    ),
    'drive-preview' => FilePreviewPage(
      repository: drive,
      file: drive.nodes['阅读资料/学习资料.pdf']!,
    ),
    'images' => ImagesPage(repository: images, english: english),
    'image-preview' => ImagePreviewPage(
      repository: images,
      image: images.records.values.first,
      english: english,
    ),
    'image-upload' => ImageUploadPage(repository: images, english: english),
    'search' => SearchPage(
      repository: SearchFixture(),
      initialQuery: '阅读',
      english: english,
      onOpenHit: (_) async {},
    ),
    'labels' => LabelsFeature(
      repository: managedLabels,
      onOpenResource: (_, resource) async {},
      english: english,
    ),
    'label-editor' => LabelEditorPage(
      repository: managedLabels,
      label: managedLabels.records[1],
      english: english,
    ),
    'label-detail' => LabelDetailPage(
      repository: managedLabels,
      labelId: 1,
      onOpenResource: (_) async {},
      english: english,
    ),
    'label-merge' => LabelMergePage(
      repository: managedLabels,
      target: managedLabels.records[1]!,
      english: english,
    ),
    'label-recommendations' => LabelRecommendationsPage(
      repository: managedLabels,
      english: english,
    ),

    'topic-summary-editor' => NoteEditorPage(
      repository: SummaryEditorRepository(topics, topics.summaries[31]!),
      note: Note(id: 31, title: '', content: topics.summaries[31]!.content),
      contentEditorTitle: english ? 'Edit summary' : '编辑小结',
      documentPath: '阅读与知识整理 · 手动记录',
      english: english,
    ),
    'topic-comment-editor' => NoteEditorPage(
      repository: CommentEditorRepository(topics, topics.commentRecords[81]!),
      note: Note(
        id: 81,
        title: '',
        content: topics.commentRecords[81]!.content,
      ),
      contentEditorTitle: english ? 'Edit comment' : '编辑评论',
      contentContextTag: english
          ? 'Summary · From notes to action'
          : '小结 · 从记录走向行动',
      english: english,
    ),
    'topic-ai-draft' => AIDraftPage(
      repository: FixtureCompletion(),
      title: '阅读与知识整理',
      initialContext: '如何把阅读转化为可执行的知识？',
      initialInstruction: english
          ? 'Extract three actionable steps'
          : '提炼三个可执行的行动',
      english: english,
    ),

    'topics' => TopicsFeature(
      repository: topics,
      tasks: topics.taskRepository,
      picker: topicPicker,
      onOpenResource: (_, resource) async {},
      english: english,
    ),
    'topic-detail' => TopicDetailPage(
      repository: topics,
      topicId: 1,
      tasks: topics.taskRepository,
      picker: topicPicker,
      onOpenResource: (_) async {},
      english: english,
    ),
    'topic-editor' => TopicEditorPage(
      repository: topics,
      topic: topics.records[1]!,
      english: english,
    ),
    'topic-calendar' => TopicCalendarPage(
      repository: topics,
      english: english,
      clock: () => DateTime(2026, 11, 4),
    ),
    'topic-comments' => TopicCommentsPage(
      repository: topics,
      topic: topics.records[1]!,
      english: english,
    ),
    'topic-picker' => TopicResourcePickerPage(
      repository: topicPicker,
      topics: topics,
      topic: topics.records[1]!,
      existing: const {},
      english: english,
    ),

    'trash' || 'trash-unknown' || 'trash-partial' => TrashPage(
      repository: TrashFixture(
        loseReceipt: page == 'trash-unknown',
        partial: page == 'trash-partial',
      ),
      english: english,
    ),
    'api-tokens' || 'api-tokens-unknown' => ApiTokensPage(
      repository: ApiTokensFixture(loseReceipt: page == 'api-tokens-unknown'),
      english: english,
    ),
    'webdav-password' || 'webdav-password-unknown' => WebdavPasswordPage(
      repository: WebdavPasswordFixture(
        loseReceipt: page == 'webdav-password-unknown',
      ),
      english: english,
    ),
    'background' || 'background-unknown' => BackgroundPage(
      repository: BackgroundFixture(loseReceipt: page == 'background-unknown'),
      preference: const BackgroundPreference(),
      picker: () async => BackgroundUpload(backgroundFixturePixels),
      onApplied: (_, _) async {},
      english: english,
    ),
    'reminders' || 'reminders-unknown' || 'reminders-unavailable' => Builder(
      builder: (context) => ReminderPage(
        repository: ReminderFixture(
          loseReceipt: page == 'reminders-unknown',
          available: page != 'reminders-unavailable',
        ),
        settings: ReminderSettings(
          preferences: const ReminderDraft(
            enabled: true,
            sendTime: '09:00',
            days: 1,
            overdue: true,
          ),
          email: 'xiao.lin@example.test',
          available: page != 'reminders-unavailable',
          processedDate: '',
        ),
        onEditEmail: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileEditPage(
                repository: ProfileFixture(),
                profile: ProfileFixture.initial,
                english: english,
              ),
            ),
          );
        },
        english: english,
      ),
    ),
    'account-security' ||
    'account-security-unknown' ||
    'account-security-storage' => AccountSecurityPage(
      member: ProfileFixture.initial,
      repository: AccountSecurityFixture(
        loseReceipt: page == 'account-security-unknown',
        failFirstStore: page == 'account-security-storage',
      ),
      english: english,
    ),
    'profile' => ProfileFixtureShell(english: english),
    'profile-edit' ||
    'profile-edit-conflict' ||
    'profile-edit-unknown' => ProfileEditPage(
      repository: ProfileFixture(
        conflict: page == 'profile-edit-conflict',
        loseReceipt: page == 'profile-edit-unknown',
      ),
      profile: ProfileFixture.initial,
      english: english,
    ),
    'public-notes' => Builder(
      builder: (context) => PublicNotesPage(
        repository: PublicNotesFixture(),
        english: english,
        onOpen: (item) async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ShareReaderPage(
                reference: item.reference,
                repository: PublicSharesFixture(),
                attachments: PublicShareAttachments(PublicSharesFixture.server),
                english: english,
              ),
            ),
          );
        },
      ),
    ),
    'share-settings' || 'share-settings-unknown' => Builder(
      builder: (context) => ShareSettingsPage(
        target: OwnerShareTarget(
          kind: PublicShareKind.blog,
          id: 7,
          title: '选择适合自己的书',
        ),
        repository: SharingFixture(
          loseTokenReceipt: page == 'share-settings-unknown',
        ),
        english: english,
        onRead: (reference) async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ShareReaderPage(
                reference: reference,
                repository: PublicSharesFixture(),
                attachments: PublicShareAttachments(PublicSharesFixture.server),
                english: english,
              ),
            ),
          );
        },
        onPassword: () async => Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => ContentPasswordPage(
              id: 7,
              repository: ContentPasswordFixture(),
              english: english,
            ),
          ),
        ),
      ),
    ),
    'content-password' || 'content-password-unknown' => ContentPasswordPage(
      id: 7,
      repository: ContentPasswordFixture(
        loseReceipt: page == 'content-password-unknown',
      ),
      english: english,
    ),
    'share-edit-link' || 'share-edit-password' => ShareEditLinkPage(
      server: PublicSharesFixture.server,
      repository: PublicEditFixture(protected: page == 'share-edit-password'),
      shares: PublicSharesFixture(),
      attachments: PublicShareAttachments(PublicSharesFixture.server),
      english: english,
    ),
    'share-edit' ||
    'share-edit-conflict' ||
    'share-edit-unknown' => FutureBuilder(
      future: PublicEditFixture(
        loseReceipt: page == 'share-edit-unknown',
      ).controller(conflict: page == 'share-edit-conflict'),
      builder: (context, snapshot) => snapshot.hasData
          ? ShareEditPage(
              controller: snapshot.data!,
              attachments: PublicShareAttachments(PublicSharesFixture.server),
              english: english,
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'share-comments' => ShareCommentsPage(
      detail: ShareCommentsFixture.detail(),
      repository: ShareCommentsFixture(),
      english: english,
    ),
    'share-book' => Builder(
      builder: (context) => ShareBookPage(
        reference: PublicSharesFixture.reference('book'),
        repository: PublicSharesFixture(),
        english: english,
        onOpen: (book, node) async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ShareChapterPage(
                book: book,
                identify: node.identify,
                onSpeak: (markdown, title, source) =>
                    speakPublicFixture(context, markdown, title, source),
                repository: PublicSharesFixture(),
                attachments: PublicShareAttachments(PublicSharesFixture.server),
                english: english,
              ),
            ),
          );
        },
      ),
    ),
    'share-chapter' => Builder(
      builder: (context) => ShareChapterPage(
        book: PublicSharesFixture.book(),
        identify: 'choose',
        repository: PublicSharesFixture(),
        attachments: PublicShareAttachments(PublicSharesFixture.server),
        english: english,
        onSpeak: (markdown, title, source) =>
            speakPublicFixture(context, markdown, title, source),
      ),
    ),
    'share-reader' => Builder(
      builder: (context) => ShareReaderPage(
        reference: PublicSharesFixture.reference('public'),
        repository: PublicSharesFixture(),
        attachments: PublicShareAttachments(PublicSharesFixture.server),
        english: english,
        onComments: (detail) async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => ShareCommentsPage(
                detail: detail,
                repository: ShareCommentsFixture(),
                english: english,
              ),
            ),
          );
        },
        onSpeak: (markdown, title, source) async {
          final speech = SpeechController(
            repository: SpeechFixtureRepository(),
            player: SpeechFixturePlayback(),
          );
          try {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => SpeechPlayerPage(
                  controller: speech,
                  english: english,
                  request: SpeechRequest(
                    markdown,
                    title: title,
                    context: source,
                  ),
                ),
              ),
            );
          } finally {
            await speech.close();
          }
        },
      ),
    ),
    'share-unlock' => FutureBuilder(
      future: PublicSharesFixture().load(
        PublicSharesFixture.reference('protected'),
      ),
      builder: (context, snapshot) => snapshot.hasData
          ? ShareUnlockPage(
              detail: snapshot.data!,
              repository: PublicSharesFixture(),
              english: english,
            )
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    ),
    'public-feed' => PublicFeedPage(
      repository: PublicFeedFixture(),
      english: english,
      onOpen: (_) async {},
      onCreate: () async {},
    ),
    'resource-create' => ResourceCreatePage(english: english),
    'document-create' => DocumentCreatePage(
      controller: DocumentCreationController(
        books: books,
        documents: documents,
        vault: DocumentCreationVault(
          namespace: 'visual-document-create',
          readValue: (key) async => values[key],
          writeValue: (key, value) async {
            values[key] = value;
          },
          deleteValue: (key) async {
            values.remove(key);
          },
        ),
      ),
      initialLocation: DocumentLocation(
        book: books.records[1]!,
        parentId: 1,
        parentName: '第一章：建立阅读习惯',
      ),
      english: english,
      onOpenEditor: (context, item) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => NoteEditorPage(
              repository: DocumentEditorRepository(documents, item.bookId),
              note: Note(id: item.id, title: item.name, content: item.markdown),
              drafts: documentVault,
              attachments: media,
              documentPath: '${books.records[1]!.name} / ${item.name}',
              english: english,
            ),
          ),
        );
      },
      onReviewBook: (context, bookId) async {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ChaptersPage(
              bookId: bookId,
              books: books,
              documents: documents,
              english: english,
              onSettings: (context, book) async {},
              onOpen: (context, id) async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => DocumentReaderPage(
                      bookId: bookId,
                      documentId: id,
                      books: books,
                      documents: documents,
                      attachments: media,
                      drafts: documentVault,
                      english: english,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    ),
    'document-location' => DocumentLocationPage(
      books: books,
      documents: documents,
      initialBook: books.records[1],
      english: english,
    ),
    'speech' => SpeechPlayerPage(
      controller: SpeechController(
        repository: SpeechFixtureRepository(),
        player: SpeechFixturePlayback(),
      ),
      english: english,
      request: const SpeechRequest(
        '阅读不必从最难的书开始。先找到一个你真正想解决的问题，再挑选能帮助你理解它的书。\n\n选择与当前问题有关的内容。\n\n能读懂，也有一点挑战。\n\n愿意读完后付诸实践。',
        title: '选择适合自己的书',
        context: '阅读的方法',
      ),
    ),
    'navigation' => NavigationPage(
      repository: NavigationFixture(navigationBookmarks),
      bookmarks: navigationBookmarks,
      labels: navigationBookmarks,
      english: english,
    ),
    'bookmarks' => BookmarksPage(
      repository: bookmarks,
      labelsRepository: bookmarks,
      english: english,
    ),
    'bookmark-editor' => BookmarkEditorPage(
      repository: bookmarks,
      bookmark: bookmarks.items[1]!,
      labelsRepository: bookmarks,
      english: english,
    ),
    'books' => BooksFeature(
      notes: repository,
      books: books,
      documents: documents,
      labels: labels,
      bookDrafts: bookVault,
      documentDrafts: documentVault,
      attachments: media,
      english: english,
    ),
    'book-settings' => BookEditorPage(
      repository: books,
      book: await books.read(1),
      labelsRepository: labels,
      vault: bookVault,
      english: english,
    ),
    'chapters' => ChaptersPage(
      bookId: 1,
      books: books,
      documents: documents,
      onOpen: openDocument,
      onSettings: openSettings,
      english: english,
    ),
    'document-reader' => DocumentReaderPage(
      onExcerpt: openExcerpt,
      bookId: 1,
      documentId: 2,
      books: books,
      documents: documents,
      drafts: documentVault,
      attachments: media,
      english: english,
    ),
    'document-editor' => NoteEditorPage(
      repository: DocumentEditorRepository(documents, 1),
      note: const Note(
        id: 2,
        title: '选择适合自己的书',
        content: DocumentsFixture.body,
      ),
      documentPath: '阅读的方法 / 第一章：建立阅读习惯',
      drafts: documentVault,
      attachments: media,
      english: english,
    ),
    _ => null,
  };
  final Widget preview =
      bookPreview ??
      (page == 'tasks' || page == 'task-calendar'
          ? TasksPage(
              repository: tasks,
              vault: taskVault,
              attachments: media,
              english: english,
              calendar: page == 'task-calendar',
              clock: () => tasks.now,
            )
          : page == 'task-editor'
          ? TaskEditorPage(
              repository: tasks,
              task: await tasks.read(1),
              vault: taskVault,
              attachments: media,
              english: english,
              clock: () => tasks.now,
            )
          : page == 'assistant'
          ? AssistantPage(
              repository: assistant,
              vault: assistantVault,
              english: english,
            )
          : NotesPage(
              repository: repository,
              collection: articles
                  ? NoteCollection.article
                  : NoteCollection.note,
              english: english,
              drafts: drafts,
              attachments: media,
            ));
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      theme: bookstarkTheme().copyWith(platform: TargetPlatform.android),
      locale: Locale(english ? 'en' : 'zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      initialRoute: '/preview',
      onGenerateRoute: (settings) => MaterialPageRoute<void>(
        settings: settings,
        builder: (_) => settings.name == '/preview'
            ? Banner(
                message: 'FIXTURE',
                location: BannerLocation.bottomStart,
                child: preview,
              )
            : const Scaffold(body: Center(child: Text('Visual fixture space'))),
      ),
    ),
  );
}
