import 'package:flutter/foundation.dart';
import 'api_client.dart';
import 'content_password_repository.dart';

enum ContentPasswordPhase {
  idle,
  loading,
  ready,
  writing,
  failed,
  unknown,
  unverified,
  confirmed,
}

class ContentPasswordController extends ChangeNotifier {
  ContentPasswordController(this.repository, this.id);
  final ContentPasswordRepository repository;
  final int id;
  ContentProtection? protection;
  ContentPasswordPhase phase = ContentPasswordPhase.idle;
  bool receivedWriteReceipt = false;
  String? _candidate;
  bool? _expectedProtected;
  bool _closed = false;
  int _generation = 0;
  bool get busy =>
      phase == ContentPasswordPhase.loading ||
      phase == ContentPasswordPhase.writing;
  bool get unresolved =>
      phase == ContentPasswordPhase.unknown ||
      phase == ContentPasswordPhase.unverified;
  void _emit() {
    if (!_closed) {
      notifyListeners();
    }
  }

  Future<void> load() async {
    if (_closed || busy || unresolved) {
      return;
    }
    final generation = ++_generation;
    phase = ContentPasswordPhase.loading;
    _emit();
    try {
      final actual = await repository.read(id);
      if (_closed || generation != _generation) {
        return;
      }
      protection = actual;
      phase = ContentPasswordPhase.ready;
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
      phase = ContentPasswordPhase.failed;
    }
    _emit();
  }

  Future<void> change({
    required String newPassword,
    String? currentPassword,
  }) async {
    final baseline = protection;
    if (_closed || busy || unresolved || baseline == null) {
      return;
    }
    if (newPassword.isNotEmpty) {
      validateContentPassword(newPassword);
    }
    if (baseline.protected) {
      if (currentPassword == null) {
        throw StateError('Current password required');
      }
      validateContentPassword(currentPassword);
    } else if (newPassword.isEmpty || currentPassword != null) {
      throw StateError('No existing password');
    }
    final generation = ++_generation;
    _candidate = newPassword.isEmpty ? null : newPassword;
    _expectedProtected = newPassword.isNotEmpty;
    receivedWriteReceipt = false;
    phase = ContentPasswordPhase.writing;
    _emit();
    try {
      await repository.change(
        baseline,
        newPassword: newPassword,
        currentPassword: currentPassword,
      );
      if (_closed || generation != _generation) {
        return;
      }
      receivedWriteReceipt = true;
      phase = ContentPasswordPhase.unverified;
    } catch (error) {
      if (_closed || generation != _generation) {
        return;
      }
      final rejected =
          error is ApiFailure &&
          error.status >= 400 &&
          error.status < 500 &&
          error.status != 408;
      phase = rejected
          ? ContentPasswordPhase.failed
          : ContentPasswordPhase.unknown;
      if (rejected) {
        _candidate = null;
        _expectedProtected = null;
      }
      _emit();
      return;
    }
    _emit();
    await inspect();
  }

  Future<void> inspect() async {
    if (_closed || !unresolved) {
      return;
    }
    final generation = ++_generation;
    try {
      final actual = await repository.read(id);
      if (_closed || generation != _generation) {
        return;
      }
      protection = actual;
      if (actual.protected != _expectedProtected) {
        _emit();
        return;
      }
      if (actual.protected) {
        final candidate = _candidate;
        if (candidate == null) {
          _emit();
          return;
        }
        await repository.verify(id, candidate);
        if (_closed || generation != _generation) {
          return;
        }
        // Recheck protection after password verification, without a second PUT.
        final latest = await repository.read(id);
        if (_closed || generation != _generation) {
          return;
        }
        protection = latest;
        if (!latest.protected) {
          _emit();
          return;
        }
      }
      phase = ContentPasswordPhase.confirmed;
      _candidate = null;
      _expectedProtected = null;
    } catch (_) {
      if (_closed || generation != _generation) {
        return;
      }
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
    protection = null;
    super.dispose();
  }
}
