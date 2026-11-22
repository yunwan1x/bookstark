/// Serialized changes to the saved server session. No secrets are logged here.
class SessionVault {
  SessionVault({
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
  });
  final Future<String?> Function() readValue;
  final Future<void> Function(String) writeValue;
  final Future<void> Function() deleteValue;
  Future<void> _tail = Future<void>.value();
  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<String?> read() => _serialize(readValue);
  Future<void> clear() => _serialize(deleteValue);
  Future<bool> save(String value, {required bool Function() stillCurrent}) =>
      _serialize(() async {
        if (!stillCurrent()) {
          return false;
        }
        await writeValue(value);
        return stillCurrent();
      });
}
