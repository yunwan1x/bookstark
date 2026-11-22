import 'package:http/http.dart' as http;
import 'raw_document_client_stub.dart'
    if (dart.library.io) 'raw_document_client_io.dart'
    as platform;

/// Native implementation returns raw wire bytes. Flutter web fails explicitly.
http.Client createRawDocumentClient() => platform.createRawDocumentClient();
