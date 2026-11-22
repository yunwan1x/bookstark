import 'api_client.dart';
import 'public_edit_link.dart';
import 'public_edit_repository.dart';
import 'public_edit_snapshot.dart';

enum PublicEditPhase {
  idle,
  loading,
  locked,
  unsupported,
  ready,
  checking,
  saving,
  unknown,
  conflict,
  acknowledged,
  unverified,
  blocked,
  failed,
}

/// Session-only state. A known PUT receipt and a verified body are separate
/// facts; neither a failed reread nor an unknown result triggers another PUT.
class PublicEditController {
  PublicEditController(this.repository, this.link);
  final PublicEditRepository repository;
  final PublicEditLink link;
  PublicEditPhase phase = PublicEditPhase.idle;
  PublicEditSnapshot? snapshot, conflict;
  PublicEditReceipt? receipt;
  String? pendingBody;
  String? _password;
  bool confirmedByRead = false, remoteStillBaseline = false;
  int _generation = 0;
  bool _closed = false;
  bool get busy => {
    PublicEditPhase.loading,
    PublicEditPhase.checking,
    PublicEditPhase.saving,
  }.contains(phase);
  void _alive(int generation) {
    if (_closed || generation != _generation) {
      throw StateError('Editing session ended');
    }
  }

  void _sameContext(PublicEditSnapshot current) {
    final base = snapshot;
    if (current.detail.reference != link.reference ||
        current.locked ||
        current.format != 'markdown' ||
        base != null &&
            (base.detail.targetId != current.detail.targetId ||
                base.detail.kind != current.detail.kind ||
                base.detail.blogType != current.detail.blogType ||
                base.detail.protected != current.detail.protected)) {
      throw StateError('Shared editing context changed');
    }
  }

  Future<void> initialize({
    String? password,
    Future<void>? abortTrigger,
  }) async {
    if (_closed ||
        busy ||
        {
          PublicEditPhase.unknown,
          PublicEditPhase.unverified,
          PublicEditPhase.conflict,
        }.contains(phase)) {
      throw StateError('Editing session unavailable');
    }
    final generation = ++_generation;
    phase = PublicEditPhase.loading;
    try {
      final value = await repository.read(
        link,
        password: password,
        abortTrigger: abortTrigger,
      );
      _alive(generation);
      snapshot = value;
      conflict = null;
      receipt = null;
      pendingBody = null;
      confirmedByRead = false;
      remoteStillBaseline = false;
      if (value.format != 'markdown') {
        _password = null;
        phase = PublicEditPhase.unsupported;
      } else if (value.locked) {
        _password = null;
        phase = PublicEditPhase.locked;
      } else {
        _password = value.detail.protected ? password : null;
        phase = PublicEditPhase.ready;
      }
    } catch (_) {
      if (!_closed && generation == _generation) phase = PublicEditPhase.failed;
      rethrow;
    }
  }

  /// A resumed editor must reread its capability without resetting its baseline
  /// or replaying a write. Unknown results keep their dedicated verify path.
  Future<void> revalidateForResume(String workingCopy) async {
    if (_closed ||
        !{
          PublicEditPhase.ready,
          PublicEditPhase.acknowledged,
          PublicEditPhase.blocked,
        }.contains(phase) ||
        snapshot == null) {
      throw StateError('Resume requires a settled editing baseline');
    }
    final generation = _generation;
    final base = snapshot!;
    final previous = phase;
    phase = PublicEditPhase.checking;
    try {
      final current = await repository.read(link, password: _password);
      _alive(generation);
      _sameContext(current);
      if (!base.sameVersion(current)) {
        conflict = current;
        pendingBody = workingCopy;
        phase = PublicEditPhase.conflict;
      } else {
        phase = previous == PublicEditPhase.blocked
            ? PublicEditPhase.ready
            : previous;
      }
    } catch (_) {
      if (!_closed && generation == _generation) {
        pendingBody = workingCopy;
        phase = PublicEditPhase.blocked;
      }
      rethrow;
    }
  }

  Future<void> save(
    String content, {
    PublicEditSnapshot? overwriteObserved,
  }) async {
    if (_closed ||
        !{
          PublicEditPhase.ready,
          PublicEditPhase.acknowledged,
          PublicEditPhase.conflict,
        }.contains(phase)) {
      throw StateError('This save cannot be repeated');
    }
    validateSharedMarkdown(content);
    final base = snapshot;
    if (base == null) throw StateError('Shared editor has no baseline');
    final generation = _generation;
    pendingBody = content;
    receipt = null;
    confirmedByRead = false;
    phase = PublicEditPhase.checking;
    remoteStillBaseline = false;
    PublicEditSnapshot current;
    try {
      current = await repository.read(link, password: _password);
      _alive(generation);
      _sameContext(current);
    } catch (_) {
      if (!_closed) phase = PublicEditPhase.blocked;
      rethrow;
    }
    if (current.content == content) {
      snapshot = current;
      pendingBody = content;
      conflict = null;
      confirmedByRead = true;
      phase = PublicEditPhase.acknowledged;
      return;
    }
    if (!base.sameVersion(current) &&
        (overwriteObserved == null ||
            !overwriteObserved.sameVersion(current))) {
      conflict = current;
      pendingBody = content;
      phase = PublicEditPhase.conflict;
      return;
    }
    pendingBody = content;
    receipt = null;
    confirmedByRead = false;
    conflict = null;
    phase = PublicEditPhase.saving;
    try {
      final result = await repository.save(
        link,
        current,
        content,
        password: _password,
      );
      _alive(generation);
      if (result.reference != link.reference || result.modified.isEmpty) {
        throw const FormatException('Invalid shared editing receipt');
      }
      receipt = result;
    } catch (error) {
      if (!_closed) {
        phase =
            error is ApiFailure &&
                {400, 409, 413, 422, 429}.contains(error.status)
            ? PublicEditPhase.ready
            : error is ApiFailure && {401, 403, 404}.contains(error.status)
            ? PublicEditPhase.blocked
            : PublicEditPhase.unknown;
      }
      rethrow;
    }
    // A valid receipt already exists. Any read failure below must keep it.
    try {
      await _verify(generation);
    } catch (_) {
      if (!_closed) phase = PublicEditPhase.unverified;
    }
  }

  Future<void> verify() async {
    if (_closed ||
        !{
          PublicEditPhase.unknown,
          PublicEditPhase.unverified,
        }.contains(phase)) {
      throw StateError('No pending save to verify');
    }
    final generation = _generation;
    phase = PublicEditPhase.checking;
    try {
      await _verify(generation);
    } catch (_) {
      if (!_closed) {
        phase = receipt == null
            ? PublicEditPhase.unknown
            : PublicEditPhase.unverified;
      }
      rethrow;
    }
  }

  Future<void> _verify(int generation) async {
    final current = await repository.read(link, password: _password);
    _alive(generation);
    _sameContext(current);
    if (current.content == pendingBody) {
      snapshot = current;
      conflict = null;
      confirmedByRead = receipt == null;
      remoteStillBaseline = false;
      phase = PublicEditPhase.acknowledged;
    } else if (receipt == null && snapshot!.sameVersion(current)) {
      remoteStillBaseline = true;
      phase = PublicEditPhase.unknown;
    } else {
      conflict = current;
      remoteStillBaseline = false;
      phase = PublicEditPhase.conflict;
    }
  }

  void acknowledgeRetry() {
    if (phase != PublicEditPhase.unknown ||
        !remoteStillBaseline ||
        receipt != null) {
      throw StateError('Remote save has not been verified as unchanged');
    }
    phase = PublicEditPhase.ready;
    remoteStillBaseline = false;
  }

  void acceptRemote() {
    if (phase != PublicEditPhase.conflict || conflict == null) {
      throw StateError('No current remote version');
    }
    snapshot = conflict;
    conflict = null;
    pendingBody = null;
    receipt = null;
    confirmedByRead = false;
    remoteStillBaseline = false;
    phase = PublicEditPhase.ready;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    final capability = repository;
    if (capability is RetirablePublicEditRepository) {
      (capability as RetirablePublicEditRepository).retire(link);
    }
    ++_generation;
    _password = null;
    snapshot = null;
    conflict = null;
    receipt = null;
    pendingBody = null;
  }
}
