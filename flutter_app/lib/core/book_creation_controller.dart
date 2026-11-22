import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'book_creation_attempt.dart';
import 'book_creation_attempt_store.dart';
import 'book_creation_transport.dart';

enum BookCreationPhase {
  empty,
  ready,
  notSent,
  submitting,
  unknown,
  known,
  storageUnconfirmed,
  failed,
}

class ExistingBookReview {
  ExistingBookReview(BookItem actual, this.attemptFingerprint)
    : book = BookItem(
        id: actual.id,
        name: actual.name,
        description: actual.description,
        identify: actual.identify,
        documentCount: actual.documentCount,
        labels: List.unmodifiable(actual.labels),
        labelsLoaded: actual.labelsLoaded,
        labelText: actual.labelText,
        modifiedAt: actual.modifiedAt,
      ) {
    if (book.id == null ||
        book.id! <= 0 ||
        !book.labelsLoaded ||
        book.identify.isEmpty ||
        book.documentCount < 0 ||
        book.identify.length > 4096 ||
        book.name.length > 4096 ||
        book.description.length > 32768 ||
        book.labels.length > 100 ||
        utf8.encode(jsonEncode(book.labels)).length > 96 * 1024) {
      throw const FormatException('Full existing book details required');
    }
    for (final value in [
      book.name,
      book.description,
      book.identify,
      ...book.labels,
    ]) {
      validateBookRecoveryText(value);
    }
  }
  final BookItem book;
  final String attemptFingerprint;
  String get fingerprint => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'id': book.id,
            'name': book.name,
            'description': book.description,
            'identify': book.identify,
            'documents': book.documentCount,
            'labels': book.labels,
            'modified_at': book.modifiedAt?.toUtc().toIso8601String(),
          }),
        ),
      )
      .toString();
}

class BookCreationController extends ChangeNotifier {
  BookCreationController({required this.store, required this.transport});
  final BookCreationAttemptStore store;
  final BookCreationTransport transport;
  BookCreationAttempt? attempt;
  ExistingBookReview? review;
  BookCreationPhase phase = BookCreationPhase.empty;
  bool busy = false,
      knownDurable = false,
      cleanupPending = false,
      _closed = false,
      _everKnown = false;
  BookCreationAttempt? _durable, _storageExpected;
  String? safeError;
  void _guard() {
    if (_closed) throw const BookCreationOwnerRetired();
    store.guard();
  }

  void _emit() {
    if (!_closed && store.isCurrent()) notifyListeners();
  }

  bool get canSubmit =>
      !_everKnown &&
      !busy &&
      (phase == BookCreationPhase.ready ||
          phase == BookCreationPhase.notSent) &&
      attempt?.state == BookAttemptState.pending &&
      _durable?.fingerprint == attempt?.fingerprint;
  bool get canReview =>
      !busy &&
      attempt?.state == BookAttemptState.submittedUnknown &&
      phase == BookCreationPhase.unknown;

  void _phaseFromRecord() {
    phase = switch (attempt?.state) {
      null => BookCreationPhase.empty,
      BookAttemptState.pending => BookCreationPhase.ready,
      BookAttemptState.submittedUnknown => BookCreationPhase.unknown,
      BookAttemptState.knownID => BookCreationPhase.known,
    };
    knownDurable = attempt?.state == BookAttemptState.knownID;
  }

  Future<void> load() async {
    _guard();
    if (busy) return;
    busy = true;
    _emit();
    try {
      final stored = await store.read();
      _guard();
      if (stored != null || !_everKnown) {
        attempt = stored;
        _durable = stored;
      }
      if (stored?.state == BookAttemptState.knownID) _everKnown = true;
      review = null;
      safeError = null;
      _phaseFromRecord();
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        phase = BookCreationPhase.failed;
        safeError =
            '无法读取创建记录。原记录已保留。 / Cannot read creation record. It is retained.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> start(BookCreationInput input) async {
    _guard();
    if (busy || attempt != null || _everKnown) return;
    busy = true;
    safeError = null;
    final next = BookCreationAttempt(
      key: store.attemptKey,
      scope: store.scope,
      input: input,
      state: BookAttemptState.pending,
    );
    attempt = next;
    _emit();
    try {
      await store.put(next);
      _guard();
      _durable = next;
      _phaseFromRecord();
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        phase = BookCreationPhase.storageUnconfirmed;
        _storageExpected = null;
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> submit() async {
    _guard();
    if (!canSubmit) return;
    final pending = attempt!;
    final lease = Object();
    try {
      store.acquireSubmission(lease);
    } catch (_) {
      safeError =
          '此创建记录正由另一操作处理，请重新读取。 / Another operation owns this creation record. Reload it.';
      _emit();
      return;
    }
    busy = true;
    phase = BookCreationPhase.submitting;
    safeError = null;
    review = null;
    _emit();
    var callbackStarted = false, callbackCompleted = false, calls = 0;
    try {
      final receipt = await transport.create(
        pending.input,
        onSubmit: () async {
          _guard();
          if (++calls != 1) {
            throw StateError('Submission callback must run exactly once');
          }
          callbackStarted = true;
          final marked = pending.unknown();
          attempt = marked;
          _storageExpected = pending;
          await store.claimSubmission(pending, lease);
          _guard();
          _durable = marked;
          callbackCompleted = true;
        },
      );
      _guard();
      // A positive received ID always closes the create path, even if a broken
      // transport omitted the callback. Keep boundaryArmed=false in that case;
      // never invent exact-boundary evidence, and never resend POST.
      final base = callbackCompleted ? attempt! : pending;
      attempt = base.known(receipt.id, BookIDOrigin.postReceipt);
      _everKnown = true;
      knownDurable = false;
      _storageExpected = _durable;
      if (!callbackCompleted) {
        safeError =
            '已保留真实ID；提交边界协议需修复，禁止再次新建。 / Known ID retained; submission protocol needs review.';
      }
      try {
        await store.put(attempt!, expected: _durable);
        _guard();
        _durable = attempt;
        knownDurable = true;
        phase = BookCreationPhase.known;
      } catch (_) {
        if (!_closed && store.isCurrent()) {
          phase = BookCreationPhase.storageUnconfirmed;
        }
      }
    } catch (error) {
      if (!_closed && store.isCurrent()) {
        if (error is BookSaveFailure && error.savedId > 0) {
          // Defensive compatibility only; proper typed transport returns the
          // POST ID before label work. Never lose an already known positive ID.
          final base = callbackCompleted ? attempt! : pending;
          attempt = base.known(error.savedId, BookIDOrigin.postReceipt);
          _everKnown = true;
          knownDurable = false;
          _storageExpected = _durable;
          safeError =
              '已获得书籍ID；标签需在既有设置中核对。 / Known ID retained; review labels in existing settings.';
          try {
            await store.put(attempt!, expected: _durable);
            _guard();
            _durable = attempt;
            knownDurable = true;
            phase = BookCreationPhase.known;
          } catch (_) {
            if (!_closed && store.isCurrent()) {
              phase = BookCreationPhase.storageUnconfirmed;
            }
          }
        } else if (!callbackCompleted) {
          // Contract proves no POST: onSubmit was never awaited successfully.
          // If marker write partially happened, repair only storage first.
          if (callbackStarted) {
            // Never roll an unknown marker back to pending. Another controller
            // may already own a successful claim, or a write may have applied.
            attempt = pending.unknown();
            _storageExpected = pending;
            phase = BookCreationPhase.unknown;
            safeError =
                '提交授权未确认。记录保留且禁止重发，请只读核对。 / Submission authorization unconfirmed. Review without resending.';
          } else {
            attempt = pending;
            phase = BookCreationPhase.notSent;
            safeError =
                '尚未发送；修复连接后可明确重交同一草稿。 / Not sent. Fix the connection, then explicitly submit this same draft.';
          }
        } else {
          phase = BookCreationPhase.unknown;
          safeError =
              '创建结果未知。请勿重复新建，请只读核对已有ID。 / Create result unknown. Review an existing ID without resending.';
        }
      }
    } finally {
      store.releaseSubmission(lease);
      busy = false;
      _emit();
    }
  }

  Future<void> retryStorage() async {
    _guard();
    if (busy ||
        phase != BookCreationPhase.storageUnconfirmed ||
        attempt == null) {
      return;
    }
    busy = true;
    _emit();
    try {
      if (cleanupPending) {
        await store.clearKnown(attempt!);
        _guard();
        cleanupPending = false;
      } else {
        await store.put(attempt!, expected: _storageExpected);
        _guard();
        _durable = attempt;
      }
      safeError = null;
      _phaseFromRecord();
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        safeError =
            '本机存储仍未确认；没有发送创建或修改请求。 / Device storage unconfirmed; no create or update was sent.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> inspectExisting(int id) async {
    _guard();
    if (!canReview || id <= 0) return;
    busy = true;
    safeError = null;
    review = null;
    _emit();
    final owner = attempt!.fingerprint;
    try {
      final actual = await transport.readExisting(id);
      _guard();
      if (actual.id != id || attempt?.fingerprint != owner) {
        throw StateError('Review identity changed');
      }
      review = ExistingBookReview(actual, owner);
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        safeError =
            '只读核对失败，原提交记录已保留。 / Read-only review failed. Submission record retained.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> adoptExisting(
    ExistingBookReview expected, {
    required bool explicitlyConfirmed,
  }) async {
    _guard();
    if (!canReview ||
        !explicitlyConfirmed ||
        review?.fingerprint != expected.fingerprint ||
        expected.attemptFingerprint != attempt!.fingerprint) {
      return;
    }
    busy = true;
    safeError = null;
    _emit();
    try {
      final fresh = ExistingBookReview(
        await transport.readExisting(expected.book.id!),
        attempt!.fingerprint,
      );
      _guard();
      if (fresh.book.id != expected.book.id ||
          fresh.fingerprint != expected.fingerprint) {
        review = fresh;
        safeError =
            '资料已变化，请重新核对并确认。 / The book changed. Review and confirm again.';
        return;
      }
      final prior = attempt!;
      attempt = prior.known(fresh.book.id!, BookIDOrigin.manualExisting);
      _everKnown = true;
      knownDurable = false;
      _storageExpected = prior;
      try {
        await store.put(attempt!, expected: prior);
        _guard();
        _durable = attempt;
        knownDurable = true;
        phase = BookCreationPhase.known;
      } catch (_) {
        if (!_closed && store.isCurrent()) {
          phase = BookCreationPhase.storageUnconfirmed;
        }
      }
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        safeError =
            '资料核对未完成，没有关联或修改书籍。 / Review incomplete; no book was linked or modified.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  Future<void> clearKnownRecord() async {
    _guard();
    if (busy || !knownDurable || attempt?.state != BookAttemptState.knownID) {
      return;
    }
    busy = true;
    cleanupPending = true;
    _emit();
    try {
      await store.clearKnown(attempt!);
      _guard();
      cleanupPending = false;
    } catch (_) {
      if (!_closed && store.isCurrent()) {
        phase = BookCreationPhase.storageUnconfirmed;
        safeError =
            '仅本机清理未确认；已有ID不会重新创建。 / Only device cleanup is unconfirmed. Known ID will not be recreated.';
      }
    } finally {
      busy = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _closed = true;
    review = null;
    super.dispose();
  }
}
