import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/complex_editor_document.dart';
import '../../core/local_generation_content_repository.dart';
import '../../core/notes_repository.dart';
import '../../core/owned15_creation_journal.dart';
import '../../core/owned15_creation_lifetime.dart';
import '../../core/owned15_creation_recovery_controller.dart';
import '../../core/owned15_creation_target.dart';
import '../../core/owned15_native_creation_repository.dart';
import '../../core/owned15_save_journal.dart';
import '../../core/owned_preview_controller.dart';
import '../../core/owned_writable_generation15.dart';
import '../../core/protected_complex_lifetime.dart';
import '../admin/admin_asset_secure_window.dart';
import '../complex_editors/complex_editor_browser.dart';
import '../html/html_editor_lease.dart';
import '../notes/note_unlock_dialog.dart';
import '../notes/notes_page.dart';
import 'owned15_creation_actual_view.dart';
import 'owned15_creation_protection_dialog.dart';
import 'owned15_creation_review_page.dart';
import 'owned15_creation_target_dialog.dart';
import 'owned15_native_creation_host.dart';
import 'owned15_webview_creation_page.dart';

/// Both warm new creation and cold recovery enter this exact generation slot.
/// No ordinary LocalStore, receipt INSERT helper or writable read-only session.
Future<bool> openOwned15Creation(
  BuildContext context, {
  required OwnedWritableGeneration15 database,
  required bool Function() isCurrentScope,
  required Future<void> Function() checkRecoveryMetadata,
  required Future<void> Function() openColdRecovery,
  required Future<String?> Function(String) readValue,
  required Future<void> Function(String, String) writeValue,
  required Future<void> Function(String) deleteValue,
  required Future<void> Function() flush,
  required void Function(ProtectedComplexOwner) registerOwner,
  required void Function(ProtectedComplexOwner) unregisterOwner,
  bool recoverOnly = false,
  bool english = false,
}) async {
  bool current() => context.mounted && database.current && isCurrentScope();
  if (!current()) return false;
  await database.confirmCurrent();
  await checkRecoveryMetadata();
  if (!context.mounted || !current()) return false;
  final lease = HtmlEditorLease.acquire(
    context,
    jsonEncode(['owned15-create', database.pointer.encode()]),
  );
  if (lease == null) return false;
  final secure = AdminAssetSecureWindow();
  Owned15CreationLifetime? lifetime;
  Owned15CreationJournal? unboundJournal;
  Owned15GenerationCreator? unboundCreator;
  final previews = <OwnedPreviewController>[];
  bool registered = false;
  try {
    final journal = unboundJournal = Owned15CreationJournal(
      owner: Owned15SaveJournal.ownerTagForGeneration(
        database.generation.draftNamespace,
      ),
      isCurrent: current,
      readValue: readValue,
      writeValue: writeValue,
      deleteValue: deleteValue,
      flush: flush,
    );
    final creator = unboundCreator = Owned15GenerationCreator(database);
    final controller = Owned15CreationRecoveryController(
      creator: creator,
      journal: journal,
      isCurrent: current,
    );
    final owner = Owned15CreationLifetime(
      controller: controller,
      isCurrentScope: current,
    );
    lifetime = owner;
    registerOwner(owner);
    registered = true;
    // Secure window precedes password dialogs and all private plaintext routes.
    await secure.acquire();
    if (!context.mounted || !owner.current) return false;
    final navigator = Navigator.of(context);
    final routes = <TransitionRoute<dynamic>>[];
    owner.bindRoute(() async {
      for (final route in routes.toList(growable: false).reversed) {
        if (route.isActive) navigator.removeRoute(route);
        await route.completed;
      }
    });
    Future<T?> route<T>(Widget page) async {
      if (!owner.current) return null;
      final typed = MaterialPageRoute<T>(builder: (context) => page);
      routes.add(typed);
      try {
        return await navigator.push<T>(typed);
      } finally {
        await typed.completed;
        routes.remove(typed);
      }
    }

    final marker = await journal.load();
    if (!context.mounted || !owner.current) return false;
    if (marker == null && recoverOnly) return false;
    Future<void> resolved() async {
      if (owner.current && navigator.canPop()) navigator.pop();
    }

    Future<bool> actual(
      BuildContext viewContext,
      Owned15CreationReview review,
    ) async {
      if (!owner.current || review.observation == null) return false;
      final latest = await controller.inspect();
      if (!viewContext.mounted ||
          !owner.current ||
          latest.fingerprint != review.fingerprint) {
        return false;
      }
      // The warm readonly engine must relinquish the single native lease
      // before a different actual-resource engine is mounted.
      await Future.wait(
        previews.toList(growable: false).map((view) => view.retire()),
      );
      if (!viewContext.mounted || !owner.current) return false;
      final request = AttachmentCancellation();
      GenerationContentHandle? handle;
      OwnedPreviewController? resourcePreview;
      Future<GenerationContentHandle>? pending;
      void cancel() {
        request.cancel();
        handle?.close();
      }

      owner.registerMemoryRelease(cancel);
      Future<void> drain() async {
        try {
          await pending;
        } catch (_) {}
      }

      owner.registerDrainer(drain);
      try {
        Future<bool> open(String? password) async {
          pending = database.content.open(
            review.observation!.receipt.id,
            collection: review.marker.collection,
            password: password,
            cancellation: request,
          );
          final loaded = await pending!;
          if (!owner.current) {
            loaded.close();
            return false;
          }
          handle = loaded;
          return true;
        }

        try {
          if (!await open(null)) return false;
        } on GenerationContentLocked {
          if (!viewContext.mounted || !owner.current) return false;
          final unlocked = await route<bool>(
            NoteUnlockDialog<bool>(
              english: english,
              onUnlock: (password) => open(password),
            ),
          );
          if (unlocked != true || !owner.current) return false;
        }
        final resource = handle;
        if (resource == null || !viewContext.mounted || !owner.current) {
          return false;
        }
        final again = await controller.inspect();
        if (!viewContext.mounted ||
            !owner.current ||
            again.fingerprint != review.fingerprint) {
          return false;
        }
        final preview = resourcePreview = OwnedPreviewController();
        previews.add(preview);
        return await route<bool>(
              Owned15CreationActualView(
                handle: resource,
                lifetime: owner,
                preview: preview,
                english: english,
              ),
            ) ==
            true;
      } finally {
        request.cancel();
        handle?.close();
        await drain();
        await resourcePreview?.retire();
        owner.unregisterMemoryRelease(cancel);
        owner.unregisterDrainer(drain);
      }
    }

    Widget review({ComplexEditorDocument? document, String? title}) {
      return Owned15CreationReviewPage(
        controller: controller,
        isCurrent: () => owner.current,
        english: english,
        warmDocument: document,
        warmTitle: title,
        onOpenCurrent: actual,
        onResolved: resolved,
        webViewSnapshotBuilder: (context, source) {
          final preview = OwnedPreviewController();
          previews.add(preview);
          owner.registerDrainer(preview.retire);
          return ComplexEditorBrowser(
            document: source,
            english: english,
            readOnly: true,
            retirementController: preview,
          );
        },
      );
    }

    if (marker != null) {
      await route<void>(review());
      return true;
    }
    final target = await route<Owned15CreationTarget>(
      Owned15CreationTargetDialog(english: english),
    );
    if (!context.mounted || !owner.current || target == null) return false;
    final random = Random.secure();
    final operation = List.generate(
      16,
      (_) => random.nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    if (target.nativeMarkdownNote) {
      final protection = await route<Owned15MemoryProtection>(
        Owned15CreationProtectionDialog(english: english),
      );
      if (!context.mounted || !owner.current || protection == null) {
        return false;
      }
      owner.registerMemoryRelease(protection.clear);
      Note? initial = Note(
        title: '',
        content: '',
        isProtected: protection.protected,
        unlockPassword: protection.password,
      );
      owner.registerMemoryRelease(() => initial = null);
      final repository = Owned15NativeCreationRepository(
        controller: controller,
        operation: operation,
        isCurrent: () => owner.current,
      );
      await route<void>(
        Owned15NativeCreationHost(
          repository: repository,
          lifetime: owner,
          english: english,
          editorBuilder: (context) => NoteEditorPage(
            repository: repository,
            note: initial!,
            drafts: null,
            attachments: null,
            allowAttachmentInsertion: false,
            english: english,
          ),
          reviewBuilder: (context) {
            final snapshot = repository.memorySnapshot;
            return review(
              document: snapshot == null
                  ? null
                  : ComplexEditorDocument.parse(
                      ComplexEditorKind.markdown,
                      snapshot.content,
                    ),
              title: snapshot?.title,
            );
          },
          openColdReview: openColdRecovery,
        ),
      );
      protection.clear();
    } else {
      await route<void>(
        Owned15WebViewCreationPage(
          lifetime: owner,
          operation: operation,
          collection: target.collection,
          english: english,
          initialDocument: target.newDocument(operation),
          reviewBuilder: (context, document, title) =>
              review(document: document, title: title),
          onMemoryReleased: openColdRecovery,
        ),
      );
    }
    return true;
  } finally {
    if (lifetime == null) {
      await unboundCreator?.retire();
      await unboundJournal?.retire();
    } else {
      await lifetime.retire();
      // A failed drain remains registered, so transitions cannot bypass it.
      if (registered) unregisterOwner(lifetime);
    }
    try {
      await Future.wait(previews.map((preview) => preview.retire()));
    } finally {
      try {
        await secure.close();
      } finally {
        lease.release();
      }
    }
  }
}
