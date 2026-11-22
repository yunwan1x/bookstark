// Native host draft only; creates HttpClient without sending network traffic.
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/raw_document_client_io.dart';
import 'package:bookstark_flutter/core/raw_document_client_stub.dart' as web;

void main() {
  test(
    'native raw HttpClient really disables automatic gzip decompression',
    () {
      final client = createRawDocumentHttpClient();
      expect(client.autoUncompress, isFalse);
      client.close(force: true);
    },
  );
  test('web raw transport is explicitly unsupported', () {
    expect(web.createRawDocumentClient, throwsUnsupportedError);
  });
}
