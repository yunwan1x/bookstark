import 'package:crypto/crypto.dart' as crypto;
import 'drive_models.dart';
import 'drive_repository.dart';
import 'file_draft_vault.dart';

/// A single editor session. UI serializes operations and disables editing while
/// saving. Pending writes survive process death and are resolved by reads only.
class FileEditorController {
  FileEditorController(this.repository, this.vault);
  final DriveRepository repository;
  final FileDraftVault vault;
  DriveText? document;
  FileDraftRecord? draft;
  String content = '';
  bool conflict = false, busy = false, cleanupPending = false;
  String? pendingHash;
  bool get dirty => document != null && content != document!.content;
  bool get writable =>
      document != null &&
      !busy &&
      !conflict &&
      pendingHash == null &&
      !cleanupPending;

  Future<void> load(DriveNode source) async {
    if (busy) throw StateError('Editor operation already running');
    busy = true;
    try {
      final current = await repository.readText(source);
      // Do not expose an editable blank file if secure storage is unreadable.
      final saved = await vault.read(current.node);
      document = current;
      draft = saved;
      content = saved?.content ?? current.content;
      pendingHash = saved?.pendingHash;
      conflict = saved != null && !saved.sameBase(current);
      cleanupPending = false;
    } finally {
      busy = false;
    }
  }

  Future<void> edit(String value) async {
    if (!writable) {
      throw StateError('Editor needs verification or conflict review');
    }
    final next = FileDraftRecord.fromDocument(document!, value);
    // Keep the visible buffer even on storage failure, but never claim durable
    // persistence or start a server write until a later draft write succeeds.
    content = value;
    await vault.write(next);
    draft = next;
  }

  Future<void> save() async {
    if (!writable) {
      throw StateError('Editor needs verification or conflict review');
    }
    if (!dirty) return;
    busy = true;
    final base = document!;
    try {
      final hash = crypto.sha256.convert(base.encode(content)).toString();
      final record = FileDraftRecord.fromDocument(
        base,
        content,
        pendingHash: hash,
      );
      await vault.write(record); // must succeed before any request can mutate
      draft = record;
      pendingHash = hash;
      DriveNode saved;
      try {
        saved = await repository.saveText(base, content);
      } on DriveConflict {
        // A verified precondition failure did not send our write. Preserve the
        // pending record until explicit review, so a crash cannot lose text.
        conflict = true;
        rethrow;
      }
      if (saved.id != base.node.id ||
          saved.path != base.node.path ||
          saved.etag != hash) {
        throw const FormatException('File save acknowledgement does not match');
      }
      document = DriveText(
        node: saved,
        content: content,
        hasBom: base.hasBom,
        hash: hash,
      );
      pendingHash = null;
      conflict = false;
      cleanupPending = true;
      await vault.remove(base.node);
      draft = null;
      cleanupPending = false;
    } finally {
      busy = false;
    }
  }

  /// Never repeats PUT, including when the server acknowledged a write but the
  /// canonical metadata read failed. A different hash requires explicit review.
  Future<bool> verifyPending() async {
    if (busy || document == null || pendingHash == null) {
      throw StateError('No pending save to verify');
    }
    busy = true;
    try {
      final current = await repository.lookup(document!.node.path);
      if (current == null || current.id != document!.node.id) {
        conflict = true;
        return false;
      }
      final actual = await repository.readText(current);
      if (actual.hash != pendingHash ||
          actual.content != content ||
          actual.hasBom != document!.hasBom) {
        conflict = true;
        return false;
      }
      document = actual;
      pendingHash = null;
      conflict = false;
      cleanupPending = true;
      await vault.remove(actual.node);
      draft = null;
      cleanupPending = false;
      return true;
    } finally {
      busy = false;
    }
  }

  /// UI must show the current server version and obtain explicit user choice
  /// before calling this. A fresh snapshot still passes normal repository checks.
  Future<void> acceptReviewedBase(DriveText reviewed) async {
    if (busy ||
        document == null ||
        reviewed.node.id != document!.node.id ||
        reviewed.node.path != document!.node.path) {
      throw StateError('Invalid reviewed file');
    }
    busy = true;
    try {
      final record = FileDraftRecord.fromDocument(reviewed, content);
      await vault.write(record);
      document = reviewed;
      draft = record;
      pendingHash = null;
      conflict = false;
      cleanupPending = false;
    } finally {
      busy = false;
    }
  }

  Future<void> retryCleanup() async {
    if (busy || !cleanupPending || document == null) {
      throw StateError('No draft cleanup pending');
    }
    busy = true;
    try {
      await vault.remove(document!.node);
      draft = null;
      cleanupPending = false;
    } finally {
      busy = false;
    }
  }
}
