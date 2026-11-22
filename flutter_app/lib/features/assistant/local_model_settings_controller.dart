import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../core/local_model_config.dart';

final class LocalModelSettingsController extends ChangeNotifier {
  LocalModelSettingsController({
    required this.vault,
    required this.probe,
    this.isCurrent,
  });
  final LocalModelConfigVault vault;
  final LocalModelProbe probe;
  final bool Function()? isCurrent;
  String endpoint = '', model = '', apiKey = '';
  bool allowKnowledge = false;
  bool loaded = false, loading = false, saving = false;
  bool unknown = false, probing = false, probeOK = false;
  bool readbackDifferent = false;
  Object? problem;
  LocalModelProbeIssue? probeIssue;
  LocalModelConfig? saved;
  bool _retired = false, _pendingReset = false;
  int _revision = 0, _loadEpoch = 0, _probeEpoch = 0;
  Completer<void>? _abort;
  bool get retired => _retired;
  bool get busy => loading || saving || probing;
  bool get _alive => !_retired && isCurrent?.call() != false;
  LocalModelConfig get draft => LocalModelConfig(
    endpoint: endpoint,
    model: model,
    apiKey: apiKey,
    allowKnowledge: allowKnowledge,
  );
  bool get valid {
    try {
      draft;
      return true;
    } on FormatException {
      return false;
    }
  }

  bool get dirty {
    if (saved == null) {
      return endpoint.trim().isNotEmpty ||
          model.trim().isNotEmpty ||
          apiKey.isNotEmpty ||
          allowKnowledge;
    }
    try {
      return !draft.same(saved);
    } on FormatException {
      return true;
    }
  }

  void _fill(LocalModelConfig? value) {
    endpoint = value?.endpoint.toString() ?? '';
    model = value?.model ?? '';
    apiKey = value?.apiKey ?? '';
    allowKnowledge = value?.allowKnowledge ?? false;
    _revision++;
  }

  void edit({
    String? endpoint,
    String? model,
    String? apiKey,
    bool? allowKnowledge,
  }) {
    if (!_alive) return;
    _stopProbe();
    if (endpoint != null) this.endpoint = endpoint;
    if (model != null) this.model = model;
    if (apiKey != null) this.apiKey = apiKey;
    if (allowKnowledge != null) this.allowKnowledge = allowKnowledge;
    _revision++;
    probeOK = false;
    probeIssue = null;
    readbackDifferent = false;
    notifyListeners();
  }

  Future<bool> load() async {
    if (!_alive || saving) return false;
    _stopProbe();
    final epoch = ++_loadEpoch, revision = _revision;
    final replaceClean = !loaded || !dirty;
    loading = true;
    problem = null;
    notifyListeners();
    try {
      final actual = await vault.read();
      if (!_alive || epoch != _loadEpoch) return false;
      if ((replaceClean && revision == _revision) ||
          (_pendingReset && actual == null)) {
        _fill(actual);
      }
      saved = actual;
      loaded = true;
      unknown = false;
      _pendingReset = false;
      readbackDifferent = dirty;
      return true;
    } catch (error) {
      if (_alive && epoch == _loadEpoch) problem = error;
      return false;
    } finally {
      if (_alive && epoch == _loadEpoch) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> save() async {
    if (!_alive || busy || unknown || !loaded) return false;
    final LocalModelConfig value;
    try {
      value = draft;
    } on FormatException catch (e) {
      problem = e;
      notifyListeners();
      return false;
    }
    saving = true;
    problem = null;
    readbackDifferent = false;
    notifyListeners();
    try {
      await vault.save(value);
      if (!_alive) return false;
      saved = value;
      unknown = false;
      return true;
    } catch (error) {
      if (_alive) {
        problem = error;
        unknown = error is LocalModelSaveUnknown;
      }
      return false;
    } finally {
      if (_alive) {
        saving = false;
        notifyListeners();
      }
    }
  }

  Future<bool> reset() async {
    if (!_alive || busy || (unknown && problem is! LocalModelConfigCorrupt)) {
      return false;
    }
    saving = true;
    problem = null;
    _pendingReset = true;
    _stopProbe();
    notifyListeners();
    try {
      await vault.reset();
      if (!_alive) return false;
      saved = null;
      _fill(null);
      loaded = true;
      unknown = false;
      _pendingReset = false;
      readbackDifferent = false;
      return true;
    } catch (error) {
      if (_alive) {
        problem = error;
        unknown = error is LocalModelSaveUnknown;
      }
      return false;
    } finally {
      if (_alive) {
        saving = false;
        notifyListeners();
      }
    }
  }

  void _stopProbe() {
    ++_probeEpoch;
    final abort = _abort;
    _abort = null;
    if (abort != null && !abort.isCompleted) abort.complete();
    probing = false;
  }

  void cancelTest() {
    if (!_alive) return;
    _stopProbe();
    probeOK = false;
    probeIssue = null;
    notifyListeners();
  }

  Future<bool> testConnection() async {
    if (!_alive || busy || unknown || !loaded) return false;
    final LocalModelConfig value;
    try {
      value = draft;
    } on FormatException catch (e) {
      problem = e;
      notifyListeners();
      return false;
    }
    _stopProbe();
    final epoch = _probeEpoch;
    final abort = Completer<void>();
    _abort = abort;
    probing = true;
    probeOK = false;
    probeIssue = null;
    problem = null;
    notifyListeners();
    try {
      await probe.test(value, abortTrigger: abort.future);
      if (!_alive || epoch != _probeEpoch) return false;
      probeOK = true;
      return true;
    } on LocalModelProbeFailure catch (e) {
      if (_alive && epoch == _probeEpoch) probeIssue = e.issue;
      return false;
    } catch (_) {
      if (_alive && epoch == _probeEpoch) {
        probeIssue = LocalModelProbeIssue.network;
      }
      return false;
    } finally {
      if (_alive && epoch == _probeEpoch) {
        _stopProbe();
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_retired) return;
    _retired = true;
    ++_loadEpoch;
    _stopProbe();
    super.dispose();
  }
}
