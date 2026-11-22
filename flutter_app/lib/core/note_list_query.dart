enum NotePinFilter { all, pinned, unpinned }

enum NoteVisibilityFilter { all, private, public }

class NoteListCapabilities {
  const NoteListCapabilities({
    required this.searchHint,
    this.labels = true,
    this.createdDate = false,
    this.pinned = false,
    this.visibility = false,
    this.hasCode = false,
  });
  final String searchHint;
  final bool labels, createdDate, pinned, visibility, hasCode;
  static const server = NoteListCapabilities(
    searchHint: 'title-or-label',
    createdDate: true,
    pinned: true,
    visibility: true,
    hasCode: true,
  );
  static const local = NoteListCapabilities(searchHint: 'title-or-content');
}

/// Filter identity excludes page. Keep this same immutable instance/value when
/// appending a page; all-default options are omitted from the Go query.
class NoteListQuery {
  const NoteListQuery({
    this.collection = 'note',
    this.keyword = '',
    this.label = '',
    this.createdDate = '',
    this.pin = NotePinFilter.all,
    this.visibility = NoteVisibilityFilter.all,
    this.hasCode = false,
  });
  final String collection, keyword, label, createdDate;
  final NotePinFilter pin;
  final NoteVisibilityFilter visibility;
  final bool hasCode;
  int get filterCount =>
      (label.isEmpty ? 0 : 1) +
      (createdDate.isEmpty ? 0 : 1) +
      (pin == NotePinFilter.all ? 0 : 1) +
      (visibility == NoteVisibilityFilter.all ? 0 : 1) +
      (hasCode ? 1 : 0);
  NoteListQuery copyWith({
    String? collection,
    String? keyword,
    String? label,
    String? createdDate,
    NotePinFilter? pin,
    NoteVisibilityFilter? visibility,
    bool? hasCode,
  }) => NoteListQuery(
    collection: collection ?? this.collection,
    keyword: keyword ?? this.keyword,
    label: label ?? this.label,
    createdDate: createdDate ?? this.createdDate,
    pin: pin ?? this.pin,
    visibility: visibility ?? this.visibility,
    hasCode: hasCode ?? this.hasCode,
  );
  void validate() {
    if (!{'note', 'article'}.contains(collection)) {
      throw const FormatException('Invalid note collection');
    }
    if (createdDate.isNotEmpty) {
      if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(createdDate)) {
        throw const FormatException('Choose a valid creation date');
      }
      final parsed = DateTime.tryParse(createdDate);
      if (parsed == null ||
          parsed.year < 1 ||
          parsed.toIso8601String().substring(0, 10) != createdDate) {
        throw const FormatException('Choose a valid creation date');
      }
    }
  }

  void requireSupported(NoteListCapabilities capabilities) {
    validate();
    if ((!capabilities.labels && label.isNotEmpty) ||
        (!capabilities.createdDate && createdDate.isNotEmpty) ||
        (!capabilities.pinned && pin != NotePinFilter.all) ||
        (!capabilities.visibility && visibility != NoteVisibilityFilter.all) ||
        (!capabilities.hasCode && hasCode)) {
      throw UnsupportedError('This local source does not support that filter');
    }
  }

  Map<String, String> parameters({required int page, int pageSize = 20}) {
    validate();
    if (page < 1 || pageSize < 1 || pageSize > 200) {
      throw const FormatException('Invalid note page');
    }
    return {
      'type': collection,
      'page': '$page',
      'page_size': '$pageSize',
      if (keyword.isNotEmpty) 'keyword': keyword,
      if (label.isNotEmpty) 'label': label,
      if (createdDate.isNotEmpty) 'date': createdDate,
      if (pin != NotePinFilter.all)
        'pinned': pin == NotePinFilter.pinned ? '1' : '0',
      if (visibility != NoteVisibilityFilter.all)
        'visibility': visibility == NoteVisibilityFilter.public ? '1' : '0',
      if (hasCode) 'has_code': '1',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is NoteListQuery &&
      collection == other.collection &&
      keyword == other.keyword &&
      label == other.label &&
      createdDate == other.createdDate &&
      pin == other.pin &&
      visibility == other.visibility &&
      hasCode == other.hasCode;
  @override
  int get hashCode => Object.hash(
    collection,
    keyword,
    label,
    createdDate,
    pin,
    visibility,
    hasCode,
  );
}
