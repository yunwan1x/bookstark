import 'dart:async';
import 'local_assistant_creation_receipts.dart';
import 'local_assistant_draft_ledger.dart';
import 'local_assistant_write_journal.dart';

class LocalAssistantCreationCommitted implements Exception {
  const LocalAssistantCreationCommitted(this.receipt);
  final LocalAssistantCreationReceipt receipt;
}

/// One editor owner, one creation attempt. SQL can only follow durable readback
/// of the complete ACTUAL editor draft, pending marker and ledger intent.
class LocalAssistantDraftCreator {
  LocalAssistantDraftCreator({
    required this.receipts,
    required this.ledger,
    required this.journal,
    required this.draft,
    required this.persistAndReadEditorSnapshot,
    this.isCurrent,
  });
  final LocalAssistantCreationReceipts receipts;
  final LocalAssistantDraftLedger ledger;
  final LocalAssistantWriteJournal journal;
  final LocalAssistantDraftRecord draft;
  final Future<LocalAssistantCreationInput> Function(
    LocalAssistantCreationInput,
  )
  persistAndReadEditorSnapshot;
  final bool Function()? isCurrent;
  Future<void>? _pending;
  Future<LocalAssistantCreationReceipt>? _acknowledging;
  LocalAssistantCreationReceipt? _knownReceipt;
  LocalAssistantWriteMarker? _knownMarker;
  bool _retired = false, _attempted = false;
  void _guard() {
    if (_retired || isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  Future<void> retireAndDrain() async {
    _retired = true;
    await _pending;
  }

  Future<LocalAssistantCreationReceipt> create(
    LocalAssistantCreationInput input,
  ) {
    _guard();
    if (_attempted ||
        input.kind != draft.payload.kind ||
        draft.state != LocalAssistantDraftState.pending) {
      throw StateError('Creation attempt requires review');
    }
    _attempted = true;
    final result = _create(input);
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<LocalAssistantCreationReceipt> _create(
    LocalAssistantCreationInput input,
  ) async {
    final readback = await persistAndReadEditorSnapshot(input);
    _guard();
    if (readback.kind != input.kind || readback.digest != input.digest) {
      throw StateError('Editor draft was not durably verified');
    }
    final marker = await journal.prepare(draft, input.digest);
    _guard();
    await ledger.prepare(draft.id, input.digest);
    _guard();
    final receipt = await receipts.create(
      draft.id,
      input,
      preparedHash: input.digest,
    );
    _knownReceipt = receipt;
    _knownMarker = marker;
    return retryKnownAcknowledgement();
  }

  /// An explicit storage-only retry after a KNOWN commit. No content SQL runs.
  Future<LocalAssistantCreationReceipt> retryKnownAcknowledgement() {
    _guard();
    if (_acknowledging case final pending?) return pending;
    final receipt = _knownReceipt, marker = _knownMarker;
    if (receipt == null || marker == null) {
      throw StateError('No known committed creation to acknowledge');
    }
    final result = _acknowledge(receipt, marker);
    _acknowledging = result;
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    unawaited(
      _pending!.then((_) {
        if (identical(_acknowledging, result)) _acknowledging = null;
      }),
    );
    return result;
  }

  Future<LocalAssistantCreationReceipt> _acknowledge(
    LocalAssistantCreationReceipt receipt,
    LocalAssistantWriteMarker marker,
  ) async {
    try {
      _guard();
      final records = await ledger.load();
      _guard();
      final matches = records.where((record) => record.id == draft.id);
      if (matches.length != 1) {
        throw StateError('Committed draft needs recovery');
      }
      var resolved = matches.single;
      if (resolved.state == LocalAssistantDraftState.created) {
        if (resolved.resourceId != receipt.resourceId ||
            resolved.inputHash != receipt.inputHash ||
            resolved.payload.kind != receipt.kind) {
          throw StateError('Creation acknowledgement changed');
        }
      } else {
        resolved = await ledger.acknowledge(draft.id, receipt);
      }
      _guard();
      await journal.clearAfterResolution(
        marker,
        resolved,
        readReceipt: () => receipts.lookup(draft.id),
      );
      _guard();
      return receipt;
    } catch (_) {
      throw LocalAssistantCreationCommitted(receipt);
    }
  }
}
