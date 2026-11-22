import 'dart:convert';
import 'package:html/parser.dart' as html;
import 'api_client.dart';
import 'public_share_models.dart';

class PublicNotePreview {
  const PublicNotePreview({
    required this.id,
    required this.reference,
    required this.title,
    required this.format,
    required this.locked,
    required this.modified,
    required this.preview,
    required this.labels,
    required this.pinned,
  });
  final int id;
  final PublicShareReference reference;
  final String title, format, preview;
  final bool locked, pinned;
  final DateTime modified;
  final List<String> labels;
}

class PublicNotesPageData {
  PublicNotesPageData(this.page, List<PublicNotePreview> items)
    : items = List.unmodifiable(items);
  final int page;
  final List<PublicNotePreview> items;

  /// Explicitly allows checking a next page; does not fabricate totals.
  bool get canRequestNext => items.isNotEmpty && page < 100000;
  Set<String> get labels =>
      Set.unmodifiable(items.expand((item) => item.labels));
}

abstract interface class PublicNotesRepository {
  Future<PublicNotesPageData> load(int page, {Future<void>? abortTrigger});
}

class RemotePublicNotesRepository implements PublicNotesRepository {
  RemotePublicNotesRepository(this.client);
  final BookstarkClient client;
  @override
  Future<PublicNotesPageData> load(
    int page, {
    Future<void>? abortTrigger,
  }) async => parsePublicNotes(
    await client.publicNotesHtml(page, abortTrigger: abortTrigger),
    server: client.baseUri,
    page: page,
  );
}

PublicNotesPageData parsePublicNotes(
  String source, {
  required Uri server,
  required int page,
}) {
  if (page < 1 || page > 100000) {
    throw const FormatException('Invalid public notes page');
  }
  final document = html.parse(source);
  if (document.querySelectorAll('#publicTimeline').length != 1) {
    throw const FormatException('Unsupported public notes template');
  }
  const prefix = 'var blogs = ';
  final scripts = document
      .querySelectorAll('script')
      .map((e) => e.text.trimLeft())
      .where((text) => text.startsWith(prefix))
      .toList();
  if (scripts.length != 1) {
    throw const FormatException('Ambiguous public notes data');
  }
  final text = scripts.single;
  var depth = 0, quoted = false, escaped = false, boundary = -1;
  for (var i = prefix.length; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        quoted = false;
      }
      continue;
    }
    if (char == '"') {
      quoted = true;
    } else if (char == '[' || char == '{') {
      depth++;
    } else if (char == ']' || char == '}') {
      depth--;
      if (depth < 0) {
        break;
      }
      if (depth == 0) {
        boundary = i + 1;
        break;
      }
    }
  }
  if (text.startsWith('null', prefix.length)) {
    boundary = prefix.length + 4;
  }
  if (boundary < 0 ||
      !RegExp(
        r"^;\s*var container = document\.getElementById\('publicTimeline'\);",
      ).hasMatch(text.substring(boundary))) {
    throw const FormatException('Unsupported public notes literal boundary');
  }
  final decoded = jsonDecode(text.substring(prefix.length, boundary));
  if (decoded != null && decoded is! List ||
      decoded is List && decoded.length > 20) {
    throw const FormatException('Invalid public note rows');
  }
  final seenIds = <int>{},
      seenIdentifiers = <String>{},
      items = <PublicNotePreview>[];
  for (final value in decoded as List? ?? []) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid public note record');
    }
    final id = value['blog_id'],
        identify = value['blog_identify'],
        title = value['blog_title'],
        locked = value['has_password'],
        format = value['editor_type'],
        modified = value['modify_time'],
        pinned = value['is_pinned'];
    if (id is! int ||
        id <= 0 ||
        id > 9007199254740991 ||
        !seenIds.add(id) ||
        identify is! String ||
        !seenIdentifiers.add(identify) ||
        title is! String ||
        title.length > 10000 ||
        locked is! bool ||
        format is! String ||
        format.isEmpty ||
        format.length > 100 ||
        modified is! String ||
        DateTime.tryParse(modified) == null ||
        value['blog_type'] != 'note' ||
        value['visibility'] != 1 ||
        pinned is! int ||
        !{0, 1}.contains(pinned)) {
      throw const FormatException('Invalid public note identity or context');
    }
    // Never validate or retain leaked locked body/labels/location data.
    final preview = locked ? '' : value['content_preview'] ?? '';
    final labels = locked ? <Object?>[] : value['labels'] ?? <Object?>[];
    if (preview is! String ||
        preview.length > 4 * 1024 * 1024 ||
        labels is! List ||
        labels.length > 1000 ||
        labels.any(
          (label) => label is! String || label.isEmpty || label.length > 2000,
        )) {
      throw const FormatException('Invalid public note preview');
    }
    items.add(
      PublicNotePreview(
        id: id,
        reference: PublicShareReference(server, identify),
        title: title,
        format: format,
        locked: locked,
        modified: DateTime.parse(modified),
        preview: preview,
        labels: List.unmodifiable(labels.cast<String>().toSet()),
        pinned: pinned == 1,
      ),
    );
  }
  return PublicNotesPageData(page, items);
}
