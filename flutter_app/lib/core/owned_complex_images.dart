import 'dart:convert';
import 'package:http/http.dart' as http;
import 'native_local_article_attachment_picker.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'image_dimensions.dart';
import 'complex_editor_document.dart';
import 'local_complex_editor_controller.dart';
import 'native_recovery_storage.dart';
import 'owned_complex_resource_lease.dart';
import 'owned_complex_resources.dart';
import 'owned_complex_document_references.dart';
import 'owned_complex_image_upload_journal.dart';
import 'owned_complex_image_upload_controller.dart';
import 'owned_complex_image_picker_action.dart';
import 'owned_complex_server_images.dart';
import 'secure_record_store.dart';

/// Actual authenticated owner binding; HTTP callbacks are not assembled in Root.
/// The protected caller may inject its existing actual editor; no password/body
/// is stored in this metadata journal.
class OwnedComplexImages {
  OwnedComplexImages({
    required BookstarkClient client,
    required int memberId,
    required int resourceId,
    required int bookId,
    required bool note,
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
         bookId: bookId,
         note: note,
         kind: editor.baseline.document.kind,
         namespace: namespace,
         isCurrentScope: isCurrent,
       ) {
    if (editor.baseline.id != resourceId ||
        editor.baseline.collection !=
            (note ? 'remote-note' : 'remote-book-document') ||
        editor.baseline.document.kind == ComplexEditorKind.markdown ||
        editor.baseline.resourceFingerprint == null) {
      throw ArgumentError('Owned full-fingerprint editor required');
    }
    final ownerTag = crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'owned-image-journal-owner-v1',
              client.baseUri.toString(),
              memberId,
              namespace,
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
    journal = OwnedComplexImageUploadJournal(
      store: store,
      bindingId: lease.identity,
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
      final fingerprint = editor.baseline.resourceFingerprint;
      if (fingerprint == null) {
        throw StateError('Owned fingerprint unavailable');
      }
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
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(sharedPreferencesName: 'FlutterSecureStorage'),
  );
  final LocalComplexEditorController editor;
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

  bool get insertionSupported => {
    ComplexEditorKind.html,
    ComplexEditorKind.richdoc,
    ComplexEditorKind.spreadsheet,
    ComplexEditorKind.mindmap,
    ComplexEditorKind.drawing,
    ComplexEditorKind.presentation,
  }.contains(editor.edit.document.kind);
  Future<bool> verifyFreshSource() async {
    lease.guard();
    if (!editor.editable) return false;
    final baseline = editor.baseline;
    final actual = await lease.use(() => editor.repository.read(baseline.id));
    lease.guard();
    return editor.editable &&
        editor.baseline.same(baseline) &&
        actual.same(baseline);
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
