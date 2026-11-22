import 'document_excerpt_origin.dart';
import 'remote_markdown_creation_vault.dart';

enum MarkdownCreationPhase {
  editing,
  creating,
  unknown,
  review,
  cleanup,
  finished,
}

class MarkdownCreationObserved {
  MarkdownCreationObserved({
    required this.scope,
    required this.id,
    required this.version,
    required this.modifiedAt,
    required this.input,
    required String editorType,
    required bool isProtected,
  }) {
    if (id <= 0 ||
        version < 0 ||
        modifiedAt < 0 ||
        editorType != 'markdown' ||
        isProtected) {
      throw const FormatException('Wrong Markdown recovery resource');
    }
  }
  final MarkdownCreationScope scope;
  final int id, version, modifiedAt;
  final MarkdownCreationInput input;
  String get fingerprint => creationDigest([
    scope.namespace,
    id,
    version,
    modifiedAt,
    input.toJson(),
  ]);
}

abstract interface class RemoteMarkdownCreationTransport {
  void retire();
  MarkdownCreationScope get scope;

  /// Adapter rechecks authenticated owner. Exactly one POST; callback is invoked
  /// immediately before send. Return only strict owned/collection/format receipt.
  /// No label mutation, implicit retry, or unrelated request follows the receipt.
  Future<int> submit(
    MarkdownCreationInput input, {
    required void Function() onSubmit,
  });

  /// Strict metadata owner/id/collection/markdown/unprotected is checked BEFORE
  /// reading full source. Metadata must bracket source+labels to detect races.
  /// No endpoint that returns only a preview can implement this method.
  Future<MarkdownCreationObserved> inspect(int id);
}

class RemoteMarkdownCreationController {
  RemoteMarkdownCreationController._(
    this.transport,
    this.vault,
    this._record,
    this._persisted,
    this.isCurrent,
    this._lease,
  );
  static final _leases = <String, Object>{};
  static Future<RemoteMarkdownCreationController> open({
    required RemoteMarkdownCreationTransport transport,
    required RemoteMarkdownCreationVault vault,
    required bool Function() isCurrent,
    required MarkdownCreationInput initial,
    DocumentExcerptOrigin? initialExcerptOrigin,
  }) async {
    final scope = vault.namespace;
    if (scope != transport.scope.namespace || !isCurrent()) {
      throw StateError('Owner retired');
    }
    if (_leases.containsKey(scope)) {
      throw StateError('Creation editor already open');
    }
    final lease = Object();
    _leases[scope] = lease;
    try {
      final stored = await vault.read();
      if (!isCurrent()) throw StateError('Owner retired');
      final result = RemoteMarkdownCreationController._(
        transport,
        vault,
        stored ??
            MarkdownCreationRecord.fresh(
              vault.scope,
              initial,
              excerptOrigin: initialExcerptOrigin,
            ),
        stored,
        isCurrent,
        lease,
      );
      if (stored?.pending == true) {
        result._phase = MarkdownCreationPhase.unknown;
      }
      return result;
    } catch (_) {
      if (identical(_leases[scope], lease)) _leases.remove(scope);
      rethrow;
    }
  }

  final RemoteMarkdownCreationTransport transport;
  final RemoteMarkdownCreationVault vault;
  final bool Function() isCurrent;
  final Object _lease;
  MarkdownCreationRecord _record;
  MarkdownCreationRecord? _persisted;
  MarkdownCreationRecord get record => _record;
  MarkdownCreationPhase _phase = MarkdownCreationPhase.editing;
  MarkdownCreationPhase get phase => _phase;
  MarkdownCreationObserved? observed;
  String? _reviewedFingerprint;
  bool _busy = false, _retired = false;
  Object? failure;
  bool get busy => _busy;
  bool get canEdit =>
      !_busy &&
      !_retired &&
      isCurrent() &&
      _phase == MarkdownCreationPhase.editing &&
      !_record.pending &&
      _record.knownId == null;
  void _guard() {
    if (_retired ||
        !isCurrent() ||
        !identical(_leases[vault.namespace], _lease)) {
      throw StateError('Creation owner retired');
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    transport.retire();
    if (identical(_leases[vault.namespace], _lease)) {
      _leases.remove(vault.namespace);
    }
  }

  Future<void> _commit(MarkdownCreationRecord next) async {
    _guard();
    await vault.compareAndWrite(_persisted, next, guard: _guard);
    _guard();
    _persisted = next;
    _record = next;
  }

  Future<void> edit(MarkdownCreationInput input) async {
    _guard();
    if (!canEdit) throw StateError('Resolve pending creation first');
    _busy = true;
    failure = null;
    try {
      await _commit(_record.copy(input: input));
    } catch (error) {
      failure = error;
      _phase = MarkdownCreationPhase.unknown;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  /// Explicitly discard only an unsubmitted editor snapshot. The caller first
  /// invalidates/drains its editor writers; pending creation is never cleared.
  Future<void> discardEditing() async {
    _guard();
    if (!canEdit) throw StateError('Pending creation cannot be discarded');
    _busy = true;
    try {
      final stored = _persisted;
      if (stored != null) {
        if (stored.fingerprint != _record.fingerprint) {
          throw StateError('Creation snapshot changed');
        }
        await vault.compareAndRemove(stored, guard: _guard);
        _guard();
      }
      _record = MarkdownCreationRecord.fresh(
        vault.scope,
        MarkdownCreationInput(title: '', content: '', labels: const []),
      );
      _persisted = null;
      observed = null;
      _reviewedFingerprint = null;
      failure = null;
    } catch (error) {
      failure = error;
      _phase = MarkdownCreationPhase.unknown;
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> save() async {
    _guard();
    if (!canEdit) throw StateError('Create is unavailable');
    if (_record.input.title.trim().isEmpty) {
      throw const FormatException('Title required');
    }
    _busy = true;
    failure = null;
    _phase = MarkdownCreationPhase.creating;
    var submitted = false;
    final ordinary = _record;
    try {
      await _commit(ordinary.copy(pending: true));
      _guard();
      final id = await transport.submit(
        ordinary.input,
        onSubmit: () {
          _guard();
          if (submitted) throw StateError('POST replay blocked');
          submitted = true;
        },
      );
      _guard();
      if (!submitted || id <= 0) throw StateError('Invalid creation receipt');
      // Known ID survives in memory if its persistence fails. The durable
      // pending record still prohibits a second POST after cold restart.
      _record = _record.copy(
        knownId: id,
        knownIDOrigin: MarkdownKnownIDOrigin.postReceipt,
      );
      _phase = MarkdownCreationPhase.unknown;
      await _commit(_record);
      await _inspect(id);
      if (_record.input.matches(observed!.input)) await _finish();
    } catch (error) {
      failure = error;
      if (!submitted &&
          _persisted?.pending == true &&
          _record.knownId == null) {
        try {
          await _commit(ordinary);
          _phase = MarkdownCreationPhase.editing;
        } catch (_) {
          _phase = MarkdownCreationPhase.unknown;
        }
      } else {
        _phase = MarkdownCreationPhase.unknown;
      }
    } finally {
      _busy = false;
    }
  }

  void _validate(MarkdownCreationObserved value, int id) {
    _guard();
    if (value.scope.namespace != vault.namespace ||
        value.id != id ||
        _record.knownId != null && _record.knownId != id) {
      throw StateError('Wrong recovery resource');
    }
  }

  Future<void> _inspect(int id) async {
    if (id <= 0 || _record.knownId != null && id != _record.knownId) {
      throw StateError('Wrong ID');
    }
    final fresh = await transport.inspect(id);
    _validate(fresh, id);
    observed = fresh;
    _reviewedFingerprint = null;
    _phase = MarkdownCreationPhase.review;
  }

  Future<void> inspect(int id) async {
    _guard();
    if (_busy ||
        !{
          MarkdownCreationPhase.unknown,
          MarkdownCreationPhase.review,
        }.contains(phase)) {
      throw StateError('No pending result to inspect');
    }
    _busy = true;
    failure = null;
    observed = null;
    _reviewedFingerprint = null;
    try {
      await _inspect(id);
    } catch (error) {
      failure = error;
      _phase = MarkdownCreationPhase.unknown;
    } finally {
      _busy = false;
    }
  }

  void markReviewed(MarkdownCreationObserved fullSnapshot) {
    _guard();
    if (_busy ||
        phase != MarkdownCreationPhase.review ||
        observed == null ||
        observed!.fingerprint != fullSnapshot.fingerprint) {
      throw StateError('Review complete current versions');
    }
    _reviewedFingerprint = fullSnapshot.fingerprint;
  }

  Future<void> adopt() async {
    _guard();
    if (_busy ||
        phase != MarkdownCreationPhase.review ||
        observed == null ||
        _reviewedFingerprint != observed!.fingerprint) {
      throw StateError('Full review required');
    }
    _busy = true;
    failure = null;
    try {
      final old = observed!;
      final fresh = await transport.inspect(old.id);
      _validate(fresh, old.id);
      observed = fresh;
      if (fresh.fingerprint != _reviewedFingerprint) {
        _reviewedFingerprint = null;
        return;
      }
      // Explicitly choosing an existing resource; does NOT prove this POST
      // created it. Never overwrite its body or labels and never issue POST.
      await _commit(
        _record.copy(
          pending: true,
          knownId: fresh.id,
          knownIDOrigin: MarkdownKnownIDOrigin.manualExisting,
        ),
      );
      await _finish();
    } catch (error) {
      failure = error;
      _reviewedFingerprint = null;
    } finally {
      _busy = false;
    }
  }

  Future<void> _finish() async {
    _guard();
    if (_record.knownId == null ||
        _persisted?.fingerprint != _record.fingerprint) {
      throw StateError('Persisted known ID required');
    }
    _phase = MarkdownCreationPhase.cleanup;
    try {
      await vault.compareAndRemove(_record, guard: _guard);
      _guard();
      _persisted = null;
      _phase = MarkdownCreationPhase.finished;
    } catch (error) {
      failure = error;
      _phase = MarkdownCreationPhase.cleanup;
    }
  }

  /// Storage-only operation; no transport method is called.
  Future<void> retryCleanup() async {
    _guard();
    if (_busy || phase != MarkdownCreationPhase.cleanup) {
      throw StateError('No cleanup to retry');
    }
    _busy = true;
    try {
      await _finish();
    } finally {
      _busy = false;
    }
  }
}
