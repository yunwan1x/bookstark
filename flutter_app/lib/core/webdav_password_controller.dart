import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'webdav_password_repository.dart';

enum WebdavPasswordPhase {
  ready,
  loading,
  failed,
  changing,
  unknown,
  unverified,
  verifying,
  confirmed,
  revoking,
  revokeUnknown,
  revokeUnverified,
  revoked,
}

class WebdavPasswordResult {
  const WebdavPasswordResult(
    this.profile,
    this.secret, {
    required this.receivedReceipt,
  });
  final WebdavCredentialProfile profile;
  final String secret;
  final bool receivedReceipt;
  @override
  String toString() => 'WebdavPasswordResult(secret: hidden)';
}

class WebdavPasswordController extends ChangeNotifier {
  WebdavPasswordController(this.repository);
  final WebdavPasswordRepository repository;
  WebdavCredentialProfile? profile;
  WebdavPasswordResult? result;
  WebdavPasswordPhase phase = WebdavPasswordPhase.ready;
  String? _candidate;
  bool receivedReceipt = false, reading = false, _closed = false;
  int _generation = 0;
  bool get canVerify =>
      _candidate != null &&
      {
        WebdavPasswordPhase.unknown,
        WebdavPasswordPhase.unverified,
      }.contains(phase);
  bool get busy =>
      reading ||
      {
        WebdavPasswordPhase.changing,
        WebdavPasswordPhase.verifying,
        WebdavPasswordPhase.revoking,
      }.contains(phase);
  bool get unresolved => {
    WebdavPasswordPhase.unknown,
    WebdavPasswordPhase.unverified,
    WebdavPasswordPhase.revokeUnknown,
    WebdavPasswordPhase.revokeUnverified,
  }.contains(phase);
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  bool _rejected(Object e) =>
      e is WebdavPasswordPreflightFailure ||
      e is ApiFailure && e.status >= 400 && e.status < 500 && e.status != 408;
  Future<void> load() async {
    if (_closed || busy) {
      return;
    }
    final g = ++_generation, prior = phase;
    reading = true;
    _emit();
    try {
      final actual = await repository.read();
      if (_closed || g != _generation) {
        return;
      }
      profile = actual;
      if ((prior == WebdavPasswordPhase.confirmed && !actual.hasPassword) ||
          (prior == WebdavPasswordPhase.revoked && actual.hasPassword)) {
        result = null;
        _candidate = null;
        phase = WebdavPasswordPhase.ready;
      } else if ({
            WebdavPasswordPhase.revokeUnknown,
            WebdavPasswordPhase.revokeUnverified,
          }.contains(prior) &&
          !actual.hasPassword) {
        phase = WebdavPasswordPhase.revoked;
        result = null;
        _candidate = null;
      } else if ({
        WebdavPasswordPhase.ready,
        WebdavPasswordPhase.failed,
      }.contains(prior)) {
        phase = WebdavPasswordPhase.ready;
      }
    } catch (_) {
      if (_closed || g != _generation) {
        return;
      }
      if (!unresolved) {
        phase = WebdavPasswordPhase.failed;
      }
    } finally {
      if (!_closed && g == _generation) {
        reading = false;
        _emit();
      }
    }
  }

  Future<void> reset({String? password}) async {
    if (_closed || busy || unresolved || profile == null) {
      return;
    }
    if (password != null) {
      validateWebdavAppPassword(password);
    }
    final g = ++_generation;
    result = null;
    _candidate = password;
    receivedReceipt = false;
    phase = WebdavPasswordPhase.changing;
    _emit();
    try {
      final actual = await repository.reset(password: password);
      if (_closed || g != _generation) {
        return;
      }
      _candidate = actual;
      receivedReceipt = true;
      phase = WebdavPasswordPhase.unverified;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      phase = _rejected(e)
          ? WebdavPasswordPhase.failed
          : WebdavPasswordPhase.unknown;
      if (phase == WebdavPasswordPhase.failed) {
        _candidate = null;
      }
      _emit();
      return;
    }
    _emit();
    await verify();
  }

  Future<void> verify() async {
    final candidate = _candidate;
    if (_closed || busy || !canVerify || candidate == null) {
      return;
    }
    final g = ++_generation;
    phase = WebdavPasswordPhase.verifying;
    _emit();
    try {
      final actual = await repository.read();
      if (!actual.hasPassword) {
        throw StateError('Actual DAV app password is absent');
      }
      await repository.verify(candidate);
      if (_closed || g != _generation) {
        return;
      }
      profile = actual;
      result = WebdavPasswordResult(
        actual,
        candidate,
        receivedReceipt: receivedReceipt,
      );
      _candidate = null;
      phase = WebdavPasswordPhase.confirmed;
    } catch (_) {
      if (_closed || g != _generation) {
        return;
      }
      phase = receivedReceipt
          ? WebdavPasswordPhase.unverified
          : WebdavPasswordPhase.unknown;
    }
    _emit();
  }

  void clearSecret() {
    result = null;
    _emit();
  }

  void acknowledgeUnknown() {
    if (!_closed && !busy && unresolved) {
      _candidate = null;
      result = null;
      receivedReceipt = false;
      phase = WebdavPasswordPhase.ready;
      _emit();
    }
  }

  Future<void> revoke() async {
    if (_closed || busy || unresolved || profile == null) {
      return;
    }
    final g = ++_generation;
    result = null;
    _candidate = null;
    receivedReceipt = false;
    phase = WebdavPasswordPhase.revoking;
    _emit();
    try {
      await repository.revoke();
      if (_closed || g != _generation) {
        return;
      }
      receivedReceipt = true;
      phase = WebdavPasswordPhase.revokeUnverified;
    } catch (e) {
      if (_closed || g != _generation) {
        return;
      }
      phase = _rejected(e)
          ? WebdavPasswordPhase.failed
          : WebdavPasswordPhase.revokeUnknown;
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
    _candidate = null;
    result = null;
    profile = null;
    repository.dispose();
    super.dispose();
  }
}
