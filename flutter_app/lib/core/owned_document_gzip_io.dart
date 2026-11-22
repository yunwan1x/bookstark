// The sender supplies raw wire bytes (autoUncompress=false).
import 'strict_single_gzip.dart';

Stream<List<int>> decodeOwnedDocumentGzip(
  Stream<List<int>> wire, {
  required int maxWireBytes,
  required int maxPlainBytes,
  required Future<void> abortTrigger,
  required Duration timeout,
}) async* {
  yield await decodeStrictSingleGzip(
    wire,
    maxWire: maxWireBytes,
    maxPlain: maxPlainBytes,
    abort: abortTrigger,
    timeout: timeout,
  );
}
