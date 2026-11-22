import 'package:flutter/foundation.dart';
import 'complex_editor_document.dart';
import 'notes_repository.dart';
import 'owned15_creation_recovery_controller.dart';

final class Owned15NativeCreationNeedsReview implements Exception {
  const Owned15NativeCreationNeedsReview();
  @override String toString()=> 'Read-only creation review is required; no creation retry is permitted.';
}

/// Null-ID native Markdown NOTE creation only. Articles never enter this class.
/// Caller must mount drafts:null and replace the editor on reviewRequired,
/// including after a known successful receipt. No saved-ID acknowledgement is
/// emitted before explicit full-tuple review and record cleanup.
final class Owned15NativeCreationRepository extends NotesRepository {
  Owned15NativeCreationRepository({required this.controller,
    required this.operation,required this.isCurrent});
  final Owned15CreationRecoveryController controller;
  final String operation;
  final bool Function() isCurrent;
  final ValueNotifier<bool> reviewRequired=ValueNotifier(false);
  Note? _snapshot;
  bool _preparing=false,_attempted=false,_closed=false;
  Note? get memorySnapshot=>_snapshot;
  void _guard() {
    if(_closed || !controller.current || !isCurrent()) {
      throw StateError('Creation editor retired');
    }
  }
  @override Future<int> save(Note note) async {
    _guard();
    if(note.id!=null || _attempted || _preparing) {
      throw const Owned15NativeCreationNeedsReview();
    }
    _preparing=true;
    try {
      if(note.isProtected && (note.unlockPassword==null ||
          note.unlockPassword!.isEmpty)) {
        throw StateError('A memory-only password is required');
      }
      final input=await controller.creator.prepare(creationKey:operation,
        collection:'note',document:ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,note.content),
        title:note.title,labels:note.labels,
        password:note.isProtected?note.unlockPassword:null);
      _guard();
      _snapshot=Note(title:note.title,content:note.content,
        labels:List<String>.unmodifiable(note.labels),isProtected:note.isProtected);
      _attempted=true;
      try {
        await controller.submit(input);
      } finally {
        if(!_closed)reviewRequired.value=true;
      }
    } finally {_preparing=false;}
    throw const Owned15NativeCreationNeedsReview();
  }
  /// Synchronous memory release. Real worker drain remains controller.retire.
  void releaseMemory() {
    _closed=true;
    _snapshot=null;
  }
  @override Future<List<Note>> list({String keyword='',int page=1})=>
    Future.error(StateError('Creation repository cannot list resources'));
  @override Future<Note> read(int id)=>
    Future.error(StateError('Use actual typed generation reader'));
  @override Future<void> remove(int id)=>
    Future.error(StateError('Creation recovery cannot delete resources'));
}
