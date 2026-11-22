import 'package:file_selector/file_selector.dart';
import '../../core/drive_models.dart';
import '../../core/local_html_note_attachments.dart';
import 'local_html_attachment_library_sheet.dart';
import '../../core/owned_html_note_images.dart';
import '../../core/owned_complex_image_upload_journal.dart';
import '../../core/owned_complex_image_picker_action.dart';
import '../complex_editors/owned_image_upload_confirmation.dart';
import '../complex_editors/owned_server_image_picker.dart';
import '../../core/native_complex_source_io.dart';
import '../complex_editors/complex_source_io_dialogs.dart';
import 'html_source_io_controller.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/html_editor_controller.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/html_notes_repository.dart';
import '../../core/labels_repository.dart';
import '../../widgets/label_picker.dart';
import '../complex_editors/complex_editor_browser.dart';
import 'html_browser_session.dart';
import 'html_source_coordinator.dart';
import 'html_preview.dart';
import 'html_version_view.dart';
import 'html_code_source_surface.dart';

typedef HtmlSourceSurfaceBuilder =
    Widget Function(
      BuildContext context, {
      required Key key,
      required ComplexEditorDocument document,
      required String title,
      required bool english,
      required bool readOnly,
      required Future<void> Function(ComplexEditorTransport) onReady,
      required void Function(ComplexEditorState) onState,
      required Future<void> Function() onSaveRequested,
      required Future<void> Function(ComplexEditorTransport) beforeRetire,
      required Future<void> Function() onReloadRequested,
      required Future<void> Function(Uri) onExternalLink,
    });

Widget defaultHtmlSourceSurface(
  BuildContext context, {
  required Key key,
  required ComplexEditorDocument document,
  required String title,
  required bool english,
  required bool readOnly,
  required Future<void> Function(ComplexEditorTransport) onReady,
  required void Function(ComplexEditorState) onState,
  required Future<void> Function() onSaveRequested,
  required Future<void> Function(ComplexEditorTransport) beforeRetire,
  required Future<void> Function() onReloadRequested,
  required Future<void> Function(Uri) onExternalLink,
}) => ComplexEditorBrowser(
  key: key,
  document: document,
  title: title,
  english: english,
  readOnly: readOnly,
  onReady: onReady,
  onState: onState,
  onSaveRequested: onSaveRequested,
  beforeRetire: beforeRetire,
  onReloadRequested: onReloadRequested,
  onExternalLink: onExternalLink,
);

/// Flutter page shell. The host provides the authenticated full browser body;
/// it owns its cookie/session lifetime independently of source editing.
class HtmlNotePage extends StatefulWidget {
  const HtmlNotePage({
    super.key,
    required this.controller,
    required this.labels,
    required this.fullPreviewBuilder,
    this.english = false,
    this.onDisposed,
    this.local = false,
    this.sourceIoScope,
    this.ownedImages,
    this.localHtmlAttachments,
    this.pickLocalAttachmentFile,
    this.localAttachmentsUnavailable = false,
    this.localInteractiveAvailable = false,
    this.sourceSurfaceBuilder = defaultHtmlSourceSurface,
    this.readOnlySourceSurfaceBuilder,
  });
  final HtmlEditorController controller;
  final LabelsRepository labels;
  final Widget Function(BuildContext, String) fullPreviewBuilder;
  final bool english;
  final VoidCallback? onDisposed;
  final bool local;
  final ComplexSourceIoScope? sourceIoScope;
  final OwnedHtmlNoteImages? ownedImages;
  final LocalHtmlNoteAttachments? localHtmlAttachments;
  final Future<XFile?> Function()? pickLocalAttachmentFile;
  final bool localAttachmentsUnavailable;
  final bool localInteractiveAvailable;
  final HtmlSourceSurfaceBuilder sourceSurfaceBuilder;
  final HtmlCodeSourceSurfaceBuilder? readOnlySourceSurfaceBuilder;
  @override
  State<HtmlNotePage> createState() => _HtmlNotePageState();
}

class _HtmlNotePageState extends State<HtmlNotePage> {
  Timer? _draftTimer;
  bool _imageWorking = false;
  late final LocalHtmlNoteAttachments? _localOwnerAtMount;
  LocalHtmlSelectedAttachment? _localSelected;
  HtmlSourceIoController? _sourceIoJob;
  late final TextEditingController _title;
  late final HtmlSourceCoordinator _sourceCoordinator;
  ComplexEditorDocument? _sourceSeed;
  ComplexEditorTransport? _sourceTransport;
  ComplexEditorState? _sourceState;
  int _sourceMount = 0;
  String _acceptedTitle = '';
  List<String> _acceptedLabels = const [];
  int? _sourceScheduledRevision;
  bool _sourceReloadRequired = false,
      _sourceWorking = false,
      _sourceOperationActive = false;
  String? _sourceNotice;
  bool _sourceMode = false,
      _light = false,
      _allowPop = false,
      _leaving = false,
      _syncing = false;
  HtmlEditorController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _localOwnerAtMount = widget.localHtmlAttachments;
    _light = widget.local;
    _title = TextEditingController(text: c.draft.title);
    _acceptedTitle = c.draft.title;
    _acceptedLabels = List<String>.unmodifiable(c.draft.labels);
    _sourceCoordinator = HtmlSourceCoordinator(
      c,
      freezeEdit: (source) => HtmlNoteEdit(
        title: c.draft.title,
        source: source,
        labels: c.draft.labels,
      ),
    );
    _title.addListener(_titleChanged);
    c.addListener(_updated);
  }

  void _titleChanged() {
    if (_syncing) return;
    if (_imageWorking) {
      _restoreAcceptedTitle();
      return;
    }
    if (_leaving) {
      _restoreAcceptedTitle();
      return;
    }
    if (_sourceMode) {
      if (!_sourceCoordinator.ready ||
          _sourceCoordinator.busy ||
          c.busy ||
          c.hasPendingOperation) {
        _restoreAcceptedTitle();
        return;
      }
      unawaited(
        _updateSourceMetadata(title: _title.text, labels: _acceptedLabels),
      );
      return;
    }
    if (c.canEdit) {
      c.edit(
        HtmlNoteEdit(
          title: _title.text,
          source: c.draft.source,
          labels: c.draft.labels,
        ),
      );
    }
  }

  void _restoreAcceptedTitle() {
    _syncing = true;
    _title.value = TextEditingValue(
      text: _acceptedTitle,
      selection: TextSelection.collapsed(offset: _acceptedTitle.length),
    );
    _syncing = false;
    if (mounted) {
      setState(
        () => _sourceNotice = t(
          '当前操作正在保存，标题暂未更改。',
          'The current save is frozen; this title change was not applied.',
        ),
      );
    }
  }

  Future<void> _updateSourceMetadata({
    required String title,
    required List<String> labels,
  }) async {
    if (_leaving ||
        _imageWorking ||
        _sourceWorking ||
        !_sourceCoordinator.ready) {
      _restoreAcceptedTitle();
      return;
    }
    _sourceOperationActive = true;
    try {
      await _sourceCoordinator.updateMetadata(title: title, labels: labels);
      _acceptedTitle = title;
      _acceptedLabels = List<String>.unmodifiable(labels);
      _scheduleSourceDraft();
    } catch (_) {
      if (_title.text != _acceptedTitle) _restoreAcceptedTitle();
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '标题或标签未能保存到草稿，请重试。',
            'The title or labels were not added to the draft. Retry.',
          ),
        );
      }
    } finally {
      _sourceOperationActive = false;
      if (mounted) setState(() {});
    }
  }

  void _updated() {
    if (!mounted) return;
    if ({HtmlEditorPhase.saved, HtmlEditorPhase.observed}.contains(c.phase)) {
      _syncing = true;
      _title.text = c.baseline.metadata.title;
      _syncing = false;
    }
    _draftTimer?.cancel();
    if (_sourceMode) {
      // Source durability is scheduled only by accepted engine revisions or
      // explicit metadata/checkpoint actions, never generic controller notify.
      if (_sourceOperationActive || _sourceWorking) return;
    } else if (c.recovery != null && !c.busy) {
      _draftTimer = Timer(const Duration(milliseconds: 650), () async {
        await c.flushRecovery();
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  void _scheduleSourceDraft() {
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 650), () {
      unawaited(_checkpointSource());
    });
  }

  Future<bool> _checkpointSource({bool keepLocked = false}) async {
    if (!_sourceMode || _sourceWorking || !c.canEdit || c.hasPendingOperation) {
      return false;
    }
    _sourceOperationActive = true;
    try {
      final stored = await _sourceCoordinator.checkpoint(
        keepLocked: keepLocked,
      );
      if (!stored) {
        _sourceNotice = t(
          '本机草稿尚未确认写入，请重试或保留当前页面。',
          'Draft durability is unconfirmed. Retry or keep this page open.',
        );
      } else {
        _sourceNotice = null;
        _sourceScheduledRevision = null;
      }
      return stored;
    } finally {
      _sourceOperationActive = false;
      if (mounted) setState(() {});
    }
  }

  Future<bool> _prepareSourceTransition() async {
    _draftTimer?.cancel();
    _sourceOperationActive = true;
    try {
      final stored = c.hasPendingOperation
          ? await c.flushRecovery()
          : await _sourceCoordinator.checkpoint(keepLocked: true);
      if (!stored) {
        if (mounted) {
          setState(
            () => _sourceNotice = t(
              '本机恢复记录未确认写入；请重试后再切换。',
              'Draft durability is unconfirmed. Retry before switching.',
            ),
          );
        }
        return false;
      }
      await HtmlBrowserSession.closeActive();
      _sourceTransport = null;
      _sourceState = null;
      return true;
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '编辑器尚未完成安全关闭，请保留当前页面并重试。',
            'The editor could not close safely. Keep this page open and retry.',
          ),
        );
      }
      return false;
    } finally {
      _sourceOperationActive = false;
    }
  }

  Future<void> _selectSourceMode(bool next) async {
    if (_leaving ||
        _imageWorking ||
        next == _sourceMode ||
        _sourceWorking ||
        c.busy) {
      return;
    }
    setState(() {
      _sourceWorking = true;
      _sourceNotice = null;
    });
    try {
      if (!next) {
        if (!await _prepareSourceTransition()) return;
        if (!mounted) return;
        setState(() {
          _sourceMode = false;
          _sourceTransport = null;
        });
        return;
      }
      // Retire the current local/authenticated preview lease before creating
      // the source generation. This also serializes rapid preview/source taps.
      await HtmlBrowserSession.closeActive();
      if (!mounted) return;
      _sourceSeed = _sourceCoordinator.beginGeneration();
      _sourceMount++;
      _sourceTransport = null;
      _sourceState = null;
      setState(() => _sourceMode = true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            'HTML 编辑器暂不可用，请重试。',
            'The HTML editor is unavailable. Retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _sourceReady(ComplexEditorTransport transport) async {
    final generation = transport.generation;
    if (!mounted || generation == null) {
      throw StateError('HTML editor load receipt is unavailable');
    }
    await _sourceCoordinator.bind(transport, generation: generation);
    if (!mounted) return;
    setState(() {
      _sourceTransport = transport;
      _sourceState = _sourceCoordinator.state;
      _sourceNotice = null;
    });
  }

  void _sourceStateChanged(ComplexEditorState state) {
    final transport = _sourceTransport;
    if (transport == null || !_sourceCoordinator.onState(transport, state)) {
      return;
    }
    if (mounted) setState(() => _sourceState = state);
    if (state.dirty &&
        !state.inputLocked &&
        c.canEdit &&
        !c.busy &&
        !c.hasPendingOperation &&
        !_sourceWorking &&
        !_imageWorking &&
        !_sourceOperationActive &&
        state.revision != _sourceCoordinator.lastCheckpointRevision &&
        state.revision != _sourceScheduledRevision) {
      // One attempt per genuine engine revision. A checkpoint unlock event
      // carries the same revision; failures require explicit retry.
      _sourceScheduledRevision = state.revision;
      _scheduleSourceDraft();
    }
  }

  Future<void> _runSourceIo() async {
    final scope = widget.sourceIoScope, transport = _sourceTransport;
    if (scope == null ||
        transport == null ||
        !widget.local ||
        !_sourceMode ||
        _sourceWorking ||
        _leaving ||
        !c.canEdit ||
        !c.canPersistDraft ||
        c.hasPendingOperation ||
        !_sourceCoordinator.ready) {
      return;
    }
    try {
      scope.guard();
    } catch (_) {
      return;
    }
    final action = await showComplexSourceIoSheet(
      context,
      format: 'HTML',
      english: widget.english,
    );
    if (!mounted ||
        action == null ||
        !identical(transport, _sourceTransport) ||
        _leaving) {
      return;
    }
    try {
      scope.guard();
    } catch (_) {
      return;
    }
    _draftTimer?.cancel();
    setState(() => _sourceWorking = true);
    _sourceOperationActive = true;
    final io = HtmlSourceIoController(
      editor: c,
      source: _sourceCoordinator,
      scope: scope,
      isCurrent: () =>
          mounted && !_leaving && identical(widget.sourceIoScope, scope),
      prepareNative: () async {
        final grant = await transport.sourceIoIdentity();
        return NativeComplexSourceIo(
          owner: scope,
          lease: grant['lease'] as String,
          generation: grant['generation'] as int,
        );
      },
      retireSurface: HtmlBrowserSession.closeActive,
      remount: () async {
        if (!mounted || _leaving) return;
        _sourceCoordinator.invalidate();
        _sourceSeed = _sourceCoordinator.beginGeneration();
        _sourceMount++;
        _sourceTransport = null;
        _sourceState = null;
        _sourceReloadRequired = false;
        setState(() {});
      },
    );
    _sourceIoJob = io;
    try {
      await io.run(
        importing: action == ComplexSourceIoAction.importSource,
        confirm: (file) =>
            confirmComplexSourceImport(context, file, english: widget.english),
      );
      if (mounted && !_leaving) {
        setState(
          () => _sourceNotice =
              io.safeError ??
              (io.completed
                  ? action == ComplexSourceIoAction.importSource
                        ? t(
                            'HTML 已导入当前草稿，仍需明确保存。',
                            'HTML imported into the current draft. Explicit Save is still required.',
                          )
                        : t(
                            '目标文件已写入并关闭；未回读目标。文档未保存。',
                            'File transferred and closed; destination was not read back. Document was not saved.',
                          )
                  : t(
                      '操作已取消，原草稿保留。',
                      'Operation cancelled. Original draft retained.',
                    )),
        );
      }
    } catch (_) {
      if (mounted && !_leaving) {
        setState(
          () => _sourceNotice = t(
            '源文件操作已停止，未保存文档。',
            'Source file operation stopped. Document was not saved.',
          ),
        );
      }
    } finally {
      io.retire();
      if (identical(_sourceIoJob, io)) _sourceIoJob = null;
      _sourceOperationActive = false;
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _saveSource() async {
    if (_imageWorking) return;
    if (_leaving ||
        !_sourceCoordinator.ready ||
        _sourceWorking ||
        !c.canEdit ||
        c.hasPendingOperation) {
      return;
    }
    _draftTimer?.cancel();
    setState(() {
      _sourceWorking = true;
      _sourceNotice = null;
    });
    _sourceOperationActive = true;
    try {
      final outcome = await _sourceCoordinator.save();
      if (outcome == null &&
          c.phase == HtmlEditorPhase.clean &&
          _sourceCoordinator.failure == null &&
          c.recoveryFailure == null) {
        _sourceNotice = t('内容没有变化。', 'No changes to save.');
      } else if (outcome == null) {
        _sourceNotice = _sourceCoordinator.failure == null
            ? t('没有可确认的保存结果，请检查状态。', 'No save receipt was confirmed.')
            : t(
                '保存未完成，请保留页面并重试或核对。',
                'Save did not complete. Keep this page and review.',
              );
      } else if (_sourceCoordinator.inputLocked &&
          _sourceCoordinator.failure != null &&
          c.phase == HtmlEditorPhase.saved) {
        _sourceReloadRequired = true;
        _sourceNotice = t(
          '保存回执已收到，但编辑器确认失败。请重新载入已保存版本；不会重复提交。',
          'Save was committed but editor acknowledgement failed. Reload the saved version; it will not be resubmitted.',
        );
      } else if (outcome.allReceiptsKnown && c.phase == HtmlEditorPhase.saved) {
        _sourceNotice = c.recoveryFailure == null
            ? null
            : t(
                '内容已保存，本机恢复记录清理待重试。',
                'Content saved; recovery cleanup needs retry.',
              );
      } else {
        _sourceNotice = t(
          '保存结果待核对；编辑器保持锁定。',
          'Save needs verification; the editor remains locked.',
        );
      }
    } catch (_) {
      _sourceNotice = t('保存未完成，请保留当前页面。', 'Save failed. Keep this page open.');
    } finally {
      _sourceOperationActive = false;
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  bool _localCurrent(LocalHtmlNoteAttachments owner) {
    if (!mounted || !identical(owner, widget.localHtmlAttachments) ||
        !identical(owner, _localOwnerAtMount) || !identical(owner.editor, c)) {
      return false;
    }
    try { owner.guard(); return true; } catch (_) { return false; }
  }
  bool get _localAttachmentAvailable {
    final owner = widget.localHtmlAttachments;
    return widget.local && owner != null && _localCurrent(owner) &&
        !_imageWorking && !_sourceWorking && !_leaving && !c.busy &&
        _sourceMode && _sourceCoordinator.ready && _sourceTransport != null &&
        !_sourceReloadRequired;
  }

  Future<void> _pickLocalAttachment() async {
    final owner = widget.localHtmlAttachments;
    final transport = _sourceTransport;
    if (!_localAttachmentAvailable || owner == null || transport == null) return;
    _draftTimer?.cancel();
    setState(() => _imageWorking = true);
    try {
      if (!await _sourceCoordinator.checkpoint(keepLocked: true) ||
          !mounted || !_localCurrent(owner)) {
        return;
      }
      final choice = await showModalBottomSheet<String>(
        context: context, isScrollControlled: true, useSafeArea: true,
        showDragHandle: true,
        builder: (sheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 8, 16,
            16 + MediaQuery.viewInsetsOf(sheet).bottom),
          child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(t('添加本地图片或文件', 'Add local image or file'),
                style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(t('文件留在当前本地空间，不上传服务器。导入文件不会保存正文。',
                'Files stay in this local space; nothing is uploaded. Import does not save the body.')),
              ListTile(leading: const Icon(Icons.folder_open_outlined),
                title: Text(t('从设备文件导入', 'Import from device')),
                onTap: () => Navigator.pop(sheet, 'device')),
              ListTile(leading: const Icon(Icons.collections_bookmark_outlined),
                title: Text(t('从本地文件库选择', 'Choose from local file library')),
                onTap: () => Navigator.pop(sheet, 'library')),
              TextButton(onPressed: () => Navigator.pop(sheet),
                child: Text(t('取消', 'Cancel'))),
            ]),
        ),
      );
      if (!mounted || !_localCurrent(owner) || choice == null) return;
      LocalHtmlSelectedAttachment? selected;
      if (choice == 'device') {
        // The durable checkpoint above is complete. Never retain a pre-picker
        // CM6 range; choosing a file retires the actual old runtime first.
        _sourceReloadRequired = true;
        await HtmlBrowserSession.closeActive();
        if (!_localCurrent(owner)) return;
        final pick = widget.pickLocalAttachmentFile ?? () => openFile();
        final picked = await pick();
        if (!_localCurrent(owner) || picked == null) return;
        selected = await owner.importDeviceFile(picked);
      } else if (choice == 'library') {
        final node = await showModalBottomSheet<DriveNode>(
          context: context, isScrollControlled: true, useSafeArea: true,
          showDragHandle: true,
          builder: (_) => LocalHtmlAttachmentLibrarySheet(
            owner: owner, english: widget.english),
        );
        if (!_localCurrent(owner) || node == null) return;
        selected = await owner.selectLibraryFile(node);
      }
      if (!_localCurrent(owner) || selected == null) return;
      setState(() {
        _localSelected = selected;
        _sourceNotice = _sourceReloadRequired
          ? t('文件已保留在本地文件库。重新载入编辑器，选择位置后明确插入。',
            'File retained in the local library. Reload the editor, choose a position, then insert explicitly.')
          : t('文件已选中。选择正文中的位置，再明确插入；仍需保存正文。',
            'File selected. Choose a body position, then insert explicitly. Body Save is still required.');
      });
    } catch (_) {
      if (_localCurrent(owner)) {
        setState(() => _sourceNotice = t(
        '文件操作未完成，正文原稿保留。已导入的文件仍在本地文件库。',
        'File operation did not finish. The original body is retained; imported files remain in the local library.'));
      }
    } finally {
      if (_localCurrent(owner) && identical(_sourceTransport, transport) &&
          !_sourceReloadRequired && _sourceCoordinator.ready) {
        try { await _sourceCoordinator.unlock(); } catch (_) {}
      }
      if (mounted) setState(() => _imageWorking = false);
    }
  }

  Future<void> _insertLocalAttachment() async {
    final owner = widget.localHtmlAttachments;
    final selected = _localSelected;
    final transport = _sourceTransport;
    if (!_localAttachmentAvailable || owner == null ||
        selected == null || transport == null) {
      return;
    }
    _draftTimer?.cancel();
    setState(() => _imageWorking = true);
    ComplexEditorSnapshot? frozen;
    try {
      if (!await _sourceCoordinator.checkpoint(keepLocked: true) ||
          !_localCurrent(owner) || !identical(transport, _sourceTransport)) {
        return;
      }
      frozen = await transport.capture();
      if (!_localCurrent(owner) || !identical(transport, _sourceTransport)) return;
      // Consume this explicit selection before sending. An unknown RPC result
      // cannot leave a convenient retry that silently inserts the tag twice.
      _localSelected = null;
      await owner.insert(transport, frozen, selected);
      if (!_localCurrent(owner)) return;
      // The actual new source remains in CM6 and the normal Save/checkpoint path.
      final retained = await _sourceCoordinator.checkpoint();
      if (_localCurrent(owner)) {
        setState(() => _sourceNotice = retained
        ? t('已插入并保留正文草稿，仍需明确保存。',
          'Inserted and draft retained. Explicit Save is still required.')
        : t('已插入，草稿持久化尚未确认。请保留此页并重试保存，不要重复插入。',
          'Inserted; draft retention is unconfirmed. Keep this page and retry Save; do not insert again.'));
      }
    } catch (_) {
      if (_localCurrent(owner) && identical(transport, _sourceTransport) &&
          _sourceCoordinator.ready) {
        // Inspect/capture the actual runtime after an uncertain insertion. This
        // never sends the insertion command again or saves SQL.
        try { await _sourceCoordinator.checkpoint(); } catch (_) {}
      }
      if (_localCurrent(owner)) {
        setState(() => _sourceNotice = t(
        '插入未确认，请检查当前正文。不会自动重复插入；文件仍在本地文件库。',
        'Insertion is unconfirmed. Inspect the current body; nothing is reinserted automatically. File retained in local library.'));
      }
    } finally {
      if (frozen != null) {
        try { await transport.release(frozen); } catch (_) {}
      }
      if (_localCurrent(owner) && identical(transport, _sourceTransport) &&
          _sourceCoordinator.ready) {
        try { await _sourceCoordinator.unlock(); } catch (_) {}
      }
      if (mounted) setState(() => _imageWorking = false);
    }
  }

  Widget _localAttachmentsPanel() {
    final selected = _localSelected;
    if (selected == null) return const SizedBox.shrink();
    return Card(child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (selected.previewBytes != null)
          Image.memory(selected.previewBytes!, height: 112, cacheWidth: 320,
            fit: BoxFit.contain, errorBuilder: (_, _, _) =>
              const Icon(Icons.broken_image_outlined)),
        Text(selected.attachment.name,
          style: Theme.of(context).textTheme.titleMedium),
        Text(selected.image
          ? '${selected.width} × ${selected.height} · ${selected.attachment.size} B'
          : '${selected.attachment.size} B'),
        const SizedBox(height: 8),
        Text(t('文件已保留在本地；插入不会保存正文。',
          'File retained locally. Insertion does not save the body.')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton(onPressed: _localAttachmentAvailable
            ? _insertLocalAttachment : null,
            child: Text(selected.image ? t('插入图片', 'Insert image')
              : t('插入附件链接', 'Insert attachment link'))),
          TextButton(onPressed: _imageWorking ? null : () =>
            setState(() => _localSelected = null),
            child: Text(t('仅保留文件', 'Keep file only'))),
        ]),
      ])));
  }

  bool get _imageActionAvailable =>
      widget.ownedImages != null &&
      widget.ownedImages!.lease.current &&
      !widget.ownedImages!.initializationFailed &&
      !_imageWorking &&
      !_sourceWorking &&
      !_leaving &&
      !c.busy &&
      c.canEdit &&
      !c.hasPendingOperation &&
      _sourceMode &&
      _sourceCoordinator.ready &&
      _sourceTransport != null;

  Future<void> _uploadOwnedImage() async {
    final images = widget.ownedImages;
    if (!_imageActionAvailable || images == null || !images.upload.canUpload) {
      return;
    }
    if (!c.canPersistDraft) {
      final consent = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(t('仅在本次会话保留正文', 'Body retained only in this session')),
          content: Text(
            t(
              '文件选择期间仅在内存保留草稿，关闭应用会丢失未保存正文。不会创建本机正文恢复备份。',
              'This draft stays only in memory while choosing a file. Closing the app loses unsaved text. No device body recovery backup is created.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('继续', 'Continue')),
            ),
          ],
        ),
      );
      if (consent != true || !mounted || !_imageActionAvailable) return;
    }
    setState(() => _imageWorking = true);
    _draftTimer?.cancel();
    try {
      final result = await images.picker.pickAndUpload(
        verifyFreshBinding: images.verifyFreshSource,
        confirm: (selection) async {
          if (!mounted || !images.lease.current) return false;
          return confirmOwnedImageUpload(
            context,
            selection,
            english: widget.english,
            protectedDocument: !c.canPersistDraft,
          );
        },
        preparePickerHandoff: () async {
          images.lease.guard();
          if (!await _prepareSourceTransition()) {
            throw StateError('HTML checkpoint unconfirmed');
          }
          images.lease.guard();
        },
        resumeEditor: () async {
          if (mounted && images.lease.current) await _reloadSource();
        },
      );
      if (mounted) {
        setState(
          () => _sourceNotice = result == OwnedImagePickResult.cancelled
              ? t('操作已取消，正文保留。', 'Operation cancelled. Source retained.')
              : t(
                  '图片地址已确认。请在新编辑器中明确插入，仍需保存。',
                  'Image URL confirmed. Insert explicitly in the reopened editor; Save is still required.',
                ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '图片操作未完成。正文和上传核对记录已保留，不会自动重传。',
            'Image operation incomplete. Source and upload review retained; no automatic reupload.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _imageWorking = false);
    }
  }

  Future<void> _insertOwnedImage({bool existing = false}) async {
    final images = widget.ownedImages, transport = _sourceTransport;
    if (!_imageActionAvailable || images == null || transport == null) return;
    setState(() => _imageWorking = true);
    _draftTimer?.cancel();
    ComplexEditorSnapshot? frozen;
    try {
      final library = images.serverImages;
      final choice = existing
          ? await chooseOwnedServerImage(
              context,
              library: library,
              english: widget.english,
              protectedDocument: !c.canPersistDraft,
            )
          : null;
      if (existing && choice == null) return;
      if (!mounted ||
          !images.lease.current ||
          !identical(_sourceTransport, transport)) {
        return;
      }
      if (!await _sourceCoordinator.checkpoint(keepLocked: true)) {
        throw StateError('HTML draft not durable');
      }
      frozen = await transport.capture();
      final snapshot = frozen;
      Future<bool> verify() async =>
          mounted &&
          identical(_sourceTransport, transport) &&
          images.lease.current &&
          await images.verifyFreshSource();
      Future<void> insert(Uri url, int id) async {
        final actual = await images.prepareExplicitInsertion(id: id, url: url);
        if (!await verify()) throw StateError('HTML image binding changed');
        await transport.insertOwnedImage(
          snapshot,
          url: actual.url,
          width: actual.width,
          height: actual.height,
        );
        frozen = null;
        if (!await _sourceCoordinator.checkpoint(keepLocked: true)) {
          throw StateError('Inserted HTML draft not durable');
        }
      }

      if (choice != null) {
        await images.upload.insertExisting(
          url: choice.url,
          verifyFreshChoice: () => library.verify(choice),
          verifyFreshBinding: verify,
          insertIntoActualEngine: (url) => insert(url, choice.id),
        );
      } else {
        final known = images.upload.record;
        if (known == null || known.uploadId == null) {
          throw StateError('No confirmed URL');
        }
        await images.upload.insert(
          verifyFreshBinding: verify,
          insertIntoActualEngine: (url) => insert(url, known.uploadId!),
        );
        await images.upload.dismissInserted();
      }
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '图片已插入草稿，仍需明确保存。',
            'Image inserted into draft. Explicit Save is still required.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '插入或草稿确认未完成。正文和图片记录保留，不会重新上传。',
            'Insertion or draft checkpoint incomplete. Source and image record retained; no reupload.',
          ),
        );
      }
    } finally {
      final captured = frozen;
      if (captured != null) {
        try {
          await transport.release(captured);
        } catch (_) {}
      }
      if (mounted &&
          identical(_sourceTransport, transport) &&
          images.lease.current) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (mounted) setState(() => _imageWorking = false);
    }
  }

  Future<void> _retryOwnedImageStorage() async {
    final images = widget.ownedImages;
    if (!_imageActionAvailable || images == null) return;
    setState(() => _imageWorking = true);
    try {
      if (images.upload.needsStorageRetry) {
        await images.upload.retryKnownStorage();
      }
      if (images.upload.record?.phase == OwnedImageUploadPhase.inserted) {
        await images.upload.dismissInserted();
      }
    } catch (_) {
      if (mounted) {
        _sourceNotice = t(
          '图片记录清理未确认；不会重新上传。',
          'Image record cleanup unconfirmed; no reupload.',
        );
      }
    } finally {
      if (mounted) setState(() => _imageWorking = false);
    }
  }

  Widget _ownedImagesPanel() {
    final images = widget.ownedImages!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.resourceReferencesUnavailable)
          Text(
            t(
              '部分图片引用不在允许范围或超限，正文保留。',
              'Some image references are outside the allowed scope or limits. Source retained.',
            ),
          ),
        if (images.initializationFailed)
          Text(
            t(
              '图片恢复记录暂不可读，上传已禁用；正文保留。',
              'Image recovery record unreadable. Upload disabled; source retained.',
            ),
          )
        else if (images.upload.record?.phase == OwnedImageUploadPhase.unknown)
          Text(
            t(
              '上传结果待核对。不会自动重传；选择已有图片不会确认原上传结果。',
              'Upload result unknown. No automatic reupload. Selecting an existing image does not confirm it.',
            ),
          )
        else if (images.upload.record != null)
          Text(
            t(
              '图片地址已确认，插入和保存仍需明确完成。',
              'Image URL confirmed. Insertion and Save remain explicit.',
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (images.upload.record?.phase ==
                    OwnedImageUploadPhase.confirmedUrl &&
                !images.upload.needsStorageRetry)
              TextButton(
                onPressed: _imageActionAvailable
                    ? () => _insertOwnedImage()
                    : null,
                child: Text(t('插入已确认图片', 'Insert confirmed image')),
              ),
            if (images.upload.needsStorageRetry ||
                images.upload.record?.phase == OwnedImageUploadPhase.inserted)
              TextButton(
                onPressed: _imageActionAvailable
                    ? _retryOwnedImageStorage
                    : null,
                child: Text(t('重试图片记录清理', 'Retry image record cleanup')),
              ),
            TextButton(
              onPressed: _imageActionAvailable
                  ? () => _insertOwnedImage(existing: true)
                  : null,
              child: Text(t('服务器已有图片', 'Server images')),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _beforeRetireSource(ComplexEditorTransport transport) async {
    final images = widget.ownedImages;
    // Account/barrier retirement drains actual HTTP; expected SAF handoff keeps
    // the same account lease alive and does not wait on its own human future.
    if (images != null && !images.lease.current) await images.retireAndDrain();
    await _sourceCoordinator.beforeRetire(transport);
  }

  Future<void> _reloadSource() async {
    if (_sourceWorking || c.busy || c.hasPendingOperation) return;
    setState(() => _sourceWorking = true);
    try {
      await HtmlBrowserSession.closeActive();
      _sourceCoordinator.invalidate();
      if (!mounted) return;
      _sourceSeed = _sourceCoordinator.beginGeneration();
      _sourceMount++;
      _sourceTransport = null;
      _sourceState = null;
      _sourceReloadRequired = false;
      _sourceNotice = null;
      setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '无法重新载入当前 HTML 草稿。',
            'Unable to reload the current HTML draft.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _acceptLatest() async {
    if (c.busy || _sourceWorking) return;
    setState(() => _sourceWorking = true);
    try {
      if (_sourceMode) await HtmlBrowserSession.closeActive();
      c.acceptLatestForEditing();
      _acceptedTitle = c.draft.title;
      _acceptedLabels = List<String>.unmodifiable(c.draft.labels);
      _syncing = true;
      _title.text = _acceptedTitle;
      _syncing = false;
      if (_sourceMode) {
        _sourceSeed = _sourceCoordinator.beginGeneration();
        _sourceMount++;
        _sourceTransport = null;
        _sourceState = null;
        _sourceReloadRequired = false;
      }
    } catch (_) {
      _sourceNotice = t(
        '核对后的编辑器未能重新打开。',
        'The reviewed editor could not be reopened.',
      );
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _verify() async {
    if (c.busy || _sourceWorking) return;
    setState(() => _sourceWorking = true);
    try {
      if (_sourceMode) await HtmlBrowserSession.closeActive();
      await c.flushRecovery();
      await c.verify();
      if (_sourceMode && !c.hasPendingOperation && !c.busy) {
        _sourceReloadRequired = true;
        _sourceNotice = t(
          '核对已完成；重新载入后继续编辑。',
          'Review completed. Reload before editing.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '无法完成只读核对，请重试。',
            'Read-only verification failed. Retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _continueLabels() async {
    if (c.busy || _sourceWorking) return;
    setState(() => _sourceWorking = true);
    try {
      if (_sourceMode) await HtmlBrowserSession.closeActive();
      await c.flushRecovery();
      await c.continueLabels();
      if (_sourceMode && !c.hasPendingOperation && !c.busy) {
        _sourceReloadRequired = true;
        _sourceNotice = t(
          '标签操作完成；重新载入后继续编辑。',
          'Label operation completed. Reload before editing.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '标签保存未完成，请重试或核对。',
            'Label save did not complete. Retry or review.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Future<void> _retireForPop() async {
    await widget.localHtmlAttachments?.retireAndDrain();
    if (_sourceMode) await HtmlBrowserSession.closeActive();
  }

  @override
  void didUpdateWidget(covariant HtmlNotePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.localHtmlAttachments, widget.localHtmlAttachments)) {
      _localSelected = null;
      final old = oldWidget.localHtmlAttachments;
      if (old != null) unawaited(old.retireAndDrain());
    }
  }

  @override
  void dispose() {
    _sourceIoJob?.retire();
    final localAttachments = widget.localHtmlAttachments;
    if (localAttachments != null) unawaited(localAttachments.retireAndDrain());
    final images = widget.ownedImages;
    if (images != null) unawaited(images.retireAndDrain());
    _draftTimer?.cancel();
    c.removeListener(_updated);
    _title.removeListener(_titleChanged);
    _title.dispose();
    final controller = c;
    final coordinator = _sourceCoordinator;
    final mustRetire = coordinator.generation != null;
    unawaited(() async {
      if (mustRetire) {
        // The page route owns this controller. Keep it alive while the shared
        // lease invokes the forced, non-vetoable coordinator hook.
        try {
          await HtmlBrowserSession.closeActive();
        } catch (_) {}
      }
      await coordinator.dispose();
      controller.dispose();
      widget.onDisposed?.call();
    }());
    super.dispose();
  }

  bool get _safeLeave => {
    HtmlEditorPhase.clean,
    HtmlEditorPhase.saved,
    HtmlEditorPhase.observed,
  }.contains(c.phase);
  void _popAfterCheckpoint() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  Future<void> _leave() async {
    if (_leaving || _imageWorking || c.busy || _sourceIoJob != null) return;
    _draftTimer?.cancel();
    setState(() => _leaving = true);
    if (_sourceMode && c.canEdit && !c.hasPendingOperation) {
      final stored = await _checkpointSource(keepLocked: true);
      if (!stored) {
        if (mounted) setState(() => _leaving = false);
        return;
      }
    } else if (_sourceMode && !await c.flushRecovery()) {
      if (mounted) setState(() => _leaving = false);
      return;
    }
    if (_safeLeave) {
      final stored = await c.flushRecovery();
      if (stored) {
        await _retireForPop();
        _popAfterCheckpoint();
      } else if (mounted) {
        setState(() => _leaving = false);
      }
      return;
    }
    final pending = c.hasPendingOperation;
    if (!mounted) {
      _leaving = false;
      return;
    }
    FocusScope.of(context).unfocus();
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .85,
      ),
      builder: (context) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('返回前确认', 'Before leaving'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                pending
                    ? t(
                        widget.local
                            ? '保存结果尚未确认。保留核对记录后，下次打开需先核对本机保存的版本。'
                            : '保存结果尚未确认。保留核对记录后，下次打开需先核对服务器。受保护正文不会保存到本机。',
                        widget.local
                            ? 'The save result is unresolved. Keep its record and verify the saved device version next time.'
                            : 'The save result is unresolved. Keep its record and verify the server next time. Protected content is not kept on this device.',
                      )
                    : t('尚有未保存的修改。', 'There are unsaved changes.'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('继续编辑', 'Keep editing')),
              ),
              if (c.recovery != null && (pending || c.canPersistDraft)) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, 'keep'),
                  child: Text(
                    pending
                        ? t('保留核对记录并返回', 'Keep recovery record and leave')
                        : t('保留草稿并返回', 'Keep draft and leave'),
                  ),
                ),
              ],
              if (!pending) ...[
                const SizedBox(height: 8),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.pop(context, 'discard'),
                  child: Text(t('放弃修改', 'Discard changes')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    // Dismissing the sheet cancelled the debounce; checkpoint without leaving.
    if (choice == null) {
      await c.flushRecovery();
      if (_sourceMode &&
          _sourceCoordinator.ready &&
          c.canEdit &&
          !c.hasPendingOperation) {
        try {
          await _sourceCoordinator.unlock();
        } catch (_) {}
      }
    }
    var stored = false;
    if (choice == 'keep') stored = await c.flushRecovery();
    if (choice == 'discard') stored = await c.discardRecovery();
    if (!mounted) return;
    if (stored) {
      if (choice == 'discard' && _sourceMode) _sourceCoordinator.invalidate();
      await _retireForPop();
      _popAfterCheckpoint();
    } else {
      _leaving = false;
      if (_sourceMode && _sourceCoordinator.ready) {
        try {
          await _sourceCoordinator.unlock();
        } catch (_) {}
      }
      setState(() {});
    }
  }

  Future<void> _keepPendingAndLeave() async {
    if (_leaving || c.busy || _sourceIoJob != null) return;
    _draftTimer?.cancel();
    _leaving = true;
    final stored = await c.flushRecovery();
    if (!mounted) return;
    if (stored) {
      await _retireForPop();
      _popAfterCheckpoint();
    } else {
      setState(() => _leaving = false);
    }
  }

  Future<void> _labels() async {
    if (_leaving || _imageWorking) return;
    final selected = await showLabelPicker(
      context,
      repository: widget.labels,
      selected: c.draft.labels,
      english: widget.english,
    );
    if (selected != null &&
        mounted &&
        !_leaving &&
        !_imageWorking &&
        c.canEdit) {
      if (_sourceMode) {
        await _updateSourceMetadata(title: _title.text, labels: selected);
      } else {
        c.edit(
          HtmlNoteEdit(
            title: _title.text,
            source: c.draft.source,
            labels: selected,
          ),
        );
      }
    }
  }

  String get _status =>
      ({
        HtmlEditorPhase.saving,
        HtmlEditorPhase.contentUnknown,
        HtmlEditorPhase.labelsPending,
        HtmlEditorPhase.verificationPending,
        HtmlEditorPhase.conflict,
      }.contains(c.phase))
      ? _statusForControllerPhase
      : _sourceMode && (_sourceState?.dirty ?? false)
      ? t('未保存', 'Unsaved')
      : _statusForControllerPhase;

  String get _statusForControllerPhase => switch (c.phase) {
    HtmlEditorPhase.clean || HtmlEditorPhase.saved => t('已保存', 'Saved'),
    HtmlEditorPhase.editing => t('未保存', 'Unsaved'),
    HtmlEditorPhase.saving => t('保存中…', 'Saving…'),
    HtmlEditorPhase.conflict => t(
      widget.local ? '本机内容已更新' : '服务器内容已更新',
      widget.local ? 'Device content changed' : 'Server content changed',
    ),
    HtmlEditorPhase.contentUnknown => t(
      '正文保存结果未确认',
      'Content save result unknown',
    ),
    HtmlEditorPhase.labelsPending =>
      c.attempt?.contentReceipt == true
          ? t('正文回执已收到，标签待确认', 'Content acknowledged; labels unresolved')
          : t('正文已核对，标签待保存', 'Content observed; labels pending'),
    HtmlEditorPhase.verificationPending => t(
      '回执已收到，等待核对',
      'Acknowledged; verification pending',
    ),
    HtmlEditorPhase.observed => t(
      widget.local ? '本机保存内容已核对，上次结果未收到' : '服务器内容已核对，部分回执未收到',
      widget.local
          ? 'Device content verified; the previous result was not received'
          : 'Server content verified; some receipts missing',
    ),
  };
  String excerpt(String text) {
    if (text.length <= 600) return text;
    var end = 600;
    if (text.codeUnitAt(end - 1) >= 0xd800 &&
        text.codeUnitAt(end - 1) <= 0xdbff) {
      end--;
    }
    return '${text.substring(0, end)}…';
  }

  Widget _card(
    String heading,
    String title,
    String source,
    List<String> labels,
  ) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => HtmlVersionViewPage(
            heading: heading,
            title: title,
            source: source,
            labels: List.unmodifiable(labels),
            english: widget.english,
            sourceSurfaceBuilder: widget.readOnlySourceSurfaceBuilder,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    heading,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
            const SizedBox(height: 8),
            Text(title),
            const SizedBox(height: 8),
            Text(
              excerpt(source),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 8),
            Text(t('查看完整版本', 'View full version')),
          ],
        ),
      ),
    ),
  );
  Future<void> _confirmSourceExternalLink(Uri uri) async {
    if (!mounted ||
        !_sourceMode ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.host == 'bookstark-editor.invalid' ||
        uri.host.endsWith('.bookstark-editor.invalid') ||
        uri.host == 'bookstark-local.invalid' ||
        uri.host.endsWith('.bookstark-local.invalid')) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('打开外部链接？', 'Open external link?')),
        content: SingleChildScrollView(child: SelectableText(uri.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('打开浏览器', 'Open browser')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _sourceWorking = true);
    try {
      if (!await _prepareSourceTransition()) return;
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('无法打开浏览器。', 'Unable to open browser.'))),
        );
      } else if (mounted) {
        setState(
          () => _sourceNotice = t(
            '编辑器已安全关闭；返回后请显式重新载入。',
            'Editor retired safely. Explicitly reload after returning.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _sourceNotice = t(
            '无法安全关闭编辑器。',
            'The editor could not be closed safely.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sourceWorking = false);
    }
  }

  Widget _localPreviewModes() {
    final wide =
        MediaQuery.sizeOf(context).width - 32 >= 340 &&
        MediaQuery.textScalerOf(context).scale(14) <= 20;
    if (wide) {
      return SegmentedButton<bool>(
        segments: [
          ButtonSegment(
            value: true,
            icon: const Icon(Icons.desktop_windows_outlined),
            label: Text(t('轻量预览', 'Light preview')),
          ),
          ButtonSegment(
            value: false,
            icon: const Icon(Icons.play_arrow_outlined),
            label: Text(t('交互预览', 'Interactive preview')),
          ),
        ],
        selected: {_light},
        onSelectionChanged: _leaving
            ? null
            : (value) => setState(() => _light = value.single),
      );
    }
    Widget option(bool light, IconData icon, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: _light == light,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: _light == light
                ? Theme.of(context).colorScheme.primary
                : Colors.white,
            foregroundColor: _light == light
                ? Colors.white
                : Theme.of(context).colorScheme.primary,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _leaving ? null : () => setState(() => _light = light),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(label, textAlign: TextAlign.center)),
            ],
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        option(
          true,
          Icons.desktop_windows_outlined,
          t('轻量预览', 'Light preview'),
        ),
        option(
          false,
          Icons.play_arrow_outlined,
          t('交互预览', 'Interactive preview'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final unresolved = {
      HtmlEditorPhase.contentUnknown,
      HtmlEditorPhase.labelsPending,
      HtmlEditorPhase.verificationPending,
    }.contains(c.phase);
    final compactLocal =
        widget.local &&
        widget.localInteractiveAvailable &&
        !_sourceMode &&
        !unresolved &&
        {
          HtmlEditorPhase.clean,
          HtmlEditorPhase.saved,
          HtmlEditorPhase.editing,
        }.contains(c.phase);
    return PopScope(
      canPop: _allowPop || (!_sourceMode && c.recovery == null && _safeLeave),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: widget.local && widget.localInteractiveAvailable
            ? const Color(0xfff1f5ff)
            : null,
        appBar: AppBar(
          backgroundColor: widget.local && widget.localInteractiveAvailable
              ? const Color(0xfff1f5ff)
              : null,
          scrolledUnderElevation:
              widget.local && widget.localInteractiveAvailable ? 0 : null,
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            t(
              _sourceMode ? '编辑 HTML' : 'HTML 笔记',
              _sourceMode ? 'Edit HTML' : 'HTML note',
            ),
          ),
          actions: [
            if (widget.localHtmlAttachments != null && _sourceMode)
              IconButton(
                tooltip: t('添加本地图片或文件', 'Add local image or file'),
                onPressed: _localAttachmentAvailable ? _pickLocalAttachment : null,
                icon: const Icon(Icons.attach_file),
              ),
            if (widget.ownedImages != null && _sourceMode)
              IconButton(
                tooltip: t('上传图片', 'Upload image'),
                onPressed:
                    _imageActionAvailable &&
                        widget.ownedImages!.upload.canUpload
                    ? _uploadOwnedImage
                    : null,
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
            if (widget.local &&
                widget.sourceIoScope != null &&
                _sourceMode &&
                c.canPersistDraft)
              IconButton(
                tooltip: t('源文件导入与导出', 'Source file import and export'),
                onPressed:
                    _sourceWorking ||
                        _leaving ||
                        !c.canEdit ||
                        c.hasPendingOperation ||
                        !_sourceCoordinator.ready
                    ? null
                    : _runSourceIo,
                icon: const Icon(Icons.import_export),
              ),
            if (compactLocal) ...[
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Tooltip(
                  message: _status,
                  child: Semantics(
                    liveRegion: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          c.phase == HtmlEditorPhase.editing
                              ? Icons.edit_outlined
                              : Icons.check_circle_outline,
                          size: 18,
                          color: Colors.blueGrey,
                        ),
                        const SizedBox(width: 4),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 100),
                          child: Text(
                            _status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.blueGrey,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                enabled: !_leaving,
                tooltip: t('更多', 'More'),
                onSelected: (value) {
                  if (value == 'source') {
                    unawaited(_selectSourceMode(true));
                  } else {
                    setState(() => _light = true);
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'source',
                    child: Text(t('编辑源码', 'Edit source')),
                  ),
                  PopupMenuItem(
                    value: 'light',
                    child: Text(t('轻量预览', 'Light preview')),
                  ),
                ],
              ),
            ],
            if (_sourceMode)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton(
                  onPressed:
                      _sourceCoordinator.ready &&
                          !_leaving &&
                          !_sourceWorking &&
                          !_imageWorking &&
                          c.canEdit &&
                          !c.hasPendingOperation
                      ? () {
                          FocusScope.of(context).unfocus();
                          unawaited(_saveSource());
                        }
                      : null,
                  child: Text(t('保存', 'Save')),
                ),
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (c.busy) const LinearProgressIndicator(),
              if (!compactLocal)
                Semantics(
                  liveRegion: true,
                  child: unresolved
                      ? Card(
                          color: const Color(0xffffedca),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.info_outline),
                                const SizedBox(height: 8),
                                Text(
                                  _status,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  t(
                                    widget.local
                                        ? '存在未确认的保存，请先核对本机版本。'
                                        : '存在未确认的提交，请先核对服务器版本。',
                                    widget.local
                                        ? 'An unresolved save requires device verification.'
                                        : 'An unresolved submission requires server verification.',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : Text(_status),
                ),
              if (c.recoveryFailure != null) ...[
                const SizedBox(height: 8),
                Text(
                  t(
                    '本机恢复记录更新失败，请重试后再离开。',
                    'The recovery record could not be updated. Retry before leaving.',
                  ),
                ),
                TextButton(
                  onPressed: c.busy || _sourceWorking || _sourceCoordinator.busy
                      ? null
                      : () async {
                          if (_sourceMode) {
                            await _checkpointSource();
                          } else {
                            await c.flushRecovery();
                          }
                          if (mounted) setState(() {});
                        },
                  child: Text(t('重试本机保存', 'Retry device storage')),
                ),
              ],
              const SizedBox(height: 12),
              if (_sourceNotice != null)
                Semantics(liveRegion: true, child: Text(_sourceNotice!)),
              if (_sourceMode && _sourceNotice != null) ...[
                Semantics(liveRegion: true, child: Text(_sourceNotice!)),
                if ((_sourceReloadRequired ||
                        (c.phase == HtmlEditorPhase.observed &&
                            _sourceCoordinator.inputLocked)) &&
                    c.canEdit &&
                    !c.hasPendingOperation &&
                    !c.busy)
                  TextButton.icon(
                    onPressed: _sourceWorking ? null : _reloadSource,
                    icon: const Icon(Icons.refresh),
                    label: Text(t('重新载入已保存版本', 'Reload saved version')),
                  ),
              ],
              if (_sourceMode && _sourceCoordinator.failure != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    t(
                      '本机草稿写入失败，请重试后再切换。',
                      'Draft storage failed. Retry before switching.',
                    ),
                  ),
                ),
              if (c.failure != null &&
                  !unresolved &&
                  c.phase != HtmlEditorPhase.conflict)
                Text(
                  t(
                    '操作未完成，请检查输入或稍后重试。',
                    'Operation incomplete. Check your input or try again.',
                  ),
                ),
              if (c.phase == HtmlEditorPhase.conflict) ...[
                Text(
                  t(
                    '你的修改已保留，请先核对最新版本。',
                    'Your changes are retained. Review the latest version first.',
                  ),
                ),
                _card(
                  t('你的修改', 'Your changes'),
                  c.draft.title,
                  c.draft.source,
                  c.draft.labels,
                ),
                if (c.latest != null)
                  _card(
                    t(
                      widget.local ? '本机已保存版本' : '服务器版本',
                      widget.local ? 'Device saved version' : 'Server version',
                    ),
                    c.latest!.metadata.title,
                    c.latest!.source,
                    c.latest!.labels,
                  ),
                FilledButton(
                  onPressed: c.busy ? null : _acceptLatest,
                  child: Text(t('核对后继续编辑', 'Continue after review')),
                ),
                const SizedBox(height: 16),
              ],
              if (!c.canPersistDraft) ...[
                Text(
                  t(
                    '受保护内容不保留本机草稿。',
                    'Protected content is not kept as a device draft.',
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (unresolved || c.phase == HtmlEditorPhase.conflict)
                Text(t('核对期间预览不运行脚本。', 'Scripts do not run during review.')),
              if (unresolved && c.latest != null) ...[
                _card(
                  t('你的草稿', 'Your draft'),
                  c.draft.title,
                  c.draft.source,
                  c.draft.labels,
                ),
                _card(
                  t(
                    widget.local ? '本机已保存版本' : '服务器版本',
                    widget.local ? 'Device saved version' : 'Server version',
                  ),
                  c.latest!.metadata.title,
                  c.latest!.source,
                  c.latest!.labels,
                ),
              ],
              if (unresolved)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: c.busy ? null : _verify,
                      child: Text(
                        t(
                          widget.local ? '只读核对本机保存' : '只读核对服务器',
                          widget.local ? 'Verify device save' : 'Verify server',
                        ),
                      ),
                    ),
                    if (c.recovery != null)
                      TextButton(
                        onPressed: c.busy ? null : _keepPendingAndLeave,
                        child: Text(
                          t('保留核对记录并返回', 'Keep recovery record and leave'),
                        ),
                      ),
                    if (c.phase == HtmlEditorPhase.labelsPending &&
                        ((c.attempt?.contentReceipt ?? false) ||
                            (c.attempt?.contentObserved ?? false)))
                      FilledButton(
                        onPressed: c.busy ? null : _continueLabels,
                        child: Text(t('继续保存标签', 'Continue labels')),
                      ),
                  ],
                ),
              if (widget.local && !compactLocal) ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Chip(
                    avatar: const Icon(Icons.computer),
                    label: Text(t('本地空间', 'Local space')),
                  ),
                ),
                Text(
                  t(
                    widget.localInteractiveAvailable && !_light
                        ? '保存在此设备。交互预览使用已选择的本地资源。'
                        : '保存在此设备。轻量预览不运行脚本。',
                    widget.localInteractiveAvailable && !_light
                        ? 'Saved on this device. Interactive preview uses selected local resources.'
                        : 'Saved on this device. Lightweight preview does not run scripts.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_sourceMode)
                TextField(
                  key: const ValueKey('html-title'),
                  controller: _title,
                  readOnly:
                      _leaving ||
                      !c.canEdit ||
                      c.busy ||
                      _sourceWorking ||
                      (_sourceMode && !_sourceCoordinator.ready),
                  decoration: InputDecoration(labelText: t('标题', 'Title')),
                )
              else if (compactLocal)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final title = Text(
                      c.draft.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                    final chip = Chip(
                      avatar: const Icon(
                        Icons.folder_outlined,
                        size: 18,
                        color: Color(0xff3d5bd9),
                      ),
                      label: Text(t('本地空间', 'Local space')),
                      labelStyle: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff3d5bd9),
                      ),
                      backgroundColor: const Color(0xffe8efff),
                      shape: const StadiumBorder(),
                      side: const BorderSide(color: Color(0xffcedafd)),
                    );
                    if (constraints.maxWidth < 340 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [title, const SizedBox(height: 8), chip],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        chip,
                      ],
                    );
                  },
                )
              else
                Text(
                  c.draft.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final label in c.draft.labels)
                    InputChip(
                      label: Text(label),
                      onDeleted:
                          _sourceMode &&
                              c.canEdit &&
                              !_leaving &&
                              !_sourceWorking &&
                              !_imageWorking &&
                              (!_sourceMode || _sourceCoordinator.ready)
                          ? () => unawaited(
                              _updateSourceMetadata(
                                title: _acceptedTitle,
                                labels: c.draft.labels
                                    .where((v) => v != label)
                                    .toList(),
                              ),
                            )
                          : null,
                    ),
                  if (_sourceMode)
                    ActionChip(
                      label: Text(t('添加标签', 'Add labels')),
                      avatar: const Icon(Icons.add),
                      onPressed:
                          c.canEdit &&
                              !_leaving &&
                              !_sourceWorking &&
                              !_imageWorking &&
                              _sourceCoordinator.ready
                          ? _labels
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(t('预览', 'Preview'))),
                  ButtonSegment(value: true, label: Text(t('源码', 'Source'))),
                ],
                selected: {_sourceMode},
                onSelectionChanged: _leaving
                    ? null
                    : (value) => unawaited(_selectSourceMode(value.single)),
              ),
              const SizedBox(height: 12),
              if (widget.local &&
                  widget.localInteractiveAvailable &&
                  !_sourceMode &&
                  !unresolved &&
                  c.phase != HtmlEditorPhase.conflict) ...[
                _localPreviewModes(),
                const SizedBox(height: 12),
              ],
              if (widget.ownedImages != null && _sourceMode)
                _ownedImagesPanel(),
              if (widget.localHtmlAttachments != null && _sourceMode)
                _localAttachmentsPanel(),
              if (widget.localAttachmentsUnavailable && _sourceMode)
                Text(t('本地文件能力暂不可用，正文原稿保留。',
                  'Local file capability unavailable. Original body retained.')),
              if (_sourceMode)
                SizedBox(
                  height: 520,
                  child: widget.sourceSurfaceBuilder(
                    context,
                    key: ValueKey(_sourceMount),
                    document: _sourceSeed ?? _sourceCoordinator.seed!,
                    title: _acceptedTitle,
                    english: widget.english,
                    readOnly: false,
                    onReady: _sourceReady,
                    onState: _sourceStateChanged,
                    onSaveRequested: _saveSource,
                    beforeRetire: _beforeRetireSource,
                    onReloadRequested: _reloadSource,
                    onExternalLink: _confirmSourceExternalLink,
                  ),
                )
              else if (_light ||
                  unresolved ||
                  c.phase == HtmlEditorPhase.conflict)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: NativeHtmlPreview(
                      source: c.draft.source,
                      english: widget.english,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 520,
                  child: widget.fullPreviewBuilder(context, c.draft.source),
                ),
              if (!widget.local &&
                  !_sourceMode &&
                  !unresolved &&
                  c.phase != HtmlEditorPhase.conflict) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(t('完整预览', 'Full preview')),
                      selected: !_light,
                      onSelected: _leaving
                          ? null
                          : (_) => setState(() => _light = false),
                    ),
                    ChoiceChip(
                      label: Text(t('轻量预览', 'Light preview')),
                      selected: _light,
                      onSelected: _leaving
                          ? null
                          : (_) => setState(() => _light = true),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _leaving
                      ? null
                      : () => unawaited(_selectSourceMode(true)),
                  icon: const Icon(Icons.code),
                  label: Text(t('编辑源码', 'Edit source')),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
