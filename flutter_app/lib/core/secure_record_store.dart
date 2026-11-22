import 'dart:async';
import 'dart:convert';
import 'local_data_maintenance.dart';

/// Ordered storage shared by drafts and conversation context. Platform secure
/// storage is injected at the application boundary, never replaced by plaintext.
class SecureRecordStore {
  SecureRecordStore({
    required this.prefix,
    required this.namespace,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    this.maintenance,
  });
  final String prefix, namespace;
  final LocalDataMaintenance? maintenance;
  final Future<String?> Function(String key) readValue;
  final Future<void> Function(String key, String value) writeValue;
  final Future<void> Function(String key) deleteValue;
  static final Map<String, Future<void>> _tails = {};
  String get _queueKey => jsonEncode([prefix, namespace]);
  String _key(Object? id) =>
      '$prefix.${base64Url.encode(utf8.encode(jsonEncode([namespace, id])))}';

  /// Stable storage identifier only; contains no record value.
  String metadataKey(Object? id) => _key(id);

  Future<T> withMaintenance<T>(Future<T> Function() action) =>
      maintenance?.use(action) ?? Future<T>.sync(action);

  Future<T> _ordered<T>(Future<T> Function() action) => withMaintenance(() {
    final queue = _queueKey;
    final previous = _tails[queue];
    final next = previous == null
        ? Future<T>.sync(action)
        : previous.then((_) => action());
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[queue] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[queue], tail)) _tails.remove(queue);
      }),
    );
    return next;
  });

  /// One namespace queue turn. Callers use injected raw callbacks inside this
  /// turn, never public queued read/write methods (which would reenter it).
  Future<T> withRecordLock<T>(Future<T> Function() action) => _ordered(action);

  Future<String?> readRecord(Object? id) => _ordered(() => readValue(_key(id)));
  Future<void> writeRecord(Object? id, String value) =>
      _ordered(() => writeValue(_key(id), value));
  Future<void> removeRecord(Object? id) =>
      _ordered(() => deleteValue(_key(id)));
}
