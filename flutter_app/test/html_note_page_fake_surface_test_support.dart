import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';
import 'package:bookstark_flutter/features/html/html_code_source_surface.dart';
import 'package:bookstark_flutter/features/html/html_source_editor.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

void installFakeHtmlSessionChannel() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(HtmlBrowserSession.channel, (_) async => null);
}

HtmlCodeSourceSurfaceBuilder fakeReadOnlyHtmlCodeSurface() =>
    ({
      required document,
      required title,
      required english,
      required onReady,
      required onState,
      required beforeRetire,
      required onReloadRequested,
    }) => HtmlSourceEditor(
      source: document.source,
      onChanged: (_) {},
      readOnly: true,
      english: english,
    );

typedef FakeHtmlCommandExtension = FutureOr<Object?> Function(
  String command, List<Object?> arguments, String currentSource,
  bool inputLocked, bool readOnly, void Function(String) applySource);

class FakeHtmlSurfaceControl {
  FakeHtmlSurfaceControl({this.autoReady = true, this.commandExtension});
  final FakeHtmlCommandExtension? commandExtension;
  bool autoReady;
  String? source;
  int revision = 0;
  bool inputLocked = true;
  bool dirty = false;
  int snapshotBegins = 0, sessionOpens = 0, retireCalls = 0;
  bool? loadedReadOnly;
}

HtmlSourceSurfaceBuilder fakeHtmlSourceSurface(
  FakeHtmlSurfaceControl control,
) =>
    (
      context, {
      required key,
      required document,
      required title,
      required english,
      required readOnly,
      required onReady,
      required onState,
      required onSaveRequested,
      required beforeRetire,
      required onReloadRequested,
      required onExternalLink,
    }) => FakeHtmlSourceSurface(
      key: key,
      document: document,
      title: title,
      readOnly: readOnly,
      onReady: onReady,
      onState: onState,
      beforeRetire: beforeRetire,
      onReloadRequested: onReloadRequested,
      control: control,
    );

class FakeHtmlSourceSurface extends StatefulWidget {
  const FakeHtmlSourceSurface({
    super.key,
    required this.document,
    required this.title,
    required this.readOnly,
    required this.onReady,
    required this.onState,
    required this.beforeRetire,
    required this.onReloadRequested,
    required this.control,
  });
  final ComplexEditorDocument document;
  final String title;
  final bool readOnly;
  final Future<void> Function(ComplexEditorTransport) onReady;
  final void Function(ComplexEditorState) onState;
  final Future<void> Function(ComplexEditorTransport) beforeRetire;
  final Future<void> Function() onReloadRequested;
  final FakeHtmlSurfaceControl control;

  @override
  State<FakeHtmlSourceSurface> createState() => _FakeHtmlSourceSurfaceState();
}

class _FakeHtmlSourceSurfaceState extends State<FakeHtmlSourceSurface> {
  static const _generation = 73;
  late final ComplexEditorTransport _transport;
  final Map<String, Uint8List> _snapshots = {};
  String _source = '';
  int _revision = 0;
  bool _locked = true, _ready = false;
  int _loadBytes = 0;
  int _snapshotSequence = 0;

  @override
  void initState() {
    super.initState();
    _source = widget.control.source ?? widget.document.source;
    widget.control.source = _source;
    _revision = widget.control.revision;
    _transport = ComplexEditorTransport(_command);
    if (widget.control.autoReady) {
      Future<void>.microtask(_start);
    }
  }

  @override
  void didUpdateWidget(covariant FakeHtmlSourceSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A changed key means a new widget state. Within one mounted generation,
    // the source seed is immutable by contract.
    assert(oldWidget.document.same(widget.document));
  }

  Future<void> _start() async {
    if (_ready || !mounted) return;
    await _transport.load(
      widget.document,
      title: widget.title,
      readOnly: widget.readOnly,
    );
    await HtmlBrowserSession.openLocal(
      retire: () async {
        widget.control.retireCalls++;
        await widget.beforeRetire(_transport);
        await _transport.retire();
      },
    );
    widget.control.sessionOpens++;
    widget.control.loadedReadOnly = widget.readOnly;
    await widget.onReady(_transport);
    if (!mounted) return;
    _ready = true;
    _emit();
    if (mounted) setState(() {});
  }

  void _emit() {
    widget.control.inputLocked = _locked;
    widget.onState(
      ComplexEditorState(
        generation: _generation,
        revision: _revision,
        ready: true,
        dirty: widget.control.dirty,
        inputLocked: _locked,
      ),
    );
  }

  Future<Object?> _command(String name, List<Object?> args) async {
    switch (name) {
      case 'beginLoad':
        _loadBytes = 0;
        return {
          'id': 'load-1',
          'bytes': args[1],
          'chunkBytes': ComplexEditorTransport.chunkBytes,
        };
      case 'appendLoad':
        final bytes = base64Decode(args[2] as String);
        _loadBytes += bytes.length;
        return {'id': args[0], 'index': args[1], 'received': _loadBytes};
      case 'commitLoad':
        _locked = widget.readOnly;
        return {
          'ready': true,
          'kind': 'html',
          'readOnly': widget.readOnly,
          'generation': _generation,
        };
      case 'setInputLocked':
        _locked = args[0] as bool;
        _emit();
        return {
          'ready': true,
          'kind': 'html',
          'generation': _generation,
          'inputLocked': _locked,
        };
      case 'beginSnapshot':
        widget.control.snapshotBegins++;
        final bytes = Uint8List.fromList(utf8.encode(_source));
        final id = 'snapshot-${++_snapshotSequence}';
        _snapshots[id] = bytes;
        return {
          'id': id,
          'bytes': bytes.length,
          'chunks':
              (bytes.length + ComplexEditorTransport.chunkBytes - 1) ~/
              ComplexEditorTransport.chunkBytes,
          'generation': _generation,
          'revision': _revision,
          'sha256': sha256.convert(bytes).toString(),
        };
      case 'readSnapshot':
        final id = args[0] as String;
        final bytes = _snapshots[id]!;
        final index = args[1] as int;
        final start = index * ComplexEditorTransport.chunkBytes;
        final end = (start + ComplexEditorTransport.chunkBytes).clamp(
          0,
          bytes.length,
        );
        return {
          'id': id,
          'generation': _generation,
          'index': index,
          'base64': base64Encode(bytes.sublist(start, end)),
        };
      case 'endSnapshot':
        _snapshots.remove(args[0]);
        return null;
      case 'acknowledgeSnapshot':
        widget.control.dirty = false;
        _emit();
        return {'ready': true, 'kind': 'html', 'generation': _generation};
      case 'retire':
        return null;
      default:
        final extension = widget.control.commandExtension;
        if (extension != null) {
          final value = await extension(name, args, _source, _locked,
            widget.readOnly, (next) {
              if (!_locked || widget.readOnly) {
                throw StateError('Fake HTML source is not an editable locked body');
              }
              ComplexEditorDocument.parse(ComplexEditorKind.html, next);
              _source = next;
              widget.control.source = next;
              widget.control.dirty = true;
              widget.control.revision = ++_revision;
              _emit();
            });
          if (name == 'insertLocalHtmlAttachmentSnapshot') {
            _snapshots.remove(args.first);
          }
          return value;
        }
        throw StateError('Unexpected fake complex-editor command: $name');
    }
  }

  void _editSource() {
    _source = '<!doctype html><p>changed through fake transport</p>\r\n';
    widget.control.source = _source;
    widget.control.dirty = true;
    widget.control.revision = ++_revision;
    _emit();
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Fake HTML source surface'),
        if (!_ready)
          TextButton(onPressed: _start, child: const Text('Complete fake load'))
        else ...[
          TextButton(
            onPressed: _locked ? null : _editSource,
            child: const Text('Change fake HTML source'),
          ),
          Text('Generation $_generation · revision $_revision'),
          TextButton(
            onPressed: () async {
              await HtmlBrowserSession.closeActive();
              await widget.onReloadRequested();
            },
            child: const Text('Reload fake source'),
          ),
        ],
      ],
    ),
  );
}
