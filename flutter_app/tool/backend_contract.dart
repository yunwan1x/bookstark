import 'html_source_contract.dart' show runHtmlSourceContract;
import 'trash_contract.dart';
import 'credentials_contract.dart';
import 'background_contract.dart';
import 'reminder_contract.dart';
import 'profile_contract.dart';
import 'account_security_contract.dart';
import 'public_notes_contract.dart';
import 'share_settings_contract.dart';
import 'public_shares_contract.dart';
import 'public_feed_contract.dart';
import 'drive_contract.dart';
import 'images_contract.dart';
import 'search_contract.dart';
import 'labels_contract.dart';
// Contract checks use the shipped Go runtime with an empty disposable database.
import 'dart:async';
import 'topics_contract.dart';
import 'completion_contract.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:file_selector/file_selector.dart';
import 'package:bookstark_flutter/core/tasks_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/navigation_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/assistant_repository.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main(List<String> arguments) async {
  final config = jsonDecode(await File(arguments.single).readAsString()) as Map;
  final client = BookstarkClient(config['base'] as String)..language = 'zh';
  try {
    await client.login(
      config['account'] as String,
      config['password'] as String,
    );
    final profile = await client.get('/api/profile');
    require(profile['member_id'] is int, 'Profile response shape');
    await runProfileContract(client, profile['member_id'] as int);
    await runAccountSecurityContract(
      client,
      profile['member_id'] as int,
      config['password'] as String,
    );
    await runReminderContract(
      client,
      profile['member_id'] as int,
      smtpHost: config['smtp_host'] as String,
      smtpPort: config['smtp_port'] as int,
      provider: config['provider'] as String,
    );
    await runBackgroundContract(client, profile['member_id'] as int);
    await runCredentialsContract(
      client,
      profile['member_id'] as int,
      config['password'] as String,
    );
    await runTrashContract(client, profile['member_id'] as int);
    await runHtmlSourceContract(client);
    await runShareSettingsContract(client);
    await runPublicNotesContract(client);
    await runPublicSharesContract(client);
    await runPublicFeedContract(client, profile['member_id'] as int);
    await runDriveContract(client);
    await runImagesContract(client);
    await runTopicsContract(client, profile['member_id'] as int);
    await runLabelsContract(client, profile['member_id'] as int);
    await runSearchContract(client, profile['member_id'] as int);
    stdout.writeln(
      'PASS production search: seven typed groups, exact IDs, protected-note exclusion, literal wildcards and real twenty-item cap',
    );
    stdout.writeln(
      'PASS production labels: document-only usage, rename, merge, unbind, global cleanup, canonical bookmark metadata and read-only recommendation preview',
    );
    stdout.writeln(
      'PASS production topics: summaries, exact resource association, comments, 101 tasks, activity calendar and deletion',
    );
    final bookmarks = RemoteBookmarksRepository(
      client,
      memberId: profile['member_id'] as int,
      isAdmin: profile['role'] == 0,
    );
    const bookmarkUrl = 'https://example.invalid/flutter-contract?x=1#keep';
    final bookmarkId = await bookmarks.save(
      const BookmarkItem(
        title: 'Flutter 书签回归',
        url: bookmarkUrl,
        description: '精确标签与图标',
        favicon: 'https://example.invalid/icon.png',
        labels: ['旧,标签', ' 保留空白 ', '普通', '开发/Flutter'],
      ),
    );
    final bookmark = (await bookmarks.findByUrl(bookmarkUrl))!;
    require(
      bookmark.id == bookmarkId &&
          bookmark.labels.toSet().containsAll(['旧,标签', ' 保留空白 ', '普通']),
      'Bookmark array names preserve commas and whitespace',
    );
    require(
      !bookmark.isPublic && !bookmark.navVisible,
      'New bookmark stays private and outside navigation',
    );
    try {
      await bookmarks.save(const BookmarkItem(title: '不能覆盖', url: bookmarkUrl));
      throw StateError('Duplicate bookmark was not detected');
    } on BookmarkAlreadyExists catch (error) {
      require(
        error.bookmark.id == bookmarkId,
        'Duplicate uses canonical saved ID',
      );
    }
    final navigation = RemoteNavigationRepository(client);
    require(
      (await navigation.load()).total == 0,
      'Hidden bookmarks excluded from navigation',
    );
    require(
      (await bookmarks.list(
            BookmarkQuery(start: DateTime(9999, 1, 1)),
          )).total ==
          0,
      'Server actually applies naive date filter',
    );
    await bookmarks.setNavVisible(bookmarkId, true);
    final grouped = await navigation.load();
    require(
      grouped.groups.single.name == '开发' &&
          grouped.groups.single.items.single.id == bookmarkId,
      'Navigation canonical hierarchy group',
    );
    require(
      (await navigation.load(scope: BookmarkScope.public)).total == 0,
      'Private navigation absent from public scope',
    );
    await bookmarks.batch(BookmarkBatch.pin, [bookmarkId]);
    final pinnedNavigation = await navigation.load();
    require(
      pinnedNavigation.pinned.single.id == bookmarkId &&
          pinnedNavigation.groups.isEmpty &&
          pinnedNavigation.ungrouped.isEmpty &&
          pinnedNavigation.total == 1,
      'Pinned navigation has no duplicate group rows',
    );
    await bookmarks.save(
      bookmark.copyWith(title: 'Flutter 书签已修改'),
      original: bookmark,
    );
    final updatedBookmark = (await bookmarks.findByUrl(bookmarkUrl))!;
    require(
      updatedBookmark.favicon == bookmark.favicon &&
          updatedBookmark.isPinned &&
          updatedBookmark.navVisible,
      'Bookmark title-only update preserves favicon, pin and navigation',
    );
    require(
      (await bookmarks.list(
        const BookmarkQuery(labels: ['旧,标签']),
      )).items.any((item) => item.id == bookmarkId),
      'Exact comma AND label filtering',
    );
    await bookmarks.batch(
      BookmarkBatch.removeLabels,
      [bookmarkId],
      labels: ['旧,标签'],
    );
    require(
      !(await bookmarks.findByUrl(bookmarkUrl))!.labels.contains('旧,标签'),
      'Exact array label removal',
    );
    await bookmarks.setPublic(bookmarkId, true);
    require(
      (await bookmarks.list(
        const BookmarkQuery(scope: BookmarkScope.public),
      )).items.any((item) => item.id == bookmarkId),
      'Public bookmark feed',
    );
    require(
      (await navigation.load(scope: BookmarkScope.public)).pinned.single.id ==
          bookmarkId,
      'Public navigation scope after explicit publication',
    );
    await bookmarks.sort({bookmarkId: 17});
    require(
      (await bookmarks.findByUrl(bookmarkUrl))!.order == 17,
      'Bookmark sort persists without losing flags',
    );
    await bookmarks.remove(bookmarkId);
    require(
      await bookmarks.findByUrl(bookmarkUrl) == null,
      'Bookmark deletion',
    );
    require(
      (await navigation.load()).total == 0,
      'Deleted navigation no longer appears',
    );
    stdout.writeln(
      'PASS production bookmarks and navigation: exact labels, duplicate confirmation, flags, visibility, canonical groups and pinned separation',
    );
    final books = RemoteBooksRepository(client);
    final bookId = await books.save(
      const BookItem(
        name: 'Flutter 原生书籍回归',
        description: '真实书籍说明',
        labels: [' 阅读 ', '学习'],
      ),
    );
    final book = await books.read(bookId);
    require(
      book.name == 'Flutter 原生书籍回归' &&
          book.labels.contains(' 阅读 ') &&
          book.labels.contains('学习') &&
          book.identify.isNotEmpty,
      'Book detail and exact label identities',
    );
    final bookPage = await books.list(keyword: 'Flutter 原生书籍回归');
    require(
      bookPage.total == 1 &&
          bookPage.items.single.id == bookId &&
          !bookPage.items.single.labelsLoaded,
      'Book search and authoritative detail distinction',
    );
    await books.save(book.copyWith(name: 'Flutter 已修改书籍', labels: []));
    final updatedBook = await books.read(bookId);
    require(
      updatedBook.labels.isEmpty &&
          updatedBook.identify == book.identify &&
          updatedBook.description == book.description,
      'Book update clears labels and preserves server identifier',
    );
    final documents = RemoteDocumentsRepository(client);
    final initial = await documents.tree(bookId);
    require(
      initial.length == 1 &&
          initial.single.name == 'Flutter 原生书籍回归' &&
          updatedBook.documentCount == 1,
      'New book starts with a real same-name document',
    );
    final chapter = await documents.create(bookId, '章节一');
    final childDocument = await documents.create(
      bookId,
      '子文档',
      parentId: chapter.id,
    );
    await documents.saveMarkdown(childDocument.id, '# 实际文档\n\n中文正文');
    await documents.rename(childDocument.id, '改名保留正文');
    require(
      (await documents.read(childDocument.id)).markdown == '# 实际文档\n\n中文正文',
      'Document rename preserves Markdown',
    );
    await documents.saveMarkdown(childDocument.id, '');
    require(
      (await documents.read(childDocument.id)).markdown.isEmpty,
      'Document body can actually be cleared',
    );
    require(
      (await documents.tree(
            bookId,
          )).singleWhere((node) => node.id == chapter.id).children.single.id ==
          childDocument.id,
      'Real chapter hierarchy',
    );
    var preventedCycle = false;
    try {
      await documents.move(bookId, chapter.id, childDocument.id);
    } on StateError {
      preventedCycle = true;
    }
    require(preventedCycle, 'Prevent moving a chapter into its descendant');
    await documents.move(bookId, childDocument.id, 0);
    final moved = await documents.tree(bookId);
    require(moved.length == 3, 'Document move to book root');
    final previousIndex = moved.indexWhere(
      (node) => node.id == childDocument.id,
    );
    await documents.reorder(childDocument.id, 'up');
    require(
      (await documents.tree(
            bookId,
          )).indexWhere((node) => node.id == childDocument.id) ==
          previousIndex - 1,
      'Real document reorder',
    );
    await documents.move(bookId, childDocument.id, chapter.id);
    await documents.remove(childDocument.id);
    await documents.remove(chapter.id);
    require(
      (await documents.tree(bookId)).single.id == initial.single.id &&
          (await books.read(bookId)).documentCount == 1,
      'Delete leaf documents and maintain document count',
    );
    stdout.writeln(
      'PASS production document repository create/tree/rename/body clear/move/reorder/leaf deletion',
    );
    await books.remove(bookId);
    require(
      (await books.list(keyword: 'Flutter 已修改书籍')).total == 0,
      'Book deletion',
    );
    stdout.writeln(
      'PASS production book repository create/search/detail/update/label verification/clear/delete',
    );
    final created = await client.post('/api/blogs', {
      'blog_title': 'Flutter 接口回归',
      'blog_content': '# 标题\n\n中文内容 **加粗**',
      'blog_type': 'note',
      'editor_type': 'markdown',
      'visibility': 0,
    });
    final id = created['blog_id'] as int;
    await client.mutate('PUT', '/api/labels/resource/blog/$id', {
      'labels': '阅读,回归',
    });
    final labels = await client.get('/api/labels/resource/blog/$id');
    require((labels['data'] as List).length == 2, 'Labels replacement');
    await client.mutate('PUT', '/api/labels/resource/blog/$id', {'labels': ''});
    require(
      ((await client.get('/api/labels/resource/blog/$id'))['data'] as List? ??
              [])
          .isEmpty,
      'Empty labels must clear',
    );
    await client.mutate('PUT', '/api/blogs/$id', {
      'blog_title': 'Flutter 接口回归',
      'blog_content': '# 已更新\n\n保存成功',
    });
    require(
      (await client.get('/api/blogs/$id'))['blog_content'] == '# 已更新\n\n保存成功',
      'Markdown round trip',
    );
    stdout.writeln(
      'PASS real login/CSRF/profile, note creation/update and clearing labels',
    );
    final bytes = utf8.encode('中文附件\n真实多段上传\n');
    final uploaded = await client.upload(
      '/api/webdav/files/upload',
      name: 'contract.txt',
      data: Stream.fromIterable([bytes.sublist(0, 5), bytes.sublist(5)]),
      length: bytes.length,
      fields: {'path': '/'},
    );
    final path = (uploaded['file'] as Map)['path'] as String;
    final downloaded = await client.download(
      '/api/webdav/files/download?path=${Uri.encodeQueryComponent(path)}',
    );
    require(
      base64Encode(downloaded) == base64Encode(bytes),
      'Private attachment bytes',
    );
    stdout.writeln(
      'PASS real private multipart upload and authenticated binary download',
    );
    final image = File('../docs/flutter-rewrite/pages/08-editor.png');
    final uploadedImage = await client.upload(
      '/api/uploads',
      name: 'contract.png',
      data: image.openRead(),
      length: await image.length(),
      fields: {'category': 'editor'},
    );
    final publicUri = client.baseUri.resolve(uploadedImage['url'] as String);
    require(
      publicUri.host == client.baseUri.host &&
          publicUri.port == client.baseUri.port,
      'Image stays on fixture server',
    );
    final anonymous = http.Client();
    try {
      final response = await anonymous.send(
        http.Request('GET', publicUri)..followRedirects = false,
      );
      require(
        response.statusCode == 200 &&
            (response.headers['content-type'] ?? '').startsWith('image/'),
        'Converted image publicly readable',
      );
      require(
        (await readBoundedResponse(
          response,
          maxBytes: 16 * 1024 * 1024,
        )).isNotEmpty,
        'Converted image bytes',
      );
      final denied = await anonymous.send(
        http.Request(
          'GET',
          client.baseUri.resolve(
            '/api/webdav/files/download?path=${Uri.encodeQueryComponent(path)}',
          ),
        )..followRedirects = false,
      );
      require(
        denied.statusCode == 401 || denied.statusCode == 403,
        'Private attachment requires authentication',
      );
      await denied.stream.drain<void>();
    } finally {
      anonymous.close();
    }
    await client.mutate('PUT', '/api/blogs/$id', {
      'blog_title': 'Flutter 接口回归',
      'blog_content': '# 保护正文',
      'new_password': config['password'],
    });
    final masked = await client.get('/api/blogs/$id');
    require(
      masked['has_password'] == true && masked['blog_content'] != '# 保护正文',
      'Protected read masks content',
    );
    var rejected = false;
    try {
      await client.post('/api/blogs/$id/verify-password', {
        'password': 'incorrect-fixture',
      });
    } on ApiFailure {
      rejected = true;
    }
    require(rejected, 'Wrong password rejected');
    final unlocked = await client.post('/api/blogs/$id/verify-password', {
      'password': config['password'],
    });
    require(
      unlocked['blog_content'] == '# 保护正文',
      'Unlock returns original content',
    );
    await client.mutate('PUT', '/api/blogs/$id', {
      'blog_title': 'Flutter 接口回归',
      'blog_content': '# 保存后仍加密',
      'password': config['password'],
    });
    require(
      (await client.get('/api/blogs/$id'))['has_password'] == true,
      'Editor save must preserve protection',
    );
    require(
      (await client.post('/api/blogs/$id/verify-password', {
            'password': config['password'],
          }))['blog_content'] ==
          '# 保存后仍加密',
      'Protected content round trip',
    );
    stdout.writeln(
      'PASS real converted image, private-file authorization and protected-note save',
    );

    await client.mutate('PUT', '/api/admin/settings', {
      'ai_enabled': '1',
      'ai_provider': 'openai',
      'ai_base_url': config['provider'],
      'ai_api_key': 'fixture-only',
      'ai_model': 'fixture',
    });
    final remoteNotes = RemoteNotesRepository(client);
    var locked = false;
    try {
      await remoteNotes.read(id);
    } on NoteLocked {
      locked = true;
    }
    require(locked, 'Actual note repository must require unlock');
    final protectedNote = await remoteNotes.unlock(
      id,
      config['password'] as String,
    );
    await remoteNotes.save(protectedNote.copyWith(content: '# 原生仓库保护保存'));
    require(
      (await remoteNotes.unlock(id, config['password'] as String)).content ==
          '# 原生仓库保护保存',
      'Production repository protected round trip',
    );
    final remoteArticles = RemoteNotesRepository(
      client,
      collection: NoteCollection.article,
    );
    final articleId = await remoteArticles.save(
      const Note(title: '原生文章回归', content: '# 文章正文', labels: ['阅读']),
    );
    final article = await remoteArticles.read(articleId);
    require(
      article.labels.single == '阅读' && article.content == '# 文章正文',
      'Production article decode and labels',
    );
    require(
      (await remoteArticles.listFiltered(label: '阅读')).single.id == articleId,
      'Production article server filter',
    );
    await remoteArticles.save(article.copyWith(labels: []));
    require(
      (await remoteArticles.read(articleId)).labels.isEmpty,
      'Production article clear labels',
    );
    await remoteArticles.remove(articleId);
    require(
      (await remoteArticles.list()).isEmpty,
      'Production article soft deletion',
    );
    final attachments = RemoteAttachments(client);
    try {
      final private = await attachments.add(
        XFile.fromData(bytes, path: 'native-contract.txt'),
        protected: true,
      );
      require(
        base64Encode(await attachments.read(private.uri)) ==
            base64Encode(bytes),
        'Production attachment repository private round trip',
      );
      final public = await attachments.add(XFile(image.path));
      require(
        public.image && (await attachments.read(public.uri)).isNotEmpty,
        'Production image repository converts and reads image',
      );
    } finally {
      attachments.close();
    }
    stdout.writeln(
      'PASS production note/article/attachment repositories against actual Go APIs',
    );
    final tasks = RemoteTasksRepository(client);
    final parentId = await tasks.save(
      const TaskItem(content: '父待办接口回归', dueDate: '2026-11-08'),
    );
    final childId = await tasks.save(
      TaskItem(content: '子待办接口回归', dueDate: '2026-11-09', parentId: parentId),
    );
    var child = await tasks.read(childId);
    await tasks.save(child.copyWith(content: '更新子待办保留父关联'));
    require(
      (await tasks.read(childId)).parentId == parentId,
      'Child edit keeps actual parent',
    );
    await tasks.setDone(childId, true);
    child = await tasks.read(childId);
    require(
      child.done && child.completedAt != null,
      'Completion records actual timestamp',
    );
    require(
      (await tasks.read(parentId)).childDone == 1,
      'Parent actual completed-child count',
    );
    await tasks.setDone(childId, false);
    child = await tasks.read(childId);
    require(
      !child.done && child.completedAt == null,
      'Reopening clears completion timestamp',
    );
    final due = await tasks.list(const TaskQuery(dueOn: '2026-11-08'));
    require(
      due.total == 1 && due.items.single.id == parentId && !due.hasMore,
      'Actual due-date filter and pagination',
    );
    final children = await tasks.list(TaskQuery(parentId: parentId));
    require(
      children.total == 1 && children.items.single.id == childId,
      'Actual child pagination',
    );
    final modifiedDay = child.modifiedAt!.substring(0, 10);
    final counts = await tasks.dailyCounts(
      int.parse(modifiedDay.substring(0, 4)),
      int.parse(modifiedDay.substring(5, 7)),
    );
    require(
      counts.singleWhere((count) => count.date == modifiedDay).total == 2,
      'Calendar counts actual modification date',
    );
    require(
      (await tasks.list(TaskQuery(modifiedOn: modifiedDay))).total == 2,
      'Selected calendar day uses modification date',
    );
    await tasks.remove(parentId);
    require(
      (await tasks.list(const TaskQuery())).total == 0,
      'Single root deletion removes actual child subtree',
    );
    stdout.writeln(
      'PASS production task repository create/edit/parent/completion/due-date/calendar/subtree deletion',
    );
    await runCompletionContract(
      client,
      Uri.parse(config['provider'] as String),
    );
    stdout.writeln(
      'PASS generic AI completion: real Go SSE, review-only text and cancellation releases local upstream',
    );
    final assistant = AssistantRepository(client);
    var session = await assistant.open();
    final updates = await assistant
        .chat(session: session.id, message: '整理测试笔记', history: [])
        .toList();
    final done = updates.singleWhere((event) => event.type == 'done');
    require(updates.any((event) => event.type == 'delta'), 'Real SSE deltas');
    final draft = done.drafts.singleWhere((draft) => draft.status == 'pending');
    final before = (await client.get('/api/blogs?type=note'))['data'] as List;
    require(before.length == 1, 'Draft must not create a note automatically');
    final receipt = await assistant.resolve(
      session.id,
      draft.id,
      confirm: true,
    );
    require(receipt.status == 'done', 'Real draft completed state');
    final resource = assistantCreatedResource(receipt);
    require(resource != null, 'Real created-resource URL');
    final detail = await assistant.readSource(resource!);
    require(detail.content.contains('真实后端测试正文'), 'Created source content');
    final repeated = await assistant.resolve(
      session.id,
      draft.id,
      confirm: true,
    );
    require(repeated.url == receipt.url, 'Idempotent creation receipt');
    final after = (await client.get('/api/blogs?type=note'))['data'] as List;
    require(after.length == 2, 'Confirm creates exactly one note');
    stdout.writeln(
      'PASS real AI SSE, pending draft, explicit confirmation, idempotency and native source',
    );
    session = await assistant.reset(session.id);
    final cancelUpdates = await assistant
        .chat(session: session.id, message: '准备取消草稿', history: [])
        .toList();
    final pending = cancelUpdates.last.drafts.singleWhere(
      (draft) => draft.status == 'pending',
    );
    require(
      (await assistant.resolve(
            session.id,
            pending.id,
            confirm: false,
          )).status ==
          'cancelled',
      'Explicit draft cancellation',
    );
    require(
      ((await client.get('/api/blogs?type=note'))['data'] as List).length == 2,
      'Cancel must not create a note',
    );
    final abort = Completer<void>();
    var gotDelta = false;
    try {
      await for (final event in assistant.chat(
        session: session.id,
        message: 'STOP_FIXTURE',
        history: [],
        abortTrigger: abort.future,
      )) {
        if (event.type == 'delta') {
          gotDelta = true;
          abort.complete();
          break;
        }
      }
    } catch (_) {
      require(gotDelta, 'Cancel after first real delta');
    }
    require(gotDelta, 'Stop fixture must produce a delta');
    var released = false;
    for (var i = 0; i < 30; i++) {
      if (!(await assistant.open()).busy) {
        released = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    require(released, 'Disconnect must release actual backend lease');
    stdout.writeln(
      'PASS real draft cancellation and stream abort releasing backend lease',
    );
  } finally {
    client.close();
  }
}
