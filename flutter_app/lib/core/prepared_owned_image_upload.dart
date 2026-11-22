/// Fixed request prepared by the real client after auth/CSRF/serialization.
/// Not an image creation/ownership receipt; the upload endpoint may deduplicate.
class PreparedOwnedImageUpload {
  PreparedOwnedImageUpload({
    required this.uri,
    required this.inputSHA256,
    required this._send,
    required this._beforeSubmit,
    required this._abort,
  });
  final Uri uri;
  final String inputSHA256;
  final Future<Map<String, Object?>> Function() _send;
  final void Function() _beforeSubmit, _abort;
  bool _used = false, _closed = false;
  Future<Map<String, Object?>> sendAfter({
    required Future<void> Function() onSubmit,
  }) async {
    // Claim synchronously, before awaiting durable storage. Concurrent sendAfter
    // must not run a second callback or send the prepared multipart twice.
    if (_used || _closed) {
      throw StateError('Prepared image upload already used');
    }
    _used = true;
    try {
      _beforeSubmit();
      await onSubmit();
      if (_closed) throw StateError('Prepared image upload ended');
      _beforeSubmit();
      return await _send();
    } finally {
      retire();
    }
  }

  void retire() {
    if (_closed) return;
    _closed = true;
    _abort();
  }
}
