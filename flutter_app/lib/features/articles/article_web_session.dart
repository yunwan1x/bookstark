import 'dart:async';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/article_web_scope.dart';
import '../html/html_browser_session.dart';

/// Joins the existing browser retirement queue, with cookies in its own profile.
/// A retirement callback hides UI only; it must not recursively close this lease.
final class ArticleWebSession {
  ArticleWebSession._(
    this.client,
    this.scope,
    this._scopeCurrent,
    this._retireUI,
    this.entryUri,
  ) : _token = client.exportSession()['token'] ?? '',
      _sessionRevision = client.sessionRevision;
  static const channel = MethodChannel('bookstark/article_web_session');
  final BookstarkClient client;
  final ArticleWebScope scope;
  final Uri entryUri;
  final bool Function() _scopeCurrent;
  final Future<void> Function() _retireUI;
  final String _token;
  final int _sessionRevision;
  HtmlBrowserSession? _html;
  Future<void>? _nativeOpening, _retiring;
  bool _retired = false, _closeComplete = false;
  String get lease =>
      _html?.lease ?? (throw StateError('Browser lease not ready'));
  bool get isCurrent {
    if (_retired ||
        _closeComplete ||
        client.exportSession()['token'] != _token ||
        client.sessionRevision != _sessionRevision) {
      return false;
    }
    try {
      return _scopeCurrent();
    } catch (_) {
      return false;
    }
  }

  static Future<ArticleWebSession> open({
    required BookstarkClient client,
    required ArticleWebScope scope,
    required bool Function() isCurrentScope,
    required Future<void> Function() retire,
    Uri? entry,
  }) async {
    final initial = entry ?? scope.listUri;
    if (!scope.isInitialEntry(initial)) {
      throw ArgumentError('Invalid article entry');
    }
    final session = ArticleWebSession._(
      client,
      scope,
      isCurrentScope,
      retire,
      initial,
    );
    if (session._token.isEmpty ||
        ArticleWebScope(client.baseUri, scope.memberId).server !=
            scope.server ||
        !session.isCurrent) {
      throw StateError('Current authenticated article scope required');
    }
    try {
      session._html = await HtmlBrowserSession.openLocal(
        retire: session._retire,
      );
      session._check();
      final cookies = Map<String, String>.of(client.exportSession());
      final opening = channel.invokeMethod<void>('open', {
        'format': 1,
        'lease': session.lease,
        'server': scope.server.toString(),
        'profile': scope.profileName,
        'entry': session.entryUri.toString(),
        'cookiePath': scope.cookiePath,
        'cookies': cookies,
        'language': client.language ?? 'zh',
      });
      session._nativeOpening = opening;
      await opening;
      session._check();
      return session;
    } catch (_) {
      await session.close();
      rethrow;
    }
  }

  void _check() {
    if (!isCurrent) throw StateError('Article browser scope retired');
  }

  Future<T?> command<T>(String method) async {
    if (!{
      'pause',
      'resume',
      'back',
      'reload',
      'prepareLeave',
      'state',
    }.contains(method)) {
      throw ArgumentError('Unsupported article browser command');
    }
    _check();
    final result = await channel.invokeMethod<T>(method, {'lease': lease});
    _check();
    return result;
  }

  Future<void> releaseDownload(String id) async {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw ArgumentError('Invalid export identity');
    }
    final html = _html;
    if (html == null) return;
    // Cleanup of this lease remains allowed after retirement; it cannot name an heir.
    await channel.invokeMethod<void>('releaseDownload', {
      'lease': html.lease,
      'id': id,
    });
  }

  Future<void> _retire() {
    final old = _retiring;
    if (old != null) return old;
    _retired = true;
    final work = _retireNow();
    _retiring = work;
    unawaited(
      work.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (identical(_retiring, work)) _retiring = null;
        },
      ),
    );
    return work;
  }

  Future<void> _retireNow() async {
    Object? error;
    StackTrace? trace;
    try {
      await _nativeOpening;
    } catch (_) {}
    final id = _html?.lease;
    if (id != null) {
      try {
        await channel.invokeMethod<void>('close', {'lease': id});
      } catch (failure, stack) {
        error = failure;
        trace = stack;
      }
    }
    try {
      await _retireUI();
    } catch (failure, stack) {
      error ??= failure;
      trace ??= stack;
    }
    if (error != null) Error.throwWithStackTrace(error, trace!);
  }

  Future<void> close() async {
    if (_closeComplete) return;
    final html = _html;
    if (html != null) {
      await html.close();
    } else {
      await _retire();
    }
    _closeComplete = true;
  }
}
