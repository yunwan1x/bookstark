import 'local_search_metadata_reader.dart';
import 'local_search_content_reader.dart';
import 'local_store.dart';
import 'local_search_body_scan.dart';
import 'search_repository.dart';
import 'search_matching.dart';

class LocalSearchRepository implements SearchRepository {
  LocalSearchRepository(this.store, {this.isCurrent});
  final LocalStore store;
  final bool Function()? isCurrent;
  void _guard() {
    if (store.maintenance.retired || !(isCurrent?.call() ?? true)) {
      throw StateError('Local search owner retired');
    }
  }

  @override
  Future<SearchResults> search(String query) => store.maintenance.use(() async {
    _guard();
    final q = normalizeSearchQuery(query);
    final escaped = q
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
    final like = '%$escaped%';
    _guard();
    final db = await store.database;
    _guard();
    return db.transaction((tx) async {
      _guard();
      final textReader=LocalSearchContentReader(guard:_guard);
      final metadata=LocalSearchMetadataReader(textReader,guard:_guard);
      // Same transaction: a failed/retired search never leaves partial discovery.
      await metadata.synchronizeLabels(tx);

      final groups = <SearchKind, List<SearchHit>>{};
      void collect(
        SearchKind kind,
        List<Map<String, Object?>> rows,
        List<String> Function(Map<String, Object?>) fields,
        Map<String, Object?> Function(Map<String, Object?>) convert,
      ) {
        final hits = <SearchHit>[];
        for (final row in rows) {
          if (isAsciiSearchWord(q) &&
              !fields(row).any((text) => matchesSearchWord(text, q))) {
            continue;
          }
          hits.add(SearchHit.fromJson(kind, convert(row)));
        }
        groups[kind] = hits;
      }

      final docs = metadata.decode(await tx.rawQuery(
        r"SELECT d.document_id AS id,length(CAST(d.markdown AS BLOB)) AS body_bytes,CASE WHEN length(CAST(d.document_name AS BLOB))<=4096 THEN CAST(d.document_name AS BLOB) ELSE NULL END AS name,CASE WHEN length(CAST(d.identify AS BLOB))<=4096 THEN CAST(d.identify AS BLOB) ELSE NULL END AS identify,CASE WHEN length(CAST(d.doc_type AS BLOB))<=64 THEN CAST(d.doc_type AS BLOB) ELSE NULL END AS doc_type,CASE WHEN (substr(CAST(d.markdown AS BLOB),1,4)=X'454E433A' OR substr(CAST(d.markdown AS BLOB),1,7)=X'EFBBBF454E433A') THEN 1 ELSE 0 END AS protected,CASE WHEN length(CAST(b.book_name AS BLOB))<=4096 THEN CAST(b.book_name AS BLOB) ELSE NULL END AS book_name,CASE WHEN length(CAST(b.identify AS BLOB))<=4096 THEN CAST(b.identify AS BLOB) ELSE NULL END AS book_identify FROM documents d JOIN books b ON b.book_id=d.book_id WHERE d.deleted=0 AND b.deleted=0 AND (d.document_name LIKE ? ESCAPE '\' OR (d.doc_type!='html' AND NOT (substr(CAST(d.markdown AS BLOB),1,4)=X'454E433A' OR substr(CAST(d.markdown AS BLOB),1,7)=X'EFBBBF454E433A') AND d.markdown LIKE ? ESCAPE '\')) ORDER BY d.modify_time DESC,d.document_id DESC LIMIT 20",
        [like, like],
      ),const {'name':4096,'identify':4096,'doc_type':64,'book_name':4096,'book_identify':4096});
      final documentHits = <SearchHit>[];
      for (final row in docs) {
        final body = row['doc_type'] == 'html' || row['protected'] == 1
            ? const LocalSearchBodyScan(wholeWord:false,snippet:'')
            : await LocalSearchBodyScan.read(tx,id:row['id'] as int,query:q,guard:_guard);
        if (isAsciiSearchWord(q) &&
            !matchesSearchWord(row['name'] as String, q) &&
            !body.wholeWord) {
          continue;
        }
        documentHits.add(
          SearchHit.fromJson(SearchKind.document, {
            ...row,
            'snippet': body.snippet,
          }),
        );
      }
      groups[SearchKind.document] = documentHits;
      final blogs = metadata.decode(await tx.rawQuery(
        r"SELECT id,CASE WHEN length(CAST(title AS BLOB))<=4096 THEN CAST(title AS BLOB) ELSE NULL END AS title,length(CAST(content AS BLOB)) AS body_bytes,CASE WHEN (substr(CAST(content AS BLOB),1,4)=X'454E433A' OR substr(CAST(content AS BLOB),1,7)=X'EFBBBF454E433A') THEN 1 ELSE 0 END AS protected,CASE WHEN length(CAST(editor_type AS BLOB))<=64 THEN CAST(editor_type AS BLOB) ELSE NULL END AS editor_type,CASE WHEN length(CAST(collection AS BLOB))<=32 THEN CAST(collection AS BLOB) ELSE NULL END AS blog_type FROM notes WHERE deleted=0 AND (title LIKE ? ESCAPE '\' OR (editor_type!='html' AND NOT (substr(CAST(content AS BLOB),1,4)=X'454E433A' OR substr(CAST(content AS BLOB),1,7)=X'EFBBBF454E433A') AND content LIKE ? ESCAPE '\')) ORDER BY updated_at DESC,id DESC LIMIT 20",
        [like, like],
      ),const {'title':4096,'editor_type':64,'blog_type':32});
      final blogHits = <SearchHit>[];
      for (final row in blogs) {
        final protected = row['protected'] == 1;
        final body = protected || row['editor_type'] == 'html'
            ? const LocalSearchBodyScan(wholeWord:false,snippet:'')
            : await LocalSearchBodyScan.read(tx,id:row['id'] as int,query:q,guard:_guard,
                collection:row['blog_type'] as String,editorType:row['editor_type'] as String);
        if (isAsciiSearchWord(q) &&
            !matchesSearchWord(row['title'] as String, q) &&
            !body.wholeWord) {
          continue;
        }
        blogHits.add(
          SearchHit.fromJson(SearchKind.blog, {
            ...row,
            'snippet': body.snippet,
          }),
        );
      }
      groups[SearchKind.blog] = blogHits;
      final books = metadata.decode(await tx.rawQuery(
        r"SELECT book_id AS id,CASE WHEN length(CAST(book_name AS BLOB))<=4096 THEN CAST(book_name AS BLOB) ELSE NULL END AS name,CASE WHEN length(CAST(identify AS BLOB))<=4096 THEN CAST(identify AS BLOB) ELSE NULL END AS identify,CASE WHEN length(CAST(description AS BLOB))<=65536 THEN CAST(description AS BLOB) ELSE NULL END AS description,doc_count FROM books WHERE deleted=0 AND (book_name LIKE ? ESCAPE '\' OR description LIKE ? ESCAPE '\') ORDER BY modify_time DESC,book_id DESC LIMIT 20",
        [like, like],
      ),const {'name':4096,'identify':4096,'description':65536});
      collect(
        SearchKind.book,
        books,
        (row) => [row['name'] as String, row['description'] as String],
        (row) => row,
      );
      final bookmarks = metadata.decode(await tx.rawQuery(
        r"SELECT bookmark_id AS id,CASE WHEN length(CAST(title AS BLOB))<=4096 THEN CAST(title AS BLOB) ELSE NULL END AS title,CASE WHEN length(CAST(url AS BLOB))<=16384 THEN CAST(url AS BLOB) ELSE NULL END AS url,CASE WHEN length(CAST(description AS BLOB))<=65536 THEN CAST(description AS BLOB) ELSE NULL END AS description FROM bookmarks WHERE deleted=0 AND (title LIKE ? ESCAPE '\' OR url LIKE ? ESCAPE '\' OR description LIKE ? ESCAPE '\') ORDER BY modify_time DESC,bookmark_id DESC LIMIT 20",
        [like, like, like],
      ),const {'title':4096,'url':16384,'description':65536});
      collect(
        SearchKind.bookmark,
        bookmarks,
        (row) => [
          row['title'] as String,
          row['url'] as String,
          row['description'] as String,
        ],
        (row) => row,
      );
      final labels = metadata.decode(await tx.rawQuery(
        r"SELECT label_id AS id,CASE WHEN length(CAST(label_name AS BLOB))<=65536 THEN CAST(label_name AS BLOB) ELSE NULL END AS name FROM local_labels WHERE label_name LIKE ? ESCAPE '\' ORDER BY label_name LIMIT 20",
        [like],
      ),const {'name':65536});
      collect(
        SearchKind.label,
        labels,
        (row) => [row['name'] as String],
        (row) => row,
      );
      final tasks = metadata.decode(await tx.rawQuery(
        r"SELECT task_id AS id,CASE WHEN length(CAST(content AS BLOB))<=65536 THEN CAST(content AS BLOB) ELSE NULL END AS content,CASE WHEN length(CAST(due_date AS BLOB))<=64 THEN CAST(due_date AS BLOB) ELSE NULL END AS due_date,done,parent_id FROM tasks WHERE deleted=0 AND content LIKE ? ESCAPE '\' ORDER BY modify_time DESC,task_id DESC LIMIT 20",
        [like],
      ),const {'content':65536,'due_date':64});
      collect(
        SearchKind.task,
        tasks,
        (row) => [row['content'] as String],
        (row) => {
          ...row,
          'done': row['done'] == 1,
          'snippet': searchSnippet(row['content'] as String, q),
        },
      );
      final topics = metadata.decode(await tx.rawQuery(
        r"""SELECT t.topic_id AS id,CASE WHEN length(CAST(t.title AS BLOB))<=4096 THEN CAST(t.title AS BLOB) ELSE NULL END AS title,
        (SELECT COUNT(*) FROM topic_resources r WHERE r.topic_id=t.topic_id) AS item_count
        FROM topics t WHERE t.deleted=0 AND (t.title LIKE ? ESCAPE '\' OR t.question LIKE ? ESCAPE '\'
        OR EXISTS(SELECT 1 FROM topic_summaries s WHERE s.topic_id=t.topic_id AND s.content LIKE ? ESCAPE '\')
        OR EXISTS(SELECT 1 FROM topic_resources r WHERE r.topic_id=t.topic_id AND (r.title_snapshot LIKE ? ESCAPE '\' OR r.desc_snapshot LIKE ? ESCAPE '\'))
        OR EXISTS(SELECT 1 FROM tasks task WHERE task.topic_id=t.topic_id AND task.deleted=0 AND task.content LIKE ? ESCAPE '\'))
        ORDER BY t.modify_time DESC,t.topic_id DESC LIMIT 20""",
        List.filled(6, like),
      ),const {'title':4096});
      final topicHits=<SearchHit>[];
      for(final row in topics){
        final id=row['id'];
        if(id is! int||id<=0)throw const FormatException('Actual topic ID required');
        final content=await textReader.topicContext(tx,id);
        if(isAsciiSearchWord(q)&&!matchesSearchWord(row['title'] as String,q)&&
           !matchesSearchWord(content.context,q)) {
          continue;
        }
        topicHits.add(SearchHit.fromJson(SearchKind.topic,{
          ...row,'question':content.question,'snippet':searchSnippet(content.context,q)}));
      }
      groups[SearchKind.topic]=topicHits;
      _guard();
      return SearchResults(query: q, groups: groups);
    });
  });
}
