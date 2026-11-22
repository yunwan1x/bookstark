import 'dart:convert';

import 'note_list_entry.dart';
import 'note_list_query.dart';

/// Additive subtype: existing NotesRepository and list overrides stay unchanged.
class FilteredNoteListEntry extends NoteListEntry {
  const FilteredNoteListEntry({
    required super.id,
    required super.title,
    required super.contentPreview,
    super.labels,
    super.updatedAt,
    super.isProtected,
    this.pinned,
    this.visibility,
    this.editorType,
  });

  /// null means metadata/capability unavailable, never a fabricated false.
  final bool? pinned;
  final NoteVisibilityFilter? visibility;
  final String? editorType;
}

class NoteListPage {
  NoteListPage({
    required List<FilteredNoteListEntry> items,
    required this.page,
    required this.hasMore,
    this.total,
    this.totalPages,
  }) : items = List.unmodifiable(items);
  final List<FilteredNoteListEntry> items;
  final int page;
  final bool hasMore;
  final int? total, totalPages;
}

abstract interface class NoteListSource {
  NoteListCapabilities get capabilities;
  Future<NoteListPage> list(NoteListQuery query, {int page = 1});
}

/// Go returns []string|null. Explicit compatibility accepts old serialized JSON
/// arrays or unescaped comma-delimited labels, preserving label whitespace.
List<String> normalizeNoteListLabels(Object? value) {
  if (value == null) return const [];
  if (value is String) {
    if (value.isEmpty) return const [];
    if (value.trimLeft().startsWith('[')) {
      value = jsonDecode(value);
    } else {
      value = value
          .split(RegExp('[,，]'))
          .where((item) => item.isNotEmpty)
          .toList();
    }
  }
  if (value is! List || value.any((label) => label is! String)) {
    throw const FormatException('Invalid note labels');
  }
  return List.unmodifiable(value.cast<String>().toSet());
}
