import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'api_tokens_repository.dart';

enum ApiTokenPhase {
  ready,
  loading,
  failed,
  creating,
  createUnknown,
  created,
  revoking,
  revokeUnknown,
  revokeUnverified,
  revoked,
}

class ApiTokensController extends ChangeNotifier {
  ApiTokensController(this.repository);
  final ApiTokensRepository repository;
  ApiTokensPage? page;
  CreatedApiToken? created;
  ApiTokenEntry? latestCreated, pendingRevoke;
  ApiTokenPhase phase = ApiTokenPhase.ready;
  bool reading = false, receivedRevocationReceipt = false, _closed = false;
  int _generation = 0;
  bool get busy =>
      reading ||
      phase == ApiTokenPhase.creating ||
      phase == ApiTokenPhase.revoking;
  bool get unresolved =>
      phase == ApiTokenPhase.createUnknown ||
      phase == ApiTokenPhase.revokeUnknown ||
      phase == ApiTokenPhase.revokeUnverified;
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  bool _rejected(Object e) =>
      e is ApiTokenPreflightFailure ||
      e is ApiFailure && e.status >= 400 && e.status < 500 && e.status != 408;
  Future<void> load() async {
    if (_closed || busy) {
      return;
    }
    final g = ++_generation;
    reading = true;
    final prior = phase;
    _emit();
    try {
      final result = await repository.read();
      if (_closed || g != _generation) {
        return;
      }
      page = result;
      if (pendingRevoke != null &&
          {
            ApiTokenPhase.revokeUnknown,
            ApiTokenPhase.revokeUnverified,
          }.contains(prior)) {
        if (result.provesAbsent(pendingRevoke!.id)) {
          phase = ApiTokenPhase.revoked;
          if (latestCreated?.id == pendingRevoke!.id) {
            latestCreated = null;
            created = null;
          }
        }
      } else if (prior == ApiTokenPhase.ready ||
          prior == ApiTokenPhase.failed) {
        phase = ApiTokenPhase.ready;
      }
    } catch (_) {
      if (_closed || g != _generation) {
        return;
      }
      if (!unresolved && prior != ApiTokenPhase.created) {
        phase = ApiTokenPhase.failed;
      }
    } finally {
      if (!_closed && g == _generation) {
        reading = false;
        _emit();
      }
    }
  }

  Future<void> create(String name) async {
    if (_closed || busy || unresolved || page == null) {
      return;
    }
    validateApiTokenName(name);
    final g = ++_generation;
    created = null;
    phase = ApiTokenPhase.creating;
    _emit();
    try {
      final actual = await repository.create(name);
      if (_closed || g != _generation) {
        return;
      }
      created = actual;
      latestCreated = actual.entry;
      phase = ApiTokenPhase.created;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      phase = _rejected(e) ? ApiTokenPhase.failed : ApiTokenPhase.createUnknown;
      _emit();
      return;
    }
    _emit();
    await load();
  }

  void clearSecret() {
    created = null;
    _emit();
  }

  // Explicit acknowledgement is needed before another non-idempotent create.
  void acknowledgeUnknownCreate() {
    if (!_closed && !busy && phase == ApiTokenPhase.createUnknown) {
      phase = ApiTokenPhase.ready;
      _emit();
    }
  }

  Future<void> revoke(ApiTokenEntry entry) async {
    if (_closed || busy || unresolved) {
      return;
    }
    final g = ++_generation;
    pendingRevoke = entry;
    receivedRevocationReceipt = false;
    phase = ApiTokenPhase.revoking;
    _emit();
    try {
      await repository.revoke(entry);
      if (_closed || g != _generation) {
        return;
      }
      receivedRevocationReceipt = true;
      phase = ApiTokenPhase.revokeUnverified;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      phase = _rejected(e) ? ApiTokenPhase.failed : ApiTokenPhase.revokeUnknown;
      _emit();
      return;
    }
    _emit();
    await load();
  }

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation++;
    created = null;
    latestCreated = null;
    pendingRevoke = null;
    page = null;
    repository.dispose();
    super.dispose();
  }
}
