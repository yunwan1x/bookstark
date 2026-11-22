Stream<List<int>> decodeOwnedDocumentGzip(
  Stream<List<int>> wire, {
  required int maxWireBytes,
  required int maxPlainBytes,
  required Future<void> abortTrigger,
  required Duration timeout,
}) => Stream<List<int>>.error(
  UnsupportedError('Raw document gzip unsupported on this platform'),
);
