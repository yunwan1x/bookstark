import 'dart:async';
import 'package:bookstark_flutter/core/api_client.dart';
import 'remote_bounded_documents_reader.dart';

SendDocumentRead authenticatedDocumentSender(
  BookstarkClient client, {
  required bool Function() isCurrent,
  Future<void>? retireTrigger,
}) => (request) async {
  if (!isCurrent() ||
      request.method != 'GET' ||
      request.followRedirects ||
      request.autoUncompress ||
      !request.useCurrentAuthenticatedSession) {
    throw StateError('Document raw scope unavailable');
  }
  final response = await client.rawDocumentGet(
    request.uri,
    maxWireBytes: request.maxWireBytes,
    abortTrigger: retireTrigger == null
        ? request.abortTrigger
        : Future.any<void>([request.abortTrigger, retireTrigger]),
  );
  if (!isCurrent()) {
    await response.stream.listen((_) {}, onError: (Object _) {}).cancel();
    throw StateError('Document raw scope retired');
  }
  Stream<List<int>> body() async* {
    await for (final chunk in response.stream) {
      if (!isCurrent()) throw StateError('Document raw scope retired');
      yield chunk;
    }
  }

  return DocumentWireResponse(
    requestUri: request.uri,
    status: response.statusCode,
    headers: response.headers,
    body: body(),
    isDecoded: false,
  );
};
