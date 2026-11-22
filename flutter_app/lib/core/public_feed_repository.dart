import 'dart:convert';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'api_client.dart';
import 'public_feed_models.dart';

abstract interface class PublicFeedRepository {
  Future<PublicFeedPageData> load(
    PublicFeedQuery query, {
    Future<void>? abortTrigger,
  });
}

class RemotePublicFeedRepository implements PublicFeedRepository {
  RemotePublicFeedRepository(this.client);
  final BookstarkClient client;
  @override
  Future<PublicFeedPageData> load(
    PublicFeedQuery query, {
    Future<void>? abortTrigger,
  }) async => parsePublicFeed(
    await client.publicFeedHtml(query, abortTrigger: abortTrigger),
    query: query,
    server: client.baseUri,
  );
}

/// A versioned semantic adapter for the existing Go template. No DOM is mounted,
/// scripts are never run and images/links are never fetched by the parser.
PublicFeedPageData parsePublicFeed(
  String source, {
  required PublicFeedQuery query,
  required Uri server,
}) {
  final document = html.parse(source);
  Element one(String selector) {
    final matches = document.querySelectorAll(selector);
    if (matches.length != 1) {
      throw FormatException('Unsupported public feed structure: $selector');
    }
    return matches.single;
  }

  PublicFeedQuery navigation(Element element) => PublicFeedQuery.fromNavigation(
    element.attributes['href'] ?? '',
    server: server,
  );
  String input(String name) {
    final inputs = one('#publicSearch').querySelectorAll('input[name="$name"]');
    if (inputs.length != 1) {
      throw const FormatException('Missing public feed filter');
    }
    return inputs.single.attributes['value'] ?? '';
  }

  if (input('type') != query.kind.name ||
      input('sort') != query.sort.name ||
      input('label') != query.label ||
      input('keyword') != query.keyword ||
      one('.public-pagination > span').text.trim() != '${query.page}' ||
      navigation(one('.public-nav a[aria-current="page"]')).kind !=
          query.kind ||
      navigation(one('.public-feed-tabs a[aria-current="page"]')).sort !=
          query.sort) {
    throw const FormatException('Public feed did not apply requested filters');
  }
  final categories = <PublicFeedCategory>[];
  for (final link in one('.public-categories').querySelectorAll('a')) {
    final target = navigation(link);
    if (target != query.copyWith(label: target.label, page: 1)) {
      throw const FormatException('Invalid public category filters');
    }
    categories.add(
      PublicFeedCategory(
        label: target.label,
        selected: link.attributes['aria-current'] == 'page',
      ),
    );
  }
  PublicFeedQuery? previous, next;
  for (final link in one('.public-pagination').querySelectorAll('a')) {
    final target = navigation(link);
    if (target == query.copyWith(page: query.page + 1) && next == null) {
      next = target;
    } else if (query.page > 1 &&
        target == query.copyWith(page: query.page - 1) &&
        previous == null) {
      previous = target;
    } else {
      throw const FormatException('Invalid public pagination');
    }
  }
  final container = one('section.public-feed .public-items-${query.kind.name}');
  final rows = container.querySelectorAll(
    query.kind == PublicFeedKind.bookmark
        ? 'article.bm-row'
        : 'article.public-entry',
  );
  if (rows.length > 15 ||
      rows.isEmpty && container.querySelector('.public-empty') == null) {
    throw const FormatException('Unsupported public feed rows');
  }
  // Read only the JSON literal bounded by known assignments. Never evaluate JS.
  Map<String, dynamic> notes = {};
  if (query.kind == PublicFeedKind.note) {
    const start = 'window.__PUBLIC_NOTES__=';
    const end = ';window.__SHARE_COMMENTS_ENABLED__=';
    final scripts = document
        .querySelectorAll('script')
        .where((element) => element.text.startsWith(start))
        .toList();
    if (scripts.length != 1) {
      throw const FormatException('Missing public note data');
    }
    final text = scripts.single.text;
    var boundary = -1, depth = 0;
    var inString = false, escaped = false;
    for (var i = start.length; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{' || char == '[') {
        depth++;
      } else if (char == '}' || char == ']') {
        depth--;
        if (depth == 0 && text.startsWith(end, i + 1)) {
          boundary = i + 1;
          break;
        }
        if (depth < 0) {
          break;
        }
      }
    }
    if (boundary < 0) {
      throw const FormatException('Unsupported public note data');
    }
    final value = jsonDecode(text.substring(start.length, boundary));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid public note data');
    }
    notes = value;
  }
  final items = <PublicFeedItem>[];
  for (final row in rows) {
    String text(String selector) =>
        row.querySelector(selector)?.text.trim() ?? '';
    if (query.kind == PublicFeedKind.bookmark) {
      final link = row.querySelector('.bm-row-title');
      final uri = Uri.tryParse(link?.attributes['href'] ?? '');
      final author = text('.bm-row-account');
      // No database ID is exposed for other owners. Scope an opaque row identity
      // to its actual response page and position, not a fabricated resource ID.
      items.add(
        PublicFeedItem(
          kind: query.kind,
          identity: 'bookmark:${query.requestPath}:${items.length}',
          title: link?.text.trim() ?? '',
          author: author,
          date: '',
          format: 'bookmark',
          locked: false,
          pinned: false,
          excerpt: text('.bm-row-desc'),
          labels: row
              .querySelectorAll('.bm-label-badge')
              .map((e) => e.text)
              .toList(),
          externalUri: uri,
        ),
      );
      continue;
    }
    final identify = row.attributes['data-share-identify'] ?? '';
    final note = query.kind == PublicFeedKind.note;
    final locked = note
        ? row.querySelector('[data-note-content]') == null
        : row.querySelector('h2 .fa-lock') != null;
    String title = text('h2 a'), format = text('.public-content-type');
    if (note && !locked) {
      final detail = notes[identify];
      if (detail is! Map<String, dynamic> ||
          detail['has_password'] == true ||
          detail['title'] is! String) {
        throw const FormatException('Invalid unlocked note metadata');
      }
      title = detail['title'] as String;
      format = detail['doc_type'] is String ? detail['doc_type'] as String : '';
    }
    final controls = row.querySelectorAll('[data-public-action]');
    int? manageId;
    String? manageType;
    for (final control in controls) {
      final id = int.tryParse(control.attributes['data-id'] ?? '');
      final type = control.attributes['data-type'];
      if (id == null ||
          manageId != null && (manageId != id || manageType != type)) {
        throw const FormatException('Invalid public management metadata');
      }
      manageId = id;
      manageType = type;
    }
    items.add(
      PublicFeedItem(
        kind: query.kind,
        identity: '${query.kind.name}:$identify',
        shareIdentify: identify,
        title: title,
        author: note
            ? text('.public-note-author-name')
            : text('.public-meta > span'),
        date: row.querySelector('time')?.attributes['datetime'] ?? '',
        format: format,
        locked: locked,
        pinned: row.querySelector('.public-pinned') != null,
        excerpt: locked
            ? ''
            : text(note ? '[data-note-content]' : '.public-excerpt'),
        labels: locked
            ? []
            : row
                  .querySelectorAll('.public-meta .tag-badge')
                  .map((e) => e.text)
                  .toList(),
        manageTargetId: manageId,
        manageType: manageType,
      ),
    );
  }
  return PublicFeedPageData(
    query: query,
    items: items,
    categories: categories,
    previous: previous,
    next: next,
  );
}
