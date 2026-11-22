/// Bounded metadata used by note/article list views.
///
/// [contentPreview] is intentionally not a [Note] body and must never be sent
/// to save or editing APIs. Read the complete resource before editing it.
class NoteListEntry {
  const NoteListEntry({
    required this.id,
    required this.title,
    required this.contentPreview,
    this.labels = const [],
    this.updatedAt,
    this.isProtected = false,
  });

  final int id;
  final String title;
  final String contentPreview;
  final List<String> labels;
  final DateTime? updatedAt;
  final bool isProtected;
}
