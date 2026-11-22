// Immutable HTML CodeMirror source viewer. No persistence policy.
import 'package:flutter/material.dart';

import '../../core/complex_editor_document.dart';
import '../../core/complex_editor_transport.dart';
import '../complex_editors/complex_editor_browser.dart';

typedef HtmlCodeSourceSurfaceBuilder =
    Widget Function({
      required ComplexEditorDocument document,
      required String title,
      required bool english,
      required Future<void> Function(ComplexEditorTransport transport) onReady,
      required void Function(ComplexEditorState state) onState,
      required Future<void> Function(ComplexEditorTransport transport)
      beforeRetire,
      required VoidCallback onReloadRequested,
    });

class HtmlCodeSourceSurface extends StatelessWidget {
  const HtmlCodeSourceSurface({
    super.key,
    required this.document,
    required this.title,
    required this.english,
    required this.onReady,
    required this.onState,
    required this.beforeRetire,
    required this.onReloadRequested,
    this.builder,
  });

  final ComplexEditorDocument document;
  final String title;
  final bool english;
  final Future<void> Function(ComplexEditorTransport transport) onReady;
  final void Function(ComplexEditorState state) onState;
  final Future<void> Function(ComplexEditorTransport transport) beforeRetire;
  final VoidCallback onReloadRequested;
  final HtmlCodeSourceSurfaceBuilder? builder;

  @override
  Widget build(BuildContext context) {
    if (document.kind != ComplexEditorKind.html) {
      throw ArgumentError.value(
        document.kind,
        'document.kind',
        'HTML required',
      );
    }
    return (builder ?? _defaultBuilder)(
      document: document,
      title: title,
      english: english,
      onReady: onReady,
      onState: onState,
      beforeRetire: beforeRetire,
      onReloadRequested: onReloadRequested,
    );
  }
}

Widget _defaultBuilder({
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required Future<void> Function(ComplexEditorTransport transport) onReady,
  required void Function(ComplexEditorState state) onState,
  required Future<void> Function(ComplexEditorTransport transport) beforeRetire,
  required VoidCallback onReloadRequested,
}) => ComplexEditorBrowser(
  document: document,
  title: title,
  english: english,
  readOnly: false,
  sourceReadOnly: true,
  onReady: onReady,
  onState: onState,
  onSaveRequested: () async {},
  beforeRetire: beforeRetire,
  onReloadRequested: () async => onReloadRequested(),
);
