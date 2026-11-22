import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/protected_complex_lifetime.dart';
import '../../core/protected_owned_complex_journal.dart';
import '../../core/protected_owned_recovery_reader.dart';
import '../html/html_editor_lease.dart';
import '../notes/note_unlock_dialog.dart';
import 'protected_owned_review_page.dart';

/// Existing resource retargeted to Markdown/HTML/article: only current remote
/// source may be reviewed. Ending tracking never proves the old request applied
/// and never transitions automatically to a writable editor.
Future<bool> openRetargetedProtectedRecovery(
  BuildContext context, {
  required String server,
  required int memberId,
  required int resourceId,
  required String namespace,
  required bool hasPassword,
  required bool Function() isCurrentScope,
  required Future<Map<String, Object?>> Function(
    String password,
    Future<void> abortTrigger,
  )
  readSource,
  required Future<String?> Function(String) readValue,
  required Future<void> Function(String, String) writeValue,
  required Future<void> Function(String) deleteValue,
  required Future<void> Function() flush,
  required void Function(ProtectedComplexOwner) registerOwner,
  required void Function(ProtectedComplexOwner) unregisterOwner,
  bool english = false,
}) async {
  bool current() {
    try {
      return context.mounted && isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  String t(String zh, String en) => english ? en : zh;
  if (!context.mounted || !current()) return false;
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode([
      'owned-remote-complex',
      server,
      memberId,
      namespace,
      'remote-note',
      0,
      resourceId,
    ]),
  );
  if (lease == null) return false;
  ProtectedComplexLifetime? lifetime;
  try {
    final journal = ProtectedOwnedComplexJournal(
      scope: ProtectedOwnedComplexJournal.scopeFor(
        server: server,
        memberId: memberId,
        namespace: namespace,
        resourceId: resourceId,
        kind: 'drawing',
      ),
      ownerTag: ProtectedOwnedComplexJournal.ownerTagFor(
        server: server,
        memberId: memberId,
        namespace: namespace,
      ),
      isCurrent: current,
      readValue: readValue,
      writeValue: writeValue,
      deleteValue: deleteValue,
      flush: flush,
    );
    final owner = ProtectedComplexLifetime(
      journal: journal,
      isCurrentScope: current,
      onDrained: unregisterOwner,
    );
    lifetime = owner;
    registerOwner(owner);
    final marker = await journal.load();
    if (marker == null || !context.mounted || !owner.current) return false;
    final navigator = Navigator.of(context);
    Future<T?> push<T>(TransitionRoute<T> page) async {
      owner.bindRoute(() async {
        if (page.isActive) navigator.removeRoute(page);
        await page.completed;
      });
      final result = await navigator.push<T>(page);
      await page.completed;
      if (owner.current) owner.bindRoute(null);
      return result;
    }

    ProtectedOwnedRecoveryReader? reader;
    Future<ComplexNote> unlock(String password) async {
      if (!owner.current) throw StateError(t('空间已变化', 'Space changed'));
      final next = ProtectedOwnedRecoveryReader(
        scope: journal.scope,
        memberId: memberId,
        resourceId: resourceId,
        isCurrent: () => owner.current,
        password: password,
        request: (password) => readSource(password, owner.abortTrigger),
      );
      owner.bindRecoveryDispose(next.dispose);
      reader = next;
      try {
        return await next.read();
      } catch (_) {
        throw StateError(
          t(
            '无法解锁或读取当前版本，记录已保留。',
            'Unable to unlock or read the current version. The record is retained.',
          ),
        );
      }
    }

    final ComplexNote? actual = hasPassword
        ? await push<ComplexNote>(
            DialogRoute<ComplexNote>(
              context: context,
              barrierDismissible: false,
              builder: (_) => NoteUnlockDialog<ComplexNote>(
                onUnlock: unlock,
                english: english,
              ),
            ),
          )
        : await unlock('');
    if (actual == null || !owner.current) return false;
    final source = reader!;
    final ended = await push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProtectedOwnedReviewPage(
          initial: actual,
          owner: owner,
          english: english,
          readFresh: source.read,
          finishReviewed: (reviewed) => journal.endReviewed(
            reviewedFingerprint: reviewed.resourceFingerprint!,
            fresh: () async => source.observation(await source.read()),
          ),
        ),
      ),
    );
    return ended == true;
  } catch (_) {
    if (context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              '无法完成只读核对，原提交标记已保留。',
              'Read-only review is incomplete. The original marker is retained.',
            ),
          ),
        ),
      );
    }
    return false;
  } finally {
    try {
      await lifetime?.retire();
    } finally {
      lease.release();
    }
  }
}
