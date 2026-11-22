// Explicit Android fixture utility, never part of the default test/ suite.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/core/share_comment_models.dart';
import 'package:bookstark_flutter/core/share_comments_repository.dart';

void main() {
  test('seed only the explicit empty Android API fixture', () async {
    final path = Platform.environment['BOOKSTARK_ANDROID_FIXTURE_CONFIG'];
    if (path == null ||
        !path.startsWith(
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-live-fixture/',
        )) {
      throw StateError('Run the isolated Android fixture host');
    }
    final file = File(path),
        config = Map<String, Object?>.from(
          jsonDecode(await File(path).readAsString()) as Map,
        );
    final base = Uri.parse(config['local_base'] as String);
    if (config['fixture'] != true ||
        base.host != '127.0.0.1' ||
        base.scheme != 'http') {
      throw StateError(
        'Android seeding is restricted to the owned loopback fixture',
      );
    }
    final client = BookstarkClient(base.toString())..language = 'zh';
    try {
      await client.login(
        config['account'] as String,
        config['password'] as String,
      );
      final profile = await client.get('/api/profile'),
          member = profile['member_id'] as int;
      final articles = RemoteNotesRepository(
        client,
        collection: NoteCollection.article,
      );
      final notes = RemoteNotesRepository(client);
      final article = await articles.save(
        const Note(
          title: 'Android public article',
          content:
              '# Native public reader\n\nReal isolated Go content.\n\n- Public Markdown\n- Native selection',
          labels: ['android-fixture'],
        ),
      );
      final published = await client.post('/api/shares', {
        'share_type': 'blog',
        'target_id': article,
        'enable_edit': true,
      });
      final protected = await notes.save(
        const Note(
          title: 'Android protected share',
          content: '# Native protected reader\n\nPassword verified content.',
        ),
      );
      final protectedShare = await client.post('/api/shares', {
        'share_type': 'blog',
        'target_id': protected,
        'enable_edit': true,
      });
      await client.mutate('PUT', '/api/blogs/$protected', {
        'new_password': config['share_password'],
      });
      final books = RemoteBooksRepository(client),
          docs = RemoteDocumentsRepository(client);
      final book = await books.save(
        const BookItem(name: 'Android shared book'),
      );
      final parent = (await docs.tree(book)).single;
      await docs.rename(parent.id, 'Android parent chapter');
      await docs.saveMarkdown(
        parent.id,
        '# Native parent chapter\n\nParent documents remain readable.',
      );
      final child = await docs.create(
        book,
        'Android child chapter',
        parentId: parent.id,
      );
      await docs.saveMarkdown(
        child.id,
        '# Native child chapter\n\nActual shared chapter membership.',
      );
      final bookShare = await client.post('/api/shares', {
        'share_type': 'book',
        'target_id': book,
      });
      final bookmarks = RemoteBookmarksRepository(
        client,
        memberId: member,
        isAdmin: true,
      );
      await bookmarks.save(
        const BookmarkItem(
          title: 'Android external bookmark',
          url: 'https://example.invalid/android-fixture',
          isPublic: true,
        ),
      );
      final localRef = PublicShareReference(
        client.baseUri,
        published['share_identify'] as String,
      );
      final detail = await RemotePublicSharesRepository(client).load(localRef);
      final comments = RemoteShareCommentsRepository(client);
      final capability = await comments.capabilities(detail);
      await comments.create(
        detail,
        capability,
        const PublicCommentInput(content: 'Native seeded public comment'),
      );
      final external = Uri.parse(config['server'] as String);
      Uri public(Map<String, Object?> row) => PublicShareReference(
        external,
        row['share_identify'] as String,
      ).canonicalUri;
      await file.writeAsString(
        jsonEncode({
          ...config,
          'seeded': true,
          'article_id': article,
          'protected_id': protected,
          'book_id': book,
          'parent_id': parent.id,
          'child_id': child.id,
          'article_identify': published['share_identify'],
          'protected_identify': protectedShare['share_identify'],
          'book_identify': bookShare['share_identify'],
          'article_url': public(published).toString(),
          'book_url': public(bookShare).toString(),
          'edit_url': public(published)
              .replace(
                queryParameters: {'token': published['edit_token'] as String},
              )
              .toString(),
          'protected_edit_url': public(protectedShare)
              .replace(
                queryParameters: {
                  'token': protectedShare['edit_token'] as String,
                },
              )
              .toString(),
        }),
      );
    } finally {
      client.close();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}
