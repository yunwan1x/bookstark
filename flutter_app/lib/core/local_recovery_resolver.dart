import 'dart:convert';
import 'local_assistant_draft_payload.dart';
import 'local_assistant_editor_drafts.dart';
import 'local_assistant_write_journal.dart';
import 'complex_editor_document.dart';
import 'complex_recovery_store.dart';
import 'complex_recovery_vault.dart';
import 'local_complex_notes_repository.dart';
import 'local_html_scope.dart';
import 'local_recovery_inventory.dart';
import 'local_store.dart';
import 'local_article_draft_receipt.dart';
import 'local_article_creation_record.dart';
import 'local_article_creation_legacy_metadata.dart';

class LocalRecoveryDestination {
  const LocalRecoveryDestination({
    required this.kind,
    required this.namespace,
    required this.title,
    this.id,
    this.assistant,
    this.assistantResourceId,
    this.collection = 'note',
  });
  final String kind, namespace, title, collection;
  final int? id;

  /// Metadata only. AI destinations must use the assistant recovery coordinator,
  /// never an ordinary new-resource editor or an automatic INSERT.
  final LocalAssistantWriteMarker? assistant;

  /// Vault record identity only; fresh ledger + receipt must confirm ownership.
  final int? assistantResourceId;
}

class ResolvedLocalRecovery {
  const ResolvedLocalRecovery(
    this.reference,
    this.destination, {
    this.archivedDisposition,
    this.archivedCreationDisposition,
  });
  final LocalRecoveryReference reference;
  final LocalRecoveryDestination? destination;
  final LocalArticleDraftDisposition? archivedDisposition;
  final LocalArticleCreationLegacyDisposition? archivedCreationDisposition;
  bool get archived =>
      archivedDisposition != null || archivedCreationDisposition != null;
}

class LocalRecoveryResolution {
  const LocalRecoveryResolution(this.summary, this.records);
  final LocalRecoverySummary summary;
  final List<ResolvedLocalRecovery> records;
}

/// Resolves keys only against current owned metadata, never decrypted bodies.
/// A key from another generation, missing resource, old misplaced vault, or an
/// unknown format has no destination and remains preserved/blocking.
class LocalRecoveryResolver {
  LocalRecoveryResolver({required this.store, required this.inventory});
  final LocalStore store;
  final LocalRecoveryInventory inventory;
  Future<LocalRecoveryResolution>
  read() => store.maintenance.exclusive(() async {
    final summary = await inventory.read();
    final namespace = store.dataPaths?.draftNamespace;
    if (namespace == null) throw StateError('Owned storage layout required');
    final records = <ResolvedLocalRecovery>[];
    for (final reference in summary.references) {
      records.add(
        ResolvedLocalRecovery(reference, await _resolve(reference, namespace)),
      );
    }
    final pending = summary.complexKeys.toSet();
    if (pending.isNotEmpty) {
      final creationRepository = LocalComplexNotesRepository(
        store,
        kind: ComplexEditorKind.markdown,
        collection: 'article',
      );
      final creationVault = LocalArticleCreationVault(
        scope: creationRepository.scope,
        store: NativeComplexRecoveryStore(),
      );
      final key = creationVault.metadataKey;
      creationRepository.dispose();
      if (pending.remove(key)) {
        records.add(
          ResolvedLocalRecovery(
            LocalRecoveryReference(
              store: 'complex',
              kind: 'article-create',
              key: key,
              namespace: namespace,
            ),
            LocalRecoveryDestination(
              kind: 'article-create',
              namespace: namespace,
              title: '',
              collection: 'article',
            ),
          ),
        );
      }
    }
    if (pending.isNotEmpty) {
      final database = await store.database;
      var cursor = 0, inspected = 0;
      while (pending.isNotEmpty) {
        final rows = await database.query(
          'notes',
          columns: ['id', 'title', 'collection', 'editor_type'],
          where:
              "id > ? AND deleted = 0 AND (editor_type IN ('spreadsheet','drawing','mindmap','richdoc','presentation') OR (collection = 'article' AND editor_type = 'markdown'))",
          whereArgs: [cursor],
          orderBy: 'id',
          limit: 256,
        );
        if (rows.isEmpty) break;
        inspected += rows.length;
        if (inspected > 250000) {
          throw const FormatException(
            'Recovery metadata inspection limit reached',
          );
        }
        for (final row in rows) {
          cursor = row['id'] as int;
          final collection = row['collection'] as String;
          final kind = ComplexEditorKind.parse(row['editor_type'] as String);
          final repository = LocalComplexNotesRepository(
            store,
            kind: kind,
            collection: collection,
          );
          final vault = ComplexRecoveryVault(
            scope: repository.scope,
            collection: collection,
            kind: kind,
            store: NativeComplexRecoveryStore(),
          );
          final key = vault.metadataKey(cursor);
          if (!pending.remove(key)) continue;
          final reference = LocalRecoveryReference(
            store: 'complex',
            kind: 'complex',
            key: key,
            namespace: namespace,
            recordId: cursor,
          );
          records.add(
            ResolvedLocalRecovery(
              reference,
              LocalRecoveryDestination(
                kind: 'complex',
                namespace: namespace,
                title: row['title'] as String,
                id: cursor,
                collection: collection,
              ),
            ),
          );
        }
      }
    }
    for (final key in pending) {
      records.add(
        ResolvedLocalRecovery(
          LocalRecoveryReference(store: 'complex', kind: 'complex', key: key),
          null,
        ),
      );
    }
    for (final archived in summary.archivedArticles) {
      final ref = archived.reference;
      var title = '';
      if (ref.namespace == jsonEncode([namespace, 'article'])) {
        final rows = await (await store.database).query(
          'notes',
          columns: ['title'],
          where: "id = ? AND collection = 'article'",
          whereArgs: [ref.recordId],
        );
        if (rows.length == 1) title = rows.single['title'] as String;
      }
      records.add(
        ResolvedLocalRecovery(
          ref,
          LocalRecoveryDestination(
            kind: 'article-archive',
            namespace: ref.namespace!,
            title: title,
            id: ref.recordId as int,
            collection: 'article',
          ),
          archivedDisposition: archived.disposition,
        ),
      );
    }
    for (final archived in summary.archivedCreations) {
      final ref = archived.reference;
      records.add(
        ResolvedLocalRecovery(
          ref,
          LocalRecoveryDestination(
            kind: 'article-create-archive',
            namespace: ref.namespace!,
            title: '',
            collection: 'article',
          ),
          archivedCreationDisposition: archived.disposition,
        ),
      );
    }
    return LocalRecoveryResolution(summary, List.unmodifiable(records));
  });

  Future<LocalRecoveryDestination?> _resolve(
    LocalRecoveryReference ref,
    String namespace,
  ) async {
    if (ref.namespace == null) return null;
    // Assistant records are creation identities, not SQL resource IDs. Resolve
    // them before any database query, including on the still-active schema14.
    if (ref.kind == 'ai-create') {
      if (ref.store != 'secure') return null;
      try {
        final marker = LocalAssistantWriteMarker.fromKey(ref.key);
        if (marker.namespace != namespace ||
            ref.namespace != marker.namespace ||
            ref.recordId != marker.recordId) {
          return null;
        }
        return LocalRecoveryDestination(
          kind: 'ai-create',
          namespace: marker.namespace,
          title: '',
          assistant: marker,
        );
      } on FormatException {
        return null;
      }
    }
    Object? decodedScope;
    try {
      decodedScope = jsonDecode(ref.namespace!);
    } on FormatException {
      // Ordinary local and local-generation identifiers are not JSON.
    }
    if (decodedScope is List &&
        decodedScope.length > 1 &&
        decodedScope[1] == 'assistant') {
      if (ref.store != 'secure' ||
          decodedScope.length != 5 ||
          decodedScope[0] != namespace ||
          decodedScope.any((value) => value is! String)) {
        return null;
      }
      final assistantScope = decodedScope;
      try {
        final kind = LocalAssistantDraftKind.values
            .where((kind) => kind.name == assistantScope[4])
            .single;
        final canonical = LocalAssistantEditorDrafts.editorNamespace(
          base: namespace,
          binding: decodedScope[2] as String,
          draft: decodedScope[3] as String,
          kind: kind,
        );
        final expectedKind = kind == LocalAssistantDraftKind.note
            ? 'note'
            : 'task';
        final originalId = kind == LocalAssistantDraftKind.note
            ? null
            : 'new:0';
        final resourceId = ref.recordId is int && (ref.recordId as int) > 0
            ? ref.recordId as int
            : null;
        if (ref.recordId != originalId && resourceId == null) return null;
        final expectedId = resourceId ?? originalId;
        final prefix = kind == LocalAssistantDraftKind.note
            ? 'bookstark.draft.v1.'
            : 'bookstark.task-draft.v1.';
        final expectedKey =
            '$prefix${base64Url.encode(utf8.encode(jsonEncode([canonical, expectedId])))}';
        if (canonical != ref.namespace ||
            ref.kind != expectedKind ||
            ref.recordId != expectedId ||
            ref.key != expectedKey) {
          return null;
        }
        return LocalRecoveryDestination(
          kind: 'ai-editor',
          assistantResourceId: resourceId,
          namespace: canonical,
          title: '',
          assistant: LocalAssistantWriteMarker(
            namespace: namespace,
            bindingId: decodedScope[2] as String,
            draftId: decodedScope[3] as String,
            kind: kind,
          ),
        );
      } on FormatException {
        return null;
      } on StateError {
        return null;
      }
    }
    final database = await store.database;
    final id = ref.recordId;
    var kind = ref.kind;
    var collection = 'note';
    final ordinaryScope = ref.namespace == namespace;
    final articleScope = ref.namespace == jsonEncode([namespace, 'article']);
    if (ref.store == 'html' && !{'html', 'html-create'}.contains(kind)) {
      return null;
    }
    if (kind == 'html' || kind == 'html-create') {
      final server = localHtmlRecoveryScope(store.path).toString();
      final scopes = {
        for (final type in ['note', 'article'])
          jsonEncode([
            server,
            1,
            type,
            'html',
            if (kind == 'html-create') 'new',
          ]): type,
      };
      collection = scopes[ref.namespace] ?? '';
      if (collection.isEmpty) return null;
      if (kind == 'html-create') {
        if (id != 'new') return null;
        return LocalRecoveryDestination(
          kind: kind,
          namespace: ref.namespace!,
          title: '',
          collection: collection,
        );
      }
    } else if (kind == 'note') {
      if (articleScope) {
        collection = 'article';
      } else if (!ordinaryScope) {
        Object? scope;
        try {
          scope = jsonDecode(ref.namespace!);
        } catch (_) {
          return null;
        }
        if (scope is! List || scope.firstOrNull != namespace) return null;
        if (scope.length == 2 && scope[1] == 'document') {
          kind = 'document';
        } else if (scope.length == 3 &&
            scope[1] == 'excerpt' &&
            scope[2] is int &&
            (scope[2] as int) > 0 &&
            id == null) {
          return LocalRecoveryDestination(
            kind: 'excerpt',
            namespace: ref.namespace!,
            title: '',
          );
        } else {
          return null;
        }
      }
    } else if (!ordinaryScope) {
      return null;
    }
    if (kind == 'document-create') {
      return LocalRecoveryDestination(
        kind: kind,
        namespace: namespace,
        title: '',
      );
    }
    if (id == null &&
        {'note', 'task', 'book', 'bookmark', 'topic'}.contains(kind)) {
      return LocalRecoveryDestination(
        kind: kind,
        namespace: ref.namespace!,
        title: '',
        collection: collection,
      );
    }
    if (id is! int || id <= 0) return null;
    if (kind == 'note' || kind == 'html') {
      final rows = await database.query(
        'notes',
        columns: ['title'],
        where: 'id = ? AND collection = ? AND deleted = 0 AND editor_type = ?',
        whereArgs: [id, collection, kind == 'html' ? 'html' : 'markdown'],
      );
      if (rows.length != 1) return null;
      return LocalRecoveryDestination(
        kind: kind,
        namespace: ref.namespace!,
        title: rows.single['title'] as String,
        id: id,
        collection: collection,
      );
    }
    const tables = <String, (String, String, String)>{
      'task': ('tasks', 'task_id', 'content'),
      'book': ('books', 'book_id', 'book_name'),
      'bookmark': ('bookmarks', 'bookmark_id', 'title'),
      'topic': ('topics', 'topic_id', 'title'),
      'file': ('local_drive_nodes', 'node_id', 'name'),
      'document': ('documents', 'document_id', 'document_name'),
    };
    final table = tables[kind];
    if (table == null) return null;
    final rows = await database.query(
      table.$1,
      columns: [table.$3],
      where:
          '${table.$2} = ?${kind == 'file' ? ' AND directory = 0' : ' AND deleted = 0'}${kind == 'document' ? " AND doc_type = 'markdown'" : ''}',
      whereArgs: [id],
    );
    if (rows.length != 1) return null;
    return LocalRecoveryDestination(
      kind: kind,
      namespace: ref.namespace!,
      title: rows.single[table.$3] as String,
      id: id,
      collection: collection,
    );
  }
}
