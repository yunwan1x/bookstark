import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/home_dashboard_models.dart';
import '../core/home_dashboard_repository.dart';

/// One controller belongs to one authenticated account or local database.
/// Read epochs and cancellation prevent an old filter or retired space from
/// publishing into the current view. Writes are never queued or replayed.
final class HomeDashboardController extends ChangeNotifier {
  HomeDashboardController(this.repository, {HomeQuery? query})
    : query = query ?? HomeQuery(),
      _restoreQuery = query == null;
  final HomeDashboardRepository repository;
  HomeQuery query;
  HomeDashboardSnapshot? snapshot;
  Object? problem;
  bool loading = false, writing = false, needsReadback = false;
  bool _retired = false;
  bool _restoreQuery, _queryUnsaved = false;
  bool get retired => _retired;
  int _epoch = 0;
  Completer<void>? _abort;
  void _cancel() {
    final current = _abort;
    _abort = null;
    if (current != null && !current.isCompleted) current.complete();
  }

  bool _current(int epoch) => !_retired && epoch == _epoch;
  Future<bool> load([HomeQuery? next]) async {
    if (_retired || writing) return false;
    _cancel();
    final epoch = ++_epoch;
    final stop = Completer<void>();
    _abort = stop;
    query = next ?? query;
    if (next != null) {
      _restoreQuery = false;
      _queryUnsaved = true;
    }
    loading = true;
    problem = null;
    notifyListeners();
    try {
      final preferences = repository is HomeQueryPreferences
          ? repository as HomeQueryPreferences
          : null;
      if (_restoreQuery && preferences != null) {
        final restored = await preferences.restoreQuery();
        if (!_current(epoch)) return false;
        query = restored ?? query;
        _restoreQuery = false;
      }
      if (_queryUnsaved && preferences != null) {
        try {
          await preferences.rememberQuery(query);
        } on HomePreferencesCorrupt {
          rethrow;
        } catch (_) {
          throw const HomeQueryPreferenceFailure();
        }
        if (!_current(epoch)) return false;
        _queryUnsaved = false;
      }
      final value = await repository.load(query, abortTrigger: stop.future);
      if (!_current(epoch)) return false;
      snapshot = value;
      needsReadback = false;
      return true;
    } catch (error) {
      if (_current(epoch)) problem = error;
      return false;
    } finally {
      if (_current(epoch)) {
        _cancel();
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> saveLayout(List<HomeLayoutItem> desired) => _write(() async {
    final result = await repository.saveLayout(
      desired,
      abortTrigger: _abort!.future,
    );
    return snapshot!.withLayout(result);
  });
  Future<bool> clearVisits() => _write(() async {
    await repository.clearVisits(abortTrigger: _abort!.future);
    return snapshot!.withoutVisits();
  });
  Future<bool> _write(Future<HomeDashboardSnapshot> Function() action) async {
    if (_retired || writing || needsReadback || snapshot == null) return false;
    _cancel();
    final epoch = ++_epoch;
    _abort = Completer<void>();
    loading = false;
    writing = true;
    problem = null;
    notifyListeners();
    try {
      final result = await action();
      if (!_current(epoch)) return false;
      snapshot = result;
      return true;
    } catch (error) {
      if (_current(epoch)) {
        problem = error;
        needsReadback = error is HomeWriteUnconfirmed;
      }
      return false;
    } finally {
      if (_current(epoch)) {
        _cancel();
        writing = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _retired = true;
    ++_epoch;
    _cancel();
    super.dispose();
  }
}
