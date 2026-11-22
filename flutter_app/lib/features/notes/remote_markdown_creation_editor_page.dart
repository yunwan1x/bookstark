import 'dart:async';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import '../../core/attachments.dart';
import '../../core/draft_vault.dart';
import '../../core/notes_repository.dart';
import '../../core/remote_markdown_creation_controller.dart';
import '../../core/remote_markdown_editor_bridge.dart';
import '../../core/remote_markdown_creation_vault.dart';
import 'notes_page.dart';
import 'remote_markdown_creation_review_page.dart';

/// New remote Markdown only. Existing IDs continue through the ordinary editor.
/// Root opens the controller with the exact server/member/collection namespace.
class RemoteMarkdownCreationEditorPage extends StatefulWidget {
  const RemoteMarkdownCreationEditorPage({
    super.key,
    required this.controller,
    required this.repository,
    required this.isCurrent,
    this.drafts,
    this.attachments,
    this.pickFile,
    this.shareFile,
    this.collection = NoteCollection.note,
    this.english = false,
    this.onSaved,
    this.beforeOpenSaved,
  });
  final RemoteMarkdownCreationController controller;
  final NotesRepository repository;
  final bool Function() isCurrent;
  final DraftVault? drafts;
  final AttachmentRepository? attachments;
  final Future<XFile?> Function(bool imagesOnly)? pickFile;
  final Future<void> Function(Attachment, Uint8List)? shareFile;
  final NoteCollection collection;
  final bool english;

  /// Open/refresh a verified existing ID; never a "created by this attempt" receipt.
  final void Function(int id)? onSaved;
  final Future<void> Function()? beforeOpenSaved;
  @override
  State<RemoteMarkdownCreationEditorPage> createState() => _EditorState();
}

class _EditorState extends State<RemoteMarkdownCreationEditorPage> {
  late RemoteMarkdownEditorBridge _bridge;
  int _epoch = 0;
  Note? _saved;
  bool _review = false, _opening = false;
  String? _error;
  bool current(int epoch) => mounted && epoch == _epoch && widget.isCurrent();
  @override
  void initState() {
    super.initState();
    _bind();
  }

  void _bind() {
    if (widget.controller.vault.scope.collection != widget.collection.name) {
      throw StateError('Wrong creation collection');
    }
    final epoch = ++_epoch;
    _review = !widget.controller.canEdit;
    _saved = null;
    _opening = false;
    _error = null;
    _bridge = RemoteMarkdownEditorBridge(
      controller: widget.controller,
      underlying: widget.repository,
      isCurrent: () => current(epoch),
      onReview: () {
        if (!current(epoch)) return;
        setState(() => _review = true);
      },
    );
  }

  @override
  void didUpdateWidget(covariant RemoteMarkdownCreationEditorPage old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller ||
        old.repository != widget.repository ||
        old.collection != widget.collection) {
      _bridge.retireEditor();
      old.controller.retire();
      unawaited(_bridge.drain());
      _bind();
    }
  }

  Future<void> _openSaved(int id) async {
    if (_opening || !current(_epoch)) return;
    final epoch = _epoch, repository = widget.repository;
    final controller = widget.controller;
    if (controller.phase != MarkdownCreationPhase.finished ||
        controller.record.knownId != id) {
      return;
    }
    _bridge.retireEditor();
    setState(() {
      _opening = true;
      _error = null;
    });
    try {
      await _bridge.drain();
      if (!current(epoch)) return;
      final before = await controller.transport.inspect(id);
      if (!current(epoch)) return;
      final actual = await repository.read(id);
      if (!current(epoch)) return;
      final after = await controller.transport.inspect(id);
      if (!current(epoch)) return;
      final input = MarkdownCreationInput(
        title: actual.title,
        content: actual.content,
        labels: actual.labels,
      );
      if (actual.id != id ||
          actual.isProtected ||
          before.scope.namespace != controller.vault.namespace ||
          after.scope.namespace != controller.vault.namespace ||
          before.id != id ||
          after.id != id ||
          before.fingerprint != after.fingerprint ||
          !input.matches(after.input)) {
        throw StateError('Saved resource changed');
      }
      await widget.beforeOpenSaved?.call();
      if (!current(epoch)) return;
      controller.retire();
      setState(() {
        _saved = actual;
        _review = false;
      });
      widget.onSaved?.call(id);
    } catch (_) {
      if (current(epoch)) {
        setState(() {
          _review = true;
          _error = widget.english
              ? 'Could not open the saved resource. No new request was sent.'
              : '无法打开已保存资料，未发送新的创建请求。';
        });
      }
    } finally {
      if (current(epoch)) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _bridge.retireEditor();
    widget.controller.retire();
    unawaited(_bridge.drain());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isCurrent()) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text(
            widget.english
                ? 'Space changed. Reopen the editor.'
                : '空间已切换，请重新打开编辑器。',
          ),
        ),
      );
    }
    if (_opening) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(_error!),
            TextButton(
              onPressed: () => _openSaved(widget.controller.record.knownId!),
              child: Text(widget.english ? 'Open saved resource' : '打开已保存资料'),
            ),
          ],
        ),
      );
    }
    if (_review) {
      return RemoteMarkdownCreationReviewPage(
        controller: widget.controller,
        english: widget.english,
        onOpenSaved: _openSaved,
      );
    }
    final actual = _saved;
    final editorEpoch = _epoch, editorController = widget.controller;
    return NoteEditorPage(
      key: ValueKey((widget.controller, actual?.id)),
      repository: actual == null ? _bridge : widget.repository,
      note: actual ?? Note(title: '', content: ''),
      drafts: actual == null ? _bridge.drafts : widget.drafts,
      attachments: widget.attachments,
      pickFile: widget.pickFile,
      shareFile: widget.shareFile,
      collection: widget.collection,
      english: widget.english,
      onSaveAcknowledged: actual == null
          ? (saved, complete, created) {
              if (complete && created && saved.id != null) {
                // Let NoteEditor finish its ack/remove/finally stack before handoff.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (current(editorEpoch) &&
                      identical(widget.controller, editorController)) {
                    unawaited(_openSaved(saved.id!));
                  }
                });
              }
            }
          : null,
    );
  }
}
