import 'owned_complex_image_upload_journal.dart';
import 'owned_complex_resource_lease.dart';
import 'prepared_owned_image_upload.dart';

/// Per-document single slot. No network operation is inferred from reopening.
class OwnedComplexImageUploadController {
  OwnedComplexImageUploadController({
    required this.journal,
    required this.lease,
    required this.validateReceipt,
  });
  final OwnedComplexImageUploadJournal journal;
  final OwnedComplexResourceLease lease;
  final ({int id, Uri url}) Function(Map<String, Object?> receipt)
  validateReceipt;
  static final Set<String> _owners = {};
  OwnedImageUploadRecord? _record, _knownInMemory;
  bool _opened = false, _retired = false, _busy = false, _claimed = false;
  OwnedImageUploadRecord? get record => _knownInMemory ?? _record;
  bool get busy => _busy;
  bool get needsStorageRetry => _knownInMemory != null;
  bool get canUpload =>
      _opened && !_retired && !_busy && record == null && lease.current;
  void _guard() {
    lease.guard();
    if (_retired) throw StateError('Upload editor ended');
  }

  Future<void> open() async {
    _guard();
    if (_opened) return;
    if (!_owners.add(journal.identity)) {
      throw StateError('Upload review already open');
    }
    _claimed = true;
    try {
      _record = await lease.use(journal.read);
      _guard();
      _opened = true;
    } catch (_) {
      // A malformed upload marker blocks image actions, not anonymous rendering.
      // No operation is left in flight when read has failed.
      _retired = true;
      if (_claimed) {
        _owners.remove(journal.identity);
        _claimed = false;
      }
      rethrow;
    }
  }

  Future<void> upload(PreparedOwnedImageUpload prepared) async {
    if (!canUpload) {
      prepared.retire();
      throw StateError('Resolve retained upload first');
    }
    _busy = true;
    try {
      _guard();
      final pending = OwnedImageUploadRecord(
        bindingId: journal.bindingId,
        inputSHA256: prepared.inputSHA256,
        phase: OwnedImageUploadPhase.unknown,
      );
      final root = await lease.use(
        () => prepared.sendAfter(
          onSubmit: () async {
            _guard();
            // Claim the slot in memory before I/O; even a failed write blocks reposting.
            _record = pending;
            await journal.write(pending);
            _guard();
          },
        ),
      );
      _guard();
      final receipt = validateReceipt(root);
      final known = OwnedImageUploadRecord(
        bindingId: journal.bindingId,
        inputSHA256: pending.inputSHA256,
        phase: OwnedImageUploadPhase.confirmedUrl,
        uploadId: receipt.id,
        url: receipt.url,
      );
      _knownInMemory = known;
      await lease.use(() => journal.write(known));
      _guard();
      _record = known;
      _knownInMemory = null;
    } finally {
      prepared.retire();
      _busy = false;
    }
  }

  /// Storage only: there is deliberately no prepared request parameter.
  Future<void> retryKnownStorage() async {
    _guard();
    if (_busy || _knownInMemory == null) {
      throw StateError('No retained receipt');
    }
    _busy = true;
    try {
      final known = _knownInMemory!;
      await lease.use(() => journal.write(known));
      _guard();
      _record = known;
      _knownInMemory = null;
    } finally {
      _busy = false;
    }
  }

  /// Engine insertion is explicit, source-bound, and never a resource save.
  Future<void> insert({
    required Future<bool> Function() verifyFreshBinding,
    required Future<void> Function(Uri url) insertIntoActualEngine,
  }) async {
    _guard();
    final known = record;
    if (_busy ||
        _knownInMemory != null ||
        known == null ||
        known.phase != OwnedImageUploadPhase.confirmedUrl ||
        known.url == null) {
      throw StateError('No durable confirmed image URL');
    }
    _busy = true;
    try {
      if (!await lease.use(verifyFreshBinding)) {
        throw StateError('Document source changed');
      }
      _guard();
      await lease.use(() => insertIntoActualEngine(known.url!));
      _guard();
      final inserted = OwnedImageUploadRecord(
        bindingId: known.bindingId,
        inputSHA256: known.inputSHA256,
        phase: OwnedImageUploadPhase.inserted,
        uploadId: known.uploadId,
        url: known.url,
      );
      _knownInMemory = inserted;
      await lease.use(() => journal.write(inserted));
      _guard();
      _record = inserted;
      _knownInMemory = null;
    } finally {
      _busy = false;
    }
  }

  /// Independent explicit selection is not reconciliation of an unknown POST.
  /// Keep the unknown marker unchanged, even after inserting an existing image.
  Future<void> insertExisting({
    required Uri url,
    required Future<bool> Function() verifyFreshChoice,
    required Future<bool> Function() verifyFreshBinding,
    required Future<void> Function(Uri url) insertIntoActualEngine,
  }) async {
    _guard();
    if (!_opened || _busy) throw StateError('Upload review unavailable');
    _busy = true;
    try {
      if (!await lease.use(verifyFreshChoice)) {
        throw StateError('Server image changed');
      }
      _guard();
      if (!await lease.use(verifyFreshBinding)) {
        throw StateError('Document source changed');
      }
      _guard();
      await lease.use(() => insertIntoActualEngine(url));
      _guard();
    } finally {
      _busy = false;
    }
  }

  Future<void> dismissInserted() async {
    _guard();
    if (_busy ||
        _knownInMemory != null ||
        record?.phase != OwnedImageUploadPhase.inserted) {
      throw StateError('Upload is not resolved');
    }
    _busy = true;
    try {
      await lease.use(journal.clearInserted);
      _guard();
      _record = null;
    } finally {
      _busy = false;
    }
  }

  // Parent retires the shared page lease before draining actual operations.
  // Hold the slot until drain finishes: another page cannot race a late write.
  void retire() {
    _retired = true;
  }

  Future<void> retireAndDrain() async {
    retire();
    await lease.retireAndDrain();
    if (_claimed) {
      _owners.remove(journal.identity);
      _claimed = false;
    }
  }
}
