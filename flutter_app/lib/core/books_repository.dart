import 'dart:convert';
import 'api_client.dart';
import 'resource_labels.dart';

class BookItem {
  const BookItem({
    this.id,
    required this.name,
    this.description = '',
    this.identify = '',
    this.documentCount = 0,
    this.labelText = '',
    this.labels = const [],
    this.labelsLoaded = true,
    this.modifiedAt,
  });
  final int? id;
  final String name, description, identify, labelText;
  final int documentCount;
  final List<String> labels;
  final bool labelsLoaded;
  final DateTime? modifiedAt;

  BookItem copyWith({
    int? id,
    String? name,
    String? description,
    List<String>? labels,
  }) => BookItem(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    identify: identify,
    documentCount: documentCount,
    labelText: labelText,
    labels: labels ?? this.labels,
    labelsLoaded: labels != null || labelsLoaded,
    modifiedAt: modifiedAt,
  );

  factory BookItem.fromJson(Map row, {required bool detail}) => BookItem(
    id: row['book_id'] as int,
    name: row['book_name'] as String? ?? '',
    description: row['description'] as String? ?? '',
    identify: row['identify'] as String? ?? '',
    documentCount: row['doc_count'] as int? ?? 0,
    labelText: row['label'] as String? ?? '',
    labels: detail
        ? List<String>.unmodifiable(
            (row['labels'] as List? ?? []).cast<String>(),
          )
        : const [],
    labelsLoaded: detail,
    modifiedAt: DateTime.tryParse(row['modify_time'] as String? ?? ''),
  );

  Map<String, Object?> writeBody() {
    if (!labelsLoaded) {
      throw StateError('请先加载书籍详情 / Load book details before saving');
    }
    if (name.trim().isEmpty ||
        utf8.encode(name).length > 200 ||
        utf8.encode(description).length > 2000) {
      throw const FormatException(
        '书名必填，最多200字节；说明最多2000字节 / Name is required (200 UTF-8 bytes); description: 2000 bytes',
      );
    }
    return {
      'book_name': name,
      'description': description,
      'labels': encodeResourceLabels(labels),
    };
  }
}

class BooksPageResult {
  const BooksPageResult(this.items, this.total, this.page, this.pageSize);
  final List<BookItem> items;
  final int total, page, pageSize;
  bool get hasMore => page * pageSize < total;
}

abstract interface class BooksRepository {
  Future<BooksPageResult> list({String keyword = '', int page = 1});
  Future<BookItem> read(int id);
  Future<int> save(BookItem book);
  Future<void> remove(int id);
}

class BookSaveFailure implements Exception {
  const BookSaveFailure(this.savedId, this.cause);
  final int savedId;
  final Object cause;
  @override
  String toString() =>
      '书籍已保存，标签待同步 / Book saved; retry label synchronization: $cause';
}

class RemoteBooksRepository implements BooksRepository {
  RemoteBooksRepository(this.client);
  final BookstarkClient client;
  @override
  Future<BooksPageResult> list({String keyword = '', int page = 1}) async {
    if (page < 1) throw const FormatException('Invalid page');
    final row = await client.get(
      '/api/books?${Uri(queryParameters: {'page': '$page', 'keyword': keyword}).query}',
    );
    final size = row['page_size'] as int;
    if (size < 1) throw const FormatException('Invalid page size');
    return BooksPageResult(
      (row['data'] as List? ?? [])
          .map((item) => BookItem.fromJson(item as Map, detail: false))
          .toList(),
      row['total'] as int,
      row['page'] as int,
      size,
    );
  }

  @override
  Future<BookItem> read(int id) async {
    final book = BookItem.fromJson(
      await client.get('/api/books/$id'),
      detail: true,
    );
    if (book.id != id) throw const FormatException('Book ID mismatch');
    return book;
  }

  @override
  Future<int> save(BookItem book) async {
    final body = book.writeBody();
    final int id;
    if (book.id == null) {
      final result = await client.post('/api/books', body);
      id = result['book_id'] as int;
    } else {
      id = book.id!;
      await client.mutate('PUT', '/api/books/$id', body);
    }
    try {
      await client.mutate('PUT', '/api/labels/resource/book/$id', {
        'labels': body['labels'],
      });
      final result = await client.get('/api/labels/resource/book/$id');
      final actual = (result['data'] as List? ?? []).cast<String>().toSet();
      final expected = book.labels.toSet();
      if (actual.length != expected.length || !actual.containsAll(expected)) {
        throw StateError('标签同步结果不一致 / Label verification failed');
      }
    } catch (error) {
      throw BookSaveFailure(id, error);
    }
    return id;
  }

  @override
  Future<void> remove(int id) async {
    await client.mutate('DELETE', '/api/books/$id', {});
  }
}
