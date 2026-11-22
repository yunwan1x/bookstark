import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'local_model_config.dart';

final class LocalAssistantBindingCorrupt extends FormatException {
  const LocalAssistantBindingCorrupt()
    : super('Invalid local assistant binding');
}

/// Configuration fingerprints stay inside encrypted values; keys contain only
/// database identity. A fresh opaque generation isolates any previous writer.
final class LocalAssistantBinding {
  LocalAssistantBinding({
    required String namespace,
    required this.readValue,
    required this.writeValue,
    this.isCurrent,
  }) : key = jsonEncode(['bookstark.ai-binding-v1', namespace]);
  final String key;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final bool Function()? isCurrent;
  static final _pending = <String, Future<void>>{};
  void _guard() {
    if (isCurrent?.call() == false) throw const LocalModelScopeRetired();
  }

  String _id() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final previous = _pending[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      _guard();
      return action();
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _pending[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_pending[key], tail)) _pending.remove(key);
      }),
    );
    return next;
  }

  Future<String> _new(LocalModelConfig config) async {
    final generation = _id();
    final record = jsonEncode({
      'version': 1,
      'generation': generation,
      'config': config.toRecord(),
    });
    _guard();
    // Root callback includes the native durability barrier.
    await writeValue(key, record);
    _guard();
    final readback = await readValue(key);
    _guard();
    if (readback != record) throw const LocalModelSaveUnknown();
    return generation;
  }

  Future<String> open(LocalModelConfig config) => _serial(() async {
    final raw = await readValue(key);
    _guard();
    if (raw != null) {
      try {
        if (utf8.encode(raw).length > 32768) {
          throw const LocalAssistantBindingCorrupt();
        }
        final data = jsonDecode(raw);
        if (data is! Map ||
            data['version'] != 1 ||
            data['generation'] is! String ||
            !RegExp(r'^[a-f0-9]{32}$').hasMatch(data['generation'] as String)) {
          throw const LocalAssistantBindingCorrupt();
        }
        final saved = LocalModelConfig.fromRecord(data['config']);
        if (config.same(saved)) return data['generation'] as String;
      } on FormatException {
        throw const LocalAssistantBindingCorrupt();
      }
    }
    return _new(config);
  });

  /// Only called after explicit recovery confirmation. Resource data and model
  /// configuration live in other records; old context is never sent by reset.
  Future<String> reset(LocalModelConfig config) => _serial(() => _new(config));
}
