import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/draft_vault.dart';
import '../../core/document_excerpt_request.dart';
import '../../core/notes_repository.dart';
import '../notes/notes_page.dart';

class _OwnedLocalExcerptNotes implements NotesRepository {
  _OwnedLocalExcerptNotes(this.inner, this.current);
  final LocalNotesRepository inner;
  final bool Function() current;
  void guard() {
    if (!current() || inner.store.maintenance.retired) {
      throw StateError('Excerpt owner retired');
    }
  }

  @override
  Future<Note> read(int id) async {
    guard();
    final result = await inner.read(id);
    guard();
    return result;
  }

  @override
  Future<int> save(Note note) async {
    guard();
    final result = await inner.save(note);
    guard();
    return result;
  }

  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async {
    guard();
    final result = await inner.list(keyword: keyword, page: page);
    guard();
    return result;
  }

  @override
  Future<void> remove(int id) async {
    guard();
    await inner.remove(id);
    guard();
  }
}

DraftVault? _ownedDrafts(DraftVault? source, bool Function() current) {
  if (source == null) return null;
  void guard() {
    if (!current()) throw StateError('Excerpt draft owner retired');
  }

  return DraftVault(
    namespace: source.namespace,
    maintenance: source.maintenance,
    readValue: (key) async {
      guard();
      final value = await source.readValue(key);
      guard();
      return value;
    },
    writeValue: (key, value) async {
      guard();
      await source.writeValue(key, value);
      guard();
    },
    deleteValue: (key) async {
      guard();
      await source.deleteValue(key);
      guard();
    },
  );
}

Future<void> openLocalBookExcerpt(
  BuildContext context, {
  required LocalNotesRepository repository,
  required DocumentExcerptRequest request,
  required bool Function() isCurrent,
  DraftVault? drafts,
  AttachmentRepository? attachments,
  bool english = false,
}) async {
  bool current() =>
      context.mounted &&
      isCurrent() &&
      request.isCurrentSource() &&
      !repository.store.maintenance.retired;
  if (repository.collection != NoteCollection.note) {
    throw StateError('Excerpt must create a note');
  }
  if (!current() || !await request.verifyCurrentSource() || !current()) return;
  final scoped = _OwnedLocalExcerptNotes(repository, current);
  if (!context.mounted) return;
  await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => NoteEditorPage(
        repository: scoped,
        note: request.note,
        drafts: _ownedDrafts(drafts, current),
        attachments: attachments,
        english: english,
      ),
    ),
  );
}
