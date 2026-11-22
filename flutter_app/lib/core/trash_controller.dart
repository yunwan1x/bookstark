import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'trash_repository.dart';

enum TrashItemPhase {
  acknowledgedRemoved,
  unknown,
  unverified,
  failed,
  absentWithoutReceipt,
}

class TrashItemResult {
  const TrashItemResult(this.entry, this.operation, this.phase);
  final TrashEntry entry;
  final TrashOperation operation;
  final TrashItemPhase phase;
  bool get unresolved =>
      phase == TrashItemPhase.unknown || phase == TrashItemPhase.unverified;
}

class TrashController extends ChangeNotifier {
  TrashController(this.repository);
  final TrashRepository repository;
  TrashPageData? data;
  String type = '';
  bool busy = false, readFailed = false, _closed = false;
  int _generation = 0;
  final selected = <int, TrashEntry>{};
  final results = <int, TrashItemResult>{};
  bool get unresolved => results.values.any((v) => v.unresolved);
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> load({String? filter, int? page}) async {
    if (_closed || busy) {
      return;
    }
    if (filter != null &&
        filter != type &&
        (selected.isNotEmpty || unresolved)) {
      return;
    }
    final g = ++_generation, nextType = filter ?? type;
    busy = true;
    readFailed = false;
    _emit();
    try {
      final actual = await repository.read(
        type: nextType,
        page: page ?? (filter != null ? 1 : data?.page ?? 1),
      );
      if (_closed || g != _generation) {
        return;
      }
      type = nextType;
      data = actual;
    } catch (_) {
      if (!_closed && g == _generation) {
        readFailed = true;
      }
    } finally {
      if (!_closed && g == _generation) {
        busy = false;
        _emit();
      }
    }
  }

  void toggle(TrashEntry entry) {
    if (_closed ||
        busy ||
        unresolved ||
        !(data?.entries.any((v) => v.same(entry)) ?? false)) {
      return;
    }
    if (selected.containsKey(entry.id)) {
      selected.remove(entry.id);
    } else {
      if (selected.length < 200) {
        selected[entry.id] = entry;
      }
    }
    _emit();
  }

  void clearSelection() {
    if (!busy && !unresolved) {
      selected.clear();
      _emit();
    }
  }

  void selectPage() {
    if (_closed || busy || unresolved || data == null) {
      return;
    }
    for (final entry in data!.entries) {
      if (selected.length >= 200) {
        break;
      }
      selected[entry.id] = entry;
    }
    _emit();
  }

  bool _rejected(Object e) =>
      e is TrashPreflightFailure ||
      e is ApiFailure && e.status >= 400 && e.status < 500 && e.status != 408;
  Future<void> apply(
    List<TrashEntry> confirmed,
    TrashOperation operation,
  ) async {
    if (_closed ||
        busy ||
        unresolved ||
        confirmed.isEmpty ||
        confirmed.length > 200 ||
        confirmed.map((v) => v.id).toSet().length != confirmed.length) {
      return;
    }
    // A confirmation refers to exact previously selected/visible metadata.
    if (confirmed.any(
      (entry) =>
          !(selected[entry.id]?.same(entry) ?? false) &&
          !(data?.entries.any((v) => v.same(entry)) ?? false),
    )) {
      return;
    }
    final g = ++_generation;
    busy = true;
    results.clear();
    _emit();
    for (final entry in confirmed) {
      if (_closed || g != _generation) {
        return;
      }
      var receipt = false;
      try {
        await repository.apply(entry, operation);
        receipt = true;
        if (_closed || g != _generation) {
          return;
        }
        final absent = await repository.isAbsent(entry);
        if (_closed || g != _generation) {
          return;
        }
        final phase = absent
            ? TrashItemPhase.acknowledgedRemoved
            : TrashItemPhase.unverified;
        results[entry.id] = TrashItemResult(entry, operation, phase);
        if (absent) {
          selected.remove(entry.id);
        } else {
          selected[entry.id] = entry;
        }
      } catch (e) {
        if (_closed || g != _generation) {
          return;
        }
        final phase = receipt
            ? TrashItemPhase.unverified
            : _rejected(e)
            ? TrashItemPhase.failed
            : TrashItemPhase.unknown;
        results[entry.id] = TrashItemResult(entry, operation, phase);
        selected[entry.id] = entry;
      }
      _emit();
      // Ambiguous writes are never followed by another mutation in this batch.
      if (results[entry.id]!.unresolved) {
        break;
      }
    }
    if (_closed || g != _generation) {
      return;
    }
    busy = false;
    _emit();
    await load();
  }

  Future<void> verify() async {
    if (_closed || busy || !unresolved) {
      return;
    }
    final g = ++_generation;
    busy = true;
    _emit();
    for (final old in results.values.where((v) => v.unresolved).toList()) {
      try {
        final absent = await repository.isAbsent(old.entry);
        if (_closed || g != _generation) {
          return;
        }
        if (absent) {
          results[old.entry.id] = TrashItemResult(
            old.entry,
            old.operation,
            old.phase == TrashItemPhase.unverified
                ? TrashItemPhase.acknowledgedRemoved
                : TrashItemPhase.absentWithoutReceipt,
          );
          selected.remove(old.entry.id);
        }
      } catch (_) {
        /* Keep ambiguous state; never resend a write. */
      }
    }
    if (_closed || g != _generation) {
      return;
    }
    busy = false;
    _emit();
    await load();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    selected.clear();
    results.clear();
    data = null;
    repository.dispose();
    super.dispose();
  }
}
