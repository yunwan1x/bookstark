import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'package:bookstark_flutter/features/html/html_note_page.dart';

import 'html_creation_source_coordinator.dart';

/// Shared creation-page source surface for editable browser-backed drafts.
class HtmlCreationSourceSurface extends StatefulWidget {
  const HtmlCreationSourceSurface({
    super.key,
    required this.coordinator,
    required this.source,
    required this.title,
    required this.english,
    required this.onChanged,
    required this.onSaveRequested,
    this.onStateChanged,
    this.builder = defaultHtmlSourceSurface,
    this.onReloadRequested,
  });
  final HtmlCreationSourceCoordinator coordinator;
  final String source, title;
  final bool english;
  final VoidCallback onChanged;
  final Future<void> Function() onSaveRequested;
  final ValueChanged<ComplexEditorState>? onStateChanged;
  final HtmlSourceSurfaceBuilder builder;
  final VoidCallback? onReloadRequested;

  @override
  State<HtmlCreationSourceSurface> createState() =>
      _HtmlCreationSourceSurfaceState();
}

class _HtmlCreationSourceSurfaceState extends State<HtmlCreationSourceSurface> {
  late final ComplexEditorDocument seed;
  late final int mountEpoch;
  @override
  void initState() {
    super.initState();
    seed = widget.coordinator.beginGeneration(widget.source);
    mountEpoch = widget.coordinator.epoch;
  }

  Future<void> _ready(ComplexEditorTransport transport) async {
    if (!widget.coordinator.isCurrentEpoch(mountEpoch)) return;
    final generation = transport.generation;
    if (generation == null) {
      throw StateError('Source load did not return generation');
    }
    try {
      await widget.coordinator.bind(transport, generation: generation);
    } catch (_) {
      if (!widget.coordinator.isCurrentEpoch(mountEpoch)) return;
      rethrow;
    }
    if (mounted && widget.coordinator.isCurrentEpoch(mountEpoch)) {
      widget.onChanged();
    }
  }

  void _state(ComplexEditorState value) {
    final transport = widget.coordinator.transport;
    if (transport != null &&
        widget.coordinator.onState(transport, value) &&
        mounted) {
      widget.onChanged();
      widget.onStateChanged?.call(value);
    }
  }

  Future<void> _reload() async => widget.onReloadRequested?.call();

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    key: ValueKey('html-create-source-$mountEpoch'),
    document: seed,
    title: widget.title,
    english: widget.english,
    readOnly: false,
    onReady: _ready,
    onState: _state,
    onSaveRequested: widget.onSaveRequested,
    beforeRetire: widget.coordinator.beforeForcedRetire,
    onReloadRequested: _reload,
    onExternalLink: (_) async {},
  );
}
