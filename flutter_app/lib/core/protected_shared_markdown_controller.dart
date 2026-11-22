import 'protected_shared_journal.dart';
import 'public_edit_controller.dart';
import 'public_edit_snapshot.dart';

class ProtectedSharedMarkdownController extends PublicEditController {
  ProtectedSharedMarkdownController(
    super.repository,
    super.link, {
    required this.journal,
  });
  final ProtectedSharedJournal journal;
  Future<void> _knownCleanup() async {
    if (phase == PublicEditPhase.acknowledged && journal.hasKnown) {
      try {
        await journal.finishKnown();
      } catch (_) {
        phase = PublicEditPhase.unverified;
        rethrow;
      }
    }
    // Unknown + matching actual body is a read-only observation, not proof of a
    // request's execution history. Its marker remains until explicit End record.
  }

  @override
  Future<void> save(
    String content, {
    PublicEditSnapshot? overwriteObserved,
  }) async {
    await super.save(content, overwriteObserved: overwriteObserved);
    await _knownCleanup();
  }

  @override
  Future<void> verify() async {
    await super.verify();
    await _knownCleanup();
  }

  @override
  void acknowledgeRetry() {
    if (journal.hasAttempt) {
      throw StateError('Explicitly review and end the submission record first');
    }
    super.acknowledgeRetry();
  }
}
