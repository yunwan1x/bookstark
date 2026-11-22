import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'bounded_note_text_reader.dart';
import 'complex_editor_document.dart';
import 'local_complex_notes_repository.dart';
import 'protected_owned_complex_journal.dart';

/// Read-only seven-kind source. Password never becomes part of a DTO/record.
/// The authenticated API callback must keep it in the bounded POST body only.
class ProtectedOwnedRecoveryReader {
  ProtectedOwnedRecoveryReader({
    required this.scope,
    required this.memberId,
    required this.resourceId,
    required this.isCurrent,
    required this.request,
    required String this._password,
  });
  final String scope;
  final int memberId, resourceId;
  final bool Function() isCurrent;
  final Future<Map<String, Object?>> Function(String password) request;
  String? _password;
  bool _closed = false;
  void _guard() {
    if (_closed || !isCurrent()) throw StateError('Protected recovery retired');
  }

  Future<ComplexNote> read() async {
    _guard();
    final envelope = await request(_password!);
    _guard();
    final data = envelope['data'];
    const keys = {
      'resource',
      'id',
      'book_id',
      'member_id',
      'kind',
      'title',
      'labels',
      'resource_fp',
      'source_base64',
      'bytes',
      'sha256',
      'blog_type',
      'protected',
    };
    if (envelope['code'] != 0 ||
        data is! Map ||
        data.length != keys.length ||
        data.keys.toSet().difference(keys).isNotEmpty ||
        data['resource'] != 'owned-blog-recovery' ||
        data['id'] != resourceId ||
        data['member_id'] != memberId ||
        data['book_id'] != 0 ||
        !const {'note', 'article'}.contains(data['blog_type']) ||
        data['protected'] is! bool ||
        data['title'] is! String ||
        data['kind'] is! String ||
        !const {
          'markdown',
          'html',
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(data['kind']) ||
        data['labels'] is! List ||
        (data['labels'] as List).length > 100 ||
        (data['labels'] as List).any((v) => v is! String) ||
        data['bytes'] is! int ||
        data['source_base64'] is! String ||
        data['resource_fp'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['resource_fp'] as String) ||
        data['sha256'] is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sha256'] as String)) {
      throw const FormatException('Invalid owned recovery source');
    }
    final kind = ComplexEditorKind.parse(data['kind'] as String);
    final limit =
        (kind == ComplexEditorKind.presentation ? 20 : 5) * 1024 * 1024;
    final encoded = data['source_base64'] as String;
    if ((data['bytes'] as int) < 0 ||
        (data['bytes'] as int) > limit ||
        encoded.length > ((limit + 2) ~/ 3) * 4 ||
        !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(encoded)) {
      throw const FormatException('Owned recovery source bound');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length != data['bytes'] ||
        bytes.length > limit ||
        base64Encode(bytes) != encoded ||
        sha256.convert(bytes).toString() != data['sha256']) {
      throw const FormatException('Owned recovery source digest mismatch');
    }
    final title = data['title'] as String,
        labels = (data['labels'] as List).cast<String>();
    ComplexEditorDocument.validateText(title);
    for (final label in labels) {
      ComplexEditorDocument.validateText(label);
    }
    if (utf8.encode(title).length > 65536 ||
        utf8.encode(jsonEncode(labels)).length > 60 * 1024) {
      throw const FormatException('Owned recovery metadata bound');
    }
    final source = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
    return ComplexNote(
      scope: scope,
      id: resourceId,
      collection: 'owned-blog-recovery',
      title: title,
      labels: labels,
      version: 0,
      document: ComplexEditorDocument.parse(kind, source),
      resourceFingerprint: data['resource_fp'] as String,
    );
  }

  ProtectedComplexObservation observation(
    ComplexNote value,
  ) => ProtectedComplexObservation(
    fingerprint: value.resourceFingerprint!,
    // Observation identity only. This reader never adopts a historical receipt;
    // retargeted resources can only be explicitly reviewed and ended.
    inputDigest: sha256
        .convert(
          utf8.encode(
            jsonEncode([
              scope,
              resourceId,
              value.document.kind.name,
              value.title,
              value.labels,
              value.document.source,
            ]),
          ),
        )
        .toString(),
  );
  void dispose() {
    _closed = true;
    _password = null;
  }
}
