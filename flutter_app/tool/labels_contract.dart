import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/label_management_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';

void _require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> runLabelsContract(BookstarkClient client, int memberId) async {
  final labels = RemoteLabelManagementRepository(client, canManage: true);
  final books = RemoteBooksRepository(client),
      documents = RemoteDocumentsRepository(client);
  final notes = RemoteNotesRepository(client),
      articles = RemoteNotesRepository(
        client,
        collection: NoteCollection.article,
      );
  final bookmarks = RemoteBookmarksRepository(
    client,
    memberId: memberId,
    isAdmin: true,
  );
  final target = await labels.save('标签契约-目标'),
      source = await labels.save('标签契约-源'),
      documentLabel = await labels.save('标签契约-文档'),
      unused = await labels.save('标签契约-未使用');
  final bookId = await books.save(
    BookItem(name: '标签契约书籍', labels: [target.name, source.name]),
  );
  final noteId = await notes.save(
    Note(title: '标签契约笔记', content: '# 保留正文', labels: [source.name]),
  );
  final articleId = await articles.save(
    Note(title: '标签契约文章', content: '# 保留文章', labels: [source.name]),
  );
  final bookmarkId = await bookmarks.save(
    BookmarkItem(
      title: '标签契约书签',
      url: 'https://example.invalid/labels-contract',
      labels: [source.name],
    ),
  );
  await bookmarks.setNavVisible(bookmarkId, true);
  final documentId = (await documents.tree(bookId)).single.id;
  await client.mutate('PUT', '/api/labels/resource/document/$documentId', {
    'labels': documentLabel.name,
  });
  final documentDetail = await labels.read(documentLabel.id);
  _require(
    documentDetail.items.any(
          (item) =>
              item.type == LabelResourceType.document && item.id == documentId,
        ) &&
        !documentDetail.verifiedUnused,
    'Document-only label is in use',
  );
  _require(
    documentDetail.label.bookCount +
            documentDetail.label.blogCount +
            documentDetail.label.bookmarkCount ==
        0,
    'Document associations are absent from three counters',
  );
  final docPage = await labels.list(
    LabelManagementQuery(keyword: documentLabel.name),
  );
  _require(
    docPage.total == 1 && docPage.used == 1 && docPage.unused == 0,
    'Filtered global statistics include document associations',
  );
  _require(
    await labels.removeUnused() >= 1,
    'Unused global cleanup reports true deleted count',
  );
  _require(
    (await labels.list(
      LabelManagementQuery(keyword: unused.name),
    )).items.isEmpty,
    'Unused label removed',
  );
  _require(
    (await labels.read(documentLabel.id)).items.isNotEmpty,
    'Document-only label survives unused cleanup',
  );
  final renamed = await labels.save('标签契约-改名', id: source.id);
  _require(
    renamed.id == source.id && renamed.name == '标签契约-改名',
    'Rename retains actual ID',
  );
  _require(
    (await notes.read(noteId)).labels.contains(renamed.name),
    'Renamed association resolves actual label name',
  );
  await labels.merge(target.id, [source.id]);
  final detail = await labels.read(target.id);
  _require(
    detail.label.bookCount == 1 &&
        detail.label.blogCount == 2 &&
        detail.label.bookmarkCount == 1,
    'Merge deduplicates book link and retains both blog collections',
  );
  _require(
    (await books.read(
          bookId,
        )).labels.where((name) => name == target.name).length ==
        1,
    'Merged book tag appears once',
  );
  _require(
    (await labels.list(
      LabelManagementQuery(keyword: renamed.name),
    )).items.isEmpty,
    'Merge removes actual source label',
  );
  final bookmark = (await bookmarks.read(bookmarkId));
  _require(
    bookmark.navVisible && bookmark.labels.contains(target.name),
    'Canonical bookmark read preserves navigation metadata after merge',
  );
  final saved = await labels.recommendationSettings();
  try {
    final candidate = LabelRecommendationSettings(
      strategy: LabelRecommendationStrategy.manual,
      manualLabels: [target.name],
      pageSize: 1,
    );
    final preview = await labels.recommendations(candidate);
    _require(
      preview.length == 1 && preview.single.id == target.id,
      'Manual preview uses actual tag identity',
    );
    final unchanged = await labels.recommendationSettings();
    _require(
      unchanged.strategy == saved.strategy &&
          unchanged.pageSize == saved.pageSize,
      'Preview does not persist configuration',
    );
    await labels.saveRecommendationSettings(candidate);
    final actual = await labels.recommendationSettings();
    _require(
      actual.strategy == LabelRecommendationStrategy.manual &&
          actual.manualLabels.single == target.name &&
          actual.pageSize == 1,
      'Recommendation settings round trip',
    );
  } finally {
    await labels.saveRecommendationSettings(saved);
  }
  final noteRef = detail.items.singleWhere(
    (item) => item.type == LabelResourceType.blog && item.id == noteId,
  );
  await labels.unbind(target.id, noteRef);
  _require(
    (await labels.read(target.id)).label.blogCount == 1,
    'Unbind affects exact typed resource only',
  );
  _require(
    (await notes.read(noteId)).content == '# 保留正文',
    'Unbind preserves source content',
  );
  await labels.remove(target.id);
  await labels.remove(documentLabel.id);
  _require(
    (await articles.read(articleId)).content == '# 保留文章',
    'Delete label preserves source article',
  );
  _require(
    (await bookmarks.read(bookmarkId)).navVisible,
    'Delete label preserves bookmark flags',
  );
  await notes.remove(noteId);
  await articles.remove(articleId);
  await bookmarks.remove(bookmarkId);
  await books.remove(bookId);
}
