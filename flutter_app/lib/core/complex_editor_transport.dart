import 'local_html_attachment_reference.dart';
import 'public_selection_protocol.dart';
import 'complex_reading_protocol.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/markdown_snapshot_selection.dart';

/// Only the owned, main-frame host exposes these bounded commands. No arbitrary
/// JavaScript, URLs, files or database operations cross this boundary.
typedef ComplexEditorCommand =
    Future<Object?> Function(String name, List<Object?> arguments);

class ComplexEditorSnapshot {
  ComplexEditorSnapshot._(
    this._owner,
    this.id,
    this.generation,
    this.revision,
    this.document,
    this.markdownSelection,
  );
  final ComplexEditorTransport _owner;
  final String id;
  final int generation, revision;
  final ComplexEditorDocument document;
  final MarkdownSnapshotSelection? markdownSelection;
  bool _released = false;
}

class ComplexEditorTransport {
  ComplexEditorTransport(this._command);
  factory ComplexEditorTransport.channel(MethodChannel channel) =>
      ComplexEditorTransport(
        (name, arguments) => channel.invokeMethod<Object?>('command', {
          'name': name,
          'arguments': arguments,
        }),
      );
  final ComplexEditorCommand _command;
  static const chunkBytes = 262144;
  ComplexEditorDocument? _document;
  int _epoch = 0;
  int? _generation;

  /// Generation from the validated ready receipt; null before load/after retire.
  int? get generation => _generation;
  bool _busy = false, _closed = false;
  bool _readingOnly = false;
  PublicSelectionBinding? _publicSelection;
  PublicSelectionBinding? get publicSelectionBinding =>
      _closed || !_readingOnly ? null : _publicSelection;
  ComplexReadingBinding? _reading;
  ComplexReadingBinding? get readingBinding =>
      _closed || !_readingOnly ? null : _reading;
  bool _localMarkdownImages = false;
  bool _localDrawingImages = false;
  bool _localDrawingResourceFailed = false;
  bool get localDrawingResourceFailed => _localDrawingResourceFailed;
  bool _localPresentationImages = false;
  bool _localPresentationResourceFailed = false;
  bool get localPresentationResourceFailed => _localPresentationResourceFailed;
  bool _sourceIoEditable = false;
  String? _localHtmlAttachmentGrant;
  String? _localHtmlAttachmentSnapshot, _localHtmlAttachmentSource;
  int? _localHtmlAttachmentGeneration;
  String? _reviewExportDigest;
  int? _reviewExportBytes;

  Future<T> _exclusive<T>(Future<T> Function(int epoch) work) async {
    if (_closed || _busy) throw StateError('Editor transport unavailable');
    _busy = true;
    final epoch = _epoch;
    try {
      final result = await work(epoch);
      _check(epoch);
      return result;
    } finally {
      _busy = false;
    }
  }

  void _check(int epoch) {
    if (_closed || epoch != _epoch) throw StateError('Editor session ended');
  }

  Future<Object?> _call(String name, List<Object?> arguments, int epoch) async {
    _check(epoch);
    try {
      final result = await _command(name, arguments);
      _check(epoch);
      return result;
    } catch (error) {
      if (kDebugMode) {
        const commands = {
          'beginLoad',
          'appendLoad',
          'commitLoad',
          'abortLoad',
          'bindReading',
          'bindPublicSelection',
          'setInputLocked',
        };
        const codes = {
          'error',
          'editor_timeout',
          'editor_command_failed',
          'editor_retired',
          'invalid_command',
          'editor_unavailable',
        };
        final operation = commands.contains(name) ? name : 'command';
        final kind = error is PlatformException
            ? (codes.contains(error.code) ? error.code : 'platform_error')
            : error.runtimeType.toString();
        debugPrint('complex_editor_command_failure:$operation:$kind');
      }
      rethrow;
    }
  }

  Future<void> load(
    ComplexEditorDocument document, {
    bool readOnly = true,
    bool sourceReadOnly = false,
    bool english = false,
    String title = '',
    Uri? publicResourceRoot,
    bool sharedMarkdownEditing = false,
    bool publicComplexReadOnly = false,
    bool sharedComplexEditing = false,
    bool localMarkdownImages = false,
    bool ownedMarkdownSourceIo = false,
    bool ownedReviewExport = false,
    String? ownedReviewExportDigest,
    int? ownedReviewExportBytes,
    String? localDrawingScope,
    Map<String, String>? localDrawingResources,
    String? localPresentationScope,
    Map<String, String>? localPresentationResources,
  }) => _exclusive((epoch) async {
    if ((ownedReviewExportDigest != null || ownedReviewExportBytes != null) &&
        (!ownedReviewExport ||
            ownedReviewExportDigest == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(ownedReviewExportDigest) ||
            ownedReviewExportBytes == null ||
            ownedReviewExportBytes < 0 ||
            ownedReviewExportBytes > 32 * 1024 * 1024)) {
      throw ArgumentError('Exact retained export digest and bytes required');
    }
    if (ownedReviewExport &&
        (!readOnly ||
            sourceReadOnly ||
            document.kind != ComplexEditorKind.markdown ||
            publicResourceRoot != null ||
            sharedMarkdownEditing ||
            publicComplexReadOnly ||
            sharedComplexEditing ||
            ownedMarkdownSourceIo)) {
      throw ArgumentError('Owned read-only Markdown review required');
    }
    if (ownedMarkdownSourceIo &&
        (document.kind != ComplexEditorKind.markdown ||
            publicResourceRoot != null ||
            sharedMarkdownEditing ||
            publicComplexReadOnly ||
            sharedComplexEditing ||
            readOnly ||
            sourceReadOnly)) {
      throw ArgumentError('Owned editable Markdown required');
    }
    if (sharedComplexEditing &&
        (publicResourceRoot == null ||
            document.kind == ComplexEditorKind.markdown ||
            sourceReadOnly ||
            publicComplexReadOnly ||
            sharedMarkdownEditing ||
            localMarkdownImages)) {
      throw ArgumentError('Isolated shared complex mode required');
    }
    if (publicComplexReadOnly &&
        (publicResourceRoot == null ||
            !readOnly ||
            sourceReadOnly ||
            sharedMarkdownEditing ||
            localMarkdownImages)) {
      throw ArgumentError('Read-only anonymous complex mode required');
    }
    if (localMarkdownImages &&
        (document.kind != ComplexEditorKind.markdown ||
            publicResourceRoot != null ||
            sharedMarkdownEditing ||
            sourceReadOnly)) {
      throw ArgumentError('Local images require a local Markdown surface');
    }
    if (sharedMarkdownEditing && publicResourceRoot == null) {
      throw ArgumentError('Shared Markdown requires its anonymous server root');
    }
    if (publicResourceRoot != null &&
        ((!publicComplexReadOnly &&
                !sharedComplexEditing &&
                document.kind != ComplexEditorKind.markdown) ||
            (!readOnly && !sharedMarkdownEditing && !sharedComplexEditing) ||
            sourceReadOnly ||
            document.byteLength >
                ((publicComplexReadOnly || sharedComplexEditing) &&
                        document.kind != ComplexEditorKind.markdown
                    ? document.kind.maxBytes
                    : 4 * 1024 * 1024) ||
            !{'http', 'https'}.contains(publicResourceRoot.scheme) ||
            publicResourceRoot.host.isEmpty ||
            publicResourceRoot.port < 1 ||
            publicResourceRoot.port > 65535 ||
            publicResourceRoot.userInfo.isNotEmpty ||
            publicResourceRoot.hasQuery ||
            publicResourceRoot.hasFragment ||
            publicResourceRoot.toString().length > 4096 ||
            publicResourceRoot.pathSegments.any(
              (part) =>
                  part == '.' ||
                  part == '..' ||
                  part.contains('/') ||
                  RegExp(r'[\x00-\x1f\x7f]').hasMatch(part) ||
                  part.contains('\\'),
            ))) {
      throw ArgumentError(
        'Public Markdown requires a bounded read-only document and server root',
      );
    }
    if (sourceReadOnly &&
        (document.kind != ComplexEditorKind.html || readOnly)) {
      throw ArgumentError('sourceReadOnly requires editable HTML host mode');
    }
    if ((localDrawingScope == null) != (localDrawingResources == null)) {
      throw ArgumentError('Exact local drawing scope/resources required');
    }
    if (localDrawingScope != null) {
      final resources = localDrawingResources;
      if (resources == null) {
        throw ArgumentError('Bound drawing resources required');
      }
      if (readOnly ||
          document.kind != ComplexEditorKind.drawing ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(localDrawingScope) ||
          sharedMarkdownEditing ||
          publicComplexReadOnly ||
          sharedComplexEditing ||
          localMarkdownImages ||
          ownedMarkdownSourceIo ||
          publicResourceRoot != null ||
          sourceReadOnly ||
          resources.length > 32) {
        throw ArgumentError('Actual ordinary-local drawing mode required');
      }
      for (final item in resources.entries) {
        if (item.key.isEmpty ||
            item.key.length > 256 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(item.value)) {
          throw ArgumentError('Bound drawing image resources required');
        }
        ComplexEditorDocument.validateText(item.key);
      }
    }
    if ((localPresentationScope == null) !=
        (localPresentationResources == null)) {
      throw ArgumentError('Exact local presentation scope/resources required');
    }
    if (localPresentationScope != null) {
      final resources = localPresentationResources;
      if (resources == null) {
        throw ArgumentError('Bound presentation resources required');
      }
      if (readOnly ||
          document.kind != ComplexEditorKind.presentation ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(localPresentationScope) ||
          sharedMarkdownEditing ||
          publicComplexReadOnly ||
          sharedComplexEditing ||
          localMarkdownImages ||
          ownedMarkdownSourceIo ||
          publicResourceRoot != null ||
          sourceReadOnly ||
          resources.values.toSet().length > 32 ||
          resources.length > 55000) {
        throw ArgumentError('Actual ordinary-local presentation mode required');
      }
      for (final item in resources.entries) {
        if (item.key.isEmpty ||
            item.key.length > 256 ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(item.value)) {
          throw ArgumentError('Bound presentation image resources required');
        }
        ComplexEditorDocument.validateText(item.key);
      }
    }
    _localDrawingImages = false;
    _localPresentationImages = false;
    _localHtmlAttachmentGrant = null;
    _localHtmlAttachmentSnapshot = null;
    _localHtmlAttachmentSource = null;
    _localHtmlAttachmentGeneration = null;
    _reviewExportDigest = null;
    _reviewExportBytes = null;
    final info = _map(
      await _call('beginLoad', [
        document.kind.name,
        document.byteLength,
        document.digest,
        {
          'readOnly': readOnly,
          'sourceReadOnly': sourceReadOnly,
          'english': english,
          'title': title,
          if (sharedMarkdownEditing) 'sharedMarkdownEditing': true,
          if (publicComplexReadOnly) 'publicComplexReadOnly': true,
          if (sharedComplexEditing) 'sharedComplexEditing': true,
          if (localMarkdownImages) 'localMarkdownImages': true,
          if (localDrawingScope != null)
            'localDrawing': {
              'scope': localDrawingScope,
              'resources': localDrawingResources,
            },
          if (localPresentationScope != null)
            'localPresentation': {
              'scope': localPresentationScope,
              'resources': localPresentationResources,
            },
          if (ownedMarkdownSourceIo) 'ownedMarkdownSourceIo': true,
          if (ownedReviewExport) 'ownedReviewExport': true,
          'ownedReviewExportDigest': ?ownedReviewExportDigest,
          'ownedReviewExportBytes': ?ownedReviewExportBytes,
          if (publicResourceRoot != null)
            'publicResourceRoot': publicResourceRoot.toString(),
        },
      ], epoch),
    );
    final id = _id(info['id']);
    try {
      if (info['bytes'] != document.byteLength ||
          info['chunkBytes'] != chunkBytes) {
        throw const FormatException('Invalid editor load receipt');
      }
      final bytes = utf8.encode(document.source);
      for (var offset = 0, index = 0; offset < bytes.length; index++) {
        final end = (offset + chunkBytes).clamp(0, bytes.length);
        final receipt = _map(
          await _call('appendLoad', [
            id,
            index,
            base64Encode(bytes.sublist(offset, end)),
          ], epoch),
        );
        if (receipt['id'] != id ||
            receipt['index'] != index ||
            receipt['received'] != end) {
          throw const FormatException('Invalid editor chunk receipt');
        }
        offset = end;
      }
      final state = _map(await _call('commitLoad', [id], epoch));
      if (state['ready'] != true ||
          state['kind'] != document.kind.name ||
          state['readOnly'] != readOnly ||
          (state['sourceReadOnly'] ?? false) != sourceReadOnly ||
          (sourceReadOnly && state['inputLocked'] != true) ||
          (localDrawingScope != null &&
              state['localDrawingResourceFailed'] is! bool) ||
          (localPresentationScope != null &&
              state['localPresentationResourceFailed'] is! bool) ||
          state['generation'] is! int ||
          (state['generation'] as int) < 1) {
        throw const FormatException('Invalid editor ready receipt');
      }
      _document = document;
      _readingOnly =
          readOnly &&
          !sharedMarkdownEditing &&
          !sharedComplexEditing &&
          !sourceReadOnly;
      _reading = null;
      _publicSelection = null;
      _localMarkdownImages = localMarkdownImages;
      _localDrawingImages = localDrawingScope != null;
      _localDrawingResourceFailed = state['localDrawingResourceFailed'] == true;
      _localPresentationImages = localPresentationScope != null;
      _localPresentationResourceFailed =
          state['localPresentationResourceFailed'] == true;
      _sourceIoEditable =
          !publicComplexReadOnly &&
          !sharedMarkdownEditing &&
          !readOnly &&
          !sourceReadOnly &&
          (publicResourceRoot == null || sharedComplexEditing) &&
          (document.kind != ComplexEditorKind.markdown ||
              ownedMarkdownSourceIo);
      _reviewExportDigest = ownedReviewExport
          ? (ownedReviewExportDigest ?? document.digest)
          : null;
      _reviewExportBytes = ownedReviewExport
          ? (ownedReviewExportBytes ?? document.byteLength)
          : null;
      _generation = state['generation'] as int;
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        try {
          await _command('abortLoad', [id]);
        } catch (_) {
          /* Preserve original failure. */
        }
      }
      rethrow;
    }
  });

  /// Export-only identity. No import/edit capability is returned or enabled.
  Future<Map<String, Object>> reviewExportIdentity() =>
      _exclusive((epoch) async {
        final document = _document, generation = _generation;
        if (document == null ||
            generation == null ||
            !_readingOnly ||
            document.kind != ComplexEditorKind.markdown) {
          throw StateError('Owned review source unavailable');
        }
        final digest = _reviewExportDigest, bytes = _reviewExportBytes;
        if (digest == null || bytes == null) {
          throw StateError('No explicit export capability');
        }
        final reply = _map(
          await _call('reviewExportIdentity', [digest, bytes], epoch),
        );
        if (reply['lease'] is! String ||
            (reply['lease'] as String).isEmpty ||
            reply['generation'] != generation ||
            reply['sha256'] != digest ||
            reply['bytes'] != bytes) {
          throw const FormatException('Invalid owned review export grant');
        }
        return {
          'lease': reply['lease'] as String,
          'generation': generation,
          'sha256': digest,
          'bytes': bytes,
        };
      });

  Future<Map<String, Object>> sourceIoIdentity() => _exclusive((epoch) async {
    if (!_sourceIoEditable || _generation == null) {
      throw StateError('Source I/O unavailable');
    }
    final reply = _map(await _call('sourceIoIdentity', [], epoch));
    if (reply['lease'] is! String ||
        (reply['lease'] as String).isEmpty ||
        reply['generation'] != _generation) {
      throw const FormatException('Invalid source I/O grant');
    }
    return {'lease': reply['lease'] as String, 'generation': _generation!};
  });

  Future<void> bindReading(
    ComplexReadingIdentity identity, {
    required String runtimeLease,
  }) => _exclusive((epoch) async {
    final document = _document, generation = _generation;
    if (!_readingOnly ||
        document == null ||
        generation == null ||
        document.kind != identity.kind ||
        document.digest != identity.sourceDigest) {
      throw StateError('Reading binding requires the exact read-only runtime');
    }
    final binding = ComplexReadingBinding(
      identity,
      runtimeLease: runtimeLease,
      generation: generation,
    );
    final result = _map(await _call('bindReading', [binding.toJson()], epoch));
    binding.verify(result['binding']);
    _reading = binding;
  });
  Future<ComplexReadingCapture> captureReading({
    bool includeSelection = true,
  }) => _exclusive((epoch) async {
    final binding = _reading;
    if (binding == null || !_readingOnly) {
      throw StateError('Reading unavailable');
    }
    return ComplexReadingCapture.parse(
      binding,
      await _call('captureReading', [
        binding.toJson(),
        includeSelection,
      ], epoch),
    );
  });
  Future<void> bindPublicSelection(
    PublicSelectionIdentity identity, {
    required String runtimeLease,
  }) => _exclusive((epoch) async {
    final document = _document, generation = _generation;
    if (!_readingOnly ||
        document == null ||
        generation == null ||
        document.kind != identity.kind ||
        document.digest != identity.sourceDigest) {
      throw StateError('Public reading source changed');
    }
    final binding = PublicSelectionBinding(
      identity,
      runtimeLease: runtimeLease,
      generation: generation,
    );
    final result = _map(
      await _call('bindPublicSelection', [binding.toJson()], epoch),
    );
    binding.verify(result['binding']);
    _publicSelection = binding;
  });
  Future<PublicSelectionCapture> capturePublicSelection() =>
      _exclusive((epoch) async {
        final binding = _publicSelection;
        if (binding == null || !_readingOnly) {
          throw StateError('Public reading unavailable');
        }
        return PublicSelectionCapture.parse(
          binding,
          await _call('capturePublicSelection', [binding.toJson()], epoch),
        );
      });
  Future<void> restoreReading(ComplexReadingAnchor anchor) => _exclusive((
    epoch,
  ) async {
    final binding = _reading;
    if (binding == null ||
        !_readingOnly ||
        anchor.kind != binding.identity.kind) {
      throw StateError('Reading owner changed');
    }
    // Reparse even an already typed anchor: never forward mutable map extras.
    final checked = ComplexReadingAnchor.parse(anchor.kind, anchor.value);
    final result = _map(
      await _call('restoreReading', [binding.toJson(), checked.value], epoch),
    );
    binding.verify(result['binding']);
    if (result['restored'] != true) {
      throw const FormatException('Reading restore not acknowledged');
    }
  });

  /// Monotonic limit for this owned editable Markdown generation only.
  /// The caller locks input before installing it and unlocks after receipt.
  Future<void> setMarkdownByteLimit(int limit) => _exclusive((epoch) async {
    final document = _document, generation = _generation;
    if (document == null ||
        generation == null ||
        document.kind != ComplexEditorKind.markdown ||
        _readingOnly ||
        limit < 1 ||
        limit > 4 * 1024 * 1024) {
      throw StateError('Owned Markdown creation source required');
    }
    final reply = _map(
      await _call('setMarkdownByteLimit', [limit, generation], epoch),
    );
    if (reply['generation'] != generation ||
        reply['kind'] != 'markdown' ||
        reply['limit'] != limit) {
      throw const FormatException('Invalid Markdown limit receipt');
    }
  });

  Future<void> setInputLocked(bool value) => _exclusive((epoch) async {
    final document = _document, generation = _generation;
    if (document == null || generation == null) {
      throw StateError('No editor document loaded');
    }
    final state = _map(
      await _call('setInputLocked', [value, generation], epoch),
    );
    if (state['generation'] != generation ||
        state['ready'] != true ||
        state['kind'] != document.kind.name ||
        state['inputLocked'] != value) {
      throw const FormatException('Invalid editor input-lock receipt');
    }
  });

  Future<ComplexEditorSnapshot> capture() => _exclusive((epoch) async {
    final loaded = _document;
    if (loaded == null) throw StateError('No editor document loaded');
    final info = _map(await _call('beginSnapshot', [], epoch));
    final id = _id(info['id']);
    try {
      final length = info['bytes'], count = info['chunks'];
      final generation = info['generation'], revision = info['revision'];
      final digest = info['sha256'];
      if (length is! int ||
          length < 0 ||
          length > loaded.kind.maxBytes ||
          count is! int ||
          count != (length + chunkBytes - 1) ~/ chunkBytes ||
          generation is! int ||
          generation < 1 ||
          generation != _generation ||
          revision is! int ||
          revision < 0 ||
          digest is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
        throw const FormatException('Invalid editor snapshot metadata');
      }
      final bytes = BytesBuilder(copy: false);
      for (var index = 0; index < count; index++) {
        final chunk = _map(await _call('readSnapshot', [id, index], epoch));
        final text = chunk['base64'];
        if (chunk['id'] != id ||
            chunk['generation'] != generation ||
            chunk['index'] != index ||
            text is! String ||
            text.length > 349528) {
          throw const FormatException('Invalid editor snapshot chunk');
        }
        final decoded = base64Decode(text);
        final expected = index == count - 1
            ? length - index * chunkBytes
            : chunkBytes;
        if (decoded.length != expected || base64Encode(decoded) != text) {
          throw const FormatException('Invalid editor snapshot encoding');
        }
        bytes.add(decoded);
      }
      final all = bytes.takeBytes();
      if (all.length != length || sha256.convert(all).toString() != digest) {
        throw const FormatException('Editor snapshot integrity mismatch');
      }
      final document = ComplexEditorDocument.fromBytes(loaded.kind, all);
      if (document.digest != digest) {
        throw const FormatException('Source identity mismatch');
      }
      final selection = _localMarkdownImages
          ? MarkdownSnapshotSelection.parse(info['markdownSelection'], document)
          : null;
      return ComplexEditorSnapshot._(
        this,
        id,
        generation,
        revision,
        document,
        selection,
      );
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        try {
          await _command('endSnapshot', [id]);
        } catch (_) {
          /* Preserve original failure. */
        }
      }
      rethrow;
    }
  });

  /// Inserts into the exact selection captured with this frozen Markdown source.
  /// The host rejects a changed revision, generation or expired snapshot.
  Future<void> insertMarkdown(
    ComplexEditorSnapshot snapshot, {
    required String text,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    if (snapshot.document.kind != ComplexEditorKind.markdown ||
        text.isEmpty ||
        utf8.encode(text).length > 65536) {
      throw ArgumentError('Bounded Markdown insertion required');
    }
    // Reuse the typed source validator to reject malformed UTF-16.
    ComplexEditorDocument.parse(ComplexEditorKind.markdown, text);
    final state = _map(
      await _call('insertMarkdownSnapshot', [snapshot.id, text], epoch),
    );
    if (state['generation'] != snapshot.generation ||
        state['ready'] != true ||
        state['kind'] != 'markdown' ||
        state['inputLocked'] != true) {
      throw const FormatException('Invalid Markdown insertion receipt');
    }
    snapshot._released = true;
  });

  /// One explicit ordinary-local HTML operation, bound to the active native
  /// Root epoch. This grants neither file reads nor an account image factory.
  Future<void> authorizeLocalHtmlAttachments({
    required ComplexEditorSnapshot snapshot,
    required String scope,
    required int scopeEpoch,
    required String identityDigest,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    if (snapshot.document.kind != ComplexEditorKind.html ||
        _document?.kind != ComplexEditorKind.html ||
        !_sourceIoEditable ||
        _readingOnly ||
        _generation == null ||
        scopeEpoch < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(identityDigest)) {
      throw StateError('Owned local HTML source required');
    }
    _localHtmlAttachmentGrant = null;
    _localHtmlAttachmentSnapshot = null;
    _localHtmlAttachmentSource = null;
    _localHtmlAttachmentGeneration = null;
    final receipt = _map(
      await _call('authorizeLocalHtmlAttachments', [
        scope,
        scopeEpoch,
        identityDigest,
        snapshot.id,
        snapshot.document.digest,
      ], epoch),
    );
    if (receipt['generation'] != _generation ||
        receipt['identityDigest'] != identityDigest ||
        receipt['scopeEpoch'] != scopeEpoch ||
        receipt['sourceDigest'] != snapshot.document.digest ||
        receipt['snapshotId'] != snapshot.id) {
      throw const FormatException('Invalid local HTML authorization receipt');
    }
    _localHtmlAttachmentGrant = identityDigest;
    _localHtmlAttachmentSnapshot = snapshot.id;
    _localHtmlAttachmentSource = snapshot.document.digest;
    _localHtmlAttachmentGeneration = _generation;
  });

  Future<void> insertLocalHtmlAttachment(
    ComplexEditorSnapshot snapshot, {
    required Uri uri,
    required bool image,
    int? width,
    int? height,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    final name = localHtmlAttachmentName(uri);
    if (snapshot.document.kind != ComplexEditorKind.html ||
        _localHtmlAttachmentGrant == null ||
        _localHtmlAttachmentSnapshot != snapshot.id ||
        _localHtmlAttachmentSource != snapshot.document.digest ||
        _localHtmlAttachmentGeneration != snapshot.generation ||
        image &&
            (width == null ||
                height == null ||
                width < 1 ||
                height < 1 ||
                width > 16384 ||
                height > 16384 ||
                width * height > 32 * 1024 * 1024)) {
      throw StateError('Current local HTML attachment authorization required');
    }
    // A failed or interrupted insertion requires a fresh explicit authorization,
    // never an automatic retry against the old source selection.
    _localHtmlAttachmentGrant = null;
    _localHtmlAttachmentSnapshot = null;
    _localHtmlAttachmentSource = null;
    _localHtmlAttachmentGeneration = null;
    final receipt = _map(
      await _call('insertLocalHtmlAttachmentSnapshot', [
        snapshot.id,
        uri.toString(),
        {
          'kind': image ? 'image' : 'file',
          'name': name,
          if (image) 'width': width,
          if (image) 'height': height,
        },
      ], epoch),
    );
    if (receipt['generation'] != snapshot.generation ||
        receipt['ready'] != true ||
        receipt['kind'] != 'html' ||
        receipt['inputLocked'] != true ||
        receipt['dirty'] != true) {
      throw const FormatException('Invalid local HTML insertion receipt');
    }
    snapshot._released = true;
  });

  Future<void> insertLocalRichdocImage(
    ComplexEditorSnapshot snapshot, {
    required Uri uri,
    required int width,
    required int height,
    required String scope,
    required int scopeEpoch,
    required String resourceIdentity,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    localHtmlAttachmentName(uri);
    if (snapshot.document.kind != ComplexEditorKind.richdoc ||
        _document?.kind != ComplexEditorKind.richdoc ||
        !_sourceIoEditable ||
        _readingOnly ||
        scopeEpoch < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceIdentity) ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        width * height > 32 * 1024 * 1024) {
      throw StateError('Actual local rich-document image grant required');
    }
    final receipt = _map(
      await _call('insertLocalRichdocImageSnapshot', [
        snapshot.id,
        uri.toString(),
        {
          'width': width,
          'height': height,
          'scope': scope,
          'scopeEpoch': scopeEpoch,
          'identityDigest': resourceIdentity,
          'sourceDigest': snapshot.document.digest,
        },
      ], epoch),
    );
    if (receipt['generation'] != snapshot.generation ||
        receipt['ready'] != true ||
        receipt['kind'] != 'richdoc' ||
        receipt['inputLocked'] != true ||
        receipt['dirty'] != true) {
      throw const FormatException('Invalid local rich-document image receipt');
    }
    snapshot._released = true;
  });

  Future<void> insertLocalDrawingImage(
    ComplexEditorSnapshot snapshot, {
    required Uri uri,
    required int width,
    required int height,
    required String scope,
    required int scopeEpoch,
    required String resourceIdentity,
    required String resourceId,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    localHtmlAttachmentName(uri);
    if (snapshot.document.kind != ComplexEditorKind.drawing ||
        _document?.kind != ComplexEditorKind.drawing ||
        !_localDrawingImages ||
        !_sourceIoEditable ||
        _readingOnly ||
        scopeEpoch < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceIdentity) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceId) ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        width * height > 32 * 1024 * 1024) {
      throw StateError('Actual local drawing image grant required');
    }
    final receipt = _map(
      await _call('insertLocalDrawingImageSnapshot', [
        snapshot.id,
        uri.toString(),
        {
          'resourceId': resourceId,
          'width': width,
          'height': height,
          'scope': scope,
          'scopeEpoch': scopeEpoch,
          'identityDigest': resourceIdentity,
          'sourceDigest': snapshot.document.digest,
        },
      ], epoch),
    );
    if (receipt['generation'] != snapshot.generation ||
        receipt['ready'] != true ||
        receipt['kind'] != 'drawing' ||
        receipt['inputLocked'] != true ||
        receipt['dirty'] != true ||
        receipt['localDrawingResourceFailed'] != false) {
      throw const FormatException('Invalid local drawing image receipt');
    }
    snapshot._released = true;
  });

  /// Check actual frozen resource status after durable draft and before SQL.
  Future<void> verifyLocalDrawingReadyForSave(ComplexEditorSnapshot snapshot) =>
      _exclusive((epoch) async {
        _owns(snapshot);
        if (!_localDrawingImages ||
            !_sourceIoEditable ||
            snapshot.document.kind != ComplexEditorKind.drawing) {
          throw StateError('Actual local drawing save source required');
        }
        final state = _map(await _call('state', [], epoch));
        if (state['generation'] != snapshot.generation ||
            state['kind'] != 'drawing' ||
            state['ready'] != true ||
            state['inputLocked'] != true ||
            state['localDrawingResourceFailed'] != false) {
          throw StateError('Drawing images unavailable; full draft retained');
        }
      });

  Future<void> insertLocalPresentationImage(
    ComplexEditorSnapshot snapshot, {
    required Uri uri,
    required int width,
    required int height,
    required String scope,
    required int scopeEpoch,
    required String resourceIdentity,
    required String resourceId,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    localHtmlAttachmentName(uri);
    if (snapshot.document.kind != ComplexEditorKind.presentation ||
        _document?.kind != ComplexEditorKind.presentation ||
        !_localPresentationImages ||
        !_sourceIoEditable ||
        _readingOnly ||
        scopeEpoch < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceIdentity) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceId) ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        width * height > 32 * 1024 * 1024) {
      throw StateError('Actual local presentation image grant required');
    }
    final receipt = _map(
      await _call('insertLocalPresentationImageSnapshot', [
        snapshot.id,
        uri.toString(),
        {
          'resourceId': resourceId,
          'width': width,
          'height': height,
          'scope': scope,
          'scopeEpoch': scopeEpoch,
          'identityDigest': resourceIdentity,
          'sourceDigest': snapshot.document.digest,
        },
      ], epoch),
    );
    if (receipt['generation'] != snapshot.generation ||
        receipt['ready'] != true ||
        receipt['kind'] != 'presentation' ||
        receipt['inputLocked'] != true ||
        receipt['dirty'] != true ||
        receipt['localPresentationResourceFailed'] != false) {
      throw const FormatException('Invalid local presentation image receipt');
    }
    snapshot._released = true;
  });

  /// Check actual frozen resource status after durable draft and before SQL.
  Future<void> verifyLocalPresentationReadyForSave(
    ComplexEditorSnapshot snapshot,
  ) => _exclusive((epoch) async {
    _owns(snapshot);
    if (!_localPresentationImages ||
        !_sourceIoEditable ||
        snapshot.document.kind != ComplexEditorKind.presentation) {
      throw StateError('Actual local presentation save source required');
    }
    final state = _map(await _call('state', [], epoch));
    if (state['generation'] != snapshot.generation ||
        state['kind'] != 'presentation' ||
        state['ready'] != true ||
        state['inputLocked'] != true ||
        state['localPresentationResourceFailed'] != false) {
      throw StateError('Presentation images unavailable; full draft retained');
    }
  });

  /// Trusted owned document image insertion. No upload or resource save.
  /// Only engines with a verified real insertion API are enabled.
  Future<void> insertLocalMindmapImage(
    ComplexEditorSnapshot snapshot, {
    required Uri uri,
    required int width,
    required int height,
    required String scope,
    required int scopeEpoch,
    required String resourceIdentity,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    localHtmlAttachmentName(uri);
    if (snapshot.document.kind != ComplexEditorKind.mindmap ||
        _document?.kind != ComplexEditorKind.mindmap ||
        !_sourceIoEditable ||
        _readingOnly ||
        scopeEpoch < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceIdentity) ||
        width < 1 ||
        height < 1 ||
        width > 16384 ||
        height > 16384 ||
        width * height > 32 * 1024 * 1024) {
      throw StateError('Actual local rich-document image grant required');
    }
    final receipt = _map(
      await _call('insertLocalMindmapImageSnapshot', [
        snapshot.id,
        uri.toString(),
        {
          'width': width,
          'height': height,
          'scope': scope,
          'scopeEpoch': scopeEpoch,
          'identityDigest': resourceIdentity,
          'sourceDigest': snapshot.document.digest,
        },
      ], epoch),
    );
    if (receipt['generation'] != snapshot.generation ||
        receipt['ready'] != true ||
        receipt['kind'] != 'mindmap' ||
        receipt['inputLocked'] != true ||
        receipt['dirty'] != true) {
      throw const FormatException('Invalid local rich-document image receipt');
    }
    snapshot._released = true;
  });

  /// Trusted owned document image insertion. No upload or resource save.
  /// Only engines with a verified real insertion API are enabled.
  Future<void> insertOwnedImage(
    ComplexEditorSnapshot snapshot, {
    required Uri url,
    required int width,
    required int height,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    if (!{
          ComplexEditorKind.html,
          ComplexEditorKind.richdoc,
          ComplexEditorKind.spreadsheet,
          ComplexEditorKind.mindmap,
          ComplexEditorKind.drawing,
          ComplexEditorKind.presentation,
        }.contains(snapshot.document.kind) ||
        !{'http', 'https'}.contains(url.scheme) ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment ||
        url.toString().length > 2048 ||
        width < 1 ||
        height < 1 ||
        width > 8192 ||
        height > 8192 ||
        width * height > 16 * 1024 * 1024) {
      throw ArgumentError('Unsupported owned image insertion');
    }
    final value = _map(
      await _call('insertImageSnapshot', [
        snapshot.id,
        url.toString(),
        width,
        height,
      ], epoch),
    );
    if (value['generation'] != snapshot.generation ||
        value['ready'] != true ||
        value['kind'] != snapshot.document.kind.name ||
        value['inputLocked'] != true ||
        value['dirty'] != true) {
      throw const FormatException('Invalid image insertion receipt');
    }
    snapshot._released = true;
  });

  /// Call only after the typed repository confirms a real committed save. The
  /// supplied readback must match the frozen snapshot, not the live editor.
  Future<void> acknowledgeSaved(
    ComplexEditorSnapshot snapshot, {
    required ComplexEditorDocument committed,
  }) => _exclusive((epoch) async {
    _owns(snapshot);
    if (!snapshot.document.same(committed)) {
      throw StateError('Save receipt does not match editor snapshot');
    }
    final state = _map(
      await _call('acknowledgeSnapshot', [snapshot.id], epoch),
    );
    if (state['generation'] != snapshot.generation ||
        state['ready'] != true ||
        state['kind'] != committed.kind.name) {
      throw const FormatException('Invalid editor save acknowledgement');
    }
    snapshot._released = true;
    _document = committed;
  });

  Future<void> release(ComplexEditorSnapshot snapshot) =>
      _exclusive((epoch) async {
        _owns(snapshot);
        await _call('endSnapshot', [snapshot.id], epoch);
        snapshot._released = true;
      });
  void _owns(ComplexEditorSnapshot snapshot) {
    if (!identical(snapshot._owner, this) ||
        snapshot._released ||
        snapshot.generation != _generation) {
      throw StateError('Editor snapshot no longer belongs to this session');
    }
  }

  Future<void> retire() async {
    if (_closed) return;
    _closed = true;
    _epoch++;
    _document = null;
    _generation = null;
    _reading = null;
    _publicSelection = null;
    _readingOnly = false;
    _localHtmlAttachmentGrant = null;
    _localHtmlAttachmentSnapshot = null;
    _localHtmlAttachmentSource = null;
    _localHtmlAttachmentGeneration = null;
    _reviewExportDigest = null;
    _reviewExportBytes = null;
    await _command('retire', []);
  }
}

Map<Object?, Object?> _map(Object? value) {
  if (value is! Map) {
    throw const FormatException('Invalid editor protocol response');
  }
  return value.cast<Object?, Object?>();
}

String _id(Object? value) {
  if (value is! String || value.isEmpty || value.length > 128) {
    throw const FormatException('Invalid editor transfer identity');
  }
  return value;
}
