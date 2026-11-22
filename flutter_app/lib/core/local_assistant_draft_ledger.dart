import 'local_assistant_creation_receipts.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'local_assistant_draft_payload.dart';

enum LocalAssistantDraftState {
  pending,
  committing,
  unknown,
  cancelled,
  created,
}

final class LocalAssistantDraftRecord {
  const LocalAssistantDraftRecord({
    required this.id,
    required this.payload,
    required this.state,
    this.inputHash,
    this.resourceId,
  });
  factory LocalAssistantDraftRecord.fromJson(Object? raw) {
    if (raw is! Map ||
        raw.keys.any(
          (key) => !{
            'id',
            'payload',
            'state',
            'input_hash',
            'resource_id',
          }.contains(key),
        ) ||
        raw['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(raw['id'] as String)) {
      throw const FormatException('Invalid assistant draft record');
    }
    final state = LocalAssistantDraftState.values.where(
      (state) => state.name == raw['state'],
    );
    if (state.length != 1) {
      throw const FormatException('Invalid assistant draft state');
    }
    final hash = raw['input_hash'], resource = raw['resource_id'];
    final needsHash = {
      LocalAssistantDraftState.committing,
      LocalAssistantDraftState.unknown,
      LocalAssistantDraftState.created,
    }.contains(state.single);
    if (needsHash
        ? hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)
        : hash != null) {
      throw const FormatException('Invalid assistant draft intent');
    }
    if (state.single == LocalAssistantDraftState.created
        ? resource is! int || resource <= 0
        : resource != null) {
      throw const FormatException('Invalid assistant draft receipt');
    }
    return LocalAssistantDraftRecord(
      id: raw['id'] as String,
      payload: LocalAssistantDraftPayload.fromJson(raw['payload']),
      state: state.single,
      inputHash: hash as String?,
      resourceId: resource as int?,
    );
  }
  final String id;
  final LocalAssistantDraftPayload payload;
  final LocalAssistantDraftState state;
  final String? inputHash;
  final int? resourceId;
  Map<String, Object?> toJson() => {
    'id': id,
    'payload': payload.toJson(),
    'state': state.name,
    if (inputHash != null) 'input_hash': inputHash,
    if (resourceId != null) 'resource_id': resourceId,
  };
}

final class LocalAssistantDraftStorageUnknown implements Exception {
  const LocalAssistantDraftStorageUnknown();
}

final class LocalAssistantDraftOwnerRetired implements Exception {
  const LocalAssistantDraftOwnerRetired();
}

/// A resolved record still owns recovery metadata or its safety could not be
/// established. UI must direct the user to local recovery management.
final class LocalAssistantDraftNeedsAttention implements Exception {
  const LocalAssistantDraftNeedsAttention();
}

/// Encrypted callbacks are supplied by the root with the native commit barrier.
/// Preparing an intent precedes the SQL write. No method here writes content.
final class LocalAssistantDraftLedger {
  LocalAssistantDraftLedger({
    required String namespace,
    required this.readValue,
    required this.writeValue,
    this.isCurrent,
  }) : key = jsonEncode(['bookstark.ai-drafts-v1', namespace]);
  final String key;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final bool Function()? isCurrent;
  static final _tails = <String, Future<void>>{};
  void _guard() {
    if (isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final previous = _tails[key] ?? Future<void>.value();
    final next = previous.then((_) async {
      _guard();
      return action();
    });
    final tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    _tails[key] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return next;
  }

  Future<List<LocalAssistantDraftRecord>> _read() async {
    _guard();
    final raw = await readValue(key);
    _guard();
    if (raw == null) return [];
    if (utf8.encode(raw).length > 160 * 1024) {
      throw const FormatException('Assistant draft record exceeds limit');
    }
    final data = jsonDecode(raw);
    if (data is! Map ||
        data.keys.any((key) => !{'version', 'drafts'}.contains(key)) ||
        data['version'] != 1 ||
        data['drafts'] is! List ||
        (data['drafts'] as List).length > 6) {
      throw const FormatException('Invalid assistant draft ledger');
    }
    final records = [
      for (final row in data['drafts'] as List)
        LocalAssistantDraftRecord.fromJson(row),
    ];
    if (records.map((record) => record.id).toSet().length != records.length) {
      throw const FormatException('Duplicate assistant draft identity');
    }
    return records;
  }

  Future<void> _write(List<LocalAssistantDraftRecord> records) async {
    final raw = jsonEncode({
      'version': 1,
      'drafts': records.map((record) => record.toJson()).toList(),
    });
    if (utf8.encode(raw).length > 160 * 1024) {
      throw const FormatException('Assistant drafts exceed limit');
    }
    _guard();
    try {
      await writeValue(key, raw);
      _guard();
      final observed = await readValue(key);
      _guard();
      if (observed != raw) throw const LocalAssistantDraftStorageUnknown();
    } on LocalAssistantDraftOwnerRetired {
      rethrow;
    } catch (_) {
      throw const LocalAssistantDraftStorageUnknown();
    }
  }

  Future<List<LocalAssistantDraftRecord>> load() =>
      _serial(() async => List.unmodifiable(await _read()));
  Future<LocalAssistantDraftRecord> propose(
    LocalAssistantDraftPayload payload,
  ) => _serial(() async {
    final records = await _read();
    if (records.length >= 6) {
      throw StateError('Assistant proposal limit reached');
    }
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final record = LocalAssistantDraftRecord(
      id: id,
      payload: payload,
      state: LocalAssistantDraftState.pending,
    );
    await _write([...records, record]);
    return record;
  });

  /// Explicit terminal-list cleanup only. The queue covers the fresh record,
  /// safety check and durable removal; no unresolved record is ever pruned.
  /// canForget must not re-enter this ledger queue.
  Future<void> forgetResolved(
    String id, {
    required Future<bool> Function(LocalAssistantDraftRecord record) canForget,
  }) => _serial(() async {
    final records = await _read();
    final index = records.indexWhere((record) => record.id == id);
    if (index < 0) throw StateError('Assistant draft record is unavailable');
    final record = records[index];
    if (!{
      LocalAssistantDraftState.created,
      LocalAssistantDraftState.cancelled,
    }.contains(record.state)) {
      throw const LocalAssistantDraftNeedsAttention();
    }
    bool allowed;
    try {
      allowed = await canForget(record);
    } on LocalAssistantDraftOwnerRetired {
      rethrow;
    } catch (_) {
      _guard();
      throw const LocalAssistantDraftNeedsAttention();
    }
    _guard();
    if (!allowed) throw const LocalAssistantDraftNeedsAttention();
    await _write([
      for (var position = 0; position < records.length; position++)
        if (position != index) records[position],
    ]);
  });

  Future<LocalAssistantDraftRecord> _change(
    String id,
    FutureOr<LocalAssistantDraftRecord> Function(LocalAssistantDraftRecord)
    action,
  ) => _serial(() async {
    final records = await _read();
    final index = records.indexWhere((record) => record.id == id);
    if (index < 0) throw StateError('Assistant draft not found');
    final changed = await action(records[index]);
    final next = List.of(records)..[index] = changed;
    await _write(next);
    return changed;
  });
  Future<LocalAssistantDraftRecord> cancel(String id) => _change(id, (record) {
    if (record.state != LocalAssistantDraftState.pending) {
      throw StateError('Pending SQL result requires review');
    }
    return LocalAssistantDraftRecord(
      id: id,
      payload: record.payload,
      state: LocalAssistantDraftState.cancelled,
    );
  });
  Future<LocalAssistantDraftRecord> prepare(String id, String inputHash) =>
      _change(id, (record) {
        if (record.state != LocalAssistantDraftState.pending ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(inputHash)) {
          throw StateError('Assistant write intent cannot be replayed');
        }
        return LocalAssistantDraftRecord(
          id: id,
          payload: record.payload,
          state: LocalAssistantDraftState.committing,
          inputHash: inputHash,
        );
      });
  Future<LocalAssistantDraftRecord> markUnknown(String id) =>
      _change(id, (record) {
        if (record.state != LocalAssistantDraftState.committing) {
          throw StateError('Assistant write is not pending');
        }
        return LocalAssistantDraftRecord(
          id: id,
          payload: record.payload,
          state: LocalAssistantDraftState.unknown,
          inputHash: record.inputHash,
        );
      });

  /// The caller obtains this receipt from this database after the save returned,
  /// or after an explicit read-only recovery review. A model response is never
  /// accepted as a receipt.
  Future<LocalAssistantDraftRecord> acknowledge(
    String id,
    LocalAssistantCreationReceipt receipt,
  ) => _change(id, (record) {
    if (!{
          LocalAssistantDraftState.committing,
          LocalAssistantDraftState.unknown,
        }.contains(record.state) ||
        receipt.key != id ||
        receipt.kind != record.payload.kind ||
        receipt.inputHash != record.inputHash ||
        receipt.resourceId <= 0) {
      throw StateError('Assistant creation receipt requires matching review');
    }
    return LocalAssistantDraftRecord(
      id: id,
      payload: record.payload,
      state: LocalAssistantDraftState.created,
      inputHash: record.inputHash,
      resourceId: receipt.resourceId,
    );
  });

  /// The UI must drain/retire the originating save before offering this action.
  /// A fresh absence check can cancel an intent; it never retries creation.
  Future<LocalAssistantDraftRecord> cancelAfterReadOnlyReview(
    String id, {
    required String expectedInputHash,
    required Future<LocalAssistantCreationReceipt?> Function() readReceipt,
  }) => _change(id, (record) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expectedInputHash) ||
        !{
          LocalAssistantDraftState.pending,
          LocalAssistantDraftState.committing,
          LocalAssistantDraftState.unknown,
        }.contains(record.state) ||
        (record.state != LocalAssistantDraftState.pending &&
            record.inputHash != expectedInputHash)) {
      throw StateError('Assistant intent changed before review');
    }
    if (await readReceipt() != null) {
      throw StateError('Committed assistant creation requires acknowledgement');
    }
    _guard();
    return LocalAssistantDraftRecord(
      id: id,
      payload: record.payload,
      state: LocalAssistantDraftState.cancelled,
    );
  });
}
