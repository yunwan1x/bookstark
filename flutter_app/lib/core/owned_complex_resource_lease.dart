import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'api_client.dart';
import 'complex_editor_document.dart';

class OwnedComplexResourceRetired implements Exception {
  const OwnedComplexResourceRetired();
}

/// Lifecycle authority only. Never passed to JS or serialized with credentials.
class OwnedComplexResourceLease {
  OwnedComplexResourceLease({
    required this.client,
    required this.memberId,
    required this.resourceId,
    required this.bookId,
    required this.note,
    required this.kind,
    this.blogCollection,
    required String namespace,
    required this.isCurrentScope,
  }) : revision = client.sessionRevision,
       _token = client.exportSession()['token'],
       identity = sha256
           .convert(
             utf8.encode(
               jsonEncode([
                 'owned-complex-resources-v1',
                 client.baseUri.toString(),
                 memberId,
                 resourceId,
                 bookId,
                 note,
                 kind.name,
                 namespace,
                 if (blogCollection != null) ['blogCollection', blogCollection],
               ]),
             ),
           )
           .toString() {
    if (memberId <= 0 ||
        resourceId <= 0 ||
        (note ? bookId != 0 : bookId <= 0) ||
        namespace.isEmpty ||
        kind == ComplexEditorKind.markdown ||
        blogCollection != null &&
            (!note || !{'note', 'article'}.contains(blogCollection))) {
      throw ArgumentError('Existing owned complex document required');
    }
    guard();
  }
  final BookstarkClient client;
  final int memberId, resourceId, bookId, revision;
  final bool note;
  final String? blogCollection;
  final ComplexEditorKind kind;
  final String identity;
  final String? _token;
  final bool Function() isCurrentScope;
  final _abort = Completer<void>();
  final _work = <Future<void>>{};
  bool _retired = false;
  Future<void>? _draining;
  Future<void> get abortTrigger => _abort.future;
  bool get current {
    if (_retired ||
        client.sessionRevision != revision ||
        _token == null ||
        _token.isEmpty ||
        client.exportSession()['token'] != _token) {
      return false;
    }
    try {
      return isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  void guard() {
    if (!current) throw const OwnedComplexResourceRetired();
  }

  Future<T> use<T>(Future<T> Function() action) {
    guard();
    final result = Future<T>.sync(action);
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _work.add(completed);
    unawaited(
      completed.then((_) {
        _work.remove(completed);
      }),
    );
    return result;
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _abort.complete();
  }

  /// Tracks HTTP/picker/capture work only, never a Navigator human future.
  Future<void> retireAndDrain() {
    retire();
    return _draining ??= Future.wait(_work.toList()).then<void>((_) {});
  }
}
