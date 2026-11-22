import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Exported so host tests can verify the actual native HttpClient setting.
HttpClient createRawDocumentHttpClient() =>
    HttpClient()..autoUncompress = false;
http.Client createRawDocumentClient() =>
    IOClient(createRawDocumentHttpClient());
