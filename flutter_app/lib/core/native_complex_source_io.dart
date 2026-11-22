import 'owned_article_review_export.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/local_protected_content.dart';

class ComplexSourceIoCancelled implements Exception {
  const ComplexSourceIoCancelled();
}

String _id() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
typedef SourceIoInvoke =
    Future<Map<Object?, Object?>?> Function(String, Map<String, Object?>);
Future<Map<Object?, Object?>?> _platform(
  String name,
  Map<String, Object?> args,
) => const MethodChannel(
  'bookstark/complex_source_io',
).invokeMapMethod<Object?, Object?>(name, args);

/// Root account/local-space owner creates once, before opening an editor.
/// A page or picker must never reactivate an old scope.
class ComplexSourceIoScope {
  ComplexSourceIoScope._(this.scope, this.epoch, this._invoke, this.isCurrent);
  final String scope;
  final int epoch;
  final SourceIoInvoke _invoke;
  final bool Function() isCurrent;
  bool _retired = false, _retirementConfirmed = false;
  final Set<Future<void> Function()> _retirementDrains = {};
  Future<void>? _retiring;
  void addRetirementDrain(Future<void> Function() drain) {
    guard();
    _retirementDrains.add(drain);
  }
  void removeRetirementDrain(Future<void> Function() drain) {
    _retirementDrains.remove(drain);
  }

  static Future<ComplexSourceIoScope> activate({
    required String scope,
    required bool Function() isCurrent,
    SourceIoInvoke invoke = _platform,
  }) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(scope) || !isCurrent()) {
      throw StateError('Scope unavailable');
    }
    final state = await invoke('scopeState', {});
    if (!isCurrent()) throw StateError('Scope retired');
    final expected = state?['epoch'];
    if (expected is! int) {
      throw const FormatException('Invalid native scope epoch');
    }
    final reply = await invoke('activateScope', {
      'scope': scope,
      'expectedEpoch': expected,
    });
    final epoch = reply?['epoch'];
    if (epoch is! int) {
      throw const FormatException('Invalid native scope acknowledgment');
    }
    final owner = ComplexSourceIoScope._(scope, epoch, invoke, isCurrent);
    if (!isCurrent()) {
      await owner.retire();
      throw StateError('Scope retired');
    }
    return owner;
  }

  void guard() {
    if (_retired || !isCurrent()) throw StateError('Scope retired');
  }

  Future<void> retire() {
    _retired = true;
    final pending = _retiring;
    if (pending != null) return pending;
    late final Future<void> work;
    work = _retireOwned().whenComplete(() {
      if (identical(_retiring, work)) _retiring = null;
    });
    _retiring = work;
    return work;
  }

  Future<void> _retireOwned() async {
    // Revoke Native authority before waiting for actual Dart file/DB work.
    // Keep the ACK separately: a failed drain retry must not CAS the old epoch.
    if (!_retirementConfirmed) {
      final reply = await _invoke('retireScope', {
        'scope': scope, 'epoch': epoch,
      });
      if (reply?['retired'] != true) {
        throw const FormatException('Native scope retirement unconfirmed');
      }
      _retirementConfirmed = true;
    }
    for (final drain in List<Future<void> Function()>.of(_retirementDrains)) {
      await drain();
    }
  }
}

class ComplexSourceFile {
  const ComplexSourceFile({required this.name, required this.document});
  final String name;
  final ComplexEditorDocument document;
}

class NativeComplexSourceIo {
  NativeComplexSourceIo({
    required this.owner,
    required this.lease,
    required this.generation,
    this.onPickerVisibility,
    this.allowMarkdown = false,
    this._invoke = _platform,
  });
  final ComplexSourceIoScope owner;
  final String lease;
  final int generation;
  final SourceIoInvoke _invoke;
  final bool allowMarkdown;
  final void Function(bool)? onPickerVisibility;
  String? _active;
  bool _closed = false;
  void _guard() {
    owner.guard();
    if (_closed) throw StateError('I/O retired');
  }

  Map<String, Object?> _args(String id) => {
    'id': id,
    'lease': lease,
    'generation': generation,
    'scope': owner.scope,
    'epoch': owner.epoch,
  };
  Future<Map<Object?, Object?>> _call(
    String method,
    Map<String, Object?> args, {
    bool picker = false,
  }) async {
    _guard();
    Map<Object?, Object?>? reply;
    if (picker) onPickerVisibility?.call(true);
    try {
      reply = await _invoke(method, args).timeout(
        picker ? const Duration(minutes: 10) : const Duration(seconds: 25),
      );
    } finally {
      if (picker) onPickerVisibility?.call(false);
    }
    _guard();
    if (reply == null || reply['id'] != args['id']) {
      throw const FormatException('Invalid source I/O response');
    }
    return reply;
  }

  Future<void> cancel() async {
    final id = _active;
    if (id == null) return;
    try {
      await _invoke('cancel', {'id': id}).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  void retire() {
    _closed = true;
    unawaited(cancel());
  }

  Future<ComplexSourceFile?> pick(ComplexEditorKind kind) async {
    _guard();
    if ((kind == ComplexEditorKind.markdown && !allowMarkdown) ||
        _active != null) {
      throw StateError('Unsupported or busy source I/O');
    }
    final id = _id();
    _active = id;
    try {
      final selected = await _call('pickImport', {
        ..._args(id),
        'bytes': kind.maxBytes,
      }, picker: true);
      if (selected['cancelled'] == true) return null;
      final name = selected['name'];
      if (name is! String || name.isEmpty || utf8.encode(name).length > 512) {
        throw const FormatException('Invalid selected name');
      }
      ComplexEditorDocument.validateText(name);
      final data = BytesBuilder(copy: false);
      var index = 0, length = 0;
      final deadline = Stopwatch()..start();
      while (true) {
        if (deadline.elapsed > const Duration(minutes: 3)) {
          throw StateError('Source read deadline');
        }
        final row = await _call('readImport', {'id': id, 'index': index});
        final encoded = row['data'];
        if (row['index'] != index ||
            encoded is! String ||
            encoded.length > 349528 ||
            row['done'] is! bool) {
          throw const FormatException('Invalid import chunk');
        }
        if (row['done'] == true) {
          if (encoded.isNotEmpty || row['bytes'] != length) {
            throw const FormatException('Invalid import end');
          }
          final bytes = data.takeBytes();
          if (row['sha256'] != sha256.convert(bytes).toString()) {
            throw const FormatException('Import hash mismatch');
          }
          final source = BoundedNoteTextReader.decodeUtf8PreservingBom(bytes);
          if (isLocalProtectedEnvelopePrefix(source)) {
            throw const FormatException('Protected source cannot be imported');
          }
          return ComplexSourceFile(
            name: name,
            document: ComplexEditorDocument.parse(kind, source),
          );
        }
        final bytes = base64Decode(encoded);
        if (bytes.isEmpty ||
            bytes.length > 262144 ||
            length + bytes.length > kind.maxBytes) {
          throw const FormatException('Import exceeds bound');
        }
        length += bytes.length;
        if (row['bytes'] != length) {
          throw const FormatException('Import length mismatch');
        }
        data.add(bytes);
        index++;
      }
    } finally {
      await cancel();
      _active = null;
    }
  }

  Future<bool> export(
    ComplexEditorDocument source, {
    required String name,
    void Function(int, int)? progress,
  }) async {
    _guard();
    if ((source.kind == ComplexEditorKind.markdown && !allowMarkdown) ||
        _active != null) {
      throw StateError('Unsupported or busy source I/O');
    }
    return _exportExact(
      utf8.encode(source.source),
      source.digest,
      source.kind == ComplexEditorKind.markdown
          ? 'text/markdown'
          : source.kind == ComplexEditorKind.html
          ? 'text/html'
          : 'application/json',
      name: name,
      progress: progress,
    );
  }

  /// Native separately authorizes only the exact owned readonly grant's
  /// SHA-256 and byte length; this cannot obtain import or document-write rights.
  Future<bool> exportOwnedReview(
    OwnedArticleReviewExport source, {
    required Future<void> Function() beforeWrite,
    void Function(int, int)? progress,
  }) async {
    _guard();
    if (_active != null) throw StateError('Source I/O busy');
    return _exportExact(
      source.bytes,
      source.digest,
      source.mime,
      name: source.name,
      progress: progress,
      beforeWrite: beforeWrite,
    );
  }

  Future<bool> _exportExact(
    List<int> bytes,
    String digest,
    String mime, {
    required String name,
    void Function(int, int)? progress,
    Future<void> Function()? beforeWrite,
  }) async {
    _guard();
    if (_active != null || bytes.length > 32 * 1024 * 1024) {
      throw StateError('Export unavailable');
    }
    if (name.isEmpty ||
        utf8.encode(name).length > 512 ||
        name == '.' ||
        name == '..' ||
        name.runes.any((r) => r < 32 || r == 127 || r == 47 || r == 92)) {
      throw const FormatException('Invalid export name');
    }
    ComplexEditorDocument.validateText(name);
    final id = _id();
    _active = id;
    try {
      final selected = await _call('beginExport', {
        ..._args(id),
        'bytes': bytes.length,
        'sha256': digest,
        'name': name,
        'mime': mime,
      }, picker: true);
      if (selected['cancelled'] == true) return false;
      if (selected['ready'] != true) {
        throw const FormatException('Export destination unavailable');
      }
      if (beforeWrite != null) await beforeWrite();
      _guard();
      var index = 0;
      final deadline = Stopwatch()..start();
      for (var offset = 0; offset < bytes.length;) {
        if (deadline.elapsed > const Duration(minutes: 3)) {
          throw StateError('Export deadline');
        }
        final end = (offset + 262144).clamp(0, bytes.length);
        final row = await _call('writeExport', {
          'id': id,
          'index': index,
          'data': base64Encode(bytes.sublist(offset, end)),
        });
        if (row['index'] != index || row['bytes'] != end) {
          throw const FormatException('Invalid export progress');
        }
        offset = end;
        index++;
        progress?.call(offset, bytes.length);
      }
      final result = await _call('finishExport', {'id': id});
      if (result['saved'] != true ||
          result['bytes'] != bytes.length ||
          result['sha256'] != digest) {
        throw const FormatException('Export write unconfirmed');
      }
      // Provider accepted/flushed/closed every transferred byte. No readback claim.
      return true;
    } finally {
      await cancel();
      _active = null;
    }
  }
}
