import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';

void validateDocumentName(String name) {
  if (name.trim().isEmpty || utf8.encode(name).length > 200) {
    throw const FormatException(
      '文档名称必填，最多200 UTF-8字节 / Document name: 1–200 UTF-8 bytes',
    );
  }
}

class DocumentNode {
  const DocumentNode({
    required this.id,
    required this.name,
    this.parentId = 0,
    this.order = 0,
    this.type = 'markdown',
    this.children = const [],
  });
  final int id, parentId, order;
  final String name, type;
  final List<DocumentNode> children;
}

/// Bound malformed/deep input and reject duplicated IDs rather than losing or
/// mutating ambiguous documents. The backend's tree response has no book_id.
List<DocumentNode> decodeDocumentTree(List rows) {
  final seen = <int>{};
  List<DocumentNode> decode(List rows, int parent, int depth) {
    if (depth > 256) throw const FormatException('Document tree too deep');
    return rows.map((value) {
      final row = value as Map;
      final id = row['document_id'] as int;
      if (id <= 0 ||
          !seen.add(id) ||
          (row['parent_id'] as int? ?? 0) != parent) {
        throw const FormatException('Invalid document tree relationship');
      }
      return DocumentNode(
        id: id,
        name: row['document_name'] as String? ?? '',
        parentId: parent,
        order: row['order_sort'] as int? ?? 0,
        type: row['doc_type'] as String? ?? 'markdown',
        children: decode(row['children'] as List? ?? [], id, depth + 1),
      );
    }).toList();
  }

  return decode(rows, 0, 0);
}

List<DocumentNode> flattenDocuments(List<DocumentNode> roots) => [
  for (final node in roots) ...[node, ...flattenDocuments(node.children)],
];

class DocumentItem {
  const DocumentItem({
    required this.id,
    required this.bookId,
    required this.name,
    this.parentId = 0,
    this.markdown = '',
    this.type = 'markdown',
    this.previousId = 0,
    this.nextId = 0,
    this.modifiedAt = '',
    this.contentUrl,
    this.contentEncoding,
    this.contentCompressed,
  });
  final int id, bookId, parentId, previousId, nextId;
  final String name, markdown, type, modifiedAt;
  final String? contentUrl, contentEncoding;
  final bool? contentCompressed;
  factory DocumentItem.fromJson(Map row) => DocumentItem(
    id: row['document_id'] as int,
    bookId: row['book_id'] as int,
    name: row['document_name'] as String? ?? '',
    parentId: row['parent_id'] as int? ?? 0,
    markdown: row['markdown'] as String? ?? '',
    type: row['doc_type'] as String? ?? 'markdown',
    previousId: row['prev_id'] as int? ?? 0,
    nextId: row['next_id'] as int? ?? 0,
    modifiedAt: row['modify_time'] as String? ?? '',
    contentUrl: row['content_url'] as String?,
    contentEncoding: row['content_encoding'] as String?,
    contentCompressed: row['content_compressed'] as bool?,
  );
}

abstract interface class DocumentsRepository {
  Future<List<DocumentNode>> tree(int bookId);
  Future<DocumentItem> read(int id);
  Future<DocumentItem> create(int bookId, String name, {int parentId = 0});
  Future<void> rename(int id, String name);
  Future<void> saveMarkdown(int id, String markdown);
  Future<void> remove(int id);
  Future<void> reorder(int id, String direction);
  Future<void> move(int bookId, int id, int parentId, {int order = 0});
}

class RemoteDocumentsRepository implements DocumentsRepository {
  RemoteDocumentsRepository(this.client);
  final BookstarkClient client;
  @override
  Future<List<DocumentNode>> tree(int bookId) async => decodeDocumentTree(
    (await client.get('/api/books/$bookId/docs/tree'))['data'] as List? ?? [],
  );
  @override
  Future<DocumentItem> read(int id) async {
    final item = DocumentItem.fromJson(await client.get('/api/docs/$id'));
    if (item.id != id) throw const FormatException('Document ID mismatch');
    return item;
  }

  @override
  Future<DocumentItem> create(
    int bookId,
    String name, {
    int parentId = 0,
  }) async {
    validateDocumentName(name);
    if (parentId < 0) throw const FormatException('Invalid parent');
    if (parentId != 0 &&
        !flattenDocuments(
          await tree(bookId),
        ).any((node) => node.id == parentId)) {
      throw StateError('父文档不属于本书 / Parent does not belong to this book');
    }
    // POST itself returns the complete created record. Do not add a fallible
    // follow-up read that could hide the real ID and cause duplicate retries.
    return DocumentItem.fromJson(
      await client.post('/api/books/$bookId/docs', {
        'document_name': name,
        'parent_id': parentId,
        'doc_type': 'markdown',
      }),
    );
  }

  @override
  Future<void> rename(int id, String name) async {
    validateDocumentName(name);
    await client.mutate('PUT', '/api/docs/$id', {'document_name': name});
  }

  @override
  Future<void> saveMarkdown(int id, String markdown) async {
    if (utf8.encode(markdown).length > 500000) {
      throw const FormatException('Markdown exceeds 500000 UTF-8 bytes');
    }
    final item = await read(id);
    if (item.type != 'markdown') {
      throw StateError('该文档需要对应原生编辑器 / A dedicated editor is required');
    }
    // Empty markdown is only written by the legacy API when name is omitted.
    await client.mutate('PUT', '/api/docs/$id', {'markdown': markdown});
  }

  @override
  Future<void> remove(int id) async {
    await client.mutate('DELETE', '/api/docs/$id', {});
  }

  @override
  Future<void> reorder(int id, String direction) async {
    if (!{'up', 'down', 'indent', 'outdent'}.contains(direction)) {
      throw const FormatException('Invalid direction');
    }
    await client.mutate('PATCH', '/api/docs/$id/reorder', {
      'direction': direction,
    });
  }

  @override
  Future<void> move(int bookId, int id, int parentId, {int order = 0}) async {
    final nodes = flattenDocuments(await tree(bookId));
    final matches = nodes.where((node) => node.id == id);
    if (matches.isEmpty) {
      throw StateError('文档不属于本书 / Document not in this book');
    }
    final forbidden = flattenDocuments([
      matches.single,
    ]).map((node) => node.id).toSet();
    if (parentId < 0 ||
        forbidden.contains(parentId) ||
        (parentId != 0 && !nodes.any((node) => node.id == parentId))) {
      throw StateError('无效父章节 / Invalid parent chapter');
    }
    await client.mutate('PATCH', '/api/docs/$id/move', {
      'parent_id': parentId,
      'order_sort': order,
    });
  }
}

/// Separate optional capability: old DocumentsRepository overrides stay valid.
abstract interface class BoundedDocumentsReader {
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  });
}

const documentMarkdownEditBytes = 500000;
const documentReadMaxBytes = 20 * 1024 * 1024;

class DocumentReadLimit implements Exception {
  const DocumentReadLimit(this.id, this.type, this.actualBytes, this.maxBytes);
  final int id, actualBytes, maxBytes;
  final String type;
}

class TypedDocumentRead {
  const TypedDocumentRead({
    required this.item,
    required this.byteLength,
    required this.source,
  });
  final DocumentItem item;
  final int byteLength;
  final String source;
  bool get largeMarkdown =>
      item.type == 'markdown' && byteLength > documentMarkdownEditBytes;
}

int documentBodyBudget(String type, int markdownBudget) {
  if (markdownBudget < 0 || markdownBudget > documentReadMaxBytes) {
    throw ArgumentError('Explicit bounded Markdown read budget required');
  }
  if (type == 'markdown') return markdownBudget;
  if ({'html', 'spreadsheet', 'drawing', 'mindmap', 'richdoc'}.contains(type)) {
    return 5 * 1024 * 1024;
  }
  // Unknown legacy types remain source-only; never grant editing.
  return documentReadMaxBytes;
}
