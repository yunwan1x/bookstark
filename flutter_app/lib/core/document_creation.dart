import 'local_data_maintenance.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'books_repository.dart';
import 'documents_repository.dart';

enum DocumentCreationPhase { editing, submitting, unknown, acknowledged }

class DocumentCreationDraft {
  DocumentCreationDraft({
    required this.bookId,
    required this.parentId,
    required this.name,
    this.phase = DocumentCreationPhase.editing,
    this.createdId,
  }) {
    if (bookId <= 0 ||
        parentId < 0 ||
        utf8.encode(name).length > 8192 ||
        (phase == DocumentCreationPhase.acknowledged
            ? createdId == null || createdId! <= 0
            : createdId != null)) {
      throw const FormatException('Invalid document creation draft');
    }
  }
  final int bookId, parentId;
  final String name;
  final DocumentCreationPhase phase;
  final int? createdId;
  DocumentCreationDraft transition(
    DocumentCreationPhase phase, {
    DocumentItem? receipt,
  }) => DocumentCreationDraft(
    bookId: bookId,
    parentId: parentId,
    name: receipt?.name ?? name,
    phase: phase,
    createdId: receipt?.id,
  );
  String encode() => jsonEncode({
    'version': 1,
    'book_id': bookId,
    'parent_id': parentId,
    'name': name,
    'phase': phase.name,
    if (createdId != null) 'created_id': createdId,
  });
  static DocumentCreationDraft decode(String raw) {
    if (raw.length > 65536) {
      throw const FormatException('Document creation draft too large');
    }
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['version'] != 1 ||
        value['book_id'] is! int ||
        value['parent_id'] is! int ||
        value['name'] is! String ||
        !DocumentCreationPhase.values.any((p) => p.name == value['phase']) ||
        value['created_id'] != null && value['created_id'] is! int) {
      throw const FormatException('Invalid document creation draft');
    }
    return DocumentCreationDraft(
      bookId: value['book_id'] as int,
      parentId: value['parent_id'] as int,
      name: value['name'] as String,
      phase: DocumentCreationPhase.values.byName(value['phase'] as String),
      createdId: value['created_id'] as int?,
    );
  }
}

/// Callbacks use the existing secure storage, isolated per server/member/local
/// space. No plaintext fallback and no automatic clearing of unreadable state.
class DocumentCreationVault {
  DocumentCreationVault({
    required String namespace,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    this.maintenance,
  }) : key =
           'bookstark.document-create.v1.${sha256.convert(utf8.encode(namespace))}';
  final String key;
  final LocalDataMaintenance? maintenance;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final Future<void> Function(String) deleteValue;
  Future<void> _tail = Future.value();
  Future<T> _withMaintenance<T>(Future<T> Function() action) =>
      maintenance?.use(action) ?? Future<T>.sync(action);
  Future<T> _ordered<T>(Future<T> Function() operation) => _withMaintenance(() {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  });

  Future<DocumentCreationDraft?> read() => _ordered(() async {
    final raw = await readValue(key);
    return raw == null ? null : DocumentCreationDraft.decode(raw);
  });
  Future<void> write(DocumentCreationDraft draft) =>
      _ordered(() => writeValue(key, draft.encode()));
  Future<void> clear() => _ordered(() => deleteValue(key));
}

/// Persist intent before POST. A process interrupted while submitting recovers
/// as unknown and can never silently repeat a non-idempotent create request.
class DocumentCreationController {
  DocumentCreationController({
    required this.vault,
    required this.books,
    required this.documents,
  });
  final DocumentCreationVault vault;
  final BooksRepository books;
  final DocumentsRepository documents;
  DocumentCreationDraft? draft;
  Object? storageError;
  bool _loaded = false, _busy = false;
  bool get busy => _busy;
  bool get loaded => _loaded;
  Future<void> initialize({DocumentCreationDraft? initial}) async {
    if (_busy || _loaded) {
      throw StateError('Creation session already initialized');
    }
    _busy = true;
    try {
      final restored = await vault.read();
      draft = restored?.phase == DocumentCreationPhase.submitting
          ? restored!.transition(DocumentCreationPhase.unknown)
          : restored ?? initial;
      _loaded = true;
    } finally {
      _busy = false;
    }
  }

  Future<void> edit(DocumentCreationDraft value) async {
    if (!_loaded ||
        _busy ||
        value.phase != DocumentCreationPhase.editing ||
        draft != null && draft!.phase != DocumentCreationPhase.editing) {
      throw StateError('Resolve existing creation before editing');
    }
    _busy = true;
    try {
      await vault.write(value);
      draft = value;
      storageError = null;
    } finally {
      _busy = false;
    }
  }

  Future<DocumentItem> create() async {
    final pending = draft;
    if (!_loaded ||
        _busy ||
        pending == null ||
        pending.phase != DocumentCreationPhase.editing) {
      throw StateError('Creation is unavailable or needs verification');
    }
    validateDocumentName(pending.name);
    _busy = true;
    try {
      // Fail read-only validation before publishing any pending write intent.
      final book = await books.read(pending.bookId);
      if (book.id != pending.bookId) {
        throw const FormatException('Book identity changed');
      }
      final tree = await documents.tree(pending.bookId);
      if (pending.parentId != 0 &&
          !flattenDocuments(tree).any((node) => node.id == pending.parentId)) {
        throw StateError('Parent no longer belongs to this book');
      }
      final intent = pending.transition(DocumentCreationPhase.submitting);
      await vault.write(intent); // Failure here must issue no POST.
      draft = intent;
      storageError = null;
      DocumentItem result;
      try {
        result = await documents.create(
          pending.bookId,
          pending.name,
          parentId: pending.parentId,
        );
        if (result.id <= 0 ||
            result.bookId != pending.bookId ||
            result.parentId != pending.parentId ||
            result.type != 'markdown') {
          throw const FormatException('Invalid document creation receipt');
        }
        validateDocumentName(result.name);
      } catch (error) {
        final rejected =
            error is ApiFailure &&
            {400, 401, 403, 404, 409, 413, 422}.contains(error.status);
        draft = pending.transition(
          rejected
              ? DocumentCreationPhase.editing
              : DocumentCreationPhase.unknown,
        );
        try {
          await vault.write(draft!);
        } catch (failure) {
          storageError = failure;
        }
        rethrow;
      }
      draft = pending.transition(
        DocumentCreationPhase.acknowledged,
        receipt: result,
      );
      try {
        await vault.write(draft!);
      } catch (error) {
        storageError = error;
      }
      return result; // A failed local cleanup cannot turn success into retry-POST.
    } finally {
      _busy = false;
    }
  }

  DocumentItem get acknowledged {
    final value = draft;
    if (value?.phase != DocumentCreationPhase.acknowledged) {
      throw StateError('No acknowledged document');
    }
    return DocumentItem(
      id: value!.createdId!,
      bookId: value.bookId,
      parentId: value.parentId,
      name: value.name,
    );
  }

  Future<void> persistAcknowledged() async {
    if (_busy || draft?.phase != DocumentCreationPhase.acknowledged) {
      throw StateError('No acknowledged document');
    }
    _busy = true;
    try {
      await vault.write(draft!);
      storageError = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> clear({bool explicitlyAbandonUnknown = false}) async {
    if (!_loaded ||
        _busy ||
        draft != null &&
            {
              DocumentCreationPhase.submitting,
              DocumentCreationPhase.unknown,
            }.contains(draft!.phase) &&
            !explicitlyAbandonUnknown) {
      throw StateError('Unknown creation requires explicit acknowledgement');
    }
    _busy = true;
    try {
      await vault.clear();
      draft = null;
      storageError = null;
    } finally {
      _busy = false;
    }
  }
}
