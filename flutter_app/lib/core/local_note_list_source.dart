import 'notes_repository.dart';
import 'note_list_query.dart';
import 'note_list_source.dart';

/// Preserves the existing local ordering/search semantics and repository
/// overrides. No schema change and no fake pin/visibility/date/code filter.
class LocalNoteListSource implements NoteListSource {
  LocalNoteListSource({
    required this.repository,
    this.isCurrent,
    this.collection = 'note',
  });
  final NoteListRepository repository;
  final String collection;
  final bool Function()? isCurrent;
  @override
  NoteListCapabilities get capabilities => NoteListCapabilities.local;
  void _guard() {
    if (isCurrent?.call() == false) throw StateError('Note list owner retired');
  }

  @override
  Future<NoteListPage> list(NoteListQuery query, {int page = 1}) async {
    _guard();
    if (query.collection != collection) {
      throw const FormatException('Note collection changed');
    }
    query.requireSupported(capabilities);
    query.parameters(page: page);
    final entries = await repository.listEntries(
      keyword: query.keyword,
      label: query.label,
      page: page,
    );
    _guard();
    // This adapter only wraps metadata; it never calls NotesRepository.read.
    return NoteListPage(
      items: [
        for (final item in entries)
          FilteredNoteListEntry(
            id: item.id,
            title: item.title,
            contentPreview: item.isProtected
                ? ''
                : String.fromCharCodes(item.contentPreview.runes.take(512)),
            labels: List.unmodifiable(item.labels),
            updatedAt: item.updatedAt,
            isProtected: item.isProtected,
          ),
      ],
      page: page,
      hasMore: entries.length >= 20,
    );
  }
}
