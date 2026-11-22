import 'dart:async';
import 'dart:convert';
import 'local_data_maintenance.dart';
import 'local_assistant_creation_receipts.dart';
import 'local_assistant_draft_ledger.dart';
import 'local_assistant_draft_payload.dart';

final class LocalAssistantWriteMarker {
  LocalAssistantWriteMarker({
    required this.namespace,
    required this.bindingId,
    required this.draftId,
    required this.kind,
    this.inputHash,
  }) {
    if (!(namespace == 'local' ||
            RegExp(r'^local-generation:[a-f0-9]{32}$').hasMatch(namespace)) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(bindingId) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(draftId) ||
        (inputHash != null &&
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(inputHash!))) {
      throw const FormatException('Invalid assistant pending-write identity');
    }
  }
  static const prefix = 'bookstark.local-ai-create.v1.';
  final String namespace, bindingId, draftId;
  final String? inputHash;
  final LocalAssistantDraftKind kind;
  String get recordId => jsonEncode([bindingId, draftId, kind.name]);
  String get key =>
      '$prefix${base64Url.encode(utf8.encode(jsonEncode([namespace, recordId])))}';
  factory LocalAssistantWriteMarker.fromKey(String key) {
    try {
      if (!key.startsWith(prefix) || key.length > 2048) {
        throw const FormatException();
      }
      final outer = jsonDecode(
        utf8.decode(base64Url.decode(key.substring(prefix.length))),
      );
      if (outer is! List ||
          outer.length != 2 ||
          outer[0] is! String ||
          outer[1] is! String) {
        throw const FormatException();
      }
      final parts = jsonDecode(outer[1] as String);
      if (parts is! List ||
          parts.length != 3 ||
          parts.any((value) => value is! String)) {
        throw const FormatException();
      }
      final kinds = LocalAssistantDraftKind.values.where(
        (kind) => kind.name == parts[2],
      );
      if (kinds.length != 1) throw const FormatException();
      final result = LocalAssistantWriteMarker(
        namespace: outer[0] as String,
        bindingId: parts[0] as String,
        draftId: parts[1] as String,
        kind: kinds.single,
      );
      if (result.key != key) throw const FormatException();
      return result;
    } catch (_) {
      throw const FormatException('Invalid assistant pending-write key');
    }
  }
}

final class LocalAssistantWriteMarkerUnknown implements Exception {
  const LocalAssistantWriteMarkerUnknown();
}

/// A body-free encrypted marker whose KEY is visible to native recovery metadata.
/// Its lifetime spans intent persistence, SQL, acknowledgement and cleanup.
/// All callbacks at the root include the native durability barrier.
final class LocalAssistantWriteJournal {
  LocalAssistantWriteJournal({
    required this.namespace,
    required this.bindingId,
    required this.maintenance,
    required this.readValue,
    required this.writeValue,
    required this.deleteValue,
    this.isCurrent,
  }) {
    LocalAssistantWriteMarker(
      namespace: namespace,
      bindingId: bindingId,
      draftId: '0' * 32,
      kind: LocalAssistantDraftKind.note,
      inputHash: '0' * 64,
    );
  }
  final String namespace, bindingId;
  final LocalDataMaintenance maintenance;
  final Future<String?> Function(String) readValue;
  final Future<void> Function(String, String) writeValue;
  final Future<void> Function(String) deleteValue;
  final bool Function()? isCurrent;
  static final _tails = <String, Future<void>>{};
  String _value(String hash) => jsonEncode({'format': 1, 'input_hash': hash});
  LocalAssistantWriteMarker _stored(
    LocalAssistantWriteMarker identity,
    String value,
  ) {
    if (value.length > 1024) {
      throw const FormatException('Assistant pending marker exceeds limit');
    }
    final data = jsonDecode(value);
    if (data is! Map ||
        data.length != 2 ||
        data['format'] != 1 ||
        data['input_hash'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['input_hash'] as String)) {
      throw const FormatException('Assistant pending marker needs recovery');
    }
    return LocalAssistantWriteMarker(
      namespace: identity.namespace,
      bindingId: identity.bindingId,
      draftId: identity.draftId,
      kind: identity.kind,
      inputHash: data['input_hash'] as String,
    );
  }

  void _identity(LocalAssistantWriteMarker marker) {
    if (marker.namespace != namespace || marker.bindingId != bindingId) {
      throw StateError('Assistant pending marker belongs to another scope');
    }
  }

  Future<LocalAssistantWriteMarker?> readMarker(
    LocalAssistantWriteMarker identity,
  ) {
    _identity(identity);
    return _serial(identity.key, () async {
      final value = await readValue(identity.key);
      _guard();
      return value == null ? null : _stored(identity, value);
    });
  }

  void _guard() {
    if (maintenance.retired || isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  Future<T> _serial<T>(String key, Future<T> Function() action) =>
      maintenance.use(() {
        _guard();
        final previous = _tails[key] ?? Future<void>.value();
        final next = previous.then((_) async {
          _guard();
          return action();
        });
        final tail = next.then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        );
        _tails[key] = tail;
        unawaited(
          tail.then((_) {
            if (identical(_tails[key], tail)) _tails.remove(key);
          }),
        );
        return next;
      });
  Future<LocalAssistantWriteMarker> prepare(
    LocalAssistantDraftRecord draft,
    String inputHash,
  ) {
    LocalAssistantDraftRecord.fromJson(draft.toJson());
    if (draft.state != LocalAssistantDraftState.pending) {
      throw StateError('Assistant draft is not ready for intent');
    }
    final marker = LocalAssistantWriteMarker(
      namespace: namespace,
      bindingId: bindingId,
      draftId: draft.id,
      kind: draft.payload.kind,
      inputHash: inputHash,
    );
    return _serial(marker.key, () async {
      final previous = await readValue(marker.key);
      _guard();
      if (previous != null) {
        throw StateError('Assistant pending write requires review');
      }
      try {
        await writeValue(marker.key, _value(inputHash));
        _guard();
        final observed = await readValue(marker.key);
        _guard();
        if (observed != _value(inputHash)) {
          throw const LocalAssistantWriteMarkerUnknown();
        }
      } on LocalAssistantDraftOwnerRetired {
        rethrow;
      } catch (_) {
        throw const LocalAssistantWriteMarkerUnknown();
      }
      return marker;
    });
  }

  Future<void> clearAfterResolution(
    LocalAssistantWriteMarker marker,
    LocalAssistantDraftRecord resolved, {
    required Future<LocalAssistantCreationReceipt?> Function() readReceipt,
  }) {
    LocalAssistantDraftRecord.fromJson(resolved.toJson());
    if (marker.inputHash == null ||
        marker.namespace != namespace ||
        marker.bindingId != bindingId ||
        resolved.id != marker.draftId ||
        resolved.payload.kind != marker.kind ||
        !{
          LocalAssistantDraftState.created,
          LocalAssistantDraftState.cancelled,
        }.contains(resolved.state)) {
      throw StateError('Assistant pending marker has not been resolved');
    }
    return _serial(marker.key, () async {
      final current = await readValue(marker.key);
      _guard();
      if (current != null &&
          _stored(marker, current).inputHash != marker.inputHash) {
        throw StateError('Assistant pending marker changed since review');
      }
      final receipt = await readReceipt();
      _guard();
      if (resolved.state == LocalAssistantDraftState.created) {
        if (receipt == null ||
            receipt.key != marker.draftId ||
            receipt.kind != marker.kind ||
            receipt.inputHash != marker.inputHash ||
            resolved.inputHash != marker.inputHash ||
            receipt.resourceId != resolved.resourceId ||
            receipt.resourceId <= 0 ||
            receipt.createdAt <= 0) {
          throw StateError('Assistant creation receipt changed during cleanup');
        }
      } else if (receipt != null) {
        throw StateError('A committed assistant resource requires review');
      }
      if (current == null) return;
      try {
        await deleteValue(marker.key);
        _guard();
        final observed = await readValue(marker.key);
        _guard();
        if (observed != null) throw const LocalAssistantWriteMarkerUnknown();
      } on LocalAssistantDraftOwnerRetired {
        rethrow;
      } catch (_) {
        throw const LocalAssistantWriteMarkerUnknown();
      }
    });
  }
}
