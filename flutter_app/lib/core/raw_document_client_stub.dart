import 'package:http/http.dart' as http;

http.Client createRawDocumentClient() => throw UnsupportedError(
  'Raw document wire transport is unavailable on this platform',
);
