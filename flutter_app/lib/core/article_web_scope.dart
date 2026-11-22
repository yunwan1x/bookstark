import 'dart:convert';
import 'package:crypto/crypto.dart';

enum ArticleWebDestination {
  list,
  editor,
  sessionEnded,
  appRoute,
  external,
  blocked,
}

final class ArticleWebNavigation {
  const ArticleWebNavigation(this.destination, this.uri, {this.appRoute});
  final ArticleWebDestination destination;
  final Uri? uri;
  final String? appRoute;
}

/// A server/account capability, with no credential in its storage identity.
final class ArticleWebScope {
  ArticleWebScope(Uri base, this.memberId) : server = _server(base) {
    if (memberId <= 0) throw ArgumentError('Positive member identity required');
  }
  factory ArticleWebScope.parse(String address, int memberId) {
    if (!_rawPathValid(address)) throw ArgumentError('Invalid server path');
    return ArticleWebScope(Uri.parse(address), memberId);
  }
  final Uri server;
  final int memberId;
  static const _nativeRoutes = {
    'home': 'home',
    'books': 'books',
    'bookmarks': 'bookmarks',
    'topics': 'topics',
    'images': 'images',
    'labels': 'labels',
    'webdav': 'files',
    'profile': 'profile',
    'trash': 'trash',
  };
  static const _resourceRoots = {
    'static',
    'api',
    'upload-files',
    'notes',
    'blogs',
    'manifest.json',
    'sw.js',
    'favicon.ico',
  };
  List<String> get _prefix =>
      server.pathSegments.where((s) => s.isNotEmpty).toList();
  String get cookiePath => _prefix.isEmpty ? '/' : '${server.path}/';
  String get profileName =>
      'bookstark.article.v1.${sha256.convert(utf8.encode(jsonEncode([server.toString(), memberId])))}';
  Uri get listUri => server.replace(
    pathSegments: [..._prefix, 'notes'],
    queryParameters: {'tab': 'articles', 'type': 'article'},
  );

  /// Metadata is authoritative only for the current numeric ID and account.
  Uri editorEntry(Map<String, Object?> metadata, {required int id}) {
    final identify = metadata['blog_identify'];
    if (id <= 0 ||
        metadata['blog_id'] is! int ||
        metadata['member_id'] is! int ||
        metadata['blog_id'] != id ||
        metadata['member_id'] != memberId ||
        metadata['blog_type'] != 'article' ||
        identify is! String ||
        identify.isEmpty ||
        utf8.encode(identify).length > 256 ||
        !_segmentsValid(Uri(pathSegments: [identify])) ||
        identify.contains('?') ||
        identify.contains('#')) {
      throw const FormatException('Invalid article identity');
    }
    final uri = server.replace(
      pathSegments: [..._prefix, 'blogs', identify, 'edit'],
    );
    if (!isInitialEntry(uri)) {
      throw const FormatException('Invalid article entry');
    }
    return uri;
  }

  /// Initial navigation cannot borrow root aliases or add query/fragment data.
  bool isInitialEntry(Uri uri) {
    if (!sameServer(uri) ||
        uri.hasFragment ||
        !_segmentsValid(uri) ||
        !_rawPathValid(uri.toString())) {
      return false;
    }
    if (uri == listUri) return true;
    final path = _relative(uri);
    return !uri.hasQuery &&
        path != null &&
        path.length == 3 &&
        path.first == 'blogs' &&
        path.last == 'edit' &&
        path[1].isNotEmpty &&
        utf8.encode(path[1]).length <= 256;
  }

  // Uri.parse normalizes dot segments; inspect them before parsing.
  static bool _rawPathValid(String value) {
    final match = RegExp(
      r'^(?:[A-Za-z][A-Za-z0-9+.-]*:)?(?://[^/?#]*)?([^?#]*)',
    ).firstMatch(value);
    if (match == null || match.group(1)!.contains('//')) return false;
    try {
      return match.group(1)!.split('/').every((raw) {
        final encoded = raw.runes
            .map(
              (rune) => rune < 128
                  ? String.fromCharCode(rune)
                  : Uri.encodeComponent(String.fromCharCode(rune)),
            )
            .join();
        final part = Uri.decodeComponent(encoded);
        return part != '.' &&
            part != '..' &&
            !part.contains('/') &&
            !part.contains('\\') &&
            !part.contains('%') &&
            !part.runes.any((c) => c < 32 || c == 127);
      });
    } on FormatException {
      return false;
    } on ArgumentError {
      return false;
    }
  }

  static bool _segmentsValid(Uri uri) => uri.pathSegments.every(
    (part) =>
        part != '.' &&
        part != '..' &&
        !part.contains('/') &&
        !part.contains(r'\') &&
        !part.contains('%') &&
        !part.runes.any((c) => c < 32 || c == 127),
  );

  static Uri _server(Uri uri) {
    if (!{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !_segmentsValid(uri) ||
        uri.port <= 0 ||
        uri.port > 65535) {
      throw ArgumentError('Trusted HTTP server base required');
    }
    final parts = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    // Reject ambiguous interior empty segments rather than merge services.
    if (uri.path.contains('//')) throw ArgumentError('Ambiguous server prefix');
    return Uri(
      scheme: uri.scheme,
      host: uri.host.toLowerCase(),
      port: uri.hasPort ? uri.port : null,
      pathSegments: parts,
    );
  }

  bool sameServer(Uri uri) =>
      uri.userInfo.isEmpty &&
      uri.scheme == server.scheme &&
      uri.host.toLowerCase() == server.host &&
      uri.port == server.port;

  List<String>? _relative(Uri uri) {
    final all = uri.pathSegments;
    final prefix = _prefix;
    if (all.length < prefix.length) return null;
    for (var i = 0; i < prefix.length; i++) {
      if (all[i] != prefix[i]) return null;
    }
    return all.sublist(prefix.length);
  }

  /// Root aliases in the Go UI mount inside the configured server prefix.
  /// Only known app/API/asset routes may acquire that interpretation.
  Uri? resolve(String value, {Uri? current, bool navigation = false}) {
    if (utf8.encode(value).length > 8192 || !_rawPathValid(value)) return null;
    final raw = Uri.tryParse(value);
    if (raw == null ||
        !_segmentsValid(raw) ||
        raw.userInfo.isNotEmpty ||
        value.contains(r'\') ||
        value.runes.any((c) => c < 32 || c == 127)) {
      return null;
    }
    final parent =
        current != null &&
            sameServer(current) &&
            _segmentsValid(current) &&
            _relative(current) != null
        ? current
        : server.replace(path: cookiePath);
    final uri = parent.resolveUri(raw);
    if (!sameServer(uri) || !_segmentsValid(uri)) return null;
    final relative = _relative(uri);
    if (relative != null) return uri;
    final parts = uri.pathSegments;
    if (parts.isEmpty) return null;
    final allowed =
        _resourceRoots.contains(parts.first) ||
        (navigation &&
            (_nativeRoutes.containsKey(parts.first) ||
                {'login', 'logout'}.contains(parts.first)));
    if (!allowed) return null;
    return uri.replace(pathSegments: [..._prefix, ...parts]);
  }

  ArticleWebNavigation navigation(String value, {Uri? current}) {
    final raw = Uri.tryParse(value);
    if (utf8.encode(value).length > 8192 ||
        !_rawPathValid(value) ||
        raw == null ||
        !_segmentsValid(raw) ||
        raw.userInfo.isNotEmpty ||
        value.contains(r'\') ||
        value.runes.any((c) => c < 32 || c == 127)) {
      return const ArticleWebNavigation(ArticleWebDestination.blocked, null);
    }
    if (raw.hasScheme && !sameServer(raw)) {
      return ArticleWebNavigation(
        {'http', 'https'}.contains(raw.scheme) && raw.host.isNotEmpty
            ? ArticleWebDestination.external
            : ArticleWebDestination.blocked,
        raw,
      );
    }
    final uri = resolve(value, current: current, navigation: true);
    if (uri == null) {
      return const ArticleWebNavigation(ArticleWebDestination.blocked, null);
    }
    final path = _relative(uri)!;
    if (path.length == 1 && {'login', 'logout'}.contains(path.first)) {
      return ArticleWebNavigation(ArticleWebDestination.sessionEnded, uri);
    }
    if (path.length == 1 && _nativeRoutes.containsKey(path.first)) {
      return ArticleWebNavigation(
        ArticleWebDestination.appRoute,
        uri,
        appRoute: _nativeRoutes[path.first],
      );
    }
    if (path.length == 1 && path.first == 'notes') {
      final query = uri.queryParametersAll;
      if (['tab', 'type'].any((k) => (query[k]?.length ?? 0) > 1)) {
        return const ArticleWebNavigation(ArticleWebDestination.blocked, null);
      }
      final tab = uri.queryParameters['tab'],
          type = uri.queryParameters['type'];
      if (tab == 'notes' || tab == 'tasks' || type == 'note') {
        return ArticleWebNavigation(
          ArticleWebDestination.appRoute,
          uri,
          appRoute: tab == 'tasks' ? 'tasks' : 'notes',
        );
      }
      if ((tab != null && tab != 'articles') ||
          (type != null && type != 'article')) {
        return const ArticleWebNavigation(ArticleWebDestination.blocked, null);
      }
      return ArticleWebNavigation(
        ArticleWebDestination.list,
        uri.replace(
          queryParameters: {
            ...uri.queryParameters,
            'tab': 'articles',
            'type': 'article',
          },
        ),
      );
    }
    if (path.length == 3 &&
        path.first == 'blogs' &&
        path.last == 'edit' &&
        path[1].isNotEmpty &&
        utf8.encode(path[1]).length <= 256) {
      final mode = uri.queryParameters['mode'];
      if (mode != null && !{'edit', 'preview'}.contains(mode)) {
        return const ArticleWebNavigation(ArticleWebDestination.blocked, null);
      }
      return ArticleWebNavigation(ArticleWebDestination.editor, uri);
    }
    return ArticleWebNavigation(ArticleWebDestination.external, uri);
  }
}
