import '../../core/owned_complex_images.dart';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../core/api_client.dart';
import '../../core/native_complex_source_io.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_recovery_vault.dart';
import '../../core/local_complex_editor_controller.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/protected_complex_lifetime.dart';
import '../../core/protected_complex_memory_store.dart';
import '../../core/protected_owned_complex_journal.dart';
import '../../core/remote_owned_complex_store.dart';
import '../html/html_editor_lease.dart';
import '../notes/note_unlock_dialog.dart';
import 'local_complex_note_page.dart';
import 'open_remote_owned_complex.dart';
import 'protected_owned_review_page.dart';

/// All owned five-kind note entries must pass this dispatcher, including when
/// protection was removed since the previous unresolved request.
Future<bool> openOwnedComplexWithProtectedRecovery(
  BuildContext context, {
  required BookstarkClient client,
  required int memberId,
  required int resourceId,
  required ComplexEditorKind kind,
  required String recoveryNamespace,
  required bool Function() isCurrentScope,
  required Future<String?> Function(String) readValue,
  required Future<void> Function(String, String) writeValue,
  required Future<void> Function(String) deleteValue,
  required Future<void> Function() flush,
  required void Function(ProtectedComplexLifetime) registerOwner,
  required void Function(ProtectedComplexLifetime) unregisterOwner,
  ComplexSourceIoScope? sourceIoScope,
  bool english = false,
}) async {
  if (!const {
    ComplexEditorKind.spreadsheet,
    ComplexEditorKind.drawing,
    ComplexEditorKind.mindmap,
    ComplexEditorKind.richdoc,
    ComplexEditorKind.presentation,
  }.contains(kind)) {
    throw ArgumentError('Owned five-kind note required');
  }
  final revision = client.sessionRevision;
  bool current() {
    try {
      return context.mounted &&
          client.sessionRevision == revision &&
          isCurrentScope();
    } catch (_) {
      return false;
    }
  }

  if (!context.mounted || !current()) return false;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
  String t(String zh, String en) => english ? en : zh;
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode([
      'owned-remote-complex',
      client.baseUri.toString(),
      memberId,
      recoveryNamespace,
      'remote-note',
      0,
      resourceId,
    ]),
  );
  if (lease == null) return false;
  ProtectedComplexLifetime? lifetime;
  bool delegated = false;
  try {
    final journal = ProtectedOwnedComplexJournal(
      scope: ProtectedOwnedComplexJournal.scopeFor(
        server: client.baseUri.toString(),
        memberId: memberId,
        namespace: recoveryNamespace,
        resourceId: resourceId,
        kind: kind.name,
      ),
      ownerTag: ProtectedOwnedComplexJournal.ownerTagFor(
        server: client.baseUri.toString(),
        memberId: memberId,
        namespace: recoveryNamespace,
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
    final metadata = await client.articleMetadata(
      resourceId,
      abortTrigger: owner.abortTrigger,
    );
    if (!context.mounted || !owner.current) return false;
    if (metadata['blog_id'] != resourceId ||
        metadata['member_id'] != memberId ||
        metadata['blog_type'] != 'note' ||
        metadata['editor_type'] != kind.name ||
        metadata['has_password'] is! bool) {
      throw StateError('Owned metadata identity mismatch');
    }
    final marker = await journal.load();
    if (!context.mounted || !owner.current) return false;
    if (metadata['has_password'] == false && marker == null) {
      await owner.retire();
      lease.release();
      if (!context.mounted || !current()) return false;
      delegated = true;
      return await openRemoteOwnedComplex(
        context,
        client: client,
        memberId: memberId,
        resourceId: resourceId,
        bookId: 0,
        note: true,
        kind: kind,
        recoveryNamespace: recoveryNamespace,
        isCurrentScope: current,
        sourceIoScope: sourceIoScope,
        english: english,
      );
    }
    if (!context.mounted || !owner.current) return false;
    final navigator = Navigator.of(context);
    Future<T?> route<T>(TransitionRoute<T> page) async {
      owner.bindRoute(() async {
        if (page.isActive) navigator.removeRoute(page);
        await page.completed;
      });
      final value = await navigator.push<T>(page);
      await page.completed;
      if (owner.current) owner.bindRoute(null);
      return value;
    }

    RemoteOwnedComplexStore? repository;
    ComplexNote? baseline;
    if (metadata['has_password'] == true) {
      baseline = await route<ComplexNote>(
        DialogRoute<ComplexNote>(
          context: context,
          barrierDismissible: false,
          builder: (_) => NoteUnlockDialog<ComplexNote>(
            english: english,
            onUnlock: (password) async {
              if (!owner.current) {
                throw StateError(t('当前账号已变化', 'Account changed'));
              }
              final next = ProtectedOwnedComplexStore(
                client: client,
                memberId: memberId,
                resourceId: resourceId,
                kind: kind,
                recoveryNamespace: recoveryNamespace,
                isCurrent: () => owner.current,
                password: password,
                journal: journal,
              );
              owner.bindRepository(next);
              repository = next;
              try {
                return await next.read(resourceId);
              } catch (_) {
                throw StateError(
                  t(
                    '无法解锁或读取此笔记。原记录已保留。',
                    'Unable to unlock or read this note. The record is retained.',
                  ),
                );
              }
            },
          ),
        ),
      );
      if (!owner.current || baseline == null) return false;
    } else {
      final plain = RemoteOwnedComplexStore(
        client: client,
        memberId: memberId,
        resourceId: resourceId,
        bookId: 0,
        note: true,
        kind: kind,
        recoveryNamespace: recoveryNamespace,
        isCurrent: () => owner.current,
      );
      owner.bindRepository(plain);
      repository = plain;
      baseline = await plain.read(resourceId);
    }
    final repo = repository!;
    if (marker != null) {
      ProtectedComplexObservation observe(ComplexNote value) {
        if (repo is ProtectedOwnedComplexStore) return repo.observation(value);
        return ProtectedComplexObservation(
          fingerprint: value.resourceFingerprint!,
          inputDigest: sha256
              .convert(utf8.encode(value.document.source))
              .toString(),
        );
      }

      final ended = await route<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => ProtectedOwnedReviewPage(
            initial: baseline!,
            owner: owner,
            english: english,
            readFresh: () => repo.read(resourceId),
            finishReviewed: (reviewed) async {
              final fresh = await repo.read(resourceId);
              if (!owner.current || !fresh.same(reviewed)) {
                throw StateError('Source changed');
              }
              final actual = observe(fresh);
              if (marker.known &&
                  actual.fingerprint == marker.knownFingerprint &&
                  actual.inputDigest == marker.inputDigest) {
                await journal.confirmColdKnown(actual);
                await journal.finishKnown();
              } else {
                await journal.endReviewed(
                  reviewedFingerprint: actual.fingerprint,
                  fresh: () async => observe(await repo.read(resourceId)),
                );
              }
            },
          ),
        ),
      );
      if (ended != true || !owner.current) return false;
      await owner.nextPreview();
      baseline = await repo.read(resourceId);
      if (!context.mounted || !owner.current) return false;
    }
    // If protection disappeared, ending the marker does not authorize editing
    // through the protected transport or an obsolete baseline.
    if (repo is! ProtectedOwnedComplexStore) return false;
    final memory = ProtectedComplexMemoryStore(journal);
    owner.bindMemory(memory);
    final vault = ComplexRecoveryVault(
      scope: repo.scope,
      collection: repo.collection,
      kind: kind,
      store: memory,
    );
    final editor = LocalComplexEditorController(
      repository: repo,
      vault: vault,
      baseline: baseline,
      ephemeralDrafts: true,
      beforeAdoptReviewed: repo.endWarmReview,
    );
    final images = OwnedComplexImages(
      client: client,
      memberId: memberId,
      resourceId: resourceId,
      bookId: 0,
      note: true,
      namespace: recoveryNamespace,
      isCurrent: () => current() && owner.current,
      editor: editor,
    );
    bool built = false;
    try {
      await images.open();
      if (!context.mounted || !owner.current) return false;
      await route<void>(
        MaterialPageRoute<void>(
          builder: (_) {
            built = true;
            return LocalComplexNotePage(
              controller: editor,
              english: english,
              ownedImages: images,
              sourceIoScope: sourceIoScope,
              documentBodyOnly: true,
              retirementController: owner.preview,
              renewRetirementController: () async {
                await owner.nextPreview();
                return owner.preview;
              },
              retentionNotice: t(
                '此受保护正文只保留在本次会话内存。关闭应用后不能恢复未保存正文；未知保存需解锁后核对服务器版本。',
                'This protected body remains only in session memory. Unsaved text cannot be recovered after closing the app. An unknown save requires unlocking and reviewing the current server version.',
              ),
              originLabel: t('远端受保护', 'Protected remote'),
            );
          },
        ),
      );
      return true;
    } finally {
      try {
        await images.retireAndDrain();
      } finally {
        if (!built) editor.dispose();
      }
    }
  } catch (_) {
    if (context.mounted && current()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              '无法安全打开。原文和提交核对记录均已保留。',
              'Unable to open safely. Source and submission review records are retained.',
            ),
          ),
        ),
      );
    }
    return false;
  } finally {
    if (!delegated) {
      try {
        await lifetime?.retire();
      } finally {
        lease.release();
      }
    }
  }
}
