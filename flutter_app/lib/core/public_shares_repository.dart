import 'dart:async';
import 'api_client.dart';
import 'public_share_models.dart';

abstract interface class PublicSharesRepository {
  Future<PublicShareDetail> load(
    PublicShareReference reference, {
    Future<void>? abortTrigger,
  });
  Future<PublicShareDetail> unlock(
    PublicShareDetail detail,
    String password, {
    Future<void>? abortTrigger,
  });
  Future<PublicShareChapter> chapter(
    PublicShareDetail book,
    String identify, {
    Future<void>? abortTrigger,
  });
}

class PublicShareChapter {
  const PublicShareChapter({
    required this.node,
    required this.title,
    required this.content,
    required this.format,
    required this.rawAvailable,
  });
  final PublicShareNode node;
  final String title, content, format;
  final bool rawAvailable;
}

class RemotePublicSharesRepository implements PublicSharesRepository {
  RemotePublicSharesRepository(this.client);
  final BookstarkClient client;
  void _check(PublicShareReference reference) {
    if (reference.server != client.baseUri) {
      throw const FormatException('Public share belongs to another server');
    }
  }

  @override
  Future<PublicShareDetail> load(
    PublicShareReference reference, {
    Future<void>? abortTrigger,
  }) async {
    _check(reference);
    final detail = PublicShareDetail.fromJson(
      reference,
      await client.publicShareJson(
        reference.detailPath,
        abortTrigger: abortTrigger,
      ),
    );
    if (detail.html && !detail.locked) {
      if (!detail.rawAvailable) {
        throw const FormatException('Missing public HTML raw endpoint');
      }
      return detail.withHtmlContent(
        await client.publicShareHtmlSource(
          reference,
          abortTrigger: abortTrigger,
        ),
      );
    }
    return detail;
  }

  @override
  Future<PublicShareDetail> unlock(
    PublicShareDetail detail,
    String password, {
    Future<void>? abortTrigger,
  }) async {
    _check(detail.reference);
    if (!detail.locked ||
        detail.kind != PublicShareKind.blog ||
        !(detail.markdown || detail.html)) {
      throw StateError('Unsupported public unlock format');
    }
    if (password.isEmpty || password.length > 4096) {
      throw const FormatException('Invalid share password');
    }
    if (detail.html) {
      final source = await client.publicShareHtmlSource(
        detail.reference,
        password: password,
        abortTrigger: abortTrigger,
      );
      return detail.withHtmlContent(source, unlocking: true);
    }
    final row = await client.publicShareJson(
      '${detail.reference.detailPath}/verify-password',
      passwordBody: {'password': password},
      abortTrigger: abortTrigger,
    );
    final content = row['content'];
    if (content is! String) {
      throw const FormatException('Missing decrypted public content');
    }
    return detail.unlockMarkdown(content);
  }

  @override
  Future<PublicShareChapter> chapter(
    PublicShareDetail book,
    String identify, {
    Future<void>? abortTrigger,
  }) async {
    _check(book.reference);
    if (book.kind != PublicShareKind.book || book.locked) {
      throw StateError('Not an accessible public book');
    }
    PublicShareNode? find(List<PublicShareNode> nodes) {
      for (final node in nodes) {
        if (node.identify == identify) return node;
        final child = find(node.children);
        if (child != null) return child;
      }
      return null;
    }

    final node = find(book.nodes);
    if (node == null) {
      throw const FormatException('Chapter is outside the loaded public book');
    }
    final row = await client.publicShareJson(
      book.reference.chapterPath(identify),
      abortTrigger: abortTrigger,
    );
    // Reuse the strict content/format parser with the known public membership.
    // The endpoint returns no ID: never manufacture a private owner record.
    final parsed = PublicShareDetail.fromJson(book.reference, {
      'share_type': 'document',
      'share_id': book.shareId,
      'target_id': node.id,
      'share_identify': book.reference.identify,
      'has_password': false,
      'title': row['title'],
      'doc_type': row['doc_type'],
      'content': row['content'],
    });
    var raw = false;
    if ({'html', 'richdoc'}.contains(parsed.format) &&
        row['content_url'] != null) {
      if (row['content_url'] is! String) {
        throw const FormatException('Invalid public chapter raw URL');
      }
      book.reference.validateRawPath(
        row['content_url'] as String,
        chapterIdentify: identify,
      );
      raw = true;
    }
    if (parsed.html && !raw) {
      throw const FormatException('Missing public chapter HTML raw endpoint');
    }
    final content = parsed.html
        ? await client.publicShareHtmlSource(
            book.reference,
            chapterIdentify: identify,
            abortTrigger: abortTrigger,
          )
        : parsed.content;
    return PublicShareChapter(
      node: node,
      title: parsed.title,
      content: content,
      format: parsed.format,
      rawAvailable: raw,
    );
  }
}
