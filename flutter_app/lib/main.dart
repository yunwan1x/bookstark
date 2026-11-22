import 'core/local_task_creation_session.dart';
import 'core/task_creation_session.dart';
import 'features/tasks/task_creation_recovery_page.dart';
import 'core/root_local_creation_dispatch.dart';
import 'core/local_recovery_inventory.dart';
import 'core/local_legacy_format_selection.dart';
import 'core/local_legacy_zip_stage.dart';
import 'features/local_backup/owned_generation15_activation_page.dart';
import 'features/local_backup/local_legacy_migration_page.dart';
import 'features/local_backup/local_pending_recovery_page.dart';
import 'features/local_backup/owned15_pending_recovery.dart';
import 'features/local_backup/open_owned15_resource.dart';
import 'features/local_backup/open_owned15_creation.dart';
import 'features/local_backup/owned15_feature.dart';
import 'core/owned_generation15_activation_preparation.dart';
import 'core/owned_generation15_restore_coordinator.dart';
import 'core/local_restore_coordinator.dart';
import 'core/local_retained_backup.dart';
import 'core/local_backup_importer.dart';
import 'core/local_backup_exporter.dart';
import 'core/local_recovery_namespaces.dart';
import 'core/local_generation_content_repository.dart';
import 'core/owned15_save_journal.dart';
import 'core/owned_writable_generation15.dart';
import 'core/resolved_local_storage.dart';
import 'core/resource_creation_result.dart';
import 'core/remote_markdown_creation_controller.dart';
import 'core/remote_markdown_creation_vault.dart';
import 'features/complex_editors/open_local_article_creation.dart';
import 'features/notes/open_remote_article_creation.dart';
import 'core/protected_shared_services.dart';
import 'core/protected_complex_lifetime.dart';
import 'core/protected_owned_resource_gate.dart';
import 'core/protected_owned_marker_inventory.dart';
import 'core/protected_owned_complex_journal.dart';
import 'features/complex_editors/open_owned_complex_with_protected_recovery.dart';
import 'features/complex_editors/open_retargeted_protected_recovery.dart';
import 'features/notes/owned_note_list_scope.dart';
import 'core/selected_speech_repository.dart';
import 'features/images/image_library_owner.dart';
import 'features/tasks/task_editor_action_route.dart';
import 'features/tasks/task_editor_remote_actions.dart';
import 'core/document_excerpt_request.dart';
import 'features/books/remote_book_excerpt_entry.dart';
import 'features/books/local_book_excerpt_entry.dart';
import 'core/local_book_document_complex_store.dart';
import 'core/remote_owned_complex_store.dart';
import 'core/owned_bounded_documents_reader.dart';
import 'features/complex_editors/open_remote_owned_complex.dart';
import 'core/complex_source_io_owner.dart';
import 'core/complex_editor_document.dart';
import 'features/complex_editors/open_local_book_document.dart';
import 'package:crypto/crypto.dart' as entry_crypto;
import 'core/owned_remote_entry_loader.dart';
import 'features/notes/remote_markdown_creation_factory.dart';
import 'features/book_creation_entry.dart';
import 'features/remote_drive_recovery_entry.dart';
import 'core/book_creation_attempt.dart';
import 'core/drive_operation_record.dart';
import 'features/assistant/open_local_assistant_recovery.dart';
import 'features/assistant/local_assistant_editor_coordinator.dart';
import 'core/local_recovery_resolver.dart';
import 'core/local_assistant_write_journal.dart';
import 'core/local_assistant_creation_receipts.dart';
import 'core/local_assistant_editor_drafts.dart';
import 'core/local_assistant_draft_payload.dart';
import 'core/local_assistant_draft_ledger.dart';
import 'core/local_assistant_binding.dart';
import 'core/local_assistant_knowledge.dart';
import 'core/local_assistant_repository.dart';
import 'core/local_model_stream.dart';
import 'features/home_dashboard_controller.dart';
import 'features/home_layout_page.dart';
import 'core/home_dashboard_models.dart';
import 'core/home_dashboard_repository.dart';
import 'core/local_home_repository.dart';
import 'core/local_model_config.dart';
import 'core/native_recovery_storage.dart';
import 'features/assistant/local_model_settings_controller.dart';
import 'features/assistant/local_model_settings_page.dart';
import 'core/local_home_tracking_repositories.dart';
import 'features/admin/admin_assets_feature.dart';
import 'features/admin/admin_assets_scope.dart';
import 'features/admin/admin_assets_repository.dart';
import 'features/admin/admin_settings_repository.dart' show AdminPrincipal;
import 'features/admin/admin_files_page.dart';
import 'features/admin/admin_remote_dav_repository.dart';
import 'features/admin/admin_remote_dav_models.dart';
import 'features/admin/admin_remote_dav_files_page.dart';
import 'features/settings/device_settings_page.dart';
import 'features/settings/settings_connection_controller.dart';
import 'core/owned_download_cache.dart';
import 'features/articles/article_web_page.dart';
import 'core/local_storage_session.dart';
import 'core/native_local_data_control.dart';
import 'features/local_backup/local_backup_feature.dart';
import 'features/local_backup/local_recovery_editor_opener.dart';
import 'core/local_data_maintenance.dart';
import 'core/local_draft_namespace.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart' show rootBundle;
import 'features/html/html_browser_session.dart';
import 'core/local_trash_repository.dart';
import 'core/trash_repository.dart';
import 'features/trash/trash_page.dart';
import 'dart:typed_data';
import 'core/background_repository.dart';
import 'widgets/background_surface.dart';
import 'core/profile_repository.dart';
import 'core/session_vault.dart';
import 'features/profile/profile_feature.dart';
import 'features/public_notes/public_notes_feature.dart';
import 'features/sharing/owner_sharing.dart';
import 'core/public_share_models.dart';
import 'features/public_shares/public_shares_feature.dart';
import 'core/document_creation.dart';
import 'features/public_feed/resource_create_coordinator.dart';
import 'core/drive_repository.dart';
import 'core/local_drive_repository.dart';
import 'core/file_draft_vault.dart';
import 'features/drive/drive_feature.dart';
import 'core/images_repository.dart';
import 'core/local_images_repository.dart';
import 'features/images/images_feature.dart';
import 'widgets/native_image.dart';
import 'core/search_repository.dart';
import 'core/local_search_repository.dart';
import 'features/search/search_page.dart';
import 'core/label_management_repository.dart';
import 'core/local_label_management_repository.dart';
import 'features/labels/labels_feature.dart';
import 'features/labels/open_label_creation.dart';
import 'features/labels/open_label_creation_recovery.dart';
import 'features/labels/open_local_label_creation.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'core/attachments.dart';
import 'core/assistant_repository.dart';
import 'features/assistant/assistant_page.dart';
import 'core/local_attachments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as paths;
import 'package:sqflite/sqflite.dart';
import 'core/api_client.dart';
import 'core/draft_vault.dart';
import 'core/app_theme.dart';
import 'core/local_store.dart';
import 'core/strings.dart';
import 'features/auth/account_form_page.dart';
import 'features/auth/connection_page.dart';
import 'features/home_page.dart';
import 'core/notes_repository.dart';
import 'core/tasks_repository.dart';
import 'core/local_tasks_repository.dart';
import 'core/task_draft_vault.dart';
import 'core/books_repository.dart';
import 'core/bookmarks_repository.dart';
import 'core/local_bookmarks_repository.dart';
import 'core/bookmark_draft_vault.dart';
import 'features/bookmarks/open_bookmark_creation.dart';
import 'features/bookmarks/open_bookmark_creation_recovery.dart';
import 'features/bookmarks/bookmarks_page.dart';
import 'core/topics_repository.dart';
import 'core/local_topics_repository.dart';
import 'core/topic_draft_vault.dart';
import 'core/topic_creation_attempt.dart';
import 'features/topics/open_topic_creation.dart';
import 'features/topics/open_topic_creation_directory.dart';
import 'core/topic_resource_picker_repository.dart';
import 'core/local_note_list_source.dart';
import 'core/remote_note_list_source.dart';
import 'core/completion_repository.dart';
import 'features/topics/topics_feature.dart';
import 'features/navigation/native_resource_opener.dart';
import 'features/navigation/navigation_page.dart';
import 'core/navigation_repository.dart';
import 'core/navigation_preferences.dart';
import 'core/book_draft_vault.dart';
import 'core/local_books_repository.dart';
import 'core/documents_repository.dart';
import 'core/local_documents_repository.dart';
import 'core/labels_repository.dart';
import 'features/books/books_feature.dart';
import 'core/reading_position_vault.dart';
import 'features/tasks/tasks_page.dart';
import 'features/notes/notes_page.dart';
import 'core/speech_runtime.dart';
import 'core/scoped_speech_repository.dart';
import 'core/speech_repository.dart';
import 'core/speech_text.dart';
import 'features/speech/speech_player_page.dart';
import 'features/speech/local_speech_provider_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'BookStark spreadsheet calculation',
    ], await rootBundle.loadString('assets/licenses/spreadsheet_calc.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['fake-indexeddb 6.2.7 (in-memory complex editor storage)'],
      await rootBundle.loadString(
        'assets/complex_editors/vendor/fake-indexeddb/LICENSE',
      ),
    );
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'DejaVu Sans Mono (Docker log display)',
    ], await rootBundle.loadString('assets/licenses/dejavu_sans_mono.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'jBCrypt 0.4',
    ], await rootBundle.loadString('assets/licenses/jbcrypt.txt'));
  });
  runApp(const BookstarkApp());
}

class BookstarkApp extends StatefulWidget {
  const BookstarkApp({
    super.key,
    this.clientFactory,
    this.localDatabaseFactory,
  });
  final BookstarkClient Function(String)? clientFactory;
  final DatabaseFactory? localDatabaseFactory;
  @override
  State<BookstarkApp> createState() => _BookstarkAppState();
}

class _BookstarkAppState extends State<BookstarkApp> {
  static const _sessionKey = 'bookstark.flutter.session';
  static const _languageKey = 'bookstark.flutter.language';
  // Plugin 9.x remembers the last nonempty preferences name. Explicitly
  // select the existing default so HTML's separate vault cannot redirect
  // subsequent session/language/draft reads or logout deletion.
  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
  );
  late final _sessions = SessionVault(
    readValue: () => _storage.read(key: _sessionKey),
    writeValue: (value) => _storage.write(key: _sessionKey, value: value),
    deleteValue: () => _storage.delete(key: _sessionKey),
  );
  final _navigator = GlobalKey<NavigatorState>();
  String? _profileDestination;
  BackgroundPreference? _accountBackground;
  Uint8List? _accountBackgroundImage;
  bool _defaultEntryPending = false;
  BookstarkClient? _client;
  LocalStore? _localStore;
  ResolvedLocalStorage? _localResolved;
  Future<ResolvedLocalStorage>? _resolvedOpening;
  Object _localResolutionToken = Object();
  OwnedWritableGeneration15? _owned15;
  final _owned15Preparations = <OwnedGeneration15ActivationPreparation>{};
  final _owned15NativeWork = <Future<void>>{};
  final _owned15Routes = <Route<void>>{};
  final _owned15Inspections = <LocalLegacyInspectionLifetime>{};
  Future<(LocalStorageSession, Directory)>? _localEnvironmentFuture;
  final _localControl = NativeLocalDataControl();
  bool _localReviewRequired = false;

  Future<(LocalStorageSession, Directory)> _localEnvironment() =>
      _localEnvironmentFuture ??= () async {
        final factory = widget.localDatabaseFactory ?? databaseFactory;
        final databasePath = paths.join(
          await factory.getDatabasesPath(),
          'bookstark-flutter.db',
        );
        final support = await getApplicationSupportDirectory();
        final cache = await getTemporaryDirectory();
        await support.create(recursive: true);
        await cache.create(recursive: true);
        return (
          LocalStorageSession(
            control: _localControl,
            privateSupport: Directory(await support.resolveSymbolicLinks()),
            legacyDatabasePath: databasePath,
            factory: factory,
          ),
          Directory(await cache.resolveSymbolicLinks()),
        );
      }();

  Future<void> _enterLocalReceipt(
    LocalStorageSession session,
    LocalControlReceipt receipt,
    int generation, {
    Route<void>? featureRoute,
  }) async {
    if (!mounted ||
        !_local ||
        _showConnection ||
        generation != _spaceGeneration) {
      throw StateError('Local space changed before reentry');
    }
    await _retireComplexSourceBeforeTransition();
    final previous = _localStore;
    if (previous != null && !previous.maintenance.retired) {
      await previous.maintenance.exclusive(() async {
        try {
          await previous.close();
        } finally {
          previous.maintenance.retire();
        }
      });
    }
    setState(() {
      _advanceSpace();
      _localReviewRequired = true;
    });
    final nextGeneration = _spaceGeneration;
    await _ensureLocalResolved(receipt: receipt);
    if (!_localEpochCurrent(nextGeneration)) {
      throw StateError('Local space changed during reentry');
    }
    setState(() {
      _localReviewRequired = false;
      _homeRevision++;
    });
    // Remove the owned feature as a unit; its nested busy routes are disposed.
    if (featureRoute != null && featureRoute.isActive) {
      _navigator.currentState!.removeRoute(featureRoute);
    }
  }

  Future<void> _localConnection({Route<void>? featureRoute}) async {
    await _retireComplexSourceBeforeTransition();
    if (!mounted) return;
    setState(() {
      _showConnection = true;
      _advanceSpace();
    });
    if (featureRoute != null && featureRoute.isActive) {
      _navigator.currentState!.removeRoute(featureRoute);
    }
  }

  bool _assistantOwns(LocalStore store, int generation) =>
      mounted &&
      _local &&
      !_showConnection &&
      generation == _spaceGeneration &&
      identical(_localStore, store) &&
      !store.maintenance.retired;

  LocalAssistantDraftLedger _assistantLedger(
    LocalStore store,
    String binding,
    bool Function() owned,
  ) {
    void guard() {
      if (!owned()) throw const LocalAssistantDraftOwnerRetired();
    }

    return LocalAssistantDraftLedger(
      namespace: LocalAssistantEditorDrafts.ledgerNamespace(
        store.path,
        binding,
      ),
      isCurrent: owned,
      readValue: (key) async {
        guard();
        final value = await _storage.read(key: key);
        guard();
        return value;
      },
      writeValue: (key, value) async {
        guard();
        await _storage.write(key: key, value: value);
        await NativeRecoveryStorage.flush();
        guard();
      },
    );
  }

  Future<bool> _canForgetAssistantDraft(
    LocalStore store,
    String binding,
    bool Function() owned,
    LocalAssistantDraftRecord record,
  ) async {
    void guard() {
      if (!owned()) throw const LocalAssistantDraftOwnerRetired();
    }

    guard();
    final ledgerKey = _assistantLedger(store, binding, owned).key;
    bool opened() => LocalAssistantEditorCoordinator.isDraftOpen(
      ledgerKey: ledgerKey,
      draftId: record.id,
    );
    if (opened()) return false;
    // Called inside the ledger queue; never acquire maintenance here.
    guard();
    if (opened()) return false;
    try {
      await NativeRecoveryStorage.flush();
      guard();
      final raw = await NativeRecoveryStorage.channel.invokeMethod<Object?>(
        'localMetadata',
      );
      guard();
      if (opened() ||
          raw is! Map ||
          raw['format'] != 1 ||
          raw['overflow'] != false ||
          raw['valuesIncluded'] != false ||
          raw['secureKeys'] is! List ||
          raw['htmlKeys'] is! List) {
        return false;
      }
      final keys = raw['secureKeys'] as List;
      if (keys.length > 10000 ||
          keys.any((key) => key is! String || key.length > 16384)) {
        return false;
      }
      final identity = LocalAssistantWriteMarker(
        namespace: store.dataPaths!.draftNamespace,
        bindingId: binding,
        draftId: record.id,
        kind: record.payload.kind,
      );
      if (keys.contains(identity.key)) return false;
      final namespace = LocalAssistantEditorDrafts.editorNamespace(
        base: identity.namespace,
        binding: binding,
        draft: record.id,
        kind: record.payload.kind,
      );
      for (final key in keys.cast<String>()) {
        final prefixes = ['bookstark.draft.v1.', 'bookstark.task-draft.v1.'];
        final prefix = prefixes.where(key.startsWith).firstOrNull;
        if (prefix == null) continue;
        final decoded = jsonDecode(
          utf8.decode(base64Url.decode(key.substring(prefix.length))),
        );
        if (decoded is! List || decoded.length != 2 || decoded[0] is! String) {
          return false;
        }
        if (decoded[0] == namespace) return false;
      }
      guard();
      return !opened();
    } on LocalAssistantDraftOwnerRetired {
      rethrow;
    } catch (_) {
      guard();
      return false;
    }
  }

  Future<void> _drainAssistantDraft(
    LocalStore store,
    LocalAssistantWriteMarker identity,
  ) => LocalAssistantEditorCoordinator.retireAndDrainDraft(
    ledgerKey: _assistantLedger(store, identity.bindingId, () => true).key,
    draftId: identity.draftId,
  );

  Future<void> _openAssistantSavedResource(
    BuildContext context,
    LocalStore store,
    int generation,
    LocalAssistantCreationInspection inspection,
  ) async {
    bool owned() => _assistantOwns(store, generation);
    if (!owned() || inspection.receipt == null) {
      throw const LocalAssistantDraftOwnerRetired();
    }
    final media = LocalAttachments(
      store.dataPaths!.attachments,
      maintenance: store.maintenance,
    );
    try {
      final opener = _nativeOpener(
        local: true,
        client: null,
        memberId: 1,
        isAdmin: false,
        namespace: store.dataPaths!.draftNamespace,
        attachments: media,
      );
      final receipt = inspection.receipt!;
      if (receipt.kind == LocalAssistantDraftKind.note) {
        await opener.openLabel(
          context,
          LabelResource(
            id: receipt.resourceId,
            type: LabelResourceType.blog,
            title: '',
          ),
          resolveCollection: (id) async {
            final actual = await store.noteCollectionOf(id);
            if (!owned()) throw const LocalAssistantDraftOwnerRetired();
            if (actual == 'note') return NoteCollection.note;
            if (actual == 'article') return NoteCollection.article;
            throw const FormatException('Unknown saved resource collection');
          },
        );
      } else {
        await opener.open(context, TopicResourceType.task, receipt.resourceId);
      }
      if (owned()) setState(() => _homeRevision++);
    } finally {
      media.close();
    }
  }

  Future<void> _editLocalAssistantDraft(
    BuildContext context,
    LocalStore store,
    int generation,
    LocalAssistantWriteMarker identity, {
    int? savedResourceId,
    String? reviewedFingerprint,
    bool resumeSaved = false,
  }) async {
    bool owned() => _assistantOwns(store, generation);
    void guard() {
      if (!owned() || identity.namespace != store.dataPaths!.draftNamespace) {
        throw const LocalAssistantDraftOwnerRetired();
      }
    }

    guard();
    Future<String?> read(String key) async {
      guard();
      final value = await _storage.read(key: key);
      guard();
      return value;
    }

    Future<void> write(String key, String value) async {
      guard();
      await _storage.write(key: key, value: value);
      await NativeRecoveryStorage.flush();
      guard();
    }

    Future<void> remove(String key) async {
      guard();
      await _storage.delete(key: key);
      await NativeRecoveryStorage.flush();
      guard();
    }

    final ledger = _assistantLedger(store, identity.bindingId, owned);
    final namespace = LocalAssistantEditorDrafts.editorNamespace(
      base: identity.namespace,
      binding: identity.bindingId,
      draft: identity.draftId,
      kind: identity.kind,
    );
    final editorDrafts = LocalAssistantEditorDrafts(
      notes: DraftVault(
        namespace: namespace,
        maintenance: store.maintenance,
        readValue: read,
        writeValue: write,
        deleteValue: remove,
      ),
      tasks: TaskDraftVault(
        namespace: namespace,
        maintenance: store.maintenance,
        readValue: read,
        writeValue: write,
        deleteValue: remove,
      ),
    );
    final journal = LocalAssistantWriteJournal(
      namespace: identity.namespace,
      bindingId: identity.bindingId,
      maintenance: store.maintenance,
      readValue: read,
      writeValue: write,
      deleteValue: remove,
      isCurrent: owned,
    );
    final media = LocalAttachments(
      store.dataPaths!.attachments,
      maintenance: store.maintenance,
    );
    try {
      await LocalAssistantEditorCoordinator(
        receipts: LocalAssistantCreationReceipts(store, isCurrent: owned),
        ledger: ledger,
        journal: journal,
        editorDrafts: editorDrafts,
        notes: LocalNotesRepository(store),
        tasks: LocalTasksRepository(store),
        isCurrent: owned,
      ).open(
        draftId: identity.draftId,
        resumeCreated: resumeSaved,
        expectedResourceId: savedResourceId,
        reviewedFingerprint: reviewedFingerprint,
        english: _english,
        attachments: media,
        presentPage: (page) async {
          guard();
          await _navigator.currentState!.push<Object?>(
            MaterialPageRoute(builder: (_) => page),
          );
        },
        onSaved: (_, id) {
          if (owned()) setState(() => _homeRevision++);
        },
        onReview: (draft, marker) async {
          guard();
          await LocalAssistantRecovery.secure(
            store: store,
            isCurrent: owned,
            drainOriginatingSave: (identity) =>
                _drainAssistantDraft(store, identity),
          ).open(
            context,
            LocalRecoveryDestination(
              kind: 'ai-create',
              namespace: identity.namespace,
              title: '',
              assistant: identity,
            ),
            english: _english,
            onResumeEditor: (_, _) async {
              throw StateError('Save requires read-only review');
            },
            onResumeSavedEditor: (context, identity, id, fingerprint) =>
                _editLocalAssistantDraft(
                  context,
                  store,
                  generation,
                  identity,
                  savedResourceId: id,
                  reviewedFingerprint: fingerprint,
                  resumeSaved: true,
                ),
            onOpenResource: (context, inspection) =>
                _openAssistantSavedResource(
                  context,
                  store,
                  generation,
                  inspection,
                ),
          );
        },
      );
    } finally {
      media.close();
    }
  }

  Future<void> _openLocalBackup() async {
    if (!_local || _showConnection || _openingFeature) return;
    _openingFeature = true;
    final generation = _spaceGeneration;
    try {
      final resolved = await _ensureLocalResolved();
      if (resolved is Owned15ResolvedLocalStorage) {
        await _openOwned15Backup(resolved.owner, generation);
        return;
      }
      final store = (resolved as OrdinaryResolvedLocalStorage).store;
      final environment = await _localEnvironment();
      if (!mounted ||
          generation != _spaceGeneration ||
          !_local ||
          _showConnection) {
        return;
      }
      late MaterialPageRoute<void> route;
      route = MaterialPageRoute<void>(
        builder: (_) => LocalBackupFeature(
          beforeActivate: _retireComplexSourceBeforeTransition,
          session: environment.$1,
          privateCache: environment.$2,
          store: store,
          openOwnedLegacyMigration: () => _openOwned15Migration(generation),
          ownedLegacyActivation: (zip, selection) =>
              _owned15ActivationRoute(zip, selection, generation),
          registerLegacyChildRoute: _owned15Routes.add,
          unregisterLegacyChildRoute: _owned15Routes.remove,
          english: _english,
          isCurrentScope: () =>
              mounted &&
              _local &&
              !_showConnection &&
              generation == _spaceGeneration &&
              identical(_localStore, store),
          onEntered: (receipt) => _enterLocalReceipt(
            environment.$1,
            receipt,
            generation,
            featureRoute: route,
          ),
          onConnection: () => _localConnection(featureRoute: route),
          openDraft: (context, destination) => LocalRecoveryEditorOpener(
            store: store,
            english: _english,
            drainOriginatingAssistantSave: (identity) =>
                _drainAssistantDraft(store, identity),
            onResumeAssistantEditor: (context, identity) =>
                _editLocalAssistantDraft(context, store, generation, identity),
            onResumeSavedAssistantEditor:
                (context, identity, id, fingerprint) =>
                    _editLocalAssistantDraft(
                      context,
                      store,
                      generation,
                      identity,
                      savedResourceId: id,
                      reviewedFingerprint: fingerprint,
                      resumeSaved: true,
                    ),
            onOpenAssistantResource: (context, inspection) =>
                _openAssistantSavedResource(
                  context,
                  store,
                  generation,
                  inspection,
                ),
            isCurrentScope: () =>
                mounted &&
                _local &&
                !_showConnection &&
                generation == _spaceGeneration &&
                identical(_localStore, store),
          ).open(context, destination),
        ),
      );
      _owned15Routes.add(route);
      try {
        await _navigator.currentState!.push(route);
      } finally {
        _owned15Routes.remove(route);
      }
    } catch (_) {
      if (mounted && generation == _spaceGeneration) {
        ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
          SnackBar(
            content: Text(_english ? 'Local backup needs review' : '本地备份需要核对'),
          ),
        );
      }
    } finally {
      _openingFeature = false;
    }
  }

  Widget _coldLocalRecovery() =>
      FutureBuilder<(LocalStorageSession, Directory)>(
        future: _localEnvironment(),
        builder: (context, snapshot) {
          final environment = snapshot.data;
          if (environment == null) {
            return Scaffold(
              appBar: AppBar(
                title: Text(_english ? 'Local data needs review' : '本机数据需要核对'),
              ),
              body: Center(
                child: snapshot.hasError
                    ? TextButton(
                        onPressed: _localConnection,
                        child: Text(
                          _english ? 'Return to connection' : '返回连接页',
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            );
          }
          final generation = _spaceGeneration;
          return LocalBackupFeature(
            beforeActivate: _retireComplexSourceBeforeTransition,
            key: ValueKey('local-review-$generation'),
            session: environment.$1,
            privateCache: environment.$2,
            recoveryOnly: true,
            english: _english,
            isCurrentScope: () =>
                mounted &&
                _local &&
                !_showConnection &&
                generation == _spaceGeneration,
            onEntered: (receipt) =>
                _enterLocalReceipt(environment.$1, receipt, generation),
            onConnection: _localConnection,
            openDraft: (_, _) async =>
                throw StateError('Local writes are paused during recovery'),
          );
        },
      );
  bool _english = false,
      _initializing = true,
      _local = false,
      _showConnection = true;
  String _server = '';
  int _homeRevision = 0;
  HomeDashboardRepository? _homeRepositoryCache;
  int _homeRepositoryGeneration = -1;
  LocalHomeDashboardRepository? _homeLocalRepository;
  int _homeLocalGeneration = -1;
  bool _openingFeature = false;
  String? _articleHandoff;
  int? _articleHandoffGeneration;
  int _spaceGeneration = 0;
  AdminAssetsScope? _homeAssetScope;
  LocalModelSettingsController? _localModelController;
  LocalAssistantRepository? _localAssistant;
  bool _openingLocalModel = false;
  final _complexSourceOwner = ComplexSourceIoOwner();
  final _protectedComplexOwners = <ProtectedComplexOwner>{};
  final _taskCreationSessions = <String, TaskCreationSession>{};
  final _localTaskCreationSessions = <String, LocalTaskCreationSession>{};
  LocalTaskCreationSession _localTaskCreationSession({
    required LocalStore store,
    required String namespace,
    required bool Function() isCurrent,
  }) {
    final key = jsonEncode([namespace, _spaceGeneration]);
    final old = _localTaskCreationSessions[key];
    if (old != null && old.current) return old;
    final generation = _spaceGeneration;
    bool current() =>
        mounted &&
        _local &&
        identical(store, _localStore) &&
        !store.maintenance.retired &&
        isCurrent() &&
        generation == _spaceGeneration &&
        !_complexSourceSwitching;
    if (!current()) throw StateError('Local task creation owner retired');
    final owner = LocalTaskCreationSession(
      store: store,
      namespace: namespace,
      isCurrent: current,
      read: (key) => _storage.read(key: key),
      write: (key, value) => _storage.write(key: key, value: value),
      remove: (key) => _storage.delete(key: key),
      flush: NativeRecoveryStorage.flush,
      draftVault: TaskDraftVault(
        namespace: namespace,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
      ),
      onRetired: (owner) {
        _protectedComplexOwners.remove(owner);
        if (identical(_localTaskCreationSessions[key], owner))
          _localTaskCreationSessions.remove(key);
      },
    );
    _localTaskCreationSessions[key] = owner;
    _protectedComplexOwners.add(owner);
    return owner;
  }

  TasksRepository _recoverableLocalTasks({
    required LocalStore store,
    required String namespace,
    required bool Function() isCurrent,
  }) => _localTaskCreationSession(
    store: store,
    namespace: namespace,
    isCurrent: isCurrent,
  ).wrap(LocalTasksRepository(store));
  Future<void> _recoverLocalTaskCreation({
    required LocalStore store,
    required String namespace,
    required bool Function() isCurrent,
  }) async {
    if (!mounted || !isCurrent() || _complexSourceSwitching) return;
    final owner = _localTaskCreationSession(
      store: store,
      namespace: namespace,
      isCurrent: isCurrent,
    );
    try {
      final retained = await owner.hasRetained();
      if (!mounted || !owner.current) return;
      if (!retained) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '没有本地待办创建恢复记录 / No local task creation recovery record',
            ),
          ),
        );
        return;
      }
      final controller = await owner.open();
      if (!mounted || !owner.current) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) => TaskCreationRecoveryPage(
            controller: controller,
            local: true,
            serverLabel: _english ? 'This local space' : '当前本地空间',
            initiatorId: 0,
            english: _english,
            onEndMissing: () async {
              await owner.endMissing();
              if (ctx.mounted && owner.current) Navigator.pop(ctx);
            },
          ),
        ),
      );
      if (!mounted || !owner.current) return;
      if (controller.endedDurably && identical(owner.controller, controller))
        await owner.clearEndedSlot();
    } catch (_) {
      if (mounted && owner.current)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '本地创建记录尚未确认 / Local creation record remains unconfirmed',
            ),
          ),
        );
    }
  }

  TaskCreationSession _taskCreationSession({
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) {
    final key = jsonEncode([
      namespace,
      memberId,
      _spaceGeneration,
      client.sessionRevision,
    ]);
    final old = _taskCreationSessions[key];
    if (old != null && old.current) return old;
    final capturedGeneration = _spaceGeneration;
    final capturedRevision = client.sessionRevision;
    bool current() =>
        mounted &&
        isCurrent() &&
        !_complexSourceSwitching &&
        capturedGeneration == _spaceGeneration &&
        identical(client, _client) &&
        capturedRevision == client.sessionRevision;
    if (!current()) throw StateError('Task creation owner retired');
    final session = TaskCreationSession(
      client: client,
      memberId: memberId,
      namespace: namespace,
      isCurrent: current,
      read: (key) => _storage.read(key: key),
      write: (key, value) => _storage.write(key: key, value: value),
      remove: (key) => _storage.delete(key: key),
      flush: NativeRecoveryStorage.flush,
      draftVault: TaskDraftVault(
        namespace: namespace,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
      ),
      onRetired: (owner) {
        _protectedComplexOwners.remove(owner);
        if (identical(_taskCreationSessions[key], owner))
          _taskCreationSessions.remove(key);
      },
    );
    _taskCreationSessions[key] = session;
    _protectedComplexOwners.add(session);
    return session;
  }

  TasksRepository _recoverableTasks({
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) => _taskCreationSession(
    client: client,
    memberId: memberId,
    namespace: namespace,
    isCurrent: isCurrent,
  ).wrap(RemoteTasksRepository(client, isCurrent: isCurrent));
  Future<void> _recoverTaskCreation({
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) async {
    final owner = _taskCreationSession(
      client: client,
      memberId: memberId,
      namespace: namespace,
      isCurrent: isCurrent,
    );
    try {
      final retained = await owner.hasRetained();
      if (!mounted || !owner.current) return;
      if (!retained) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('没有待办创建恢复记录 / No task creation recovery record'),
          ),
        );
        return;
      }
      final controller = await owner.open();
      if (!mounted || !owner.current) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (ctx) => TaskCreationRecoveryPage(
            controller: controller,
            serverLabel: client.baseUri.toString(),
            initiatorId: memberId,
            english: _english,
            onEndMissing: () async {
              await owner.endMissing();
              if (ctx.mounted && owner.current) Navigator.pop(ctx);
            },
          ),
        ),
      );
      if (!mounted || !owner.current) return;
      if (controller.endedDurably && identical(owner.controller, controller))
        await owner.clearEndedSlot();
    } catch (_) {
      if (mounted && owner.current)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('恢复记录尚未确认 / Recovery record remains unconfirmed'),
          ),
        );
    }
  }

  final _imageLibraryOwners = <ImageLibraryOwner>{};
  ImageLibraryOwner _newImageLibraryOwner(bool Function() isCurrent) {
    if (_complexSourceSwitching || !isCurrent()) {
      throw StateError('Image space retired');
    }
    late ImageLibraryOwner owner;
    owner = ImageLibraryOwner(
      isCurrentScope: () => !_complexSourceSwitching && isCurrent(),
      onDrained: () => _imageLibraryOwners.remove(owner),
    );
    _imageLibraryOwners.add(owner);
    return owner;
  }

  final _ownedDocumentReaders = <OwnedBoundedDocumentsReader>{};
  bool _complexSourceSwitching = false;
  Future<void> _retireComplexSourceBeforeTransition() async {
    try {
      _complexSourceSwitching = true;
      while (_owned15NativeWork.isNotEmpty) {
        await Future.wait(_owned15NativeWork.toList());
      }
      // Cancel any resolver before it can publish a late RW capability. Await
      // its real RO/RW handles before changing pointer/space, not its UI future.
      _localResolutionToken = Object();
      final opening = _resolvedOpening;
      if (opening != null) {
        try {
          await opening;
        } catch (_) {
          /* cancellation is expected */
        }
      }
      await _retireRuntimeBeforeTransition();
      for (final preparation in _owned15Preparations.toList()) {
        await preparation.retire();
        _owned15Preparations.remove(preparation);
      }
      for (final inspection in _owned15Inspections.toList()) {
        await inspection.retire();
        _owned15Inspections.remove(inspection);
      }
      for (final route in _owned15Routes.toList().reversed) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
      _owned15Routes.clear();
      final owned = _owned15;
      if (owned != null) await owned.retire();
    } catch (_) {
      if (mounted && _local) setState(() => _localReviewRequired = true);
      rethrow;
    }
  }

  Future<void> _retireRuntimeBeforeTransition() async {
    _complexSourceSwitching = true;
    await retireSpeechBeforeTransition(
      owner: _speechOwner,
      localOwner: _localSpeechGrant?.owner,
      close: _closeSpeech,
    );
    // Revoke the shared native browser/cookie lease BEFORE any identity change.
    // Close failure retains the switching barrier and must be explicitly retried.
    await Future.wait(
      _protectedComplexOwners.toList().map((owner) => owner.retire()),
    );
    await HtmlBrowserSession.closeActive();
    // Retire synchronously before any identity mutation, then drain actual
    // repository work (including local discovery/write and thumbnail reads).
    // Already-started work settles in the old space BEFORE _advanceSpace.
    await Future.wait(
      _imageLibraryOwners.toList().map((owner) => owner.retireAndDrain()),
    );
    for (final reader in _ownedDocumentReaders) {
      reader.retire();
    }
    _ownedDocumentReaders.clear();
    await _complexSourceOwner.beforeTransition();
  }

  Future<void> _ensureLocalComplexSource(
    LocalStore store,
    int generation,
  ) async {
    if (_complexSourceSwitching) return;
    await _complexSourceOwner.ensure(
      identity: jsonEncode([
        'local',
        store.dataPaths!.draftNamespace,
        generation,
      ]),
      isCurrent: () =>
          !_complexSourceSwitching && _assistantOwns(store, generation),
    );
  }

  Future<void> _ensureAccountComplexSource(
    BookstarkClient client,
    int generation,
  ) async {
    final revision = client.sessionRevision;
    final token = client.exportSession()['token'];
    await _complexSourceOwner.ensure(
      identity: jsonEncode([
        'account',
        client.baseUri.toString(),
        generation,
        revision,
      ]),
      isCurrent: () =>
          mounted &&
          !_complexSourceSwitching &&
          generation == _spaceGeneration &&
          client.sessionRevision == revision &&
          client.exportSession()['token'] == token,
    );
  }

  BoundedDocumentsReader _documentReader({
    required bool local,
    required BookstarkClient? client,
    required bool Function() isCurrent,
  }) {
    if (local) return _homeDocuments(_localStore!);
    final reader = OwnedBoundedDocumentsReader(
      client: client!,
      isCurrent: isCurrent,
    );
    _ownedDocumentReaders.add(reader);
    return reader;
  }

  Future<void> Function(BuildContext, DocumentExcerptRequest)
  _documentExcerptAction({
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required String namespace,
    required AttachmentRepository attachments,
    required bool Function() isCurrent,
  }) {
    final sourceStore = _localStore;
    return (context, request) async {
      bool current() =>
          context.mounted &&
          isCurrent() &&
          request.isCurrentSource() &&
          (local
              ? identical(sourceStore, _localStore) &&
                    sourceStore?.maintenance.retired == false
              : identical(client, _client));
      if (!current()) return;
      final legacyExcerpt = _nativeDrafts(
        jsonEncode([namespace, 'excerpt', request.origin.documentId]),
      );
      if (local) {
        await openLocalBookExcerpt(
          context,
          repository: _homeNotes(sourceStore!),
          request: request,
          isCurrent: current,
          drafts: legacyExcerpt,
          attachments: attachments,
          english: _english,
        );
        return;
      }
      await openRemoteBookExcerpt(
        context,
        client: client!,
        memberId: memberId,
        namespace: namespace,
        request: request,
        repository: RemoteNotesRepository(client),
        // SAME ordinary note slot; both old draft locations must be inspected.
        drafts: _nativeDrafts(namespace),
        additionalLegacyDrafts: [legacyExcerpt],
        attachments: attachments,
        english: _english,
        readValue: (key) => _storage.read(key: key),
        writeValue: _writeNativeEditorDraft,
        deleteValue: _deleteNativeEditorDraft,
        flush: NativeRecoveryStorage.flush,
        isCurrent: current,
        onSaved: (_) {
          if (current()) setState(() => _homeRevision++);
        },
      );
    };
  }

  Future<String?> Function(TypedDocumentRead) _documentReadingFingerprint({
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) {
    final store = _localStore;
    return (read) async {
      if (!isCurrent()) throw StateError('Reading owner retired');
      final kind = ComplexEditorKind.parse(read.item.type);
      if (kind == ComplexEditorKind.markdown) return null;
      if (local) {
        if (store == null) throw StateError('Local reading store retired');
        final repository = LocalBookDocumentComplexStore(
          store,
          bookId: read.item.bookId,
          kind: kind,
          isCurrent: isCurrent,
        );
        try {
          final actual = await repository.read(read.item.id);
          if (!isCurrent() ||
              actual.document.source != read.source ||
              actual.title != read.item.name) {
            throw StateError('Document changed during reading preparation');
          }
          return actual.resourceFingerprint;
        } finally {
          repository.dispose();
        }
      }
      final repository = RemoteOwnedComplexStore(
        client: client!,
        memberId: memberId,
        resourceId: read.item.id,
        bookId: read.item.bookId,
        kind: kind,
        note: false,
        recoveryNamespace: namespace,
        isCurrent: isCurrent,
      );
      try {
        final actual = await repository.read(read.item.id);
        if (!isCurrent() ||
            actual.document.source != read.source ||
            actual.title != read.item.name) {
          throw StateError('Document changed during reading preparation');
        }
        return actual.resourceFingerprint;
      } finally {
        repository.dispose();
      }
    };
  }

  Future<void> Function(BuildContext, int, DocumentItem)
  _documentComplexWriter({
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) {
    final ioScope = _complexSourceOwner.current;
    return (context, bookId, document) async {
      if (!isCurrent() || !context.mounted) return;
      if (local) {
        await _openOwnedBookComplex(context, bookId, document);
        return;
      }
      final kind = ComplexEditorKind.parse(document.type);
      if (kind == ComplexEditorKind.markdown) return;
      await openRemoteOwnedComplex(
        context,
        client: client!,
        memberId: memberId,
        resourceId: document.id,
        bookId: bookId,
        note: false,
        kind: kind,
        recoveryNamespace: namespace,
        isCurrentScope: isCurrent,
        sourceIoScope: ioScope,
        english: _english,
      );
    };
  }

  TaskEditorActionsFactory _taskEditorActionsFactory({
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) {
    final rootCurrent = isCurrent;
    final revision = client.sessionRevision;
    return ({required isCurrent, required abortTrigger}) async {
      bool current() =>
          rootCurrent() && isCurrent() && client.sessionRevision == revision;
      final service = await TaskEditorRemoteActions.create(
        client: client,
        memberId: memberId,
        scope: namespace,
        isCurrent: current,
        abortTrigger: abortTrigger,
      );
      if (!current()) {
        service.retire();
        throw StateError('Task owner retired');
      }
      return TaskEditorOwnedActions(
        bindings: service.bindings,
        retire: service.retire,
      );
    };
  }

  OpenOwnedComplexNote _ownedComplexNoteWriter({
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required bool Function() isCurrent,
  }) {
    final revision = client.sessionRevision;
    final ioScope = _complexSourceOwner.current;
    return (
      context, {
      required id,
      required collection,
      required kind,
      required isCurrentScope,
    }) async {
      bool current() =>
          isCurrent() && isCurrentScope() && client.sessionRevision == revision;
      if (!context.mounted || !current()) return false;
      if (id <= 0 ||
          collection != NoteCollection.note ||
          !{
            ComplexEditorKind.spreadsheet,
            ComplexEditorKind.drawing,
            ComplexEditorKind.mindmap,
            ComplexEditorKind.richdoc,
            ComplexEditorKind.presentation,
          }.contains(kind)) {
        throw const FormatException('Invalid owned complex note identity');
      }
      return openOwnedComplexWithProtectedRecovery(
        context,
        client: client,
        memberId: memberId,
        resourceId: id,
        kind: kind,
        recoveryNamespace: namespace,
        isCurrentScope: () => !_complexSourceSwitching && current(),
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
        flush: NativeRecoveryStorage.flush,
        registerOwner: (owner) {
          if (_complexSourceSwitching || !current()) {
            unawaited(owner.retire());
            throw StateError('Protected owner retired');
          }
          _protectedComplexOwners.add(owner);
        },
        unregisterOwner: (owner) => _protectedComplexOwners.remove(owner),
        sourceIoScope: ioScope,
        english: _english,
      );
    };
  }

  Future<void> _openOwnedBookComplex(
    BuildContext context,
    int bookId,
    DocumentItem document,
  ) async {
    final store = _localStore;
    final generation = _spaceGeneration;
    if (store == null || !_assistantOwns(store, generation)) return;
    final kind = ComplexEditorKind.parse(document.type);
    if (kind == ComplexEditorKind.markdown) return;
    await _ensureLocalComplexSource(store, generation);
    if (!_assistantOwns(store, generation) || !context.mounted) return;
    final scope = _complexSourceOwner.current;
    await openLocalBookDocumentComplex(
      context,
      store: store,
      bookId: bookId,
      documentId: document.id,
      kind: kind,
      english: _english,
      sourceIoScope: scope,
      isCurrentScope: () => _assistantOwns(store, generation),
    );
  }

  int _advanceSpace() {
    if (_owned15?.current == true ||
        _owned15Preparations.isNotEmpty ||
        _owned15NativeWork.isNotEmpty ||
        _owned15Inspections.isNotEmpty) {
      throw StateError('Owned15 retirement not drained');
    }
    _owned15 = null;
    _localResolved = null;
    _resolvedOpening = null;
    _localResolutionToken = Object();
    if (_protectedComplexOwners.isNotEmpty) {
      throw StateError('Protected retirement not drained');
    }
    if (_imageLibraryOwners.isNotEmpty) {
      throw StateError('Image retirement not drained');
    }
    _speechOwner?.retire();
    _localSpeechGrant?.owner.retire();
    _complexSourceOwner.assertTransitionAllowed();
    _complexSourceSwitching = false;
    _localAssistant?.close();
    _localAssistant = null;
    _localModelController?.dispose();
    _localModelController = null;
    _homeAssetScope?.close();
    _spaceGeneration += 1;
    return _spaceGeneration;
  }

  bool _choosingSpeechProvider = false;
  int _localSpeechRequest = 0;
  LocalSpeechGrant? _localSpeechGrant;
  SpeechOwner? _speechOwner;
  Future<SpeechRuntime>? _speech;
  BookstarkClient? _speechClient;
  StreamSubscription<bool>? _notification;
  bool _speechPageOpen = false;
  BookstarkClient _makeClient(String server) =>
      widget.clientFactory?.call(server) ?? BookstarkClient(server);
  AppStrings get strings => AppStrings(english: _english);
  @override
  void initState() {
    super.initState();
    _restore();
    _notification = SpeechRuntime.notificationClicks.listen((clicked) {
      if (clicked) unawaited(_openCurrentSpeech());
    });
  }

  Future<void> _openCurrentSpeech() async {
    final future = _speech;
    if (future == null ||
        _showConnection ||
        _speechPageOpen ||
        _complexSourceSwitching) {
      return;
    }
    try {
      final runtime = await future;
      if (!mounted || !identical(future, _speech) || _showConnection) return;
      await _speechPage(runtime);
    } catch (_) {
      /* A failed initialization has already been reported in-page. */
    }
  }

  Future<void> _speechPage(
    SpeechRuntime runtime, {
    SpeechRequest? request,
  }) async {
    if (!mounted || _speechPageOpen) return;
    _speechPageOpen = true;
    try {
      await _navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => SpeechPlayerPage(
            controller: runtime.controller,
            request: request,
            english: _english,
            onStop: _localSpeechGrant == null
                ? null
                : () async {
                    await _closeSpeech();
                    if (mounted && _navigator.currentState!.canPop()) {
                      _navigator.currentState!.pop();
                    }
                  },
          ),
        ),
      );
    } finally {
      _speechPageOpen = false;
    }
  }

  Future<void> _openSpeech(
    String markdown,
    String title,
    String context, {
    LocalSpeechSelection? selection,
  }) async {
    if (_complexSourceSwitching) return;
    if (selection != null &&
        (!selection.current || !await selection.verifyFreshBinding())) {
      return;
    }
    if (_complexSourceSwitching) return;
    final readable = selection?.text ?? markdown;
    if (_local && !_showConnection && !_speechPageOpen) {
      if (_choosingSpeechProvider) return;
      final request = ++_localSpeechRequest;
      final generation = _spaceGeneration;
      bool current() =>
          mounted &&
          !_complexSourceSwitching &&
          _local &&
          !_showConnection &&
          generation == _spaceGeneration &&
          request == _localSpeechRequest &&
          (selection?.current ?? true);
      speechSegments(readable);
      LocalSpeechGrant? grant;
      _choosingSpeechProvider = true;
      try {
        await _closeSpeech();
        if (!current()) return;
        grant = await _navigator.currentState!.push<LocalSpeechGrant>(
          MaterialPageRoute(
            builder: (_) => LocalSpeechProviderPage(
              text: markdown,
              title: title,
              isCurrentScope: current,
              selection: selection,
              english: _english,
            ),
          ),
        );
      } finally {
        _choosingSpeechProvider = false;
      }
      if (grant == null) return;
      if (!current()) {
        await grant.close();
        return;
      }
      await _closeSpeech();
      if (!current()) {
        await grant.close();
        return;
      }
      _localSpeechGrant = grant;
      _speechOwner = grant.owner;
      try {
        final future = grant.start(
          grant.authorizedText,
          title: title,
          context: context,
        );
        _speech = future;
        final runtime = await future;
        if (!current()) {
          await _closeSpeech();
          return;
        }
        await _speechPage(runtime);
      } catch (_) {
        await _closeSpeech();
        rethrow;
      }
      return;
    }
    if (_local || _showConnection || _client == null || _speechPageOpen) return;
    speechSegments(readable); // Validate before replacing an existing reading.
    final generation = _spaceGeneration, client = _client!;
    if (selection != null || _speechClient != client) await _closeSpeech();
    if (!mounted || generation != _spaceGeneration) return;
    _speechClient = client;
    final owner = _speechOwner ??= SpeechOwner(
      isCurrent: () =>
          mounted &&
          !_complexSourceSwitching &&
          generation == _spaceGeneration &&
          !_showConnection &&
          !_local &&
          identical(_client, client) &&
          (selection?.current ?? true),
    );
    final future = _speech ??= SpeechRuntime.create(
      selection == null
          ? RemoteSpeechRepository(client)
          : SelectedSpeechRepository(
              RemoteSpeechRepository(client),
              isCurrent: () => owner.current && selection.current,
              verifyFresh: selection.verifyFreshBinding,
            ),
      owner: owner,
    );
    final SpeechRuntime runtime;
    try {
      runtime = await future;
    } catch (_) {
      if (identical(_speech, future)) {
        _speech = null;
        _speechClient = null;
      }
      rethrow;
    }
    if (!mounted ||
        generation != _spaceGeneration ||
        _showConnection ||
        _client != client) {
      await runtime.close();
      return;
    }
    await _speechPage(
      runtime,
      request: SpeechRequest(
        readable,
        title: title,
        context: context,
        isCurrent: () =>
            mounted &&
            !_complexSourceSwitching &&
            generation == _spaceGeneration &&
            identical(_client, client) &&
            !_local &&
            !_showConnection &&
            (selection?.current ?? true),
        verifyBeforeStart: selection?.verifyFreshBinding,
      ),
    );
  }

  Future<void> _closeSpeech() async {
    final localGrant = _localSpeechGrant;
    _localSpeechGrant = null;
    localGrant?.owner.retire();
    if (localGrant != null) await localGrant.close();
    final owner = _speechOwner;
    _speechOwner = null;
    owner?.retire();
    final future = _speech;
    if (future == null) return;
    try {
      await (await future).close();
    } finally {
      if (identical(_speech, future)) {
        _speech = null;
        _speechClient = null;
      }
    }
  }

  Future<void> _restore() async {
    try {
      final language = await _storage.read(key: _languageKey);
      if (language == 'en' || language == 'zh') {
        _english = language == 'en';
      }
    } catch (_) {}
    try {
      final saved = await _sessions.read();
      if (saved != null) {
        final json = jsonDecode(saved);
        if (json case {
          'server': final String server,
          'cookies': final Map cookies,
        }) {
          final client = _makeClient(server)..language = _english ? 'en' : 'zh';
          client.restoreSession({
            for (final entry in cookies.entries)
              if (entry.key is String && entry.value is String)
                entry.key as String: entry.value as String,
          });
          if (client.exportSession().containsKey('token')) {
            await _ensureAccountComplexSource(client, _spaceGeneration);
            _server = server;
            _client = client;
            _showConnection = false;
            _defaultEntryPending = true;
          } else {
            client.close();
          }
        }
      }
    } catch (_) {
      // A corrupt or unavailable platform session never bypasses sign-in.
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _login(String server, String account, String password) async {
    await _retireComplexSourceBeforeTransition();
    if (!mounted) return;
    final attempt = _advanceSpace();
    _accountBackground = null;
    _accountBackgroundImage = null;
    final client = _makeClient(server)..language = _english ? 'en' : 'zh';
    try {
      await client.login(account, password);
      if (!client.exportSession().containsKey('token')) {
        throw const ApiFailure(401, '服务器未建立登录会话');
      }
      if (!mounted || attempt != _spaceGeneration) {
        client.close();
        return;
      }
      await _sessions.save(
        jsonEncode({
          'server': client.baseUri.toString(),
          'cookies': client.exportSession(),
        }),
        stillCurrent: () => mounted && attempt == _spaceGeneration,
      );
      if (!mounted || attempt != _spaceGeneration) {
        client.close();
        return;
      }
      await _ensureAccountComplexSource(client, attempt);
      await _closeSpeech();
      _client?.close();
      setState(() {
        _client = client;
        _server = server;
        _local = false;
        _showConnection = false;
        _defaultEntryPending = true;
      });
    } catch (_) {
      client.close();
      rethrow;
    }
  }

  bool _localEpochCurrent(int generation) =>
      mounted && _local && !_showConnection && generation == _spaceGeneration;

  Future<ResolvedLocalStorage> _ensureLocalResolved({
    LocalControlReceipt? receipt,
  }) async {
    final cached = _localResolved;
    if (cached != null && receipt == null) return cached;
    final opening = _resolvedOpening;
    if (opening != null && receipt == null) return opening;
    final generation = _spaceGeneration, token = _localResolutionToken;
    bool current() =>
        _localEpochCurrent(generation) &&
        identical(token, _localResolutionToken);
    final future = () async {
      final environment = await _localEnvironment();
      if (!current()) throw StateError('Local resolver retired');
      final workspace = Directory(
        paths.join(
          environment.$1.privateSupport.path,
          'owned15-active-verification',
        ),
      );
      await workspace.create(recursive: true);
      final resolved = await ResolvedLocalStorage.open(
        session: environment.$1,
        verificationWorkspace: workspace,
        isCurrentScope: current,
        sourceReentry: receipt,
      );
      if (!current()) {
        await resolved.retire();
        throw StateError('Local resolution changed');
      }
      if (resolved is OrdinaryResolvedLocalStorage) {
        final old = _localStore;
        if (old != null &&
            !identical(old, resolved.store) &&
            !old.maintenance.retired) {
          await old.close();
        }
        _localStore = resolved.store;
        _owned15 = null;
        await _ensureLocalComplexSource(resolved.store, generation);
      } else if (resolved is Owned15ResolvedLocalStorage) {
        _localStore = null;
        _owned15 = resolved.owner;
      }
      if (!current()) {
        await resolved.retire();
        throw StateError('Local resolution retired');
      }
      return _localResolved = resolved;
    }();
    _resolvedOpening = future;
    try {
      return await future;
    } catch (_) {
      if (current()) setState(() => _localReviewRequired = true);
      rethrow;
    } finally {
      if (identical(_resolvedOpening, future)) _resolvedOpening = null;
    }
  }

  Future<LocalRecoverySummary> _owned15Inventory(
    OwnedWritableGeneration15 owner,
    int generation,
  ) async {
    if (!_localEpochCurrent(generation) ||
        !identical(_owned15, owner) ||
        !owner.current) {
      throw StateError('Owned15 inventory retired');
    }
    final namespaces = await localRecoveryNamespaces(owner.generation);
    final summary = await LocalRecoveryInventory(
      maintenance: LocalDataMaintenance(),
      localNamespaces: namespaces,
    ).read();
    if (!_localEpochCurrent(generation) ||
        !identical(_owned15, owner) ||
        !owner.current) {
      throw StateError('Owned15 inventory changed');
    }
    return summary;
  }

  Future<void> _openOwned15Creation(
    OwnedWritableGeneration15 owner,
    int generation, {
    bool recoverOnly = false,
  }) async {
    bool current() =>
        _localEpochCurrent(generation) &&
        identical(_owned15, owner) &&
        owner.current &&
        !_complexSourceSwitching;
    if (!current()) return;
    final context = _navigator.currentState!.context;
    if (!context.mounted) return;
    await openOwned15Creation(
      context,
      database: owner,
      recoverOnly: recoverOnly,
      english: _english,
      isCurrentScope: current,
      checkRecoveryMetadata: () async {
        final summary = await _owned15Inventory(owner, generation);
        if (summary.unknown != 0 ||
            summary.overflow ||
            summary.activeTransfers != 0) {
          throw PendingLocalRecovery(summary);
        }
      },
      openColdRecovery: () =>
          _openOwned15Creation(owner, generation, recoverOnly: true),
      readValue: (key) => _storage.read(key: key),
      writeValue: (key, value) => _storage.write(key: key, value: value),
      deleteValue: (key) => _storage.delete(key: key),
      flush: NativeRecoveryStorage.flush,
      registerOwner: (editor) {
        if (!current()) {
          unawaited(editor.retire().catchError((Object _) {}));
          throw StateError('Owned15 creator retired');
        }
        _protectedComplexOwners.add(editor);
      },
      unregisterOwner: (editor) => _protectedComplexOwners.remove(editor),
    );
    if (current()) setState(() => _homeRevision++);
  }

  Future<void> _openOwned15Resource(
    OwnedWritableGeneration15 owner,
    int generation,
    GenerationContentMetadata metadata,
  ) async {
    bool current() =>
        _localEpochCurrent(generation) &&
        identical(_owned15, owner) &&
        owner.current &&
        !_complexSourceSwitching;
    if (!current()) return;
    final recovery = await _owned15Inventory(owner, generation);
    if (!current()) return;
    if (recovery.unknown != 0 ||
        recovery.overflow ||
        recovery.activeTransfers != 0) {
      throw PendingLocalRecovery(recovery);
    }
    final creationOwner = Owned15SaveJournal.ownerTagForGeneration(
      owner.generation.draftNamespace,
    );
    if (recovery.references.any(
      (reference) =>
          reference.kind == 'owned15-create' &&
          reference.namespace == creationOwner,
    )) {
      await _openOwned15Creation(owner, generation, recoverOnly: true);
      return;
    }
    await _complexSourceOwner.ensure(
      identity: jsonEncode(['owned15', owner.pointer.encode(), generation]),
      isCurrent: current,
    );
    final scope = _complexSourceOwner.current;
    if (!current() || scope == null) {
      throw StateError('Owned15 source IO unavailable');
    }
    final context = _navigator.currentState!.context;
    if (!context.mounted) return;
    await openOwned15Resource(
      context,
      database: owner,
      metadata: metadata,
      sourceIoScope: scope,
      isCurrentScope: current,
      english: _english,
      checkRecoveryMetadata: () async {
        final summary = await _owned15Inventory(owner, generation);
        // Current opaque marker is intentionally allowed into readonly review.
        // Malformed keys/overflow/active handoff can never authorize entry.
        if (summary.unknown != 0 ||
            summary.overflow ||
            summary.activeTransfers != 0) {
          throw PendingLocalRecovery(summary);
        }
      },
      createJournal: (collection, id, ownedCurrent) => Owned15SaveJournal(
        draftNamespace: owner.generation.draftNamespace,
        collection: collection,
        resourceId: id,
        isCurrent: ownedCurrent,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
        flush: NativeRecoveryStorage.flush,
      ),
      registerOwner: (editor) {
        if (!current()) {
          unawaited(editor.retire());
          throw StateError('Owned15 editor retired');
        }
        _protectedComplexOwners.add(editor);
      },
      unregisterOwner: (editor) => _protectedComplexOwners.remove(editor),
    );
  }

  Future<void> _openOwned15Pending(
    OwnedWritableGeneration15 owner,
    int generation,
  ) async {
    if (!_localEpochCurrent(generation) || !owner.current) return;
    final cancellation = AttachmentCancellation();
    try {
      await _navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => LocalPendingRecoveryPage(
            english: _english,
            load: () => loadOwned15Pending(
              owner: owner,
              readInventory: () => _owned15Inventory(owner, generation),
              isCurrent: () =>
                  _localEpochCurrent(generation) && identical(_owned15, owner),
              openResource: (metadata) =>
                  _openOwned15Resource(owner, generation, metadata),
              cancellation: cancellation,
              openCreationRecovery: () =>
                  _openOwned15Creation(owner, generation, recoverOnly: true),
              english: _english,
            ),
          ),
        ),
      );
    } finally {
      cancellation.cancel();
    }
  }

  Future<LocalControlReceipt> _runOwned15Native(
    Future<LocalControlReceipt> Function() operation,
  ) async {
    final generation = _spaceGeneration;
    final future = Future<LocalControlReceipt>.sync(operation);
    final settled = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _owned15NativeWork.add(settled);
    try {
      return await future;
    } finally {
      _owned15NativeWork.remove(settled);
      if (_localEpochCurrent(generation) &&
          (_complexSourceSwitching ||
              _owned15?.current == false ||
              _localStore?.maintenance.retired == true)) {
        setState(() => _localReviewRequired = true);
      }
    }
  }

  Future<void> _retireOwned15Preparation(
    OwnedGeneration15ActivationPreparation preparation,
  ) async {
    await preparation.retire();
    _owned15Preparations.remove(preparation);
  }

  Future<void> _showOwned15ActivationReview(int generation) async {
    if (!_localEpochCurrent(generation)) return;
    // No acknowledgement here. Native intent/ready result is reviewed in the
    // existing real recovery page; all source-route callbacks become hidden.
    setState(() => _localReviewRequired = true);
    for (final route in _owned15Routes.toList().reversed) {
      final navigator = route.navigator;
      if (route.isActive && navigator != null) navigator.removeRoute(route);
    }
    _owned15Routes.clear();
  }

  Future<OwnedLegacyActivationRoute> _owned15ActivationRoute(
    LegacyZipStage zip,
    LegacyFormatSelection selection,
    int generation,
  ) async {
    if (!_localEpochCurrent(generation)) {
      throw StateError('Legacy source owner changed');
    }
    final environment = await _localEnvironment();
    final workspace = Directory(
      paths.join(environment.$2.path, 'owned15-source-preparation'),
    );
    await workspace.create(recursive: true);
    if (!_localEpochCurrent(generation)) {
      throw StateError('Legacy preparation retired');
    }
    final preparation = OwnedGeneration15ActivationPreparation(
      zip: zip,
      selection: selection,
      session: environment.$1,
      privateCache: environment.$2,
      workspace: workspace,
      isCurrentScope: () => _localEpochCurrent(generation),
    );
    _owned15Preparations.add(preparation);
    final items = selection.source.items;
    return OwnedLegacyActivationRoute(
      retire: () => _retireOwned15Preparation(preparation),
      page: OwnedGeneration15ActivationPage(
        summary: Owned15ActivationSummary(
          notes: items.where((item) => item.collection == 'note').length,
          articles: items.where((item) => item.collection == 'article').length,
          protectedItems: items.where((item) => item.isProtected).length,
          attachments: zip.files.values
              .where((file) => file.logicalName.startsWith('uploads/'))
              .length,
        ),
        english: _english,
        isCurrentScope: () => _localEpochCurrent(generation),
        prepareCandidate: preparation.prepare,
        activate: (candidate) async {
          await _runOwned15Native(
            () => _activateOwned15Candidate(candidate, generation),
          );
        },
        onCancel: () => _retireOwned15Preparation(preparation),
        onReview: () => _showOwned15ActivationReview(generation),
      ),
    );
  }

  Future<LocalControlReceipt> _activateOwned15Candidate(
    LocalBackupCandidate candidate,
    int generation,
  ) async {
    if (!_localEpochCurrent(generation)) {
      throw StateError('Activation owner changed');
    }
    final resolved = await _ensureLocalResolved();
    final environment = await _localEnvironment();
    if (!_localEpochCurrent(generation)) {
      throw StateError('Activation scope changed');
    }
    if (resolved is Owned15ResolvedLocalStorage) {
      final owner = resolved.owner;
      return OwnedGeneration15RestoreCoordinator(
        owner: owner,
        exporter: OwnedGeneration15BackupExporter(
          owner: owner,
          factory: environment.$1.factory ?? databaseFactory,
          workspace: Directory(
            paths.join(environment.$2.path, 'owned15-retained-export'),
          ),
          checkPendingRecovery: () async {
            (await _owned15Inventory(owner, generation)).requireClear();
          },
        ),
        control: _localControl,
        beforeSeal: _retireRuntimeBeforeTransition,
      ).apply(candidate);
    }
    final store = (resolved as OrdinaryResolvedLocalStorage).store;
    await _retireRuntimeBeforeTransition();
    final inventory = LocalRecoveryInventory(
      maintenance: store.maintenance,
      localNamespaces: await localRecoveryNamespaces(store.dataPaths!),
    );
    final exporter = LocalBackupExporter(
      store: store,
      attachments: store.dataPaths!.attachments,
      driveBlobs: store.dataPaths!.driveBlobs,
      workspace: Directory(
        paths.join(environment.$2.path, 'legacy-to-owned15-retention'),
      ),
      checkPendingRecovery: () async {
        (await inventory.read()).requireClear();
      },
    );
    return LocalRestoreCoordinator(
      retainedBuilder: LocalRetainedBackupBuilder(
        exporter: exporter,
        control: _localControl,
      ),
    ).apply(candidate);
  }

  Future<void> _openOwned15Migration(int generation) async {
    if (!_localEpochCurrent(generation)) return;
    final environment = await _localEnvironment();
    if (!_localEpochCurrent(generation)) return;
    final inspection = LocalLegacyInspectionLifetime();
    _owned15Inspections.add(inspection);
    late MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      builder: (_) => LocalLegacyMigrationPage(
        inspectionLifetime: inspection,
        privateCache: environment.$2,
        availableBytes: _localControl.availableBytes,
        isCurrentScope: () => _localEpochCurrent(generation),
        factory: environment.$1.factory,
        english: _english,
        ownedActivation: (zip, selection) =>
            _owned15ActivationRoute(zip, selection, generation),
        registerChildRoute: _owned15Routes.add,
        unregisterChildRoute: _owned15Routes.remove,
      ),
    );
    _owned15Routes.add(route);
    try {
      await _navigator.currentState!.push<void>(route);
    } finally {
      _owned15Routes.remove(route);
      await inspection.retire();
      _owned15Inspections.remove(inspection);
    }
  }

  Future<void> _openOwned15Backup(
    OwnedWritableGeneration15 owner,
    int generation,
  ) async {
    if (!_localEpochCurrent(generation) || !owner.current) return;
    final environment = await _localEnvironment();
    if (!_localEpochCurrent(generation) || !owner.current) return;
    late MaterialPageRoute<void> route;
    route = MaterialPageRoute<void>(
      builder: (_) => LocalBackupFeature(
        owned15: owner,
        session: environment.$1,
        privateCache: environment.$2,
        isCurrentScope: () => _localEpochCurrent(generation),
        onEntered: (receipt) => _enterLocalReceipt(
          environment.$1,
          receipt,
          generation,
          featureRoute: route,
        ),
        onConnection: () => _localConnection(featureRoute: route),
        // Owned15 journals use their metadata resolver, never ordinary SQL/Vault.
        openDraft: (_, _) async {
          throw StateError('Use the owned15 recovery catalog');
        },
        openOwnedPending: () => _openOwned15Pending(owner, generation),
        openOwnedLegacyMigration: () => _openOwned15Migration(generation),
        beforeOwnedSeal: _retireRuntimeBeforeTransition,
        runOwnedActivation: _runOwned15Native,
        english: _english,
      ),
    );
    _owned15Routes.add(route);
    try {
      await _navigator.currentState!.push<void>(route);
    } finally {
      _owned15Routes.remove(route);
    }
  }

  Future<LocalStore> _ensureLocalStore() async {
    final resolved = await _ensureLocalResolved();
    if (resolved is! OrdinaryResolvedLocalStorage) {
      throw StateError(
        'Owned schema15 requires its dedicated resource feature',
      );
    }
    return resolved.store;
  }

  bool _homeLocalCurrent(int generation, LocalStore store) =>
      mounted &&
      !_showConnection &&
      _local &&
      generation == _spaceGeneration &&
      identical(_localStore, store) &&
      !store.maintenance.retired;
  LocalHomeDashboardRepository _localHomeFor(LocalStore store, int generation) {
    if (_homeLocalGeneration == generation &&
        identical(_homeLocalRepository?.store, store)) {
      return _homeLocalRepository!;
    }
    if (!_homeLocalCurrent(generation, store)) {
      throw StateError('Local home scope changed');
    }
    final preferences = LocalHomePreferences(
      namespace: store.path,
      readValue: (key) => _storage.read(key: key),
      writeValue: (key, value) => _storage.write(key: key, value: value),
      stillCurrent: () => _homeLocalCurrent(generation, store),
    );
    _homeLocalGeneration = generation;
    return _homeLocalRepository = LocalHomeDashboardRepository(
      store,
      preferences,
    );
  }

  LocalHomeResourceOpened _localVisitRecorder(LocalStore store) {
    final generation = _spaceGeneration;
    return (kind, id) async {
      if (_homeLocalCurrent(generation, store)) {
        await _localHomeFor(store, generation).recordVisit(kind, id);
      }
    };
  }

  LocalNotesRepository _homeNotes(
    LocalStore store, {
    NoteCollection collection = NoteCollection.note,
  }) => HomeLocalNotesRepository(
    store,
    collection: collection,
    onOpened: _localVisitRecorder(store),
  );
  LocalBooksRepository _homeBooks(LocalStore store) =>
      HomeLocalBooksRepository(store, onOpened: _localVisitRecorder(store));
  LocalDocumentsRepository _homeDocuments(LocalStore store) =>
      HomeLocalDocumentsRepository(store, onOpened: _localVisitRecorder(store));
  HomeDashboardRepository _homeDashboard() {
    final generation = _spaceGeneration, local = _local, client = _client;
    if (_homeRepositoryGeneration == generation &&
        _homeRepositoryCache != null) {
      return _homeRepositoryCache!;
    }
    bool current() =>
        mounted &&
        !_showConnection &&
        generation == _spaceGeneration &&
        local == _local &&
        (local || identical(client, _client));
    final HomeDashboardRepository inner = local
        ? DeferredHomeDashboardRepository(() async {
            if (!current()) throw StateError('Home scope changed');
            final store = await _ensureLocalStore();
            if (!current()) throw StateError('Home scope changed');
            return _localHomeFor(store, generation);
          })
        : RemoteHomeDashboardRepository(client!);
    _homeRepositoryGeneration = generation;
    return _homeRepositoryCache = ObservedHomeDashboardRepository(
      inner,
      onLoaded: () {
        if (!local && current() && _defaultEntryPending) {
          _defaultEntryPending = false;
          unawaited(_openDefaultModule(client!, generation));
        }
      },
      onUnauthorized: () async {
        if (local || !current()) return;
        await _retireComplexSourceBeforeTransition();
        if (!current()) return;
        final retiring = _advanceSpace();
        _accountBackground = null;
        _accountBackgroundImage = null;
        try {
          await _closeSpeech();
        } catch (_) {
          /* Session revocation still proceeds. */
        }
        if (!mounted ||
            retiring != _spaceGeneration ||
            !identical(client, _client) ||
            _local) {
          return;
        }
        try {
          await _sessions.clear();
        } finally {
          if (mounted &&
              retiring == _spaceGeneration &&
              identical(client, _client) &&
              !_local) {
            setState(() => _showConnection = true);
          }
        }
      },
    );
  }

  Future<void> Function()? _resetHomePreferencesAction() {
    if (!_local) return null;
    final generation = _spaceGeneration;
    return () async {
      if (!mounted ||
          !_local ||
          _showConnection ||
          generation != _spaceGeneration) {
        throw StateError('Home scope changed');
      }
      final store = await _ensureLocalStore();
      await _localHomeFor(store, generation).preferences.reset();
    };
  }

  Future<void> Function(HomeDashboardController) _homeCustomizeAction() {
    final generation = _spaceGeneration, local = _local, client = _client;
    return (controller) async {
      if (!mounted ||
          _showConnection ||
          generation != _spaceGeneration ||
          local != _local ||
          (!local && !identical(client, _client)) ||
          _openingFeature ||
          controller.retired) {
        return;
      }
      _openingFeature = true;
      try {
        await _navigator.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => HomeLayoutPage(
              controller: controller,
              english: _english,
              local: local,
              scopeLabel: local
                  ? (_english
                        ? 'This device · Current local space'
                        : '当前设备 · 当前本地空间')
                  : (_english
                        ? 'Current server · Current account'
                        : '当前服务器 · 当前账号'),
            ),
          ),
        );
      } finally {
        _openingFeature = false;
      }
    };
  }

  void Function(String) _homeNavigateAction() {
    final generation = _spaceGeneration;
    return (route) {
      if (mounted && !_showConnection && generation == _spaceGeneration) {
        unawaited(_navigate(route));
      }
    };
  }

  void Function(String, HomeContentItem) _homeItemAction() {
    final generation = _spaceGeneration;
    return (key, item) {
      if (mounted && !_showConnection && generation == _spaceGeneration) {
        unawaited(_openHomeItem(key, item));
      }
    };
  }

  void Function(String) _homeAllAction() {
    final generation = _spaceGeneration;
    return (key) {
      if (!mounted || _showConnection || generation != _spaceGeneration) return;
      if (key == 'assets') {
        unawaited(_openHomeAssets());
        return;
      }
      unawaited(_navigate(key == 'shares' ? 'public-feed' : key));
    };
  }

  Future<void> _openHomeItem(String key, HomeContentItem item) async {
    switch (key) {
      case 'notes':
      case 'articles':
        await _navigate('blog/${item.id}');
      case 'books':
        await _navigate('book/${item.id}');
      case 'bookmarks':
      case 'nav':
        await _navigate('bookmark/${item.id}');
      case 'tasks':
        await _navigate('home-task/${item.id}');
      case 'topics':
        await _navigate('home-topic/${item.id}');
      case 'shares':
        if (!_local && item.shareIdentify != null) {
          await _navigate(
            'home-share/${Uri.encodeComponent(item.shareIdentify!)}',
          );
        }
      case 'assets':
        await _openHomeAssets(target: item);
    }
  }

  int? _homeTargetId(String route, String prefix) {
    final match = RegExp(
      '^${RegExp.escape(prefix)}/([1-9][0-9]*)'
      r'$',
    ).firstMatch(route);
    return match == null ? null : int.tryParse(match[1]!);
  }

  PublicShareReference? _homeShareTarget(String route) {
    if (_local || _client == null || !route.startsWith('home-share/')) {
      return null;
    }
    final value = route.substring('home-share/'.length);
    if (value.contains('/')) return null;
    try {
      return PublicShareReference(_client!.baseUri, Uri.decodeComponent(value));
    } on FormatException {
      return null;
    }
  }

  Future<void> _openHomeAssets({HomeContentItem? target}) async {
    if (_local || _showConnection || _openingFeature || _client == null) return;
    final generation = _spaceGeneration,
        client = _client!,
        session = _client!.exportSession()['token'];
    bool current() =>
        mounted &&
        !_showConnection &&
        !_local &&
        generation == _spaceGeneration &&
        identical(client, _client) &&
        client.exportSession()['token'] == session;
    AdminAssetsScope? scope;
    AdminAssetsRepository? hosts;
    AdminDavRepository? dav;
    _openingFeature = true;
    try {
      final profile = await client.adminAssetPrincipalJson();
      if (!current()) return;
      final id = profile['member_id'],
          account = profile['account'],
          role = profile['role'];
      if (session == null ||
          id is! int ||
          id <= 0 ||
          account is! String ||
          account.isEmpty ||
          role != 0) {
        throw StateError('Administrator unavailable');
      }
      final held = AdminAssetsScope(
        client,
        AdminPrincipal(memberId: id, account: account, role: 0),
      );
      scope = held;
      _homeAssetScope = held;
      final nav = _navigator.currentState!;
      Widget page;
      if (target == null) {
        page = AdminAssetsFeature(
          scope: held,
          english: _english,
          onReturn: () => nav.pop(),
        );
      } else if (target.badge == 'ssh') {
        hosts = AdminAssetsRepository(client);
        final rows = await hosts.readHosts(held.owner);
        if (!current()) return;
        final host = rows.firstWhere((row) => row.id == target.id);
        page = AdminFilesPage(
          scope: held,
          host: host,
          english: _english,
          onReturn: () => nav.pop(),
        );
      } else if (target.badge == 'webdav') {
        dav = AdminDavRepository(held);
        final rows = await dav.list();
        if (!current()) return;
        final server = rows.whereType<AdminDavServer>().firstWhere(
          (row) => row.id == target.id,
        );
        final binding = await dav.bind(server);
        if (!current()) return;
        page = AdminDavFilesPage(
          scope: held,
          binding: binding,
          english: _english,
          onReturn: () => nav.pop(),
        );
      } else {
        throw const FormatException('Invalid asset kind');
      }
      await nav.push<void>(MaterialPageRoute(builder: (_) => page));
    } catch (_) {
      final messageContext = _navigator.currentState?.context;
      if (current() && messageContext != null && messageContext.mounted) {
        ScaffoldMessenger.of(messageContext).showSnackBar(
          SnackBar(
            content: Text(
              _english
                  ? 'Could not open this asset. Reload and check permissions.'
                  : '无法打开该资产，请重新读取并核对权限与资料。',
            ),
          ),
        );
      }
    } finally {
      dav?.dispose();
      hosts?.dispose();
      if (identical(_homeAssetScope, scope)) _homeAssetScope = null;
      scope?.dispose();
      _openingFeature = false;
    }
    if (current()) setState(() => _homeRevision++);
  }

  Future<Map<String, Object?>> _loadHome() async {
    if (_local) {
      await _ensureLocalStore();
      return _localStore!.homeSummary();
    }
    try {
      final result = await _client!.get('/api/home');
      if (_defaultEntryPending) {
        _defaultEntryPending = false;
        unawaited(_openDefaultModule(_client!, _spaceGeneration));
      }
      return result;
    } on ApiFailure catch (error) {
      if (error.status == 401) {
        await _retireComplexSourceBeforeTransition();
        if (!mounted) rethrow;
        _advanceSpace();
        _accountBackground = null;
        _accountBackgroundImage = null;
        await _closeSpeech();
        await _sessions.clear();
        if (mounted) setState(() => _showConnection = true);
      }
      rethrow;
    }
  }

  Future<void> _openDefaultModule(
    BookstarkClient client,
    int generation,
  ) async {
    try {
      final row = await client.profileSettingsJson();
      final member = row['member_id'];
      if (member is int && member > 0) {
        unawaited(_readAccountBackground(client, generation, member));
      }
      final module = row['default_home'];
      if (module is! String ||
          !profileHomeModules.contains(module) ||
          module == 'home') {
        return;
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted ||
          generation != _spaceGeneration ||
          _client != client ||
          _showConnection ||
          _local ||
          _openingFeature ||
          _navigator.currentState!.canPop()) {
        return;
      }
      await _navigate(module);
    } catch (_) {
      /* The connected home remains available if preference loading fails. */
    }
  }

  Future<void> _readAccountBackground(
    BookstarkClient client,
    int generation,
    int memberId,
  ) async {
    try {
      final repository = RemoteBackgroundRepository(client, memberId: memberId);
      final preference = await repository.read();
      final image = preference.mode == 'image'
          ? await repository.image(preference.imageHash)
          : null;
      if (!mounted ||
          _spaceGeneration != generation ||
          !identical(_client, client) ||
          _showConnection ||
          _local) {
        return;
      }
      setState(() {
        _accountBackground = preference;
        _accountBackgroundImage = image;
      });
    } catch (_) {
      /* Keep the readable default canvas when private preferences cannot be verified. */
    }
  }

  Future<void> _setLanguage(bool english) async {
    await _storage.write(key: _languageKey, value: english ? 'en' : 'zh');
    if (!mounted) {
      return;
    }
    setState(() => _english = english);
    _client?.language = english ? 'en' : 'zh';
  }

  void _toggleLanguage() {
    unawaited(
      _setLanguage(!_english).catchError((Object _) {
        if (mounted) {
          ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
            SnackBar(
              content: Text(
                _english
                    ? 'Language preference could not be saved.'
                    : '无法保存语言偏好。',
              ),
            ),
          );
        }
      }),
    );
  }

  Future<bool> _persistClientSession(
    BookstarkClient client,
    int generation,
  ) async {
    if (!client.exportSession().containsKey('token')) {
      return false;
    }
    return _sessions.save(
      jsonEncode({
        'server': client.baseUri.toString(),
        'cookies': client.exportSession(),
      }),
      stillCurrent: () =>
          mounted &&
          _client == client &&
          generation == _spaceGeneration &&
          !_showConnection &&
          !_local,
    );
  }

  Future<void> _leaveServer() async {
    await _retireComplexSourceBeforeTransition();
    await HtmlBrowserSession.closeActive();
    await _closeSpeech();
    await _sessions.clear();
    if (!mounted) {
      return;
    }
    _advanceSpace();
    _accountBackground = null;
    _accountBackgroundImage = null;
    _profileDestination = null;
    _defaultEntryPending = false;
    _client?.restoreSession({});
    _client?.close();
    _client = null;
    setState(() {
      _local = false;
      _showConnection = true;
    });
    _navigator.currentState!.popUntil((route) => route.isFirst);
  }

  void _accountForm(AccountForm form) {
    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (context) => AccountFormPage(
          form: form,
          strings: strings,
          server: _server,
          clientFactory: (server) =>
              BookstarkClient(server)..language = _english ? 'en' : 'zh',
          onBack: () =>
              _navigator.currentState!.popUntil((route) => route.isFirst),
          onReset: () => _accountForm(AccountForm.reset),
        ),
      ),
    );
  }

  LocalDataMaintenance? _localDraftMaintenance(String namespace) {
    if (!LocalDraftNamespace.isLocal(namespace)) return null;
    final store = _localStore;
    if (store == null) throw StateError('Local data has not been opened');
    return store.maintenance;
  }

  Future<void> _writeNativeEditorDraft(String key, String value) async {
    await _storage.write(key: key, value: value);
    await NativeRecoveryStorage.flush();
  }

  Future<void> _deleteNativeEditorDraft(String key) async {
    await _storage.delete(key: key);
    await NativeRecoveryStorage.flush();
  }

  DraftVault _nativeDrafts(String namespace) => DraftVault(
    maintenance: _localDraftMaintenance(namespace),
    namespace: namespace,
    readValue: (key) => _storage.read(key: key),
    writeValue: _writeNativeEditorDraft,
    deleteValue: _deleteNativeEditorDraft,
  );

  TaskDraftVault _nativeTaskDrafts(String namespace) => TaskDraftVault(
    maintenance: _localDraftMaintenance(namespace),
    namespace: namespace,
    readValue: (key) => _storage.read(key: key),
    writeValue: _writeNativeEditorDraft,
    deleteValue: _deleteNativeEditorDraft,
  );

  Widget _searchFeature({
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required AttachmentRepository attachments,
  }) {
    final searchGeneration = _spaceGeneration,
        searchStore = _localStore,
        searchRevision = client?.sessionRevision;
    bool searchCurrent() =>
        mounted &&
        !_showConnection &&
        !_complexSourceSwitching &&
        searchGeneration == _spaceGeneration &&
        local == _local &&
        (local
            ? identical(searchStore, _localStore) &&
                  searchStore != null &&
                  !searchStore.maintenance.retired
            : identical(client, _client) &&
                  client!.sessionRevision == searchRevision);
    final scopeIdentity = (
      searchGeneration,
      local,
      searchStore,
      client,
      searchRevision,
      memberId,
      namespace,
    );
    final opener = _nativeOpener(
      local: local,
      client: client,
      memberId: memberId,
      isAdmin: isAdmin,
      namespace: namespace,
      attachments: attachments,
    );
    Future<NoteCollection> collection(int id) async {
      if (!searchCurrent()) throw StateError('Search owner retired');
      Object? value;
      if (local) {
        value = await searchStore!.noteCollectionOf(id);
      } else {
        value = (await client!.articleMetadata(id))['blog_type'];
      }
      if (!searchCurrent()) throw StateError('Search owner retired');
      if (value == 'note') return NoteCollection.note;
      if (value == 'article') return NoteCollection.article;
      throw StateError('未知资源类型 / Unknown resource collection');
    }

    return Builder(
      key: ValueKey(scopeIdentity),
      builder: (context) => SearchPage(
        scopeIdentity: scopeIdentity,
        repository: local
            ? LocalSearchRepository(searchStore!, isCurrent: searchCurrent)
            : RemoteSearchRepository(client!, isCurrent: searchCurrent),
        english: _english,
        local: local,
        onOpenHit: (hit) async {
          if (!context.mounted || !searchCurrent()) {
            throw StateError('Search owner retired');
          }
          switch (hit.kind) {
            case SearchKind.document:
              await opener.open(context, TopicResourceType.document, hit.id);
            case SearchKind.bookmark:
              await opener.open(context, TopicResourceType.bookmark, hit.id);
            case SearchKind.task:
              await opener.open(context, TopicResourceType.task, hit.id);
            case SearchKind.blog:
              if (hit.collection == null) {
                throw StateError('未知资源类型 / Unknown content collection');
              }
              await opener.open(
                context,
                hit.collection == NoteCollection.article
                    ? TopicResourceType.article
                    : TopicResourceType.note,
                hit.id,
              );
            case SearchKind.book:
              await opener.openLabel(
                context,
                LabelResource(
                  id: hit.id,
                  type: LabelResourceType.book,
                  title: hit.title,
                ),
                resolveCollection: collection,
              );
            case SearchKind.label:
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => _labelsFeature(
                    initialLabelId: hit.id,
                    local: local,
                    client: client,
                    memberId: memberId,
                    isAdmin: isAdmin,
                    namespace: namespace,
                    attachments: attachments,
                  ),
                ),
              );
            case SearchKind.topic:
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => _topicsFeature(
                    initialTopicId: hit.id,
                    local: local,
                    client: client,
                    memberId: memberId,
                    isAdmin: isAdmin,
                    namespace: namespace,
                    attachments: attachments,
                  ),
                ),
              );
          }
        },
      ),
    );
  }

  RemoteBookmarksRepository _recoverableBookmarks({
    required BookstarkClient client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required bool Function() isCurrent,
  }) => RemoteBookmarksRepository(
    client,
    memberId: memberId,
    isAdmin: isAdmin,
    isCurrent: isCurrent,
    createRecoverably: (draft) async {
      if (!mounted || !isCurrent()) throw StateError('Bookmark owner retired');
      final row = await submitRecoverableBookmarkCreation(
        context: context,
        client: client,
        memberId: memberId,
        namespace: namespace,
        body: {
          'title': draft.title,
          'url': draft.url,
          'description': draft.description,
          'favicon': draft.favicon,
          'is_public': draft.isPublic,
          'labels': draft.labels.toSet().toList(),
        },
        read: (key) => _storage.read(key: key),
        write: (key, value) => _storage.write(key: key, value: value),
        remove: (key) => _storage.delete(key: key),
        flush: NativeRecoveryStorage.flush,
        isCurrent: isCurrent,
        english: _english,
      );
      if (!mounted || !isCurrent()) throw StateError('Bookmark owner retired');
      return BookmarkItem.fromJson(row);
    },
  );

  NativeResourceOpener _nativeOpener({
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required AttachmentRepository attachments,
  }) {
    final openerGeneration = _spaceGeneration;
    final openerStore = _localStore;
    final openerIoScope = local ? _complexSourceOwner.current : null;
    final openerRevision = client?.sessionRevision;
    bool documentCurrent() =>
        mounted &&
        !_showConnection &&
        openerGeneration == _spaceGeneration &&
        local == _local &&
        (local
            ? identical(openerStore, _localStore) &&
                  !openerStore!.maintenance.retired
            : identical(client, _client) &&
                  client!.sessionRevision == openerRevision);

    final NotesRepository notes = local
        ? _homeNotes(_localStore!)
        : RemoteNotesRepository(client!);
    final NotesRepository articles = local
        ? _homeNotes(_localStore!, collection: NoteCollection.article)
        : RemoteNotesRepository(client!, collection: NoteCollection.article);
    final BooksRepository books = local
        ? _homeBooks(_localStore!)
        : RemoteBooksRepository(client!);
    final DocumentsRepository documents = local
        ? _homeDocuments(_localStore!)
        : RemoteDocumentsRepository(client!);
    final TasksRepository tasks = local
        ? _recoverableLocalTasks(
            store: _localStore!,
            namespace: namespace,
            isCurrent: documentCurrent,
          )
        : _recoverableTasks(
            client: client!,
            memberId: memberId,
            namespace: namespace,
            isCurrent: () => documentCurrent() && !_complexSourceSwitching,
          );
    final BookmarksRepository bookmarks = local
        ? LocalBookmarksRepository(_localStore!)
        : _recoverableBookmarks(
            client: client!,
            namespace: namespace,
            memberId: memberId,
            isAdmin: isAdmin,
            isCurrent: () => documentCurrent() && !_complexSourceSwitching,
          );
    final LabelsRepository labels = local
        ? LocalLabelsRepository(_localStore!)
        : RemoteLabelsRepository(client!);
    final bookmarkDrafts = BookmarkDraftVault(
      maintenance: _localDraftMaintenance(namespace),
      namespace: namespace,
      readValue: (key) => _storage.read(key: key),
      writeValue: (key, value) => _storage.write(key: key, value: value),
      deleteValue: (key) => _storage.delete(key: key),
    );
    final documentReader = _documentReader(
      local: local,
      client: client,
      isCurrent: documentCurrent,
    );
    return NativeResourceOpener(
      recoverTaskCreation: local
          ? () => _recoverLocalTaskCreation(
              store: _localStore!,
              namespace: namespace,
              isCurrent: documentCurrent,
            )
          : () => _recoverTaskCreation(
              client: client!,
              memberId: memberId,
              namespace: namespace,
              isCurrent: documentCurrent,
            ),
      taskActionsFactory: local
          ? null
          : _taskEditorActionsFactory(
              client: client!,
              memberId: memberId,
              namespace: namespace,
              isCurrent: documentCurrent,
            ),
      onCreateExcerpt: _documentExcerptAction(
        local: local,
        client: client,
        memberId: memberId,
        namespace: namespace,
        attachments: attachments,
        isCurrent: documentCurrent,
      ),
      beforeOpenOwnedBlog: local
          ? null
          : (context, id, collection) async {
              final ownedClient = client!;
              bool current() => !_complexSourceSwitching && documentCurrent();
              if (!current()) return false;
              try {
                final gate = ProtectedOwnedResourceGate(
                  server: ownedClient.baseUri.toString(),
                  memberId: memberId,
                  namespace: namespace,
                  isCurrent: current,
                  readValue: (key) => _storage.read(key: key),
                  writeValue: (key, value) =>
                      _storage.write(key: key, value: value),
                  deleteValue: (key) => _storage.delete(key: key),
                  flush: NativeRecoveryStorage.flush,
                );
                if (!await gate.hasRetainedMarker(id)) return current();
                final metadata = await ownedClient.articleMetadata(id);
                if (!current() || !context.mounted) return false;
                if (metadata['blog_id'] == id &&
                    metadata['member_id'] == memberId &&
                    metadata['blog_type'] == 'note' &&
                    collection == NoteCollection.note &&
                    const {
                      'spreadsheet',
                      'drawing',
                      'mindmap',
                      'richdoc',
                      'presentation',
                    }.contains(metadata['editor_type'])) {
                  return true;
                }
                if (metadata['blog_id'] != id ||
                    metadata['member_id'] != memberId ||
                    metadata['has_password'] is! bool ||
                    !const {
                      'note',
                      'article',
                    }.contains(metadata['blog_type'])) {
                  throw StateError('Owned recovery target identity changed');
                }
                await openRetargetedProtectedRecovery(
                  context,
                  server: ownedClient.baseUri.toString(),
                  memberId: memberId,
                  resourceId: id,
                  namespace: namespace,
                  hasPassword: metadata['has_password'] as bool,
                  isCurrentScope: current,
                  readSource: (password, abort) =>
                      ownedClient.readOwnedProtectedRecoveryJson(
                        id,
                        password: password,
                        expectedSessionRevision: openerRevision!,
                        abortTrigger: abort,
                      ),
                  readValue: (key) => _storage.read(key: key),
                  writeValue: (key, value) =>
                      _storage.write(key: key, value: value),
                  deleteValue: (key) => _storage.delete(key: key),
                  flush: NativeRecoveryStorage.flush,
                  registerOwner: (owner) {
                    if (!current()) {
                      unawaited(owner.retire());
                      throw StateError('Protected owner retired');
                    }
                    _protectedComplexOwners.add(owner);
                  },
                  unregisterOwner: (owner) =>
                      _protectedComplexOwners.remove(owner),
                  english: _english,
                );
                // Explicit review cleanup never automatically enters an editor.
                return false;
              } catch (_) {
                if (current() && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _english
                            ? 'Recovery status is unavailable. Editing remains blocked.'
                            : '无法确认恢复状态，已保留记录并阻止编辑。',
                      ),
                    ),
                  );
                }
                return false;
              }
            },
      openOwnedComplexNote: local
          ? null
          : _ownedComplexNoteWriter(
              client: client!,
              memberId: memberId,
              namespace: namespace,
              isCurrent: documentCurrent,
            ),
      sourceIoScope: openerIoScope,
      isCurrentScope: documentCurrent,
      boundedDocuments: documentReader,
      readingFingerprint: _documentReadingFingerprint(
        local: local,
        client: client,
        memberId: memberId,
        namespace: namespace,
        isCurrent: documentCurrent,
      ),
      inspectDocument: local
          ? documents.read
          : (documentReader as OwnedBoundedDocumentsReader).discover,
      onEditComplexDocument: _documentComplexWriter(
        local: local,
        client: client,
        memberId: memberId,
        namespace: namespace,
        isCurrent: documentCurrent,
      ),
      notes: notes,
      articles: articles,
      books: books,
      documents: documents,
      tasks: tasks,
      bookmarks: bookmarks,
      labels: labels,
      bookDrafts: BookDraftVault(
        maintenance: _localDraftMaintenance(namespace),
        namespace: namespace,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
      ),
      noteDrafts: _nativeDrafts(namespace),
      articleDrafts: _nativeDrafts(jsonEncode([namespace, 'article'])),
      documentDrafts: _nativeDrafts(jsonEncode([namespace, 'document'])),
      excerptDrafts: (id) =>
          _nativeDrafts(jsonEncode([namespace, 'excerpt', id])),
      taskDrafts: _nativeTaskDrafts(namespace),
      bookmarkDrafts: bookmarkDrafts,
      attachments: attachments,
      positions: ReadingPositionVault(
        maintenance: _localDraftMaintenance(namespace),
        namespace: namespace,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
      ),
      server: local ? null : client!.baseUri,
      onSpeak: _openSpeech,
      onSpeakSelection: (selection, title, path) =>
          _openSpeech('', title, path, selection: selection),
      openArticle: local
          ? (context, id) async {
              bool current() =>
                  mounted &&
                  !_complexSourceSwitching &&
                  _local &&
                  !_showConnection &&
                  openerGeneration == _spaceGeneration &&
                  identical(_localStore, openerStore);
              if (!current()) return;
              await openNativeNoteEditor(
                context,
                sourceIoScope: openerIoScope,
                repository: articles,
                id: id,
                collection: NoteCollection.article,
                drafts: _nativeDrafts(jsonEncode([namespace, 'article'])),
                attachments: attachments,
                english: _english,
                isCurrentScope: current,
              );
            }
          : (context, id) =>
                _openArticleResource(context, client!, memberId, id),
      english: _english,
    );
  }

  Widget _labelsFeature({
    int? initialLabelId,
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required AttachmentRepository attachments,
  }) {
    final labelGeneration = _spaceGeneration,
        labelStore = _localStore,
        labelRevision = client?.sessionRevision;
    bool labelCurrent() =>
        mounted &&
        !_showConnection &&
        !_complexSourceSwitching &&
        labelGeneration == _spaceGeneration &&
        local == _local &&
        (local
            ? identical(labelStore, _localStore) &&
                  !labelStore!.maintenance.retired
            : identical(client, _client) &&
                  client!.sessionRevision == labelRevision);
    final opener = _nativeOpener(
      local: local,
      client: client,
      memberId: memberId,
      isAdmin: isAdmin,
      namespace: namespace,
      attachments: attachments,
    );
    late final LocalLabelManagementRepository? localLabelRepository;
    localLabelRepository = local
        ? LocalLabelManagementRepository(
            labelStore!,
            isCurrent: labelCurrent,
            createRecoverably: (name, create) async {
              final result = await openLocalLabelCreation(
                context: context,
                store: labelStore,
                namespace: namespace,
                name: name,
                create: (_) => create(),
                isCurrent: labelCurrent,
                english: _english,
                read: (key) =>
                    labelStore.maintenance.use(() => _storage.read(key: key)),
                write: (key, value) => labelStore.maintenance.use(
                  () => _storage.write(key: key, value: value),
                ),
                remove: (key) =>
                    labelStore.maintenance.use(() => _storage.delete(key: key)),
                flush: () =>
                    labelStore.maintenance.use(NativeRecoveryStorage.flush),
              );
              if (!labelCurrent() || result == null) {
                throw StateError('Local label result not adopted');
              }
              return result;
            },
          )
        : null;
    return LabelsFeature(
      key: ValueKey((
        labelGeneration,
        local,
        labelStore,
        client,
        labelRevision,
        initialLabelId,
      )),
      onRecoverCreations: local
          ? (routeContext) async {
              final result = await openLocalLabelCreation(
                context: routeContext,
                store: labelStore!,
                namespace: namespace,
                create: localLabelRepository!.createLocalTransaction,
                isCurrent: labelCurrent,
                english: _english,
                read: (key) =>
                    labelStore.maintenance.use(() => _storage.read(key: key)),
                write: (key, value) => labelStore.maintenance.use(
                  () => _storage.write(key: key, value: value),
                ),
                remove: (key) =>
                    labelStore.maintenance.use(() => _storage.delete(key: key)),
                flush: () =>
                    labelStore.maintenance.use(NativeRecoveryStorage.flush),
              );
              if (!routeContext.mounted || !labelCurrent() || result == null) {
                return;
              }
              final actual = ManagedLabel.fromJson(result.wire);
              await Navigator.of(routeContext).push<void>(
                MaterialPageRoute(
                  builder: (_) => _labelsFeature(
                    initialLabelId: actual.id,
                    local: true,
                    client: null,
                    memberId: memberId,
                    isAdmin: true,
                    namespace: namespace,
                    attachments: attachments,
                  ),
                ),
              );
            }
          : (routeContext) async {
              final actual = await openLabelCreationRecovery(
                context: routeContext,
                client: client!,
                memberId: memberId,
                namespace: namespace,
                read: (key) => _storage.read(key: key),
                write: (key, value) => _storage.write(key: key, value: value),
                remove: (key) => _storage.delete(key: key),
                flush: NativeRecoveryStorage.flush,
                isCurrent: labelCurrent,
                english: _english,
              );
              if (!routeContext.mounted || !labelCurrent() || actual == null) {
                return;
              }
              await Navigator.of(routeContext).push<void>(
                MaterialPageRoute(
                  builder: (_) => _labelsFeature(
                    initialLabelId: ManagedLabel.fromJson(actual.wire).id,
                    local: false,
                    client: client,
                    memberId: memberId,
                    isAdmin: isAdmin,
                    namespace: namespace,
                    attachments: attachments,
                  ),
                ),
              );
            },
      initialLabelId: initialLabelId,
      repository: local
          ? localLabelRepository!
          : RemoteLabelManagementRepository(
              client!,
              canManage: isAdmin,
              isCurrent: labelCurrent,
              createRecoverably: (name) async {
                final row = await submitRecoverableLabelCreation(
                  context: context,
                  client: client,
                  memberId: memberId,
                  namespace: namespace,
                  body: {'label_name': name},
                  read: (key) => _storage.read(key: key),
                  write: (key, value) => _storage.write(key: key, value: value),
                  remove: (key) => _storage.delete(key: key),
                  flush: NativeRecoveryStorage.flush,
                  isCurrent: labelCurrent,
                  english: _english,
                );
                if (!labelCurrent()) {
                  throw StateError('Label initiating scope retired');
                }
                return row;
              },
            ),
      drafts: _nativeDrafts(jsonEncode([namespace, 'label'])),
      english: _english,
      local: local,
      onOpenResource: (context, resource) => opener.openLabel(
        context,
        resource,
        resolveCollection: (id) async {
          if (!labelCurrent()) throw StateError('Label owner retired');
          Object? value;
          if (local) {
            value = await labelStore!.noteCollectionOf(id);
          } else {
            value = (await client!.articleMetadata(id))['blog_type'];
          }
          if (!labelCurrent()) throw StateError('Label owner retired');
          if (value == 'note') return NoteCollection.note;
          if (value == 'article') return NoteCollection.article;
          throw StateError('未知资源类型 / Unknown resource collection');
        },
      ),
    );
  }

  Widget _topicsFeature({
    int? initialTopicId,
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required AttachmentRepository attachments,
  }) {
    final topicGeneration = _spaceGeneration,
        topicRevision = client?.sessionRevision;
    final topicStore = _localStore;
    bool topicCurrent() =>
        mounted &&
        !_showConnection &&
        !_complexSourceSwitching &&
        topicGeneration == _spaceGeneration &&
        local == _local &&
        (local
            ? identical(topicStore, _localStore) &&
                  !topicStore!.maintenance.retired
            : identical(client, _client) &&
                  client!.sessionRevision == topicRevision);
    final opener = _nativeOpener(
      local: local,
      client: client,
      memberId: memberId,
      isAdmin: isAdmin,
      namespace: namespace,
      attachments: attachments,
    );
    final notes = opener.notes, articles = opener.articles;
    final books = opener.books,
        documents = opener.documents,
        tasks = opener.tasks,
        bookmarks = opener.bookmarks;
    return TopicsFeature(
      recoverTaskCreation: local
          ? () => _recoverLocalTaskCreation(
              store: topicStore!,
              namespace: namespace,
              isCurrent: topicCurrent,
            )
          : () => _recoverTaskCreation(
              client: client!,
              memberId: memberId,
              namespace: namespace,
              isCurrent: topicCurrent,
            ),
      onRecoverCreations: local
          ? null
          : (routeContext) => openTopicCreationDirectory(
              context: routeContext,
              client: client!,
              memberId: memberId,
              namespace: namespace,
              isCurrent: topicCurrent,
              metadata: () => NativeRecoveryStorage.channel
                  .invokeMethod<Object?>('metadata'),
              read: (key) => _storage.read(key: key),
              write: (key, value) => _storage.write(key: key, value: value),
              remove: (key) => _storage.delete(key: key),
              flush: NativeRecoveryStorage.flush,
              english: _english,
            ),
      initialTopicId: initialTopicId,
      repository: local
          ? LocalTopicsRepository(_localStore!)
          : RemoteTopicsRepository(
              client!,
              memberId: memberId,
              isCurrent: topicCurrent,
              createRecoverably: (kind, topicId, body) =>
                  submitRecoverableTopicCreation(
                    context: context,
                    client: client,
                    memberId: memberId,
                    namespace: namespace,
                    kind: TopicCreationKind.values.byName(kind),
                    topicId: topicId,
                    body: body,
                    read: (key) => _storage.read(key: key),
                    write: (key, value) =>
                        _storage.write(key: key, value: value),
                    remove: (key) => _storage.delete(key: key),
                    flush: NativeRecoveryStorage.flush,
                    isCurrent: topicCurrent,
                    english: _english,
                  ),
            ),
      tasks: tasks,
      picker: ExistingTopicResourcePickerRepository(
        notes: notes,
        articles: articles,
        noteMetadata: local
            ? LocalNoteListSource(
                repository: notes as NoteListRepository,
                isCurrent: topicCurrent,
              )
            : RemoteNoteListSource(
                expectedMemberId: memberId,
                isCurrent: topicCurrent,
                readBoundedPage: (path) => client!.noteListPageMetadata(path),
              ),
        articleMetadata: local
            ? LocalNoteListSource(
                repository: articles as NoteListRepository,
                collection: 'article',
                isCurrent: topicCurrent,
              )
            : RemoteNoteListSource(
                expectedMemberId: memberId,
                isCurrent: topicCurrent,
                readBoundedPage: (path) => client!.noteListPageMetadata(path),
              ),
        bookRepository: books,
        documents: documents,
        bookmarks: bookmarks,
        tasks: tasks,
      ),
      onOpenResource: (context, resource) =>
          opener.open(context, resource.type, resource.targetId),
      topicDrafts: TopicDraftVault(
        maintenance: _localDraftMaintenance(namespace),
        namespace: namespace,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
      ),
      summaryDrafts: (id) =>
          _nativeDrafts(jsonEncode([namespace, 'topic-summary', id])),
      commentDrafts: (id, type, target) => _nativeDrafts(
        jsonEncode([namespace, 'topic-comment', id, type.name, target]),
      ),
      taskDrafts: (id) =>
          _nativeTaskDrafts(jsonEncode([namespace, 'topic-tasks', id])),
      attachments: attachments,
      completion: local ? null : RemoteCompletionRepository(client!),
      onSpeak: _openSpeech,
      english: _english,
      local: local,
    );
  }

  LabelResource? _recentResource(String route) {
    final match = RegExp(
      r'^(blog|book|bookmark|document)/([1-9][0-9]*)$',
    ).firstMatch(route);
    if (match == null) return null;
    final id = int.tryParse(match.group(2)!);
    if (id == null || id <= 0) return null;
    return LabelResource(
      id: id,
      type: LabelResourceType.values.byName(match.group(1)!),
      title: '',
    );
  }

  Future<ResourceCreationResult?> _createOwnedArticle(
    BuildContext context, {
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required AttachmentRepository attachments,
    required NotesRepository repository,
    required DraftVault drafts,
    required bool Function() isCurrent,
  }) async {
    if (!context.mounted) return null;
    if (local) {
      try {
        final ordinary = RootLocalCreationDispatch.dispatch(
          resolved: _localResolved,
          owned: _owned15,
          create: (store) => store,
        );
        if (!identical(ordinary, _localStore)) {
          throw const LocalCreationUnavailable();
        }
      } on LocalCreationUnavailable {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(LocalCreationUnavailable.message)),
        );
        return null;
      }
    }
    final generation = _spaceGeneration, store = _localStore;
    final revision = client?.sessionRevision;
    final sourceIo = _complexSourceOwner.current;
    bool current() =>
        mounted &&
        !_showConnection &&
        _local == local &&
        isCurrent() &&
        !_complexSourceSwitching &&
        _spaceGeneration == generation &&
        (local
            ? identical(_localStore, store) &&
                  store != null &&
                  !store.maintenance.retired
            : identical(_client, client) &&
                  client?.sessionRevision == revision);
    if (!context.mounted || !current()) return null;
    if (local) {
      ResourceCreationResult? receipt;
      await openLocalArticleCreation(
        context,
        store: store!,
        legacyDrafts: drafts,
        english: _english,
        isCurrentScope: current,
        sourceIoScope: sourceIo,
        onCreatedReceipt: (actual) {
          if (!current()) return;
          receipt = ResourceCreationResult(
            kind: CreatedResourceKind.article,
            id: actual.id,
            title: actual.title,
            created: true,
            metadataComplete: true,
          );
        },
      );
      return context.mounted && current() ? receipt : null;
    }
    final opener = _nativeOpener(
      local: false,
      client: client,
      memberId: memberId,
      isAdmin: isAdmin,
      namespace: namespace,
      attachments: attachments,
    );
    return openRemoteArticleCreation(
      context,
      client: client!,
      memberId: memberId,
      namespace: namespace,
      repository: repository,
      drafts: drafts,
      english: _english,
      readValue: (key) => _storage.read(key: key),
      writeValue: _writeNativeEditorDraft,
      deleteValue: _deleteNativeEditorDraft,
      flush: NativeRecoveryStorage.flush,
      isCurrent: current,
      sourceIoScope: sourceIo,
      openKnown: (id, origin) async {
        if (!context.mounted || !current()) return;
        await opener.open(context, TopicResourceType.article, id);
      },
    );
  }

  Future<ResourceCreationResult?> _createRemoteNoteForResource(
    BuildContext context, {
    required BookstarkClient client,
    required int memberId,
    required String namespace,
    required NotesRepository repository,
    required DraftVault drafts,
    required AttachmentRepository attachments,
    required bool Function() isCurrent,
  }) async {
    if (!context.mounted || !isCurrent()) return null;
    final page = await createRemoteMarkdownCreationEditor(
      client: client,
      memberId: memberId,
      namespace: namespace,
      collection: NoteCollection.note,
      repository: repository,
      drafts: drafts,
      attachments: attachments,
      english: _english,
      readValue: (key) => _storage.read(key: key),
      writeValue: _writeNativeEditorDraft,
      deleteValue: _deleteNativeEditorDraft,
      flush: NativeRecoveryStorage.flush,
      isCurrent: isCurrent,
    );
    final controller = page.controller;
    if (!context.mounted || !isCurrent()) {
      retireRemoteMarkdownCreationEditor(page);
      return null;
    }
    try {
      await Navigator.of(
        context,
      ).push<void>(MaterialPageRoute(builder: (_) => page));
      if (!context.mounted || !isCurrent()) return null;
      final record = controller.record, id = record.knownId;
      if (id == null ||
          record.knownIDOrigin == MarkdownKnownIDOrigin.unknownLegacy) {
        return null;
      }
      final manual =
          record.knownIDOrigin == MarkdownKnownIDOrigin.manualExisting;
      final actual = controller.observed;
      if (manual &&
          (actual == null ||
              actual.id != id ||
              actual.scope.namespace != controller.vault.scope.namespace)) {
        return null;
      }
      return ResourceCreationResult(
        kind: CreatedResourceKind.note,
        id: id,
        title: manual ? actual!.input.title : record.input.title,
        created: record.knownIDOrigin == MarkdownKnownIDOrigin.postReceipt,
        metadataComplete: controller.phase == MarkdownCreationPhase.finished,
      );
    } finally {
      controller.retire();
    }
  }

  ResourceCreateCoordinator _resourceCreator({
    required bool local,
    required BookstarkClient? client,
    required int memberId,
    required bool isAdmin,
    required String namespace,
    required AttachmentRepository attachments,
  }) {
    if (local) {
      final ordinary = RootLocalCreationDispatch.dispatch(
        resolved: _localResolved,
        owned: _owned15,
        create: (store) => store,
      );
      if (!identical(ordinary, _localStore)) {
        throw const LocalCreationUnavailable();
      }
    }
    final generation = _spaceGeneration, revision = client?.sessionRevision;
    bool current() =>
        mounted &&
        !_showConnection &&
        _local == local &&
        !_complexSourceSwitching &&
        _spaceGeneration == generation &&
        (local ||
            identical(_client, client) && client?.sessionRevision == revision);
    final opener = _nativeOpener(
      local: local,
      client: client,
      memberId: memberId,
      isAdmin: isAdmin,
      namespace: namespace,
      attachments: attachments,
    );
    // This factory supplies secure vaults for every native editor, with the
    // same account/space namespaces as ordinary resource navigation.
    return ResourceCreateCoordinator(
      notes: opener.notes,
      articles: opener.articles,
      bookmarks: opener.bookmarks,
      books: opener.books,
      documents: opener.documents,
      labels: opener.labels,
      noteDrafts: opener.noteDrafts!,
      articleDrafts: opener.articleDrafts!,
      documentDrafts: opener.documentDrafts!,
      bookmarkDrafts: opener.bookmarkDrafts!,
      bookDrafts: opener.bookDrafts!,
      documentCreationVault: DocumentCreationVault(
        maintenance: _localDraftMaintenance(namespace),
        namespace: namespace,
        readValue: (key) => _storage.read(key: key),
        writeValue: (key, value) => _storage.write(key: key, value: value),
        deleteValue: (key) => _storage.delete(key: key),
      ),
      attachments: attachments,
      english: _english,
      local: local,
      isCurrent: current,
      onCreateArticle: (context) => _createOwnedArticle(
        context,
        local: local,
        client: client,
        memberId: memberId,
        isAdmin: isAdmin,
        namespace: namespace,
        attachments: attachments,
        repository: opener.articles,
        drafts: opener.articleDrafts!,
        isCurrent: current,
      ),
      onCreateNote: local
          ? null
          : (context) => _createRemoteNoteForResource(
              context,
              client: client!,
              memberId: memberId,
              namespace: namespace,
              repository: opener.notes,
              drafts: opener.noteDrafts!,
              attachments: attachments,
              isCurrent: current,
            ),
    );
  }

  /// Nested resource routes retire the WebView before returning here. A module
  /// handoff waits for its containing feature's finally block to release the gate.
  Future<bool> _protectedArticleModuleMayOpen(
    BuildContext context,
    BookstarkClient client,
    int memberId,
    bool Function() isCurrent,
  ) async {
    if (!context.mounted || !isCurrent()) return false;
    try {
      final namespace = jsonEncode([client.baseUri.toString(), memberId]);
      final ownerTag = ProtectedOwnedComplexJournal.ownerTagFor(
        server: client.baseUri.toString(),
        memberId: memberId,
        namespace: namespace,
      );
      await NativeRecoveryStorage.flush().timeout(const Duration(seconds: 30));
      if (!context.mounted || !isCurrent()) return false;
      final metadata = await NativeRecoveryStorage.channel
          .invokeMethod<Object?>('localMetadata')
          .timeout(const Duration(seconds: 30));
      if (!context.mounted || !isCurrent()) return false;
      final records = protectedOwnedMarkersForOwner(metadata, ownerTag);
      if (records.isEmpty) return true;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(_english ? 'Protected saves need review' : '受保护保存需要核对'),
          content: Text(
            _english
                ? 'This account has retained protected submission records. The article module can navigate between resources, so it remains closed. Return to Search or the resource list and open the corresponding resource by its actual ID to review the current source. Records are retained; no save is resent.'
                : '当前账号仍有受保护提交核对记录。文章模块可在资料之间跳转，暂时不能打开。请返回搜索或资料列表，按实际ID打开对应资料核对当前版本。原记录保留，不会重发保存。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_english ? 'Return to list' : '返回列表'),
            ),
          ],
        ),
      );
      return false;
    } catch (_) {
      if (context.mounted && isCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _english
                  ? 'Recovery metadata is unavailable, corrupt or over its limit. The article module remains closed; records are retained.'
                  : '恢复元数据不可用、损坏或超出限制。文章模块暂时关闭，原记录保留。',
            ),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _openArticleResource(
    BuildContext context,
    BookstarkClient client,
    int memberId,
    int id,
  ) async {
    final generation = _spaceGeneration, revision = client.sessionRevision;
    bool current() =>
        mounted &&
        !_complexSourceSwitching &&
        client.sessionRevision == revision &&
        !_local &&
        !_showConnection &&
        generation == _spaceGeneration &&
        identical(_client, client);
    if (!current() || !context.mounted) return;
    if (!await _protectedArticleModuleMayOpen(
          context,
          client,
          memberId,
          current,
        ) ||
        !current()) {
      return;
    }
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    final destination = await navigator.push<String>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          body: SafeArea(
            child: ArticleWebPage(
              client: client,
              memberId: memberId,
              articleId: id,
              english: _english,
              isCurrentScope: current,
              onBack: () async {
                if (navigator.mounted && current()) navigator.pop();
              },
              onNavigate: (route) async {
                if (navigator.mounted && current()) navigator.pop(route);
              },
              onConnection: () async {
                if (navigator.mounted && current()) navigator.pop('space');
              },
            ),
          ),
        ),
      ),
    );
    if (destination == null || !current()) return;
    _articleHandoff = destination;
    _articleHandoffGeneration = generation;
    _navigator.currentState!.popUntil((route) => route.isFirst);
    if (!_openingFeature) _drainArticleHandoff(generation);
  }

  void _drainArticleHandoff(int generation) {
    if (_articleHandoffGeneration != generation) return;
    final destination = _articleHandoff;
    _articleHandoff = null;
    _articleHandoffGeneration = null;
    if (destination == null || destination == 'home') return;
    // Deferral also covers recent-resource branches that return inside try.
    scheduleMicrotask(() {
      if (mounted &&
          generation == _spaceGeneration &&
          !_local &&
          !_showConnection &&
          !_openingFeature) {
        unawaited(_navigate(destination));
      }
    });
  }

  Future<void> _openArticleModule() async {
    if (_openingFeature || _local || _showConnection) return;
    final client = _client;
    if (client == null) return;
    _openingFeature = true;
    final generation = _spaceGeneration;
    String? destination;
    try {
      final profile = await client.get('/api/profile');
      final member = profile['member_id'];
      if (member is! int || member <= 0) {
        throw const FormatException('Invalid server member identity');
      }
      if (!mounted || generation != _spaceGeneration || _showConnection) return;
      final articleContext = _navigator.currentContext;
      final articleRevision = client.sessionRevision;
      bool articleCurrent() =>
          mounted &&
          !_local &&
          !_showConnection &&
          generation == _spaceGeneration &&
          identical(client, _client) &&
          client.sessionRevision == articleRevision;
      if (articleContext == null || !articleContext.mounted) return;
      if (!await _protectedArticleModuleMayOpen(
            articleContext,
            client,
            member,
            articleCurrent,
          ) ||
          !articleCurrent()) {
        return;
      }
      final navigator = _navigator.currentState!;
      destination = await navigator.push<String>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            body: SafeArea(
              child: ArticleWebPage(
                client: client,
                memberId: member,
                english: _english,
                isCurrentScope: () =>
                    mounted &&
                    !_local &&
                    !_showConnection &&
                    generation == _spaceGeneration &&
                    identical(_client, client),
                onNavigate: (route) async {
                  if (navigator.mounted) navigator.pop(route);
                },
                onConnection: () async {
                  if (navigator.mounted) navigator.pop('space');
                },
              ),
            ),
          ),
        ),
      );
      if (mounted) setState(() => _homeRevision++);
    } catch (_) {
      if (mounted && generation == _spaceGeneration) {
        ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
          SnackBar(
            content: Text(_english ? 'Unable to open articles.' : '暂时无法打开文章。'),
          ),
        );
      }
    } finally {
      _openingFeature = false;
    }
    if (destination != null &&
        destination != 'home' &&
        mounted &&
        generation == _spaceGeneration &&
        !_showConnection) {
      await _navigate(destination);
    }
  }

  Future<void> _openDeviceSettings() async {
    if (_openingFeature || _showConnection) return;
    _openingFeature = true;
    final generation = _spaceGeneration;
    final local = _local;
    final client = _client;
    SettingsConnectionController? controller;
    String? destination;
    bool current() =>
        mounted &&
        !_showConnection &&
        generation == _spaceGeneration &&
        local == _local &&
        identical(_client, client);
    try {
      final temporary = await getTemporaryDirectory();
      if (!current()) return;
      if (!local && client == null) {
        throw StateError('Server session unavailable');
      }
      controller = SettingsConnectionController(
        local: local,
        server: local ? null : client!.baseUri.toString(),
        isCurrent: current,
        checkConnection: (abort) async {
          if (!current() || local || client == null) {
            throw StateError('Space changed');
          }
          final session = client.exportSession()['token'];
          final profile = await client.profileSettingsJson(abortTrigger: abort);
          if (!current() ||
              client.exportSession()['token'] != session ||
              profile['member_id'] is! int ||
              (profile['member_id'] as int) <= 0) {
            throw StateError('Connection identity changed');
          }
        },
      );
      destination = await _navigator.currentState!.push<String>(
        MaterialPageRoute(
          builder: (_) => DeviceSettingsPage(
            connection: controller!,
            english: _english,
            canBackup: local,
            onLocalModel: !local
                ? null
                : () async {
                    if (!current() || _openingLocalModel) return;
                    _openingLocalModel = true;
                    try {
                      final store = await _ensureLocalStore();
                      bool owned() =>
                          current() &&
                          identical(_localStore, store) &&
                          !store.maintenance.retired;
                      if (!owned()) return;
                      final modelController = LocalModelSettingsController(
                        isCurrent: owned,
                        vault: LocalModelConfigVault(
                          namespace: store.path,
                          isCurrent: owned,
                          readValue: (key) => _storage.read(key: key),
                          writeValue: (key, value) async {
                            if (!owned()) throw const LocalModelScopeRetired();
                            await _storage.write(key: key, value: value);
                            await NativeRecoveryStorage.flush();
                          },
                        ),
                        probe: LocalModelProbe(),
                      );
                      _localModelController = modelController;
                      try {
                        await _navigator.currentState!.push<void>(
                          MaterialPageRoute(
                            builder: (_) => LocalModelSettingsPage(
                              controller: modelController,
                              english: _english,
                            ),
                          ),
                        );
                      } finally {
                        modelController.dispose();
                        if (identical(_localModelController, modelController)) {
                          _localModelController = null;
                        }
                      }
                    } catch (_) {
                      if (mounted && current()) {
                        ScaffoldMessenger.of(
                          _navigator.currentState!.context,
                        ).showSnackBar(
                          SnackBar(
                            content: Text(
                              _english
                                  ? 'Unable to open local model settings.'
                                  : '暂时无法打开本地模型配置。',
                            ),
                          ),
                        );
                      }
                    } finally {
                      _openingLocalModel = false;
                    }
                  },

            cache: OwnedDownloadCache(temporary),
            onLanguage: () async {
              await _setLanguage(!_english);
              return _english;
            },
            prepareSwitch: () async {
              await HtmlBrowserSession.closeActive();
              await _closeSpeech();
              if (!current()) throw StateError('Space changed');
            },
          ),
        ),
      );
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
          SnackBar(
            content: Text(
              _english ? 'Unable to open device settings.' : '暂时无法打开应用设置。',
            ),
          ),
        );
      }
    } finally {
      controller?.dispose();
      _openingFeature = false;
    }
    if (!current() || destination == null) return;
    try {
      if (destination == 'settings-local') {
        await _retireComplexSourceBeforeTransition();
        if (!mounted) return;
        setState(() {
          _advanceSpace();
          _accountBackground = null;
          _accountBackgroundImage = null;
          _local = true;
          _showConnection = false;
        });
      } else if (destination == 'settings-logout') {
        await _leaveServer();
      } else if (destination == 'space' || destination == 'local-backup') {
        await _navigate(destination);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
          SnackBar(
            content: Text(
              _english ? 'Switch did not complete. Retry.' : '切换尚未完成，请重试。',
            ),
          ),
        );
      }
    }
  }

  Future<void> _navigate(String route) async {
    final homeTask = _homeTargetId(route, 'home-task'),
        homeTopic = _homeTargetId(route, 'home-topic');
    final homeShare = _homeShareTarget(route);
    if (route == 'settings') {
      await _openDeviceSettings();
      return;
    }
    if (route == 'articles' && !_local) {
      await _openArticleModule();
      return;
    }
    if (route == 'local-backup') {
      await _openLocalBackup();
      return;
    }
    if ([
          'notes',
          'articles',
          'assistant',
          'tasks',
          'books',
          'bookmarks',
          'nav',
          'topics',
          'labels',
          'search',
          'images',
          'files',
          'create-resource',
          'trash',
          'public-feed',
          'public-notes',
          'profile',
        ].contains(route) ||
        _recentResource(route) != null ||
        homeTask != null ||
        homeTopic != null ||
        homeShare != null) {
      if ((['public-feed', 'public-notes', 'profile'].contains(route)) &&
          _local) {
        return;
      }
      if (_local && route == 'create-resource' && _owned15?.current == true) {
        await _openOwned15Creation(_owned15!, _spaceGeneration);
        return;
      }
      if (_openingFeature) return;
      _openingFeature = true;
      final generation = _spaceGeneration;
      final local = _local;
      final client = _client;
      AttachmentRepository? attachments;
      try {
        String namespace;
        var memberId = 1;
        var isAdmin = false;
        if (local) {
          await _ensureLocalStore();
          namespace = _localStore!.dataPaths!.draftNamespace;
        } else {
          final profile = await client!.get('/api/profile');
          final member = profile['member_id'];
          if (member is! int || member <= 0) {
            throw const FormatException('Invalid server member identity');
          }
          memberId = member;
          isAdmin = profile['role'] == 0;
          namespace = jsonEncode([client.baseUri.toString(), member]);
        }
        attachments = local
            ? LocalAttachments(
                _localStore!.dataPaths!.attachments,
                maintenance: _localStore!.maintenance,
              )
            : RemoteAttachments(client!);
        // All local readers and writers use the same resolved resource layout.
        final driveRoot = route == 'files' && local
            ? _localStore!.dataPaths!.driveBlobs
            : null;
        final media = attachments;
        final drafts = DraftVault(
          maintenance: _localDraftMaintenance(
            route == 'articles'
                ? jsonEncode([namespace, 'article'])
                : namespace,
          ),
          namespace: route == 'articles'
              ? jsonEncode([namespace, 'article'])
              : namespace,
          readValue: (key) => _storage.read(key: key),
          writeValue: _writeNativeEditorDraft,
          deleteValue: _deleteNativeEditorDraft,
        );
        if (!mounted || generation != _spaceGeneration || _showConnection) {
          return;
        }
        final sourceStore = local ? _localStore : null;
        final sourceRevision = client?.sessionRevision;
        bool sourceOwned() =>
            mounted &&
            !_showConnection &&
            generation == _spaceGeneration &&
            _local == local &&
            (local
                ? identical(_localStore, sourceStore) &&
                      sourceStore?.maintenance.retired == false
                : identical(_client, client) &&
                      client?.sessionRevision == sourceRevision);
        Future<void> openAssistantSource(Map<String, Object?> source) async {
          if (!sourceOwned()) throw StateError('Source space retired');
          final id = source['id'], kind = source['kind'];
          if (id is! int || id <= 0) {
            throw const FormatException('Invalid source identity');
          }
          final context = _navigator.currentState!.overlay!.context;
          if (kind == 'topic') {
            await _navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => _topicsFeature(
                  initialTopicId: id,
                  local: local,
                  client: client,
                  memberId: memberId,
                  isAdmin: isAdmin,
                  namespace: namespace,
                  attachments: media,
                ),
              ),
            );
            return;
          }
          final opener = _nativeOpener(
            local: local,
            client: client,
            memberId: memberId,
            isAdmin: isAdmin,
            namespace: namespace,
            attachments: media,
          );
          if (kind == 'book' || kind == 'note' || kind == 'article') {
            await opener.openLabel(
              context,
              LabelResource(
                id: id,
                type: kind == 'book'
                    ? LabelResourceType.book
                    : LabelResourceType.blog,
                title: '',
              ),
              resolveCollection: (id) async {
                final Object? actual = local
                    ? await sourceStore!.noteCollectionOf(id)
                    : (await client!.articleMetadata(id))['blog_type'];
                if (!sourceOwned()) throw StateError('Source space retired');
                if (actual == 'note') return NoteCollection.note;
                if (actual == 'article') return NoteCollection.article;
                throw const FormatException('Unknown source collection');
              },
            );
          } else {
            final types = TopicResourceType.values.where(
              (type) => type.name == kind,
            );
            if (types.length != 1) {
              throw const FormatException('Invalid source kind');
            }
            await opener.open(context, types.single, id);
          }
        }

        if (homeTask != null || homeTopic != null) {
          if (homeTask != null) {
            await _nativeOpener(
              local: local,
              client: client,
              memberId: memberId,
              isAdmin: isAdmin,
              namespace: namespace,
              attachments: media,
            ).open(
              _navigator.currentState!.overlay!.context,
              TopicResourceType.task,
              homeTask,
            );
          } else {
            await _navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => _topicsFeature(
                  initialTopicId: homeTopic,
                  local: local,
                  client: client,
                  memberId: memberId,
                  isAdmin: isAdmin,
                  namespace: namespace,
                  attachments: media,
                ),
              ),
            );
          }
          if (mounted && generation == _spaceGeneration) {
            setState(() => _homeRevision++);
          }
          return;
        }
        final recent = _recentResource(route);
        if (recent != null) {
          final opener = _nativeOpener(
            local: local,
            client: client,
            memberId: memberId,
            isAdmin: isAdmin,
            namespace: namespace,
            attachments: media,
          );
          await opener.openLabel(
            _navigator.currentState!.overlay!.context,
            recent,
            resolveCollection: (id) async {
              Object? value;
              if (local) {
                value = await _localStore!.noteCollectionOf(id);
              } else {
                value = (await client!.articleMetadata(id))['blog_type'];
              }
              if (value == 'note') return NoteCollection.note;
              if (value == 'article') return NoteCollection.article;
              throw StateError('Unknown resource collection');
            },
          );
          if (mounted && generation == _spaceGeneration) {
            setState(() => _homeRevision++);
          }
          return;
        }
        if (route == 'create-resource') {
          await _resourceCreator(
            local: local,
            client: client,
            memberId: memberId,
            isAdmin: isAdmin,
            namespace: namespace,
            attachments: media,
          ).open(_navigator.currentState!.overlay!.context);
          if (mounted && generation == _spaceGeneration) {
            setState(() => _homeRevision++);
          }
          return;
        }
        if (route == 'assistant' && local) {
          final store = _localStore!;
          bool owned() =>
              mounted &&
              !_showConnection &&
              generation == _spaceGeneration &&
              _local &&
              identical(_localStore, store) &&
              !store.maintenance.retired;
          Future<void> write(String key, String value) async {
            if (!owned()) throw const LocalModelScopeRetired();
            await _storage.write(key: key, value: value);
            await NativeRecoveryStorage.flush();
            if (!owned()) throw const LocalModelScopeRetired();
          }

          final config = await LocalModelConfigVault(
            namespace: store.path,
            isCurrent: owned,
            readValue: (key) => _storage.read(key: key),
            writeValue: write,
          ).read();
          if (!owned() || !mounted) return;
          if (config == null) {
            ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
              SnackBar(
                content: Text(
                  _english
                      ? 'Configure a local model in Settings first.'
                      : '请先在设置中配置本地模型。',
                ),
              ),
            );
            return;
          }
          final bindingVault = LocalAssistantBinding(
            namespace: store.path,
            isCurrent: owned,
            readValue: (key) => _storage.read(key: key),
            writeValue: write,
          );
          String binding;
          try {
            binding = await bindingVault.open(config);
          } on LocalAssistantBindingCorrupt {
            if (!owned() || !mounted) return;
            final reset = await showDialog<bool>(
              context: _navigator.currentState!.overlay!.context,
              builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(
                  _english ? 'Conversation record needs recovery' : '会话记录需要恢复',
                ),
                content: Text(
                  _english
                      ? 'The local conversation link is unreadable. Start an empty conversation? Local resources and model settings are retained. Old context will not be sent.'
                      : '本地会话关联无法读取。重新建立空白会话？本地资料和模型配置保留，旧上下文不会发送给模型。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(_english ? 'Back' : '返回'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(
                      _english ? 'Start empty conversation' : '建立空白会话',
                    ),
                  ),
                ],
              ),
            );
            if (reset != true || !owned()) return;
            binding = await bindingVault.reset(config);
          }
          if (!owned()) return;
          final assistantLedger = _assistantLedger(store, binding, owned);
          final repository = LocalAssistantRepository(
            draftLedger: assistantLedger,
            canForgetResolved: (record) =>
                _canForgetAssistantDraft(store, binding, owned, record),
            sessionId: binding,
            transport: LocalModelStreamTransport(config, isCurrent: owned),
            knowledge: LocalAssistantKnowledge(
              store,
              permitted: () => config.allowKnowledge,
              isCurrent: owned,
            ),
            allowKnowledge: config.allowKnowledge,
            isCurrent: owned,
          );
          _localAssistant = repository;
          try {
            await _navigator.currentState!.push<void>(
              MaterialPageRoute(
                builder: (_) => AssistantPage(
                  local: true,
                  onForgetLocalDraft: repository.forgetResolved,
                  onEditLocalDraft: (draftId) async {
                    final draftContext =
                        _navigator.currentState!.overlay!.context;
                    final records = await assistantLedger.load();
                    if (!owned() || !draftContext.mounted) {
                      throw const LocalAssistantDraftOwnerRetired();
                    }
                    final draft = records
                        .where((record) => record.id == draftId)
                        .single;
                    await _editLocalAssistantDraft(
                      draftContext,
                      store,
                      generation,
                      LocalAssistantWriteMarker(
                        namespace: namespace,
                        bindingId: binding,
                        draftId: draft.id,
                        kind: draft.payload.kind,
                      ),
                    );
                  },
                  modelLabel: config.model,
                  knowledgeGranted: config.allowKnowledge,
                  repository: repository,
                  english: _english,
                  attachments: media,
                  onSpeak: (markdown) => _openSpeech(
                    markdown,
                    _english ? 'AI reply' : 'AI 回复',
                    _english ? 'Local assistant' : '本地助手',
                  ),
                  vault: AssistantConversationVault(
                    namespace: jsonEncode([
                      'local-assistant',
                      store.path,
                      binding,
                    ]),
                    readValue: (key) async {
                      if (!owned()) throw const LocalModelScopeRetired();
                      return _storage.read(key: key);
                    },
                    writeValue: write,
                    deleteValue: (key) async {
                      if (!owned()) throw const LocalModelScopeRetired();
                      await _storage.delete(key: key);
                      await NativeRecoveryStorage.flush();
                    },
                  ),
                  onOpenSource: openAssistantSource,
                ),
              ),
            );
            if (sourceOwned()) setState(() => _homeRevision++);
          } finally {
            repository.close();
            if (identical(_localAssistant, repository)) _localAssistant = null;
          }
          return;
        }
        await _navigator.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => route == 'trash'
                ? TrashPage(
                    repository: local
                        ? LocalTrashRepository(_localStore!)
                        : RemoteTrashRepository(client!, memberId: memberId),
                    english: _english,
                    local: local,
                  )
                : route == 'profile'
                ? ProfileFeature(
                    client: client!,
                    memberId: memberId,
                    english: _english,
                    onLanguage: _setLanguage,
                    onBackgroundApplied: (value, bytes) async {
                      if (!mounted ||
                          _spaceGeneration != generation ||
                          !identical(_client, client)) {
                        return;
                      }
                      setState(() {
                        _accountBackground = value;
                        _accountBackgroundImage = bytes;
                      });
                    },
                    persistSession: () =>
                        _persistClientSession(client, generation),
                    verifierFactory: widget.clientFactory,
                    onLogout: _leaveServer,
                    onNavigate: (destination) {
                      if (!{
                        'home',
                        'notes',
                        'bookmarks',
                        'files',
                      }.contains(destination)) {
                        return;
                      }
                      _profileDestination = destination;
                      _navigator.currentState!.popUntil(
                        (route) => route.isFirst,
                      );
                    },
                  )
                : route == 'public-notes'
                ? PublicNotesFeature(
                    onSpeakSelection: (selection, title, path) =>
                        _openSpeech('', title, path, selection: selection),
                    isCurrentScope: () =>
                        mounted &&
                        generation == _spaceGeneration &&
                        !_local &&
                        !_showConnection &&
                        identical(client, _client),
                    client: client!,
                    onSpeak: _openSpeech,
                    english: _english,
                  )
                : route == 'public-feed' || homeShare != null
                ? PublicSharesFeature(
                    protectedServices: ProtectedSharedServices(
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                      flush: NativeRecoveryStorage.flush,
                      listKeys: nativeProtectedSharedKeys,
                      registerOwner: (owner) {
                        if (_complexSourceSwitching ||
                            !mounted ||
                            generation != _spaceGeneration ||
                            _local ||
                            _showConnection ||
                            !identical(client, _client)) {
                          unawaited(owner.retire());
                          throw StateError('Protected shared owner retired');
                        }
                        _protectedComplexOwners.add(owner);
                      },
                      unregisterOwner: (owner) =>
                          _protectedComplexOwners.remove(owner),
                    ),
                    onSpeakSelection: (selection, title, path) =>
                        _openSpeech('', title, path, selection: selection),
                    sourceIoScope: _complexSourceOwner.current,
                    isCurrentScope: () =>
                        mounted &&
                        generation == _spaceGeneration &&
                        !_local &&
                        !_showConnection &&
                        identical(client, _client),
                    initialReference: homeShare,
                    client: client!,
                    english: _english,
                    onSpeak: _openSpeech,
                    onCreate: () async {
                      await _resourceCreator(
                        local: false,
                        client: client,
                        memberId: memberId,
                        isAdmin: isAdmin,
                        namespace: namespace,
                        attachments: media,
                      ).open(_navigator.currentState!.overlay!.context);
                    },
                  )
                : route == 'files'
                ? DriveFeature(
                    key: ValueKey((
                      namespace,
                      generation,
                      client?.sessionRevision,
                    )),
                    pageBuilder: local
                        ? null
                        : (repository, vault) => OwnedRemoteEntryLoader(
                            create: (routeCurrent) =>
                                createRemoteDriveRecoveryEntry(
                                  client: client!,
                                  scope: DriveOperationScope(
                                    server: client.baseUri.toString(),
                                    member: memberId,
                                    binding: entry_crypto.sha256
                                        .convert(utf8.encode(namespace))
                                        .toString()
                                        .substring(0, 32),
                                  ),
                                  repository: repository,
                                  vault: vault,
                                  readValue: (key) => _storage.read(key: key),
                                  writeValue: _writeNativeEditorDraft,
                                  deleteValue: _deleteNativeEditorDraft,
                                  flush: NativeRecoveryStorage.flush,
                                  isCurrent: () =>
                                      sourceOwned() && routeCurrent(),
                                  english: _english,
                                  beforePlay: () async {
                                    final speech = _speech;
                                    if (speech != null) {
                                      await (await speech).controller.pause();
                                    }
                                  },
                                ),
                            retire: retireRemoteDriveEntry,
                          ),
                    createRepository: () => local
                        ? LocalDriveRepository(_localStore!, driveRoot!)
                        : RemoteDriveRepository(client!),
                    vault: FileDraftVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    beforePlay: () async {
                      final speech = _speech;
                      if (speech != null) {
                        await (await speech).controller.pause();
                      }
                    },
                  )
                : route == 'images'
                ? ImagesFeature(
                    createOwner: () => _newImageLibraryOwner(sourceOwned),
                    ownerScope: (
                      namespace,
                      generation,
                      client?.sessionRevision,
                    ),
                    english: _english,
                    createRepository: () => local
                        ? LocalImagesRepository(
                            _localStore!,
                            media as LocalAttachments,
                            dimensionsReader: nativeImageDimensions,
                            isCurrentScope: () =>
                                !_complexSourceSwitching && sourceOwned(),
                          )
                        : RemoteImagesRepository(
                            client!,
                            isCurrentScope: () =>
                                !_complexSourceSwitching && sourceOwned(),
                          ),
                  )
                : route == 'search'
                ? _searchFeature(
                    local: local,
                    client: client,
                    memberId: memberId,
                    isAdmin: isAdmin,
                    namespace: namespace,
                    attachments: media,
                  )
                : route == 'labels'
                ? _labelsFeature(
                    local: local,
                    client: client,
                    memberId: memberId,
                    isAdmin: isAdmin,
                    namespace: namespace,
                    attachments: media,
                  )
                : route == 'topics'
                ? _topicsFeature(
                    local: local,
                    client: client,
                    memberId: memberId,
                    isAdmin: isAdmin,
                    namespace: namespace,
                    attachments: media,
                  )
                : route == 'nav'
                ? NavigationPage(
                    faviconIsCurrent: sourceOwned,
                    repository: local
                        ? LocalNavigationRepository(_localStore!)
                        : RemoteNavigationRepository(client!),
                    bookmarks: local
                        ? LocalBookmarksRepository(_localStore!)
                        : _recoverableBookmarks(
                            client: client!,
                            namespace: namespace,
                            memberId: memberId,
                            isAdmin: isAdmin,
                            isCurrent: sourceOwned,
                          ),
                    labels: local
                        ? LocalLabelsRepository(_localStore!)
                        : RemoteLabelsRepository(client!),
                    drafts: BookmarkDraftVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    preferences: NavigationPreferencesVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    english: _english,
                    local: local,
                  )
                : route == 'bookmarks'
                ? BookmarksPage(
                    recoverCreation: local
                        ? null
                        : () => openBookmarkCreationRecovery(
                            context: context,
                            client: client!,
                            memberId: memberId,
                            namespace: namespace,
                            read: (key) => _storage.read(key: key),
                            write: (key, value) =>
                                _storage.write(key: key, value: value),
                            remove: (key) => _storage.delete(key: key),
                            flush: NativeRecoveryStorage.flush,
                            isCurrent: sourceOwned,
                            english: _english,
                          ),
                    faviconScopeKey: (
                      namespace,
                      generation,
                      client?.sessionRevision,
                    ),
                    faviconIsCurrent: sourceOwned,
                    repository: local
                        ? LocalBookmarksRepository(_localStore!)
                        : _recoverableBookmarks(
                            client: client!,
                            namespace: namespace,
                            memberId: memberId,
                            isAdmin: isAdmin,
                            isCurrent: sourceOwned,
                          ),
                    labelsRepository: local
                        ? LocalLabelsRepository(_localStore!)
                        : RemoteLabelsRepository(client!),
                    vault: BookmarkDraftVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    english: _english,
                    local: local,
                  )
                : route == 'books'
                ? BooksFeature(
                    onCreateExcerpt: _documentExcerptAction(
                      local: local,
                      client: client,
                      memberId: memberId,
                      namespace: namespace,
                      attachments: media,
                      isCurrent: sourceOwned,
                    ),
                    readingFingerprint: _documentReadingFingerprint(
                      local: local,
                      client: client,
                      memberId: memberId,
                      namespace: namespace,
                      isCurrent: sourceOwned,
                    ),
                    boundedReader: _documentReader(
                      local: local,
                      client: client,
                      isCurrent: sourceOwned,
                    ),
                    onEditComplexDocument: _documentComplexWriter(
                      local: local,
                      client: client,
                      memberId: memberId,
                      namespace: namespace,
                      isCurrent: sourceOwned,
                    ),
                    ownerScope: (
                      namespace,
                      generation,
                      client?.sessionRevision,
                    ),
                    isCurrentScope: sourceOwned,
                    onCreateBook: local
                        ? null
                        : (context, repository, labels, vault) async {
                            if (!context.mounted ||
                                !sourceOwned() ||
                                vault == null) {
                              return;
                            }
                            final page = await createRemoteBookEntry(
                              client: client!,
                              scope: BookCreationScope(
                                server: client.baseUri.toString(),
                                memberId: memberId,
                                binding: entry_crypto.sha256
                                    .convert(utf8.encode(namespace))
                                    .toString()
                                    .substring(0, 32),
                              ),
                              repository: repository,
                              labelsRepository: labels,
                              ordinaryDrafts: vault,
                              readValue: (key) => _storage.read(key: key),
                              writeValue: _writeNativeEditorDraft,
                              deleteValue: _deleteNativeEditorDraft,
                              flush: NativeRecoveryStorage.flush,
                              isCurrent: sourceOwned,
                              english: _english,
                            );
                            if (!context.mounted || !sourceOwned()) {
                              retireRemoteBookEntry(page);
                              return;
                            }
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(builder: (_) => page),
                            );
                          },
                    onShareBook: local
                        ? null
                        : (context, book) => openOwnerSharing(
                            context,
                            client: client!,
                            kind: PublicShareKind.book,
                            id: book.id!,
                            title: book.name,
                            english: _english,
                            onSpeak: _openSpeech,
                          ),
                    onShareDocument: local
                        ? null
                        : (context, item) => openOwnerSharing(
                            context,
                            client: client!,
                            kind: PublicShareKind.document,
                            id: item.id,
                            title: item.name,
                            english: _english,
                            onSpeak: _openSpeech,
                          ),
                    onSpeakSelection: (selection, title, path) =>
                        _openSpeech('', title, path, selection: selection),
                    onSpeak: _openSpeech,
                    notes: local
                        ? _homeNotes(_localStore!)
                        : RemoteNotesRepository(client!),
                    server: local ? null : client!.baseUri,
                    positions: ReadingPositionVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    excerptDrafts: (id) => DraftVault(
                      maintenance: _localDraftMaintenance(
                        jsonEncode([namespace, 'excerpt', id]),
                      ),
                      namespace: jsonEncode([namespace, 'excerpt', id]),
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    books: local
                        ? _homeBooks(_localStore!)
                        : RemoteBooksRepository(client!),
                    documents: local
                        ? _homeDocuments(_localStore!)
                        : RemoteDocumentsRepository(client!),
                    labels: local
                        ? LocalLabelsRepository(_localStore!)
                        : RemoteLabelsRepository(client!),
                    bookDrafts: BookDraftVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    documentDrafts: DraftVault(
                      maintenance: _localDraftMaintenance(
                        jsonEncode([namespace, 'document']),
                      ),
                      namespace: jsonEncode([namespace, 'document']),
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    attachments: media,
                    english: _english,
                  )
                : route == 'tasks'
                ? TasksPage(
                    recoverCreation: local
                        ? () => _recoverLocalTaskCreation(
                            store: _localStore!,
                            namespace: namespace,
                            isCurrent: sourceOwned,
                          )
                        : () => _recoverTaskCreation(
                            client: client!,
                            memberId: memberId,
                            namespace: namespace,
                            isCurrent: sourceOwned,
                          ),
                    isCurrentScope: () =>
                        sourceOwned() && !_complexSourceSwitching,
                    editorActionsFactory: local
                        ? null
                        : _taskEditorActionsFactory(
                            client: client!,
                            memberId: memberId,
                            namespace: namespace,
                            isCurrent: sourceOwned,
                          ),
                    repository: local
                        ? _recoverableLocalTasks(
                            store: _localStore!,
                            namespace: namespace,
                            isCurrent: sourceOwned,
                          )
                        : _recoverableTasks(
                            client: client!,
                            memberId: memberId,
                            namespace: namespace,
                            isCurrent: () =>
                                sourceOwned() && !_complexSourceSwitching,
                          ),
                    vault: TaskDraftVault(
                      maintenance: _localDraftMaintenance(namespace),
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    attachments: media,
                    english: _english,
                  )
                : route != 'assistant'
                ? OwnedNoteListScope(
                    identity: (
                      namespace,
                      generation,
                      route == 'articles' ? 'article' : 'note',
                      sourceRevision,
                      local,
                    ),
                    isCurrent: () => sourceOwned() && !_complexSourceSwitching,
                    create: (current) => local
                        ? OwnedNoteListBinding.local(
                            repository: _homeNotes(
                              sourceStore!,
                              collection: route == 'articles'
                                  ? NoteCollection.article
                                  : NoteCollection.note,
                            ),
                            isCurrent: current,
                          )
                        : OwnedNoteListBinding.remote(
                            client: client!,
                            memberId: memberId,
                            collection: route == 'articles'
                                ? NoteCollection.article
                                : NoteCollection.note,
                            scope: jsonEncode([
                              'note-list',
                              namespace,
                              generation,
                              sourceRevision,
                            ]),
                            isCurrent: current,
                          ),
                    builder: (context, binding) => NotesPage(
                      onOpenOwnedComplex: local || route == 'articles'
                          ? null
                          : _ownedComplexNoteWriter(
                              client: client!,
                              memberId: memberId,
                              namespace: namespace,
                              isCurrent: sourceOwned,
                            ),
                      onOpenExisting: (id) async {
                        if (!context.mounted || !sourceOwned()) return;
                        await _nativeOpener(
                          local: local,
                          client: client,
                          memberId: memberId,
                          isAdmin: isAdmin,
                          namespace: namespace,
                          attachments: media,
                        ).open(
                          context,
                          route == 'articles'
                              ? TopicResourceType.article
                              : TopicResourceType.note,
                          id,
                        );
                      },
                      sourceIoScope: local ? _complexSourceOwner.current : null,
                      onCreateArticleMarkdown: local
                          ? null
                          : (context) async {
                              if (!context.mounted || !sourceOwned()) return;
                              await _createOwnedArticle(
                                context,
                                local: false,
                                client: client,
                                memberId: memberId,
                                isAdmin: isAdmin,
                                namespace: namespace,
                                attachments: media,
                                repository: binding.repository,
                                drafts: drafts,
                                isCurrent: sourceOwned,
                              );
                            },
                      onCreateMarkdown: local || route == 'articles'
                          ? null
                          : (context) async {
                              if (!context.mounted || !sourceOwned()) return;
                              final collection = route == 'articles'
                                  ? NoteCollection.article
                                  : NoteCollection.note;
                              final page =
                                  await createRemoteMarkdownCreationEditor(
                                    client: client!,
                                    memberId: memberId,
                                    namespace: namespace,
                                    collection: collection,
                                    repository: RemoteNotesRepository(
                                      client,
                                      collection: collection,
                                    ),
                                    drafts: drafts,
                                    attachments: media,
                                    english: _english,
                                    readValue: (key) => _storage.read(key: key),
                                    writeValue: _writeNativeEditorDraft,
                                    deleteValue: _deleteNativeEditorDraft,
                                    flush: NativeRecoveryStorage.flush,
                                    isCurrent: sourceOwned,
                                  );
                              if (!context.mounted || !sourceOwned()) {
                                retireRemoteMarkdownCreationEditor(page);
                                return;
                              }
                              await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(builder: (_) => page),
                              );
                            },
                      isCurrentScope: () =>
                          sourceOwned() && !_complexSourceSwitching,
                      collection: route == 'articles'
                          ? NoteCollection.article
                          : NoteCollection.note,
                      repository: binding.repository,
                      listSource: binding.source,
                      pinActions: binding.actions,
                      onShareSettings: local
                          ? null
                          : (note) => openOwnerSharing(
                              _navigator.currentState!.overlay!.context,
                              client: client!,
                              kind: PublicShareKind.blog,
                              id: note.id,
                              title: note.title,
                              english: _english,
                              onSpeak: _openSpeech,
                            ),
                      english: _english,
                      drafts: drafts,
                      attachments: media,
                    ),
                  )
                : AssistantPage(
                    onOpenSource: openAssistantSource,
                    onSpeak: (markdown) => _openSpeech(
                      markdown,
                      _english ? 'AI reply' : 'AI 回复',
                      _english ? 'AI assistant' : 'AI 助手',
                    ),
                    repository: AssistantRepository(client!),
                    vault: AssistantConversationVault(
                      namespace: namespace,
                      readValue: (key) => _storage.read(key: key),
                      writeValue: (key, value) =>
                          _storage.write(key: key, value: value),
                      deleteValue: (key) => _storage.delete(key: key),
                    ),
                    attachments: media,
                    english: _english,
                  ),
          ),
        );
        if (mounted) setState(() => _homeRevision++);
      } catch (error) {
        if (mounted && generation == _spaceGeneration) {
          ScaffoldMessenger.of(_navigator.currentState!.context).showSnackBar(
            SnackBar(
              content: Text(
                route == 'assistant'
                    ? (_english
                          ? 'Unable to open this assistant. Retry after checking local settings.'
                          : '暂时无法打开助手，请检查当前设置后重试。')
                    : error.toString(),
              ),
            ),
          );
        }
      } finally {
        attachments?.close();
        _openingFeature = false;
        _drainArticleHandoff(generation);
      }
      if (route == 'profile') {
        final destination = _profileDestination;
        _profileDestination = null;
        if (destination != null &&
            mounted &&
            generation == _spaceGeneration &&
            !_showConnection) {
          await _navigate(destination);
        }
      }
    }
    if (route == 'space') {
      try {
        await _retireComplexSourceBeforeTransition();
        if (!mounted) return;
        _advanceSpace();
        _accountBackground = null;
        _accountBackgroundImage = null;
        await _closeSpeech();
        if (mounted) setState(() => _showConnection = true);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(
            _navigator.currentState!.context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }
  }

  @override
  void dispose() {
    for (final owner in _protectedComplexOwners.toList()) {
      unawaited(owner.retire());
    }
    for (final reader in _ownedDocumentReaders) {
      reader.retire();
    }
    _ownedDocumentReaders.clear();
    for (final owner in _imageLibraryOwners.toList()) {
      unawaited(owner.retireAndDrain());
    }
    unawaited(_complexSourceOwner.close().catchError((Object _) {}));
    _localAssistant?.close();
    _localAssistant = null;
    _localModelController?.dispose();
    _homeAssetScope?.dispose();
    _notification?.cancel();
    unawaited(_closeSpeech().catchError((Object _) {}));
    _client?.close();
    final owned = _owned15;
    if (owned != null) unawaited(owned.retire().catchError((Object _) {}));
    for (final preparation in _owned15Preparations) {
      unawaited(preparation.retire().catchError((Object _) {}));
    }
    for (final inspection in _owned15Inspections) {
      unawaited(inspection.retire().catchError((Object _) {}));
    }
    if (_localStore?.maintenance.retired == false) _localStore!.close();
    super.dispose();
  }

  Widget _ordinaryHome() => HomePage(
    key: ValueKey('${_local ? 'local' : _server}:$_homeRevision'),
    strings: strings,
    load: _loadHome,
    dashboard: _homeDashboard(),
    onDashboardItem: _homeItemAction(),
    onDashboardAll: _homeAllAction(),
    onDashboardCustomize: _homeCustomizeAction(),
    onResetLocalPreferences: _resetHomePreferencesAction(),
    local: _local,
    onLanguage: _toggleLanguage,
    onNavigate: _homeNavigateAction(),
    canNavigate: (route) =>
        (route == 'local-backup' && _local) ||
        route == 'assistant' ||
        [
          'home',
          'space',
          'settings',
          'notes',
          'articles',
          'tasks',
          'books',
          'bookmarks',
          'nav',
          'topics',
          'labels',
          'search',
          'images',
          'files',
          'create-resource',
          'trash',
        ].contains(route) ||
        _recentResource(route) != null ||
        ([
              'assistant',
              'public-feed',
              'public-notes',
              'profile',
            ].contains(route) &&
            !_local),
  );

  Widget _ownedResolvedHome() => FutureBuilder<ResolvedLocalStorage>(
    future: _ensureLocalResolved(),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _coldLocalRecovery();
      final resolved = snapshot.data;
      if (resolved == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (resolved is OrdinaryResolvedLocalStorage) return _ordinaryHome();
      final owner = (resolved as Owned15ResolvedLocalStorage).owner;
      if (!owner.current) return _coldLocalRecovery();
      final generation = _spaceGeneration;
      return Owned15Feature(
        owner: owner,
        english: _english,
        isCurrent: () =>
            _localEpochCurrent(generation) && identical(_owned15, owner),
        openResource: (metadata) =>
            _openOwned15Resource(owner, generation, metadata),
        openBackup: () => _openOwned15Backup(owner, generation),
        openMigration: () => _openOwned15Migration(generation),
        openCreation: () => _openOwned15Creation(owner, generation),
        openCreationRecovery: () =>
            _openOwned15Creation(owner, generation, recoverOnly: true),
        onConnection: _localConnection,
      );
    },
  );

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'BookStark',
    debugShowCheckedModeBanner: false,
    navigatorKey: _navigator,
    theme: _accountBackground == null
        ? bookstarkTheme()
        : bookstarkTheme().copyWith(
            scaffoldBackgroundColor: Colors.transparent,
          ),
    builder: (context, child) => _accountBackground == null
        ? child!
        : AccountBackgroundScope(
            child: BackgroundSurface(
              preference: _accountBackground!,
              image: _accountBackgroundImage,
              child: child!,
            ),
          ),
    locale: Locale(_english ? 'en' : 'zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: _initializing
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : _showConnection
        ? ConnectionPage(
            strings: strings,
            onLanguage: _toggleLanguage,
            onLogin: _login,
            onLocal: () async {
              try {
                await _retireComplexSourceBeforeTransition();
                if (!mounted) return;
                setState(() {
                  _advanceSpace();
                  _accountBackground = null;
                  _accountBackgroundImage = null;
                  _local = true;
                  _showConnection = false;
                });
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    _navigator.currentState!.context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _english
                            ? 'Switch did not complete. Retry.'
                            : '切换尚未完成，请重试。',
                      ),
                    ),
                  );
                }
              }
            },
            onRegister: () => _accountForm(AccountForm.register),
            onForgot: () => _accountForm(AccountForm.forgot),
          )
        : _local && _localReviewRequired
        ? _coldLocalRecovery()
        : _local
        ? _ownedResolvedHome()
        : _ordinaryHome(),
  );
}
