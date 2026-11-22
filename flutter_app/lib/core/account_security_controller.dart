import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'account_password_repository.dart';

enum AccountSecurityPhase {
  ready,
  changing,
  rejected,
  unknown,
  unverified,
  verifying,
  sessionUnstored,
  persisting,
  complete,
}

class AccountSecurityController extends ChangeNotifier {
  AccountSecurityController(this.repository);
  final AccountPasswordRepository repository;
  AccountSecurityPhase phase = AccountSecurityPhase.ready;
  bool receivedWriteReceipt = false, credentialsVerified = false;
  String? _candidate;
  int _generation = 0;
  bool _closed = false;
  bool get busy => {
    AccountSecurityPhase.changing,
    AccountSecurityPhase.verifying,
    AccountSecurityPhase.persisting,
  }.contains(phase);
  bool get unresolved => {
    AccountSecurityPhase.unknown,
    AccountSecurityPhase.unverified,
    AccountSecurityPhase.sessionUnstored,
  }.contains(phase);
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> change(String current, String next) async {
    if (_closed || busy || unresolved) {
      return;
    }
    validateLoginPassword(current);
    validateLoginPassword(next, newPassword: true);
    final generation = ++_generation;
    _candidate = next;
    receivedWriteReceipt = false;
    credentialsVerified = false;
    phase = AccountSecurityPhase.changing;
    _emit();
    try {
      await repository.change(current, next);
      if (_closed || generation != _generation) {
        return;
      }
      receivedWriteReceipt = true;
      phase = AccountSecurityPhase.unverified;
    } catch (error) {
      if (_closed || generation != _generation) {
        return;
      }
      final rejected =
          error is AccountPasswordPreflightFailure ||
          error is ApiFailure &&
              error.status >= 400 &&
              error.status < 500 &&
              error.status != 408;
      phase = rejected
          ? AccountSecurityPhase.rejected
          : AccountSecurityPhase.unknown;
      if (rejected) {
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
    if (_closed ||
        busy ||
        candidate == null ||
        !{
          AccountSecurityPhase.unknown,
          AccountSecurityPhase.unverified,
        }.contains(phase)) {
      return;
    }
    final generation = ++_generation;
    phase = AccountSecurityPhase.verifying;
    _emit();
    try {
      await repository.verifyAndAdopt(candidate);
      if (_closed || generation != _generation) {
        return;
      }
      credentialsVerified = true;
      _candidate = null;
      phase = AccountSecurityPhase.sessionUnstored;
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
      phase = receivedWriteReceipt
          ? AccountSecurityPhase.unverified
          : AccountSecurityPhase.unknown;
      _emit();
      return;
    }
    _emit();
    await persist();
  }

  Future<void> persist() async {
    if (_closed ||
        busy ||
        !credentialsVerified ||
        phase != AccountSecurityPhase.sessionUnstored) {
      return;
    }
    final generation = ++_generation;
    phase = AccountSecurityPhase.persisting;
    _emit();
    try {
      final saved = await repository.persistSession();
      if (_closed || generation != _generation) {
        return;
      }
      phase = saved
          ? AccountSecurityPhase.complete
          : AccountSecurityPhase.sessionUnstored;
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
      phase = AccountSecurityPhase.sessionUnstored;
    }
    _emit();
  }

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _generation++;
    _candidate = null;
    super.dispose();
  }
}
