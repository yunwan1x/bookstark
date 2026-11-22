import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/share_comment_models.dart';
import 'package:bookstark_flutter/core/share_comments_repository.dart';
import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

Future<void> runPublicSharesContract(BookstarkClient owner) async {
  final public = BookstarkClient(owner.baseUri.toString());
  final repo = RemotePublicSharesRepository(public);
  final notes = RemoteNotesRepository(owner);
  final books = RemoteBooksRepository(owner);
  final docs = RemoteDocumentsRepository(owner);
  final note = await notes.save(
    const Note(
      title: '分享原生阅读契约',
      content: '# 真实公开正文\n\n中文 & %2F',
      labels: ['公开标签'],
    ),
  );
  final book = await books.save(const BookItem(name: '公开目录契约'));
  final foreign = await books.save(const BookItem(name: '其他私有书籍'));
  try {
    final published = await owner.post('/api/shares', {
      'share_type': 'blog',
      'target_id': note,
      'enable_edit': true,
    });
    final identify = published['share_identify'] as String;
    final reference = PublicShareReference(public.baseUri, identify);
    final value = await repo.load(reference);
    check(
      value.targetId == note &&
          value.content.contains('真实公开正文') &&
          !value.locked,
      'Actual anonymous Markdown share',
    );
    await owner.mutate('PUT', '/api/blogs/$note', {
      'new_password': ' fixture-only ',
    });
    final locked = await repo.load(reference);
    check(
      locked.locked && locked.content.isEmpty && locked.labels.isEmpty,
      'Actual protected share masked',
    );
    var rejected = false;
    try {
      await repo.unlock(locked, 'wrong');
    } on ApiFailure {
      rejected = true;
    }
    check(rejected, 'Actual wrong password rejected');
    final unlocked = await repo.unlock(locked, ' fixture-only ');
    check(
      unlocked.unlocked && unlocked.content == value.content,
      'Actual password decrypted once with spaces preserved',
    );
    final protectedLink = PublicEditLink.parse(
      public.baseUri,
      reference.canonicalUri
          .replace(
            queryParameters: {'token': published['edit_token'] as String},
          )
          .toString(),
    );
    final protectedEditor = PublicEditController(
      RemotePublicEditRepository(public),
      protectedLink,
    );
    await protectedEditor.initialize();
    check(
      protectedEditor.phase == PublicEditPhase.locked &&
          protectedEditor.snapshot!.content.isEmpty,
      'Actual protected edit snapshot stays locked',
    );
    await protectedEditor.initialize(password: ' fixture-only ');
    check(
      protectedEditor.phase == PublicEditPhase.ready &&
          protectedEditor.snapshot!.content == value.content,
      'Actual protected editing requires independent password verification',
    );
    await protectedEditor.save('${value.content}\n保护编辑验证');
    check(
      protectedEditor.phase == PublicEditPhase.acknowledged,
      'Actual password-bearing shared PUT and encrypted reread',
    );
    await protectedEditor.save(value.content);
    protectedEditor.close();
    stdout.writeln(
      'PASS protected shared editor: valid link plus separate password, raw password spaces, encrypted PUT and verified body without owner endpoint',
    );
    await runPublicCommentsContract(owner, public, unlocked);
    final root = (await docs.tree(book)).single;
    final created = await docs.create(book, '实际共享章节', parentId: root.id);
    await docs.saveMarkdown(created.id, '# 实际章节内容');
    final other = (await docs.tree(foreign)).single;
    final shared = await owner.post('/api/shares', {
      'share_type': 'book',
      'target_id': book,
    });
    final bookRef = PublicShareReference(
      public.baseUri,
      shared['share_identify'] as String,
    );
    final sharedBook = await repo.load(bookRef);
    final child = sharedBook.nodes.single.children.single;
    final chapter = await repo.chapter(sharedBook, child.identify);
    check(
      chapter.node.id == created.id && chapter.content == '# 实际章节内容',
      'Actual public tree and chapter membership',
    );
    // Read actual identify through owner detail, then deliberately call PUBLIC
    // endpoint to prove backend rejects a cross-book document independently.
    final otherRow = await owner.get('/api/docs/${other.id}');
    final otherIdentify = otherRow['identify'] as String;
    rejected = false;
    try {
      await public.publicShareJson(bookRef.chapterPath(otherIdentify));
    } on ApiFailure catch (e) {
      rejected = e.status == 403;
    }
    check(rejected, 'Public endpoint rejects actual foreign chapter');
    final docShare = await owner.post('/api/shares', {
      'share_type': 'document',
      'target_id': created.id,
      'enable_edit': true,
    });
    final docRef = PublicShareReference(
      public.baseUri,
      docShare['share_identify'] as String,
    );
    final doc = await repo.load(docRef);
    check(
      doc.kind == PublicShareKind.document &&
          doc.targetId == created.id &&
          doc.content == chapter.content,
      'Actual independent document share',
    );
    final editLink = PublicEditLink.parse(
      public.baseUri,
      docRef.canonicalUri
          .replace(queryParameters: {'token': docShare['edit_token'] as String})
          .toString(),
    );
    final editor = PublicEditController(
      RemotePublicEditRepository(public),
      editLink,
    );
    await editor.initialize();
    check(
      editor.snapshot!.detail.targetId == created.id &&
          editor.snapshot!.content == chapter.content,
      'Actual shared editing public context',
    );
    await editor.save('');
    check(
      editor.phase == PublicEditPhase.acknowledged &&
          editor.receipt != null &&
          (await docs.read(created.id)).markdown.isEmpty,
      'Actual shared edit clears body and confirms via GET',
    );
    await docs.saveMarkdown(created.id, '# Other writer');
    await editor.save('# Local proposed');
    check(
      editor.phase == PublicEditPhase.conflict &&
          (await docs.read(created.id)).markdown == '# Other writer',
      'Actual shared edit preflight detects external content without PUT',
    );
    await editor.save('# Local proposed', overwriteObserved: editor.conflict);
    check(
      editor.phase == PublicEditPhase.acknowledged &&
          (await docs.read(created.id)).markdown == '# Local proposed',
      'Explicit observed conflict overwrite uses shared token endpoint',
    );
    await owner.mutate(
      'PATCH',
      '/api/shares/document/${created.id}/edit-token',
      {'action': 'reset'},
    );
    var editRejected = false;
    try {
      await editor.save('# Revoked old token');
    } on ApiFailure catch (e) {
      editRejected = e.status == 403;
    }
    check(
      editRejected &&
          editor.phase == PublicEditPhase.blocked &&
          (await docs.read(created.id)).markdown == '# Local proposed',
      'Reset editing token blocks stale capability without owner bypass',
    );
    editor.close();
    stdout.writeln(
      'PASS shared Markdown editor: actual token context, empty save receipt/reread, external change conflict, explicit overwrite and reset-token rejection',
    );
    await owner.mutate('DELETE', '/api/shares/document/${created.id}', {});
    rejected = false;
    try {
      await repo.load(docRef);
    } on ApiFailure catch (e) {
      rejected = e.status == 404;
    }
    check(rejected, 'Actual revoked document share is unavailable');
    stdout.writeln(
      'PASS anonymous public share repository: Markdown, masked locked fields, wrong/correct password, public book and chapter, cross-book 403, document share and revocation',
    );
  } finally {
    public.close();
    await notes.remove(note);
    await books.remove(book);
    await books.remove(foreign);
  }
}

Future<void> runPublicCommentsContract(
  BookstarkClient owner,
  BookstarkClient anonymous,
  PublicShareDetail detail,
) async {
  final authenticated = RemoteShareCommentsRepository(owner),
      guest = RemoteShareCommentsRepository(anonymous);
  final settings = await owner.get('/api/admin/settings');
  final oldEnabled = settings['share_comments_enabled'] as String? ?? '1';
  final oldMax = settings['share_comment_max_length'] as String? ?? '2000';
  try {
    await owner.mutate('PUT', '/api/admin/settings', {
      'share_comments_enabled': '1',
      'share_comment_max_length': '100',
    });
    final capabilities = await authenticated.capabilities(detail),
        guestCap = await guest.capabilities(detail);
    check(
      capabilities.enabled &&
          capabilities.maxLength == 100 &&
          capabilities.signedIn &&
          !guestCap.signedIn,
      'Actual HTML comment capabilities and account context',
    );
    final root = await authenticated.create(
      detail,
      capabilities,
      const PublicCommentInput(content: '实际公开根评论'),
    );
    final reply = await guest.create(
      detail,
      guestCap,
      PublicCommentInput(
        content: '访客回复 📚',
        author: '明确公开昵称',
        email: 'fixture@example.invalid',
        parentId: root.id,
        replyToId: root.id,
      ),
    );
    check(
      reply.id > 0 &&
          reply.parentId == root.id &&
          reply.rootId == root.id &&
          reply.author == '明确公开昵称' &&
          !reply.canDelete,
      'Actual anonymous reply receipt and public nickname',
    );
    var page = await guest.list(detail, 1);
    check(
      page.totalThreads == 1 &&
          page.items.single.id == root.id &&
          page.items.single.replies.single.id == reply.id,
      'Actual root-thread count and flat reply membership',
    );
    var rejected = false;
    try {
      await anonymous.publicCommentsJson(detail.reference, deleteId: root.id);
    } on ApiFailure catch (e) {
      rejected = e.status == 403;
    }
    check(rejected, 'Anonymous direct comment deletion rejected by server');
    rejected = false;
    try {
      await anonymous.publicCommentsJson(
        detail.reference,
        body: {'content': List.filled(101, '📚').join(), 'author_name': '访客'},
      );
    } on ApiFailure catch (e) {
      rejected = e.status == 400;
    }
    check(
      rejected,
      'Actual configurable Unicode rune limit enforced by server',
    );
    page = await authenticated.list(detail, 1);
    await authenticated.remove(detail, page.items.single);
    page = await authenticated.list(detail, 1);
    check(
      page.items.single.deleted &&
          page.items.single.content.isEmpty &&
          page.items.single.author.isEmpty &&
          page.items.single.replies.single.id == reply.id,
      'Deleted root masks fields while actual replies survive',
    );
    await authenticated.remove(detail, page.items.single.replies.single);
    check(
      (await guest.list(detail, 1)).items.isEmpty,
      'Deleted thread with no visible replies disappears',
    );
    await owner.mutate('PUT', '/api/admin/settings', {
      'share_comments_enabled': '0',
    });
    check(
      !(await guest.capabilities(detail)).enabled &&
          (await guest.list(detail, 1)).items.isEmpty,
      'Actual disabled capability is distinguished from enabled empty comments',
    );
    stdout.writeln(
      'PASS public comments: actual HTML capability/account, configured rune limit, anonymous nickname/reply, root-thread count, delete permission, deleted masking and disabled state',
    );
  } finally {
    await owner.mutate('PUT', '/api/admin/settings', {
      'share_comments_enabled': oldEnabled,
      'share_comment_max_length': oldMax,
    });
  }
}
