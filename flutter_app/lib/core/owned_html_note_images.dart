import 'dart:convert';
import 'package:http/http.dart' as http;
import 'native_local_article_attachment_picker.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'image_dimensions.dart';
import 'complex_editor_document.dart';
import 'html_editor_controller.dart';
import 'html_recovery_vault.dart';
import 'html_notes_repository.dart';
import 'native_recovery_storage.dart';
import 'owned_complex_resource_lease.dart';
import 'owned_complex_resources.dart';
import 'owned_complex_document_references.dart';
import 'owned_complex_image_upload_journal.dart';
import 'owned_complex_image_upload_controller.dart';
import 'owned_complex_image_picker_action.dart';
import 'owned_complex_server_images.dart';
import 'secure_record_store.dart';

/// Dedicated existing HTML-note/article binding. Uses its real HTML baseline,
/// repository fingerprint and password-in-memory path, never a forged complex
/// resource. The image journal contains metadata only, not HTML or passwords.
/// Fresh checks retain the existing server's observed-baseline contract; this
/// adapter does not invent a transaction/CAS guarantee absent from HTML saves.
class OwnedHtmlNoteImages {
  OwnedHtmlNoteImages({
    required BookstarkClient client,
    required int memberId,
    required int resourceId,
    required String namespace,
    required bool Function() isCurrent,
    required this.editor,
    SecureRecordStore? journalStore,
    Future<void> Function()? flush,
    NativeLocalArticleAttachmentPicker? attachmentPicker,
    http.Client? resourceTransport,
    OwnedComplexImageValidator? imageValidator,
  }) : lease = OwnedComplexResourceLease(
         client: client,
         memberId: memberId,
         resourceId: resourceId,
         bookId: 0,
         note: true,
         kind: ComplexEditorKind.html,
         blogCollection: editor.baseline.metadata.collection,
         namespace: namespace,
         isCurrentScope: isCurrent,
       ) {
    if (editor.baseline.metadata.id != resourceId ||
        editor.baseline.metadata.memberId != memberId ||
        !{'note', 'article'}.contains(editor.baseline.metadata.collection)) {
      throw ArgumentError('Actual owned existing HTML baseline required');
    }
    final ownerTag = crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned-html-image-journal-owner-v1',
              client.baseUri.toString(),
              memberId,
            ]),
          ),
        )
        .toString();
    final store =
        journalStore ??
        SecureRecordStore(
          prefix: OwnedComplexImageUploadJournal.prefix,
          namespace: ownerTag,
          readValue: (key) => _storage.read(key: key),
          writeValue: (key, value) => _storage.write(key: key, value: value),
          deleteValue: (key) => _storage.delete(key: key),
        );
    // One stable storage slot for this actual blog ID across collection changes.
    // Full binding still contains collection: a changed type fails closed on read,
    // retaining the old unknown marker rather than opening a new POST lane.
    final storageId = crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned-html-image-document-v1',
              client.baseUri.toString(),
              memberId,
              resourceId,
            ]),
          ),
        )
        .toString();
    journal = OwnedComplexImageUploadJournal(
      store: store,
      bindingId: lease.identity,
      storageId: storageId,
      flush: flush ?? NativeRecoveryStorage.flush,
    );
    upload = OwnedComplexImageUploadController(
      journal: journal,
      lease: lease,
      validateReceipt: (root) {
        final data = root['data'];
        if (root['code'] is! int ||
            root['code'] != 0 ||
            data is! Map ||
            data['id'] is! int ||
            (data['id'] as int) <= 0 ||
            data['url'] is! String ||
            (data['url'] as String).length > 2048) {
          throw const FormatException('Invalid server image receipt');
        }
        final scope = _resources;
        if (scope == null) {
          throw StateError('Document resource scope unavailable');
        }
        final uri = scope.canonical(Uri.parse(data['url'] as String));
        final path = uri.pathSegments.sublist(
          client.baseUri.pathSegments.length,
        );
        if (path.first != 'upload-files') {
          throw const FormatException('Invalid uploaded image route');
        }
        return (id: data['id'] as int, url: uri);
      },
    );
    picker = OwnedComplexImagePickerAction(
      controller: upload,
      lease: lease,
      picker: attachmentPicker,
    );
    resourceFactory = (document) {
      lease.guard();
      final fingerprint = _fingerprint(editor.baseline);
      Set<Uri> references = {};
      resourceReferencesUnavailable = false;
      try {
        references = OwnedComplexDocumentReferences.capture(
          document,
          fullFingerprint: fingerprint,
        ).references;
      } on FormatException {
        resourceReferencesUnavailable = true;
      }
      // Resource bounds must not prevent opening/editing an otherwise valid source.
      // An incomplete allowlist grants nothing; the source itself remains exact.
      final result = OwnedComplexResources(
        lease: lease,
        documentReferences: references,
        sourceDigest: document.digest,
        transport: resourceTransport,
        validateImage: imageValidator,
      );
      if (result.rejectedReferences > 0) resourceReferencesUnavailable = true;
      _resources = result;
      return result;
    };
  }
  static String _fingerprint(HtmlNote note) => crypto.sha256
      .convert(
        utf8.encode(
          jsonEncode([
            note.metadata.id,
            note.metadata.memberId,
            note.metadata.collection,
            note.metadata.version,
            note.metadata.modifiedAt,
            note.metadata.protected,
            htmlNoteFingerprint(note),
          ]),
        ),
      )
      .toString();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
  );
  final HtmlEditorController editor;
  final OwnedComplexResourceLease lease;
  late final OwnedComplexImageUploadJournal journal;
  late final OwnedComplexImageUploadController upload;
  late final OwnedComplexImagePickerAction picker;
  late final OwnedComplexResources Function(ComplexEditorDocument)
  resourceFactory;
  OwnedComplexResources? _resources;
  bool initializationFailed = false, resourceReferencesUnavailable = false;
  Future<void> open() async {
    try {
      await upload.open();
    } catch (_) {
      initializationFailed = true;
    }
  }

  bool get insertionSupported => true;
  Future<bool> verifyFreshSource() async {
    lease.guard();
    if (!editor.canEdit || editor.hasPendingOperation) return false;
    final baseline = editor.baseline, expected = _fingerprint(editor.baseline);
    final actual = await lease.use(
      () => editor.repository.read(
        baseline.metadata.id,
        password: baseline.unlockPassword,
      ),
    );
    lease.guard();
    return editor.canEdit &&
        !editor.hasPendingOperation &&
        _fingerprint(editor.baseline) == expected &&
        _fingerprint(actual) == expected;
  }

  OwnedComplexServerImages get serverImages {
    lease.guard();
    final resources = _resources;
    if (resources == null) throw StateError('Resource scope unavailable');
    return OwnedComplexServerImages(lease: lease, resources: resources);
  }

  void approveExisting({required int id, required Uri url}) {
    lease.guard();
    final resources = _resources;
    if (resources == null) throw StateError('Resource scope unavailable');
    resources.approveConfirmedUpload(uploadId: id, uri: url);
  }

  Future<({Uri url, int width, int height})> prepareExplicitInsertion({
    required int id,
    required Uri url,
  }) async {
    approveExisting(id: id, url: url);
    final resources = _resources!;
    final image = await lease.use(() => resources.read(url));
    lease.guard();
    if (!image.mime.startsWith('image/')) {
      throw const FormatException('Raster image required');
    }
    final (width, height) = encodedImageDimensions(image.bytes);
    return (url: resources.canonical(url), width: width, height: height);
  }

  Future<void> retireAndDrain() async {
    lease.retire();
    _resources?.close();
    await picker.retireAndDrain();
  }
}
