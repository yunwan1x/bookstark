class NoteSelectionRetired implements Exception {
  const NoteSelectionRetired();
}

class NoteSelectionSnapshot {
  NoteSelectionSnapshot._(
    this.scope,
    this._owner,
    this._epoch,
    Map<int, int> versions,
  ) : _versions = Map.unmodifiable(versions),
      ids = Set.unmodifiable(versions.keys);
  final String scope;
  final Object _owner;
  final int _epoch;
  final Map<int, int> _versions;
  final Set<int> ids;
}

/// Explicit IDs only, independent of the currently visible page/query results.
/// An older completion cannot remove an ID the user deselected and reselected.
class NoteListSelectionController {
  NoteListSelectionController({required this.scope, this.isCurrent}) {
    if (scope.isEmpty) throw ArgumentError('Owned selection scope required');
  }
  final String scope;
  final bool Function()? isCurrent;
  final Object _owner = Object();
  final _selected = <int, int>{};
  int _epoch = 0, _ticket = 0;
  bool _retired = false;
  void _guard() {
    if (_retired || isCurrent?.call() == false) {
      throw const NoteSelectionRetired();
    }
  }

  void _id(int id) {
    if (id <= 0) throw const FormatException('Positive selected ID required');
  }

  Set<int> get selectedIds => Set.unmodifiable(_selected.keys);
  int get count => _selected.length;
  bool get hasSelection => _selected.isNotEmpty;
  bool contains(int id) => _selected.containsKey(id);
  int offscreenCount(Iterable<int> loadedIds) {
    final loaded = Set<int>.of(loadedIds);
    return _selected.keys.where((id) => !loaded.contains(id)).length;
  }

  void setSelected(int id, bool selected) {
    _guard();
    _id(id);
    if (selected) {
      _selected.putIfAbsent(id, () => ++_ticket);
    } else {
      _selected.remove(id);
    }
  }

  void selectLoaded(Iterable<int> loadedIds) {
    _guard();
    final ids = Set<int>.of(loadedIds);
    for (final id in ids) {
      _id(id);
    }
    for (final id in ids) {
      setSelected(id, true);
    }
  }

  NoteSelectionSnapshot capture() {
    _guard();
    return NoteSelectionSnapshot._(scope, _owner, _epoch, _selected);
  }

  void reconcile(
    NoteSelectionSnapshot snapshot, {
    required Iterable<int> verifiedIds,
  }) {
    _guard();
    if (!identical(snapshot._owner, _owner) ||
        snapshot.scope != scope ||
        snapshot._epoch != _epoch) {
      throw const NoteSelectionRetired();
    }
    final verified = Set<int>.of(verifiedIds);
    if (!snapshot.ids.containsAll(verified)) {
      throw const FormatException(
        'Completion IDs exceed the explicit snapshot',
      );
    }
    for (final id in verified) {
      if (_selected[id] == snapshot._versions[id]) _selected.remove(id);
    }
  }

  bool clearForQueryChange({required bool confirmed}) {
    _guard();
    if (_selected.isNotEmpty && !confirmed) return false;
    _selected.clear();
    _epoch++;
    return true;
  }

  void retire() {
    _retired = true;
    _selected.clear();
    _epoch++;
  }
}
