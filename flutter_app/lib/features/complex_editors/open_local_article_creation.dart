import '../../core/native_complex_source_io.dart';
import 'open_local_complex_note.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/draft_vault.dart';
import '../../core/local_article_creation_controller.dart';
import '../../core/local_article_creation_legacy_handoff.dart';
import '../../core/local_article_creation_record.dart';
import '../../core/local_complex_notes_repository.dart';
import '../../core/local_recovery_namespaces.dart';
import '../../core/local_store.dart';
import 'article_draft_archive_view.dart';
import 'local_article_create_page.dart';
import 'local_article_creation_services.dart';
import 'local_article_creation_source_surface.dart';

enum _ArchiveAction { restore, resume, openCreated, unavailable }

class _ArchiveChoice {
  const _ArchiveChoice(
    this.action, {
    this.creationKey,
    this.record,
    this.noteId,
    this.message,
  });
  final _ArchiveAction action;
  final String? creationKey, message;
  final LocalArticleCreationRecord? record;
  final int? noteId;
}

class _ArchiveApproval {
  const _ArchiveApproval({
    required this.namespace,
    required this.digest,
    required this.ciphertextSHA256,
    required this.action,
    required this.creationKey,
    this.recordSHA256,
    this.noteId,
  });
  final String namespace, digest, ciphertextSHA256, creationKey;
  final _ArchiveAction action;
  final String? recordSHA256;
  final int? noteId;
}

String _recordHash(LocalArticleCreationRecord record) =>
    sha256.convert(record.encode()).toString();

Future<void> _creationMessage(
  BuildContext context, {
  required String title,
  required String message,
  required bool english,
}) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    scrollable: true,
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(english ? 'Return' : '返回'),
      ),
    ],
  ),
);

Future<bool> openLocalArticleCreation(
  BuildContext context, {
  required LocalStore store,
  DraftVault? legacyDrafts,
  bool english = false,
  bool forceLegacyReview = false,
  bool Function()? isCurrentScope,
  ComplexSourceIoScope? sourceIoScope,
  void Function(ComplexNote actual)? onCreatedReceipt,
  LocalArticleCreationServices? services,
  ArticleCreationSurfaceBuilder sourceBuilder = defaultArticleCreationSurface,
  ArticleCreationReviewBuilder reviewBuilder = defaultArticleCreationReview,
}) => _openCreation(
  context,
  store: store,
  legacyDrafts: legacyDrafts,
  english: english,
  forceLegacyReview: forceLegacyReview,
  isCurrentScope: isCurrentScope,
  sourceIoScope: sourceIoScope,
  onCreatedReceipt: onCreatedReceipt,
  providedServices: services,
  sourceBuilder: sourceBuilder,
  reviewBuilder: reviewBuilder,
);

Future<bool> _openCreation(
  BuildContext context, {
  required LocalStore store,
  DraftVault? legacyDrafts,
  required bool english,
  bool forceLegacyReview = false,
  bool Function()? isCurrentScope,
  ComplexSourceIoScope? sourceIoScope,
  void Function(ComplexNote actual)? onCreatedReceipt,
  LocalArticleCreationServices? providedServices,
  _ArchiveApproval? approval,
  ArticleCreationSurfaceBuilder sourceBuilder = defaultArticleCreationSurface,
  ArticleCreationReviewBuilder reviewBuilder = defaultArticleCreationReview,
}) async {
  String t(String zh, String en) => english ? en : zh;
  bool current() {
    if (!context.mounted || store.maintenance.retired) return false;
    try {
      return isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  if ((!context.mounted || !current())) return false;
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    await _creationMessage(
      context,
      title: t(
        '此平台暂不支持文章编辑',
        'Article editing is unavailable on this platform',
      ),
      message: t(
        '请在 Android 客户端打开本地文章。原草稿未改动。',
        'Open local articles in the Android client. Existing drafts are unchanged.',
      ),
      english: english,
    );
    return false;
  }
  LocalArticleCreationServices? services;
  LocalArticleCreationController? controller;
  var ownedByPage = false;
  try {
    services =
        providedServices ??
        LocalArticleCreationServices.forStore(store, legacy: legacyDrafts);
    if (!identical(services.store, store) ||
        legacyDrafts != null && !identical(legacyDrafts, services.legacy)) {
      throw ArgumentError('Article creation services belong to another scope');
    }
    final handoff = services.handoff(current);
    var record = await services.vault.read();
    if ((!context.mounted || !current())) return false;
    if (approval != null) {
      if (approval.namespace != services.legacy.namespace) {
        throw StateError('Archived creation approval belongs to another space');
      }
      final archive = await services
          .archiveReader(
            namespace: approval.namespace,
            ownedNamespaces: {store.dataPaths!.draftNamespace},
            isCurrentScope: current,
          )
          .readHandled();
      if ((!context.mounted || !current())) return false;
      if (archive.draft.digest != approval.digest ||
          archive.draft.ciphertextSHA256 != approval.ciphertextSHA256) {
        throw StateError('Archived creation changed after confirmation');
      }
      if (approval.action == _ArchiveAction.resume) {
        if (record == null ||
            record.key != approval.creationKey ||
            _recordHash(record) != approval.recordSHA256) {
          throw StateError('Pending creation changed after confirmation');
        }
      } else if (approval.action != _ArchiveAction.restore) {
        throw StateError('Invalid creation editor approval');
      }
      record = await handoff.restore(
        archive.draft,
        expectedCreationKey: approval.creationKey,
      );
      if ((!context.mounted || !current())) return false;
    } else {
      LocalArticleCreationLegacyDraft? candidate;
      if (record == null || record.legacyBinding != null || forceLegacyReview) {
        try {
          candidate = await handoff.inspect(forceReview: forceLegacyReview);
          if ((!context.mounted || !current())) return false;
          record = await services.vault.read();
          if ((!context.mounted || !current())) return false;
        } catch (_) {
          if (record == null || (!context.mounted || !current())) rethrow;
          final proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: Text(
                t('原旧稿暂不能核对', 'The old draft cannot be verified yet'),
              ),
              content: Text(
                t(
                  '现有新建草稿与原旧稿均已保留。',
                  'The current creation draft and original old draft are retained.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text(t('返回', 'Return')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text(t('继续现有草稿', 'Continue current draft')),
                ),
              ],
            ),
          );
          if ((!context.mounted || !current()) || proceed != true) return false;
        }
      }
      if (candidate != null && current()) {
        final copied = record?.legacyBinding;
        if (record != null &&
            copied?.legacyKey == candidate.legacyKey &&
            copied?.digest == candidate.digest) {
          // Repaired durable transfer: continue its exact existing draft.
        } else {
          LocalArticleCreationLegacyArchive? handled;
          try {
            handled = await handoff.readHandled();
          } catch (_) {}
          if ((!context.mounted || !current())) return false;
          if (handled != null) {
            return await openLocalArticleCreationArchive(
              context,
              store: store,
              namespace: services.legacy.namespace,
              english: english,
              isCurrentScope: current,
              services: services,
              sourceBuilder: sourceBuilder,
              reviewBuilder: reviewBuilder,
            );
          }
          final hasCurrent = record != null;
          final choice = await showDialog<String>(
            context: context,
            builder: (context) => AlertDialog(
              scrollable: true,
              title: Text(
                hasCurrent
                    ? t('已有新建草稿', 'A creation draft already exists')
                    : t('发现原有新建草稿', 'Original new-article draft found'),
              ),
              content: Text(
                hasCurrent
                    ? t(
                        '请先处理现有草稿。原旧稿仍保留，不会覆盖现有内容。',
                        'Resolve the current draft first. The old draft is retained without overwriting it.',
                      )
                    : t(
                        '原草稿会保留。恢复后仍需点击创建。',
                        'The original draft is retained. Restore still requires an explicit Create.',
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(t('返回', 'Return')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, 'skip'),
                  child: Text(t('暂不恢复', 'Not now')),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    hasCurrent ? 'current' : 'restore',
                  ),
                  child: Text(
                    hasCurrent
                        ? t('继续处理', 'Continue')
                        : t('恢复草稿', 'Restore draft'),
                  ),
                ),
              ],
            ),
          );
          if ((!context.mounted || !current()) || choice == null) return false;
          if (choice == 'restore') {
            record = await handoff.restore(candidate);
          } else if (choice == 'skip') {
            await handoff.skip(candidate);
          }
          if ((!context.mounted || !current())) return false;
        }
      }
    }
    if ((!context.mounted || !current())) return false;
    final activeServices = services;
    controller = LocalArticleCreationController(
      repository: activeServices.repository,
      vault: activeServices.vault,
      record: record,
      isCurrentScope: current,
    );
    final owner = controller;
    final completed =
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) {
              ownedByPage = true;
              return LocalArticleCreatePage(
                controller: owner,
                sourceIoScope: sourceIoScope,
                english: english,
                sourceBuilder: sourceBuilder,
                reviewBuilder: reviewBuilder,
              );
            },
          ),
        ) ??
        false;
    final created = owner.created;
    if (completed && created != null && context.mounted && current()) {
      onCreatedReceipt?.call(created);
      if (!context.mounted || !current()) return false;
      await openLocalComplexNote(
        context,
        store: store,
        id: created.id,
        collection: 'article',
        kind: ComplexEditorKind.markdown,
        english: english,
        isCurrentScope: current,
        legacyMarkdownDrafts: activeServices.legacy,
        recoveryStore: activeServices.vault.store,
        sourceIoScope: sourceIoScope,
      );
    }
    return completed;
  } catch (_) {
    if (context.mounted && current()) {
      await _creationMessage(
        context,
        title: t('新建草稿无法核对', 'Cannot verify the creation draft'),
        message: t(
          '已有草稿和已保存文章均已保留。请返回后重试。',
          'Existing drafts and saved articles are retained. Return and retry.',
        ),
        english: english,
      );
    }
    return false;
  } finally {
    if (!ownedByPage) controller?.dispose();
    // A services object may have been shared with an archive route. Repository
    // disposal is idempotent; the local store and original drafts stay owned.
    services?.dispose();
  }
}

Future<_ArchiveChoice> _archiveChoice(
  LocalArticleCreationServices services,
  LocalArticleCreationLegacyArchive archive,
  String namespace,
  bool Function() current,
) async {
  void check() {
    if (!current()) throw StateError('Article archive scope changed');
  }

  if (namespace != services.legacy.namespace) {
    return const _ArchiveChoice(
      _ArchiveAction.unavailable,
      message: 'retained-space',
    );
  }
  check();
  final pending = await services.vault.read();
  check();
  final binding = pending?.legacyBinding;
  final linked = archive.receipt.creationKey;
  if (pending != null &&
      binding?.legacyKey == archive.draft.legacyKey &&
      binding?.digest == archive.draft.digest &&
      (linked == null || linked == pending.key)) {
    return _ArchiveChoice(
      _ArchiveAction.resume,
      creationKey: pending.key,
      record: pending,
    );
  }
  if (linked != null) {
    final receipt = await services.repository.findCreation(linked);
    check();
    if (receipt != null) {
      if (receipt.note == null) {
        return const _ArchiveChoice(
          _ArchiveAction.unavailable,
          message: 'target-unavailable',
        );
      }
      return _ArchiveChoice(
        _ArchiveAction.openCreated,
        creationKey: linked,
        noteId: receipt.noteId,
      );
    }
  }
  if (pending != null) {
    return const _ArchiveChoice(
      _ArchiveAction.unavailable,
      message: 'pending-other',
    );
  }
  return _ArchiveChoice(_ArchiveAction.restore, creationKey: linked);
}

Future<bool> openLocalArticleCreationArchive(
  BuildContext context, {
  required LocalStore store,
  required String namespace,
  bool english = false,
  bool Function()? isCurrentScope,
  LocalArticleCreationServices? services,
  ArticleArchiveBodyBuilder archiveBuilder = defaultArticleArchiveBody,
  Future<bool> Function(int id)? existingArticleOpener,
  ArticleCreationSurfaceBuilder sourceBuilder = defaultArticleCreationSurface,
  ArticleCreationReviewBuilder reviewBuilder = defaultArticleCreationReview,
}) async {
  String t(String zh, String en) => english ? en : zh;
  bool current() {
    if (!context.mounted || store.maintenance.retired) return false;
    try {
      return isCurrentScope?.call() ?? true;
    } catch (_) {
      return false;
    }
  }

  if ((!context.mounted || !current())) return false;
  final env = services ?? LocalArticleCreationServices.forStore(store);
  try {
    if (!identical(env.store, store)) {
      throw ArgumentError('Article archive services belong to another store');
    }
    final namespaces = await localRecoveryNamespaces(store.dataPaths!);
    if ((!context.mounted || !current())) return false;
    final reader = env.archiveReader(
      namespace: namespace,
      ownedNamespaces: namespaces,
      isCurrentScope: current,
    );
    final archive = await reader.readHandled();
    if ((!context.mounted || !current())) return false;
    final initial = await _archiveChoice(env, archive, namespace, current);
    if ((!context.mounted || !current())) return false;
    final available = initial.action != _ArchiveAction.unavailable;
    final label = initial.action == _ArchiveAction.resume
        ? t('继续处理', 'Continue')
        : initial.action == _ArchiveAction.openCreated
        ? t('打开已创建文章', 'Open created article')
        : t('恢复旧稿', 'Restore old draft');
    final unavailable = initial.message == 'retained-space'
        ? t(
            '此旧稿属于保留的旧空间，仅供只读查阅。',
            'This draft belongs to a retained space and is read-only.',
          )
        : initial.message == 'pending-other'
        ? t(
            '请先处理现有的新建草稿，旧稿仍保留。',
            'Resolve the current creation draft first. This old draft is retained.',
          )
        : t(
            '已创建的文章已不可用，创建记录和旧稿仍保留，不会重新创建。',
            'The created article is unavailable. Its receipt and old draft remain; it will not be recreated.',
          );
    final approval = await Navigator.push<_ArchiveApproval>(
      context,
      MaterialPageRoute(
        builder: (_) => ArticleDraftArchiveView<_ArchiveApproval>(
          title: archive.draft.edit.title.isEmpty
              ? t('未命名新建草稿', 'Untitled creation draft')
              : archive.draft.edit.title,
          document: archive.draft.edit.document,
          pageTitle: t('旧版新建草稿', 'Old creation draft'),
          english: english,
          actionLabel: label,
          confirmActionLabel: label,
          confirmTitle: initial.action == _ArchiveAction.openCreated
              ? t('打开已创建文章？', 'Open the created article?')
              : initial.action == _ArchiveAction.resume
              ? t('继续处理新建草稿？', 'Continue the creation draft?')
              : t('恢复到新建草稿？', 'Restore as a creation draft?'),
          confirmBody: initial.action == _ArchiveAction.openCreated
              ? t(
                  '只会打开已有文章，原旧稿继续保留。',
                  'Only the existing article opens. The old draft remains.',
                )
              : initial.action == _ArchiveAction.resume
              ? t(
                  '不会覆盖现有草稿，未确认的创建仍需核对。',
                  'The current draft is retained. Uncertain creation still requires review.',
                )
              : t(
                  '原草稿会保留。恢复后仍需点击创建。',
                  'The old draft remains. Restore still requires an explicit Create.',
                ),
          notice: t(
            '这是已处理的旧稿，不会自动创建或覆盖文章。',
            'This handled old draft never creates or overwrites an article automatically.',
          ),
          unavailableMessage: unavailable,
          bodyBuilder: archiveBuilder,
          isCurrentScope: current,
          prepareRestore: !available
              ? null
              : () async {
                  final fresh = await reader.readHandled();
                  if ((!context.mounted || !current()) ||
                      fresh.draft.digest != archive.draft.digest ||
                      fresh.draft.ciphertextSHA256 !=
                          archive.draft.ciphertextSHA256) {
                    throw StateError('Old creation draft changed after review');
                  }
                  final choice = await _archiveChoice(
                    env,
                    fresh,
                    namespace,
                    current,
                  );
                  if ((!context.mounted || !current()) ||
                      choice.action != initial.action ||
                      choice.creationKey != initial.creationKey ||
                      choice.noteId != initial.noteId) {
                    throw StateError(
                      'Creation destination changed after review',
                    );
                  }
                  return _ArchiveApproval(
                    namespace: namespace,
                    digest: fresh.draft.digest,
                    ciphertextSHA256: fresh.draft.ciphertextSHA256,
                    action: choice.action,
                    creationKey: choice.creationKey ?? newComplexCreationKey(),
                    recordSHA256: choice.record == null
                        ? null
                        : _recordHash(choice.record!),
                    noteId: choice.noteId,
                  );
                },
        ),
      ),
    );
    if ((!context.mounted || !current()) || approval == null) return false;
    final fresh = await reader.readHandled();
    if ((!context.mounted || !current()) ||
        approval.namespace != namespace ||
        fresh.draft.digest != approval.digest ||
        fresh.draft.ciphertextSHA256 != approval.ciphertextSHA256) {
      throw StateError('Old creation draft approval changed');
    }
    if (approval.action == _ArchiveAction.openCreated) {
      final receipt = await env.repository.findCreation(approval.creationKey);
      if ((!context.mounted || !current()) ||
          receipt?.note == null ||
          receipt!.noteId != approval.noteId) {
        throw StateError('Created article is no longer available');
      }
      if (existingArticleOpener != null) {
        return await existingArticleOpener(receipt.noteId);
      }
      return await openLocalComplexNote(
        context,
        store: store,
        id: receipt.noteId,
        collection: 'article',
        kind: ComplexEditorKind.markdown,
        english: english,
        isCurrentScope: current,
      );
    }
    if ((!context.mounted || !current())) return false;
    return await _openCreation(
      context,
      store: store,
      english: english,
      isCurrentScope: current,
      providedServices: env,
      approval: approval,
      sourceBuilder: sourceBuilder,
      reviewBuilder: reviewBuilder,
    );
  } finally {
    if (services == null) env.dispose();
  }
}
