import 'note_list_query.dart';
import 'note_list_source.dart';

/// REQUIRED integration contract: this callback reads one authenticated source
/// through a deadline/byte-bounded streaming JSON projection. It discards body
/// fields and bounds content_preview before materializing JSON. Do not wire the
/// existing unbounded BookstarkClient.get here: Go note previews can be full text.
typedef ReadBoundedNoteListPage =
    Future<Map<String, Object?>> Function(String path);

class RemoteNoteListSource implements NoteListSource {
  RemoteNoteListSource({
    required this.readBoundedPage,
    this.isCurrent,
    this.expectedMemberId,
    this.pageSize = 20,
  });
  final ReadBoundedNoteListPage readBoundedPage;
  final bool Function()? isCurrent;
  final int pageSize;
  final int? expectedMemberId;
  @override
  NoteListCapabilities get capabilities => NoteListCapabilities.server;
  void _guard() {
    if (isCurrent?.call() == false) throw StateError('Note list owner retired');
  }

  @override
  Future<NoteListPage> list(NoteListQuery query, {int page = 1}) async {
    _guard();
    query.requireSupported(capabilities);
    final expectedOwner = expectedMemberId;
    if (expectedOwner != null && expectedOwner <= 0) {
      throw const FormatException('Invalid note-list owner');
    }
    final parameters = {
      ...query.parameters(page: page, pageSize: pageSize),
      'metadata_only': '1',
    };
    final result = await readBoundedPage(
      '/api/blogs?${Uri(queryParameters: parameters).query}',
    );
    _guard();
    if (result['code'] != 0 && result['code'] != 200) {
      throw const FormatException('Invalid note page receipt');
    }
    final total = result['total'],
        receivedPage = result['page'],
        receivedSize = result['page_size'],
        totalPages = result['total_pages'];
    if (total is! int ||
        total < 0 ||
        receivedPage != page ||
        receivedSize != pageSize ||
        totalPages is! int ||
        totalPages < 0) {
      throw const FormatException('Invalid note pagination');
    }
    final raw = result['data'];
    if (raw != null && raw is! List || raw == null && total != 0) {
      throw const FormatException('Invalid note page data');
    }
    final rows = raw as List? ?? const [];
    if (rows.length > pageSize) {
      throw const FormatException('Note page exceeds item limit');
    }
    final items = <FilteredNoteListEntry>[];
    final ids = <int>{};
    for (final rawRow in rows) {
      if (rawRow is! Map) throw const FormatException('Invalid note list item');
      final id = rawRow['blog_id'],
          title = rawRow['blog_title'],
          preview = rawRow['content_preview'] ?? '';
      final protected = rawRow['has_password'];
      final member = rawRow['member_id'], collection = rawRow['blog_type'];
      if (expectedOwner != null &&
          (member != expectedOwner || collection != query.collection)) {
        throw const FormatException('Note-list owner or collection changed');
      }
      if (collection != null && collection != query.collection) {
        throw const FormatException('Note-list collection changed');
      }

      if (id is! int ||
          id <= 0 ||
          title is! String ||
          title.length > 4096 ||
          preview is! String ||
          preview.runes.length > 512 ||
          protected is! bool) {
        throw const FormatException('Unbounded or invalid list metadata');
      }
      if (!ids.add(id)) continue;
      bool? pin;
      final rawPin = rawRow['is_pinned'];
      if (rawPin == 0 || rawPin == false) {
        pin = false;
      } else if (rawPin == 1 || rawPin == true) {
        pin = true;
      } else if (rawPin != null) {
        throw const FormatException('Invalid pin metadata');
      }
      final visibility = rawRow['visibility'];
      if (visibility != null && visibility != 0 && visibility != 1) {
        throw const FormatException('Invalid visibility metadata');
      }
      final editor = rawRow['editor_type'];
      if (expectedOwner != null &&
          (rawPin == null || visibility == null || editor == null)) {
        throw const FormatException('Missing authoritative note-list metadata');
      }
      if (editor != null && (editor is! String || editor.length > 64)) {
        throw const FormatException('Invalid editor metadata');
      }
      items.add(
        FilteredNoteListEntry(
          id: id,
          title: title,
          contentPreview: protected ? '' : preview,
          labels: normalizeNoteListLabels(rawRow['labels']),
          isProtected: protected,
          updatedAt: DateTime.tryParse(rawRow['modify_time'] as String? ?? ''),
          pinned: pin,
          visibility: visibility == null
              ? null
              : visibility == 1
              ? NoteVisibilityFilter.public
              : NoteVisibilityFilter.private,
          editorType: editor as String?,
        ),
      );
    }
    return NoteListPage(
      items: items,
      page: page,
      hasMore: page < totalPages,
      total: total,
      totalPages: totalPages,
    );
  }
}
