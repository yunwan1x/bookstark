import 'local_assistant_creation_receipts.dart';
import 'local_assistant_draft_ledger.dart';
import 'local_assistant_write_journal.dart';

/// Created only after the originating editor save has been retired and drained.
/// Never inserts or updates content; retries only durable acknowledgement/cleanup.
class LocalAssistantSaveReview {
  LocalAssistantSaveReview({
    required this.receipts,
    required this.ledger,
    required this.journal,
    required this.identity,
    required this.drainOriginatingSave,
    this.isCurrent,
    this.expectedResourceId,
  });
  final LocalAssistantCreationReceipts receipts;
  final LocalAssistantDraftLedger ledger;
  final LocalAssistantWriteJournal journal;
  final LocalAssistantWriteMarker identity;
  final Future<void> Function() drainOriginatingSave;
  final bool Function()? isCurrent;
  final int? expectedResourceId;
  bool _drained = false, _busy = false;
  void _guard() {
    if (isCurrent?.call() == false) {
      throw const LocalAssistantDraftOwnerRetired();
    }
  }

  Future<LocalAssistantCreationInspection> inspect() async {
    _guard();
    if (!_drained) {
      await drainOriginatingSave();
      _guard();
      _drained = true;
    }
    final result = await receipts.inspect(identity.draftId);
    _guard();
    if (expectedResourceId != null &&
        (result.receipt == null ||
            result.receipt!.resourceId != expectedResourceId)) {
      throw StateError('Editor resource identity changed');
    }
    final marker = await journal.readMarker(identity);
    _guard();
    if (marker == null) {
      final records = await ledger.load();
      _guard();
      final record = records
          .where((record) => record.id == identity.draftId)
          .single;
      final receipt = result.receipt;
      if (record.state != LocalAssistantDraftState.created ||
          record.payload.kind != identity.kind ||
          receipt == null ||
          receipt.key != identity.draftId ||
          receipt.kind != identity.kind ||
          record.inputHash != receipt.inputHash ||
          record.resourceId != receipt.resourceId) {
        throw StateError('Missing write marker needs recovery');
      }
    }
    return result;
  }

  Future<void> resolve(LocalAssistantCreationInspection reviewed) async {
    if (_busy) throw StateError('Review resolution already in progress');
    _busy = true;
    try {
      final fresh = await inspect();
      if (fresh.key != reviewed.key ||
          fresh.fingerprint != reviewed.fingerprint) {
        throw StateError('Save review changed');
      }
      final marker = await journal.readMarker(identity);
      _guard();
      final records = await ledger.load();
      _guard();
      final matches = records.where((record) => record.id == identity.draftId);
      if (matches.length != 1) throw StateError('Draft needs recovery');
      var record = matches.single;
      if (record.payload.kind != identity.kind) {
        throw StateError('Draft kind changed');
      }
      final receipt = fresh.receipt;
      if (expectedResourceId != null &&
          (receipt == null || receipt.resourceId != expectedResourceId)) {
        throw StateError('Editor resource identity changed');
      }
      if (marker == null) {
        // A successful delete followed by a failed durability barrier can leave
        // no marker. Only an already acknowledged, exact receipt is sufficient.
        // Keep editor vaults untouched: they can contain newer unsaved edits.
        if (record.state != LocalAssistantDraftState.created ||
            receipt == null ||
            receipt.key != identity.draftId ||
            receipt.kind != identity.kind ||
            record.inputHash != receipt.inputHash ||
            record.resourceId != receipt.resourceId) {
          throw StateError('Missing write marker needs recovery');
        }
        return;
      }
      if (marker.inputHash == null) {
        throw StateError('Pending save identity is unavailable');
      }
      if (receipt != null) {
        if (receipt.inputHash != marker.inputHash ||
            receipt.kind != marker.kind) {
          throw StateError('Receipt does not match the reviewed write');
        }
        if (record.state == LocalAssistantDraftState.created) {
          if (record.inputHash != receipt.inputHash ||
              record.resourceId != receipt.resourceId) {
            throw StateError('Acknowledgement changed');
          }
        } else {
          record = await ledger.acknowledge(identity.draftId, receipt);
        }
      } else if (record.state != LocalAssistantDraftState.cancelled) {
        record = await ledger.cancelAfterReadOnlyReview(
          identity.draftId,
          expectedInputHash: marker.inputHash!,
          readReceipt: () => receipts.lookup(identity.draftId),
        );
      }
      _guard();
      await journal.clearAfterResolution(
        marker,
        record,
        readReceipt: () => receipts.lookup(identity.draftId),
      );
      _guard();
    } finally {
      _busy = false;
    }
  }
}
