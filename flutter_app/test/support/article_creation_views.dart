import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import 'package:bookstark_flutter/features/complex_editors/complex_editor_browser.dart';
import 'markdown_creation_host.dart';

/// Owned widget/transport fake, never actual Android or browser evidence.
class OwnedArticleCreationViews {
  OwnedArticleCreationViews(this.events);
  final List<String> events;
  final states = <OwnedArticleBodyState>[];
  Widget editor(
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
  }) => OwnedArticleBody(
    key: key,
    views: this,
    document: document,
    lease: retirementController,
    onReady: onReady,
    onState: onState,
    beforeRetire: beforeRetire,
    readOnly: false,
  );
  Widget review(
    BuildContext context, {
    required Key key,
    required ComplexEditorDocument document,
    required String title,
    required bool english,
    required OwnedPreviewController retirementController,
    required Future<void> Function(ComplexEditorTransport) onReady,
    required Future<void> Function() onReloadRequested,
  }) => OwnedArticleBody(
    key: key,
    views: this,
    document: document,
    lease: retirementController,
    onReady: onReady,
    readOnly: true,
  );
  Widget archive(
    BuildContext context, {
    required ComplexEditorDocument document,
    required String title,
    required bool english,
    required OwnedPreviewController retirementController,
  }) => OwnedArticleBody(
    key: const ValueKey('owned-archive-test-body'),
    views: this,
    document: document,
    lease: retirementController,
    onReady: (_) async {},
    readOnly: true,
  );
}

class OwnedArticleBody extends StatefulWidget {
  const OwnedArticleBody({
    super.key,
    required this.views,
    required this.document,
    required this.lease,
    required this.onReady,
    required this.readOnly,
    this.onState,
    this.beforeRetire,
  });
  final OwnedArticleCreationViews views;
  final ComplexEditorDocument document;
  final OwnedPreviewController lease;
  final bool readOnly;
  final Future<void> Function(ComplexEditorTransport) onReady;
  final void Function(ComplexEditorState)? onState;
  final Future<void> Function(ComplexEditorTransport)? beforeRetire;
  @override
  State<OwnedArticleBody> createState() => OwnedArticleBodyState();
}

class OwnedArticleBodyState extends State<OwnedArticleBody> {
  final host = MarkdownCreationHost();
  late final transport = ComplexEditorTransport(host.call);
  late Future<void> loading;
  Completer<void>? closeGate;
  bool ready = false;
  @override
  void initState() {
    super.initState();
    widget.views.states.add(this);
    widget.lease.bind(this, () async {
      widget.views.events.add('view-close-start');
      await loading;
      await widget.beforeRetire?.call(transport);
      await closeGate?.future;
      await transport.retire();
      widget.views.events.add('view-closed');
    });
    loading = _load();
  }

  Future<void> _load() async {
    await transport.load(widget.document, readOnly: widget.readOnly);
    if (!mounted || widget.lease.retired) return;
    await widget.onReady(transport);
    if (mounted) setState(() => ready = true);
  }

  void enter(String value) {
    host.source = value;
    host.revision++;
    widget.onState?.call(
      ComplexEditorState.parse(host.state(), ComplexEditorKind.markdown)!,
    );
    setState(() {});
  }

  @override
  void dispose() {
    widget.lease.unbind(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
    child: Column(
      children: [
        Text(widget.readOnly ? '只读测试正文' : '编辑测试正文'),
        Text(host.source, maxLines: 3, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
