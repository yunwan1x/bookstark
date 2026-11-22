import 'dart:async';
import 'api_client.dart';
import 'documents_repository.dart';
import 'document_authenticated_sender.dart';
import 'remote_bounded_documents_reader.dart';
import 'owned_document_gzip.dart';

/// Captured account/session and immediate Root retirement abort; no legacy GET.
class OwnedBoundedDocumentsReader implements BoundedDocumentsReader {
  OwnedBoundedDocumentsReader({
    required BookstarkClient client,
    required this._isCurrent,
  }) : _client = client,
       _revision = client.sessionRevision,
       _token = client.exportSession()['token'] {
    _reader = RemoteBoundedDocumentsReader(
      baseUri: client.baseUri,
      send: authenticatedDocumentSender(
        client,
        isCurrent: _current,
        retireTrigger: _stop.future,
      ),
      decodeGzip: decodeOwnedDocumentGzip,
    );
  }
  final BookstarkClient _client;
  final bool Function() _isCurrent;
  final int _revision;
  final String? _token;
  final _stop = Completer<void>();
  late final RemoteBoundedDocumentsReader _reader;
  bool _current() =>
      !_stop.isCompleted &&
      _isCurrent() &&
      _client.sessionRevision == _revision &&
      _client.exportSession()['token'] == _token;
  void retire() {
    if (!_stop.isCompleted) _stop.complete();
  }

  Future<DocumentItem> discover(int id) async {
    if (!_current()) throw StateError('Document account retired');
    final result = await _reader.discoverBounded(id);
    if (!_current()) throw StateError('Document account retired');
    return result.item;
  }

  @override
  Future<TypedDocumentRead> readBounded(
    int id, {
    required int bookId,
    int maxMarkdownReadBytes = documentReadMaxBytes,
  }) async {
    if (!_current()) throw StateError('Document account retired');
    final result = await _reader.readBounded(
      id,
      bookId: bookId,
      maxMarkdownReadBytes: maxMarkdownReadBytes,
    );
    if (!_current()) throw StateError('Document account retired');
    if (result.item.id != id || result.item.bookId != bookId) {
      throw const FormatException('Document identity changed');
    }
    return result;
  }
}
