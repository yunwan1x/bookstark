import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/article_web_scope.dart';

void main() {
  ArticleWebScope scope([String base = 'https://example.test']) =>
      ArticleWebScope.parse(base, 7);
  test(
    'entry is the actual article tab and preserves custom port and prefix',
    () {
      final value = scope('https://example.test:54321/team/bookstark/');
      expect(
        value.listUri.toString(),
        'https://example.test:54321/team/bookstark/notes?tab=articles&type=article',
      );
      expect(value.cookiePath, '/team/bookstark/');
      expect(scope().cookiePath, '/');
    },
  );
  test(
    'profile identity isolates account, origin and path without credentials',
    () {
      final value = scope('https://EXAMPLE.test/app/');
      expect(value.profileName, scope('https://example.test/app').profileName);
      expect(
        value.profileName,
        matches(r'^bookstark\.article\.v1\.[a-f0-9]{64}$'),
      );
      expect(
        value.profileName,
        isNot(ArticleWebScope(value.server, 8).profileName),
      );
      expect(
        value.profileName,
        isNot(scope('https://example.test/app2').profileName),
      );
      expect(
        value.profileName,
        isNot(scope('http://example.test/app').profileName),
      );
    },
  );
  test(
    'invalid server authorities and ambiguous prefixes fail before cookies',
    () {
      for (final url in [
        'file:///private',
        'https://user:secret@example.test',
        'https://example.test/a//b',
        'https://example.test/%2e%2e',
        'https://example.test/?token=secret',
        'https://example.test/#fragment',
      ]) {
        expect(() => scope(url), throwsArgumentError);
      }
      expect(
        () => ArticleWebScope(Uri.parse('https://example.test'), 0),
        throwsArgumentError,
      );
    },
  );
  test('root Go resource and API aliases mount only once inside prefix', () {
    final value = scope('https://example.test/team/app');
    for (final path in [
      '/static/js/notes.js?v=1',
      '/api/blogs?type=article',
      '/upload-files/照片.png',
      '/blogs/article-1/edit?mode=edit',
    ]) {
      final resolved = value.resolve(path)!;
      expect(resolved.path, startsWith('/team/app/'));
      expect(value.resolve(resolved.toString()), resolved);
    }
    expect(value.resolve('/another-service/secret'), isNull);
    expect(value.resolve('https://elsewhere.test/static/js/notes.js'), isNull);
  });
  test(
    'traversal, encoded separators, double encoding and userinfo are denied',
    () {
      final value = scope('https://example.test/team');
      for (final path in [
        '../notes',
        '/static/../api/blogs',
        '/static/%2e%2e/api/blogs',
        '/static/a%2fb.js',
        '/static/%252e%252e/x',
        '/static/a%5cb.js',
        '/static/%00x',
        'https://user@example.test/notes',
      ]) {
        expect(value.resolve(path), isNull, reason: path);
        expect(
          value.navigation(path).destination,
          ArticleWebDestination.blocked,
        );
      }
    },
  );
  test('same-host prefix lookalikes cannot escape to sibling service', () {
    final value = scope('https://example.test/app');
    expect(value.resolve('https://example.test/app-evil/notes'), isNull);
    expect(value.resolve('https://example.test:444/app/notes'), isNull);
    expect(value.resolve('/api/blogs')?.path, '/app/api/blogs');
  });
  test(
    'list return is normalized, other actual app tabs leave through native routes',
    () {
      final value = scope('https://example.test/app');
      final list = value.navigation('/notes?page=2');
      expect(list.destination, ArticleWebDestination.list);
      expect(list.uri!.queryParameters, {
        'page': '2',
        'tab': 'articles',
        'type': 'article',
      });
      expect(value.navigation('/notes?tab=tasks').appRoute, 'tasks');
      expect(value.navigation('/notes?tab=notes').appRoute, 'notes');
      expect(value.navigation('/books').appRoute, 'books');
      expect(value.navigation('/webdav').appRoute, 'files');
      expect(
        value.navigation('/notes?tab=articles&tab=notes').destination,
        ArticleWebDestination.blocked,
      );
    },
  );
  test(
    'Go editor path, preview mode and from query survive without inventing IDs',
    () {
      final value = scope('https://example.test/app');
      final result = value.navigation(
        '/blogs/travel_01/edit?mode=preview&from=%2Fnotes%3Ftab%3Darticles',
      );
      expect(result.destination, ArticleWebDestination.editor);
      expect(result.uri!.path, '/app/blogs/travel_01/edit');
      expect(result.uri!.queryParameters['from'], '/notes?tab=articles');
      expect(
        value.navigation('/blogs/a/edit?mode=unknown').destination,
        ArticleWebDestination.blocked,
      );
      expect(
        value.navigation('/blogs/%2F/edit').destination,
        ArticleWebDestination.blocked,
      );
    },
  );
  test(
    'expired auth and external schemes cannot become authenticated documents',
    () {
      final value = scope();
      expect(
        value.navigation('/login').destination,
        ArticleWebDestination.sessionEnded,
      );
      expect(
        value.navigation('/logout').destination,
        ArticleWebDestination.sessionEnded,
      );
      expect(
        value.navigation('https://outside.test/article').destination,
        ArticleWebDestination.external,
      );
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/passwd',
        'content://provider/private',
        'intent://launch',
        'data:text/html,x',
      ]) {
        expect(
          value.navigation(url).destination,
          ArticleWebDestination.blocked,
        );
      }
    },
  );
  test(
    'relative editor links and fragments use only a current owned document',
    () {
      final value = scope('https://example.test/app');
      final current = value.navigation('/blogs/travel/edit?mode=edit').uri!;
      expect(value.resolve('#section', current: current)?.path, current.path);
      expect(value.resolve('#section', current: current)?.fragment, 'section');
      expect(
        value
            .resolve('notes', current: Uri.parse('https://outside.test/a'))
            ?.path,
        '/app/notes',
      );
    },
  );
}
