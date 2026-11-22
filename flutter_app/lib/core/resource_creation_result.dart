enum CreatedResourceKind { note, article, bookmark, document }

/// Only an acknowledged server/local ID belongs here. No body, password, auth
/// or guessed list position is returned to a caller such as topic association.
class ResourceCreationResult {
  ResourceCreationResult({
    required this.kind,
    required this.id,
    required this.title,
    required this.created,
    required this.metadataComplete,
    this.description = '',
    this.identify = '',
    this.bookId,
  }) {
    if (id <= 0 ||
        (kind == CreatedResourceKind.document
            ? bookId == null || bookId! <= 0
            : bookId != null)) {
      throw const FormatException('Invalid acknowledged resource identity');
    }
  }
  final CreatedResourceKind kind;
  final int id;
  final String title, description, identify;
  final int? bookId;
  final bool created;

  /// False still means the resource exists. Retry metadata/association using
  /// this ID, never repeat resource creation after a partial-save receipt.
  final bool metadataComplete;
}
