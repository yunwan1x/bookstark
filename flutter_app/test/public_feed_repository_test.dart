import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_feed_models.dart';
import 'package:bookstark_flutter/core/public_feed_repository.dart';

String fixture({String kind = 'article', String row = '', String extra = ''}) =>
    '''
<nav class="public-nav"><a href="/shares?type=$kind" aria-current="page">Type</a></nav>
<form id="publicSearch"><input name="type" value="$kind"><input name="sort" value="latest"><input name="label" value=""><input name="keyword" value=""></form>
<aside class="public-categories"><a href="/shares?type=$kind&amp;sort=latest&amp;page=1" aria-current="page"><span>All</span></a></aside>
<div class="public-feed-tabs"><a href="/shares?type=$kind&amp;sort=latest" aria-current="page">Latest</a></div>
<section class="public-feed"><div class="public-items-$kind">$row</div></section>
<nav class="public-pagination"><span>1</span><a href="/shares?type=$kind&amp;sort=latest&amp;page=2">Next</a></nav>$extra
''';
const article =
    '<article class="public-entry" data-share-identify="blog-original"><h2><a>Actual title</a></h2><span class="public-content-type">Markdown</span><p class="public-excerpt">Actual excerpt</p><div class="public-meta"><span>Owner</span><time datetime="2026-11-05"></time><span class="tag-badge">a,b&amp;c</span></div></article>';
void main() {
  final server = Uri.parse('https://example.test/base');
  PublicFeedPageData parse(
    String source, {
    PublicFeedKind kind = PublicFeedKind.article,
  }) => parsePublicFeed(
    source,
    query: PublicFeedQuery(kind: kind),
    server: server,
  );
  test(
    'semantic article parser retains exact labels, identities and real adjacent pages',
    () {
      final data = parse(fixture(row: article));
      expect(data.items.single.shareIdentify, 'blog-original');
      expect(data.items.single.title, 'Actual title');
      expect(data.items.single.labels, ['a,b&c']);
      expect(data.next?.page, 2);
      expect(data.previous, isNull);
      expect(data.loadedCount, 1);
    },
  );
  test(
    'locked article discards accidental protected markup before UI models',
    () {
      final data = parse(
        fixture(
          row: article.replaceFirst(
            'Actual title',
            'Actual title<i class="fa-lock"></i>',
          ),
        ),
      );
      expect(data.items.single.locked, true);
      expect(data.items.single.excerpt, isEmpty);
      expect(data.items.single.labels, isEmpty);
    },
  );
  test('note title comes from inert JSON while script is never evaluated', () {
    final data = parse(
      fixture(
        kind: 'note',
        row:
            '<article class="public-entry" data-share-identify="note-1"><span class="public-note-author-name">Owner</span><div data-note-content>Visible body</div></article>',
        extra:
            '<script>window.__PUBLIC_NOTES__={"note-1":{"title":"Actual note","doc_type":"markdown","has_password":false}};window.__SHARE_COMMENTS_ENABLED__=false;throw new Error("never execute");</script>',
      ),
      kind: PublicFeedKind.note,
    );
    expect(data.items.single.title, 'Actual note');
    expect(data.items.single.excerpt, 'Visible body');
  });
  test(
    'literal assignment marker inside note JSON does not truncate its string',
    () {
      const title = 'literal ;window.__SHARE_COMMENTS_ENABLED__= and "quote"';
      final value = {
        'note-1': {
          'title': title,
          'doc_type': 'markdown',
          'has_password': false,
          'content': 'braces } [ and backslash \\',
        },
      };
      final data = parse(
        fixture(
          kind: 'note',
          row:
              '<article class="public-entry" data-share-identify="note-1"><div data-note-content>Body</div></article>',
          extra:
              '<script>window.__PUBLIC_NOTES__=${jsonEncode(value)};window.__SHARE_COMMENTS_ENABLED__=false;</script>',
        ),
        kind: PublicFeedKind.note,
      );
      expect(data.items.single.title, title);
    },
  );
  test('bookmarks sharing the same URL remain separate actual rows', () {
    const row =
        '<article class="bm-row"><a class="bm-row-title" href="https://external.test/page">Bookmark</a><span class="bm-row-account">Owner</span></article>';
    final data = parse(
      fixture(kind: 'bookmark', row: row + row),
      kind: PublicFeedKind.bookmark,
    );
    expect(data.items.length, 2);
    expect(data.items.map((e) => e.identity).toSet().length, 2);
    expect(data.items.every((e) => e.manageTargetId == null), true);
  });
  test(
    'changed structure, ignored filters and malicious navigation fail explicitly',
    () {
      for (final source in [
        '<html>Login instead</html>',
        fixture(row: article).replaceFirst(
          'name="type" value="article"',
          'name="type" value="note"',
        ),
        fixture(row: article).replaceFirst(
          '/shares?type=article&amp;sort=latest&amp;page=2',
          'https://evil.test/shares?page=2',
        ),
        fixture(row: article + article),
        fixture(row: ''),
      ]) {
        expect(() => parse(source), throwsFormatException);
      }
      expect(
        parse(fixture(row: '<div class="public-empty">Empty</div>')).items,
        isEmpty,
      );
    },
  );
}
