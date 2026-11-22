import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/notes_repository.dart';
import '../../core/note_list_source.dart';
import '../../core/local_note_list_source.dart';
import '../../core/remote_note_list_source.dart';
import '../../core/note_pin_actions.dart';

/// One mounted list route owns stable repository/source/action instances.
class OwnedNoteListBinding {
  OwnedNoteListBinding._(
    this.repository,
    this.source,
    this.actions,
    this._close,
  );
  final NotesRepository repository;
  final NoteListSource source;
  final NotePinActions? actions;
  final void Function() _close;
  bool _closed = false;
  void retire() {
    if (_closed) return;
    _closed = true;
    actions?.retire();
    _close();
  }

  factory OwnedNoteListBinding.local({
    required LocalNotesRepository repository,
    required bool Function() isCurrent,
  }) {
    var active = true;
    bool current() =>
        active && isCurrent() && !repository.store.maintenance.retired;
    return OwnedNoteListBinding._(
      repository,
      LocalNoteListSource(
        repository: repository,
        collection: repository.collection.name,
        isCurrent: current,
      ),
      null,
      () {
        active = false;
      },
    );
  }
  factory OwnedNoteListBinding.remote({
    required BookstarkClient client,
    required int memberId,
    required NoteCollection collection,
    required String scope,
    required bool Function() isCurrent,
  }) {
    if (memberId <= 0 || scope.isEmpty) {
      throw ArgumentError('Owned list identity required');
    }
    final revision = client.sessionRevision,
        token = client.exportSession()['token'];
    final abort = Completer<void>();
    var active = true;
    bool current() =>
        active &&
        isCurrent() &&
        client.sessionRevision == revision &&
        token != null &&
        token.isNotEmpty &&
        client.exportSession()['token'] == token;
    if (!current()) throw StateError('Owned note list session retired');
    final repository = _OwnedRemoteNoteListRepository(
      client,
      collection: collection,
      isCurrent: current,
      abort: abort.future,
    );
    final source = RemoteNoteListSource(
      expectedMemberId: memberId,
      isCurrent: current,
      readBoundedPage: (path) =>
          client.noteListPageMetadata(path, abortTrigger: abort.future),
    );
    final actions = collection == NoteCollection.note
        ? NotePinActions(
            client: client,
            memberId: memberId,
            scope: scope,
            isCurrent: current,
          )
        : null;
    return OwnedNoteListBinding._(repository, source, actions, () {
      active = false;
      if (!abort.isCompleted) abort.complete();
    });
  }
}

/// Builder closures may change on rebuild; the identity owns binding lifetime.
class OwnedNoteListScope extends StatefulWidget {
  const OwnedNoteListScope({
    super.key,
    required this.identity,
    required this.isCurrent,
    required this.create,
    required this.builder,
  });
  final Object identity;
  final bool Function() isCurrent;
  final OwnedNoteListBinding Function(bool Function() isCurrent) create;
  final Widget Function(BuildContext, OwnedNoteListBinding) builder;
  @override
  State<OwnedNoteListScope> createState() => _OwnedNoteListScopeState();
}

class _OwnedNoteListScopeState extends State<OwnedNoteListScope> {
  late OwnedNoteListBinding binding;
  int epoch = 0;
  OwnedNoteListBinding make() {
    final generation = ++epoch;
    return widget.create(
      () => mounted && epoch == generation && widget.isCurrent(),
    );
  }

  @override
  void initState() {
    super.initState();
    binding = make();
  }

  @override
  void didUpdateWidget(covariant OwnedNoteListScope old) {
    super.didUpdateWidget(old);
    if (old.identity != widget.identity) {
      binding.retire();
      binding = make();
    }
  }

  @override
  void dispose() {
    epoch++;
    binding.retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, binding);
}

/// Preserve the concrete remote repository routing contract while binding the
/// list's destructive action to its original owner at the actual send boundary.
class _OwnedRemoteNoteListRepository extends RemoteNotesRepository {
  _OwnedRemoteNoteListRepository(
    super.client, {
    required super.collection,
    required this.isCurrent,
    required this.abort,
  });
  final bool Function() isCurrent;
  final Future<void> abort;
  void _guard() {
    if (!isCurrent()) throw StateError('Owned note list retired');
  }

  @override
  Future<void> remove(int id) async {
    _guard();
    if (id <= 0) throw ArgumentError('Positive note ID required');
    try {
      await client.mutate(
        'DELETE',
        '/api/blogs/$id',
        const {},
        abortTrigger: abort,
        beforeSubmit: _guard,
      );
    } catch (_) {
      _guard();
      rethrow;
    }
    _guard();
  }
}
