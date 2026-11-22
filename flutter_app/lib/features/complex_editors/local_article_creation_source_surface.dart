import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/owned_preview_controller.dart';
import 'complex_editor_browser.dart';
import 'local_article_creation_source_coordinator.dart';

typedef ArticleCreationSurfaceBuilder =
    Widget Function(
      BuildContext context, {
      required Key key,
      required ComplexEditorDocument document,
      required String title,
      required bool english,
      required OwnedPreviewController retirementController,
      required Future<void> Function(ComplexEditorTransport) onReady,
      required void Function(ComplexEditorState) onState,
      required Future<void> Function() onSaveRequested,
      required Future<void> Function(ComplexEditorTransport) beforeRetire,
      required Future<void> Function() onReloadRequested,
    });

Widget defaultArticleCreationSurface(
  BuildContext context, {
  required Key key,
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required OwnedPreviewController retirementController,
  required Future<void> Function(ComplexEditorTransport) onReady,
  required void Function(ComplexEditorState) onState,
  required Future<void> Function() onSaveRequested,
  required Future<void> Function(ComplexEditorTransport) beforeRetire,
  required Future<void> Function() onReloadRequested,
}) => ComplexEditorBrowser(
  key: key,
  document: document,
  title: title,
  english: english,
  readOnly: false,
  ownedMarkdownSourceIo: true,
  retirementController: retirementController,
  onReady: onReady,
  onState: onState,
  onSaveRequested: onSaveRequested,
  beforeRetire: beforeRetire,
  onReloadRequested: onReloadRequested,
  onExternalLink: (_) async {},
);

/// One Markdown generation and its exact owned browser lease.
class LocalArticleCreationSourceSurface extends StatefulWidget {
  const LocalArticleCreationSourceSurface({
    super.key,
    required this.coordinator,
    required this.source,
    required this.title,
    required this.english,
    required this.retirementController,
    required this.onChanged,
    required this.onSaveRequested,
    required this.onReloadRequested,
    this.onStateChanged,
    this.builder = defaultArticleCreationSurface,
  });
  final LocalArticleCreationSourceCoordinator coordinator;
  final String source, title;
  final bool english;
  final OwnedPreviewController retirementController;
  final VoidCallback onChanged;
  final Future<void> Function() onSaveRequested, onReloadRequested;
  final ValueChanged<ComplexEditorState>? onStateChanged;
  final ArticleCreationSurfaceBuilder builder;
  @override
  State<LocalArticleCreationSourceSurface> createState() =>
      _LocalArticleCreationSourceSurfaceState();
}

class _LocalArticleCreationSourceSurfaceState
    extends State<LocalArticleCreationSourceSurface> {
  late final ComplexEditorDocument seed;
  late final int mountEpoch;
  @override
  void initState() {
    super.initState();
    seed = widget.coordinator.beginGeneration(widget.source);
    mountEpoch = widget.coordinator.epoch;
  }

  Future<void> _ready(ComplexEditorTransport transport) async {
    if (!mounted || !widget.coordinator.isCurrentEpoch(mountEpoch)) return;
    final generation = transport.generation;
    if (generation == null) {
      throw StateError('Article source generation unavailable');
    }
    try {
      await widget.coordinator.bind(transport, generation: generation);
    } catch (_) {
      if (!mounted || !widget.coordinator.isCurrentEpoch(mountEpoch)) return;
      rethrow;
    }
    if (mounted && widget.coordinator.isCurrentEpoch(mountEpoch)) {
      widget.onChanged();
    }
  }

  void _state(ComplexEditorState state) {
    final transport = widget.coordinator.transport;
    if (mounted &&
        transport != null &&
        widget.coordinator.onState(transport, state)) {
      widget.onChanged();
      widget.onStateChanged?.call(state);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
    context,
    key: ValueKey('article-create-source-$mountEpoch'),
    document: seed,
    title: widget.title,
    english: widget.english,
    retirementController: widget.retirementController,
    onReady: _ready,
    onState: _state,
    onSaveRequested: () async {
      if (mounted && widget.coordinator.isCurrentEpoch(mountEpoch)) {
        await widget.onSaveRequested();
      }
    },
    beforeRetire: widget.coordinator.beforeForcedRetire,
    onReloadRequested: () async {
      if (mounted && widget.coordinator.isCurrentEpoch(mountEpoch)) {
        await widget.onReloadRequested();
      }
    },
  );
}
