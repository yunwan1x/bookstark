import 'dart:typed_data';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_recovery_store.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';

/// Owned bytes fake plus actual-SQL reply-loss adapter; no native proof.
class OwnedBytes implements ComplexRecoveryBytesStore {
  final values = <String, Uint8List>{};
  final events = <String>[];
  bool failWrite = false,
      loseWriteReply = false,
      failRemove = false,
      failKnownId = false;
  Future<void> Function(LocalArticleCreationRecord)? beforeWrite;
  @override
  Future<Uint8List?> read(String key) async {
    final value = values[key];
    return value == null ? null : Uint8List.fromList(value);
  }

  @override
  Future<void> write(String key, Uint8List bytes) async {
    final record = LocalArticleCreationRecord.decode(bytes);
    if (failWrite || failKnownId && record.createdId != null) {
      throw StateError('Owned storage failure');
    }
    await beforeWrite?.call(record);
    values[key] = Uint8List.fromList(bytes);
    if (loseWriteReply) throw StateError('Owned lost durable reply');
  }

  @override
  Future<void> remove(String key) async {
    if (failRemove) throw StateError('Owned cleanup failure');
    values.remove(key);
    events.add("draft-delete");
  }
}

class LostReplySQL implements ComplexNotesCreationRepository {
  LostReplySQL(this.delegate);
  final LocalComplexNotesRepository delegate;
  bool dropAfterCommit = false;
  int creates = 0, lookups = 0;
  Future<void> Function()? afterCommit;
  @override
  String get scope => delegate.scope;
  @override
  String get collection => delegate.collection;
  @override
  ComplexEditorKind get kind => delegate.kind;
  @override
  Future<ComplexCreationOutcome> createOnce(
    ComplexNoteEdit edit, {
    required String creationKey,
  }) async {
    creates++;
    final result = await delegate.createOnce(edit, creationKey: creationKey);
    await afterCommit?.call();
    if (dropAfterCommit) {
      throw StateError('Owned actual SQL commit reply dropped');
    }
    return result;
  }

  @override
  Future<ComplexCreationReceipt?> findCreation(String key) async {
    lookups++;
    return delegate.findCreation(key);
  }
}
