import '../../core/local_presentation_local_files.dart';
import 'local_presentation_image_library_sheet.dart';
import '../../core/local_mindmap_local_files.dart';
import '../../core/local_drawing_local_files.dart';
import 'local_mindmap_image_library_sheet.dart';
import 'local_drawing_image_library_sheet.dart';
import 'local_drawing_retained_export_page.dart';
import '../../core/local_drawing_retained_export.dart';
import '../../core/local_richdoc_local_files.dart';
import '../../core/drive_models.dart';
import 'local_richdoc_image_library_sheet.dart';
import '../../core/owned15_generation_resources.dart';
import '../../core/owned_complex_images.dart';
import '../../core/owned_complex_image_picker_action.dart';
import '../../core/owned_complex_image_upload_journal.dart';
import 'owned_image_upload_confirmation.dart';
import 'owned_server_image_picker.dart';
import '../../core/owned_preview_controller.dart';
import 'dart:async';
import '../../core/native_complex_source_io.dart';
import '../../core/complex_source_io_controller.dart';
import 'complex_source_io_dialogs.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import '../../core/attachments.dart';
import '../../core/local_attachments.dart';
import '../../core/local_markdown_resources.dart';
import '../../core/local_article_attachment_import.dart';
import '../../core/native_local_article_attachment_picker.dart';
import '../../widgets/native_image.dart';
import '../../widgets/bookstark_markdown.dart';
import 'local_article_attachment_dialogs.dart';
import 'package:flutter/material.dart';
import '../../core/complex_editor_document.dart';
import '../../core/complex_editor_transport.dart';
import '../../core/local_complex_editor_controller.dart';
import '../../core/local_complex_notes_repository.dart';
import '../html/html_browser_session.dart';
import 'complex_editor_browser.dart';
import 'article_metadata_dialog.dart';
import 'complex_recovery_review_page.dart';

/// Owns a single local editor and its typed save controller for the route.
class LocalComplexNotePage extends StatefulWidget {
  const LocalComplexNotePage({
    super.key,
    required this.controller,
    this.english = false,
    this.onDisposed,
    this.onUnplannedBackground,
    this.attachments,
    this.pickAttachment,
    this.documentBodyOnly = false,
    this.sourceIoScope,
    this.originLabel,
    this.retentionNotice,
    this.retentionActions,
    this.retirementController,
    this.renewRetirementController,
    this.anonymousSharedServer,
    this.ownedImages,
    this.generationResourceFactory,
    this.localRichdocFiles,
    this.localMindmapFiles,
    this.localDrawingFiles,
    this.localPresentationFiles,
  });
  final LocalComplexEditorController controller;
  final LocalAttachments? attachments;
  final LocalRichdocLocalFiles? localRichdocFiles;
  final LocalMindmapLocalFiles? localMindmapFiles;
  final LocalDrawingLocalFiles? localDrawingFiles;
  final LocalPresentationLocalFiles? localPresentationFiles;
  final Future<XFile?> Function()? pickAttachment;
  final bool english;
  final bool documentBodyOnly;
  final ComplexSourceIoScope? sourceIoScope;
  final String? originLabel;
  final String? retentionNotice;
  final Widget? retentionActions;
  final OwnedPreviewController? retirementController;
  final Future<OwnedPreviewController> Function()? renewRetirementController;
  final Uri? anonymousSharedServer;
  final OwnedComplexImages? ownedImages;
  final Future<Owned15GenerationResources?> Function(
    ComplexEditorDocument document,
  )?
  generationResourceFactory;
  final VoidCallback? onDisposed;
  final Future<void> Function()? onUnplannedBackground;
  @override
  State<LocalComplexNotePage> createState() => _LocalComplexNotePageState();
}

class _LocalComplexNotePageState extends State<LocalComplexNotePage>
    with WidgetsBindingObserver {
  LocalComplexEditorController get owner => widget.controller;
  bool get _bodyOnly =>
      widget.documentBodyOnly ||
      const {
        'book-document',
        'remote-book-document',
      }.contains(owner.baseline.collection);
  bool get _metadataAllowed =>
      !_bodyOnly &&
      (_markdownArticle ||
          const {'note', 'remote-note'}.contains(owner.baseline.collection));
  late ComplexEditorDocument _surface;
  OwnedPreviewController? _activeRetirementController;
  ComplexEditorTransport? _transport;
  Timer? _timer;
  Future<void>? _draftJob;
  ComplexNoteEdit? _retirementEdit;
  LocalComplexEditorController? _retirementEditOwner;
  Future<bool>? _saveCheckpoint;
  int _surfaceKey = 0;
  bool _retiringSurface = false;
  bool _editingMetadata = false;
  bool _webDirty = false,
      _saving = false,
      _captureAgain = false,
      _skipCheckpoint = false,
      _allowPop = false,
      _leaving = false;
  String? _notice;
  bool _sourceIoBusy = false,
      _sourceIoHandoff = false,
      _sourceIoPickerExpected = false;
  ComplexSourceIoController? _sourceIoJob;
  bool _attachmentBusy = false, _attachmentResumePending = false;
  Future<bool>? _attachmentCheckpoint;
  AttachmentCancellation? _attachmentCancellation;
  NativeLocalArticleAttachmentPicker? _nativeAttachmentPicker;
  String? _pendingAttachmentMarkup, _attachmentReferenceDigest;
  List<Attachment> _attachmentReferences = const [];
  final _importedSizes = <Uri, int?>{};
  int _localImageFailures = 0;
  LocalRichdocSelectedImage? _selectedLocalRichdocImage;
  late final LocalRichdocLocalFiles? _localRichdocAtMount;
  void _localRichdocRetired() {
    if (mounted) setState(() => _selectedLocalRichdocImage = null);
  }

  bool _localRichdocCurrent(LocalRichdocLocalFiles files) {
    if (!mounted ||
        !identical(files, widget.localRichdocFiles) ||
        !identical(files, _localRichdocAtMount) ||
        !identical(files.owner.controller, owner)) {
      return false;
    }
    try {
      files.guard();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _localRichdocActionAvailable {
    final files = widget.localRichdocFiles;
    return files != null &&
        _localRichdocCurrent(files) &&
        !_attachmentBusy &&
        !_sourceIoBusy &&
        !_saving &&
        !_editingMetadata &&
        !_leaving &&
        !_retiringSurface &&
        _transport != null &&
        _transport!.generation != null &&
        owner.editable &&
        !owner.busy;
  }

  LocalMindmapSelectedImage? _selectedLocalMindmapImage;
  late final LocalMindmapLocalFiles? _localMindmapAtMount;
  void _localMindmapRetired() {
    if (mounted) setState(() => _selectedLocalMindmapImage = null);
  }

  bool _localMindmapCurrent(LocalMindmapLocalFiles files) {
    if (!mounted ||
        !identical(files, widget.localMindmapFiles) ||
        !identical(files, _localMindmapAtMount) ||
        !identical(files.owner.controller, owner)) {
      return false;
    }
    try {
      files.guard();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _localMindmapActionAvailable {
    final files = widget.localMindmapFiles;
    return files != null &&
        _localMindmapCurrent(files) &&
        !_attachmentBusy &&
        !_sourceIoBusy &&
        !_saving &&
        !_editingMetadata &&
        !_leaving &&
        !_retiringSurface &&
        _transport != null &&
        _transport!.generation != null &&
        owner.editable &&
        !owner.busy;
  }

  bool _drawingResourceFailed = false;
  bool _drawingInitializationFailed = false;
  bool get _drawingBodyIncomplete {
    final files = widget.localDrawingFiles;
    if (files == null) return false;
    try {
      return !files.owner.currentBody.complete;
    } catch (_) {
      return true;
    }
  }

  LocalDrawingSelectedImage? _selectedLocalDrawingImage;
  late final LocalDrawingLocalFiles? _localDrawingAtMount;
  void _localDrawingRetired() {
    if (mounted) setState(() => _selectedLocalDrawingImage = null);
  }

  bool _localDrawingCurrent(LocalDrawingLocalFiles files) {
    if (!mounted ||
        !identical(files, widget.localDrawingFiles) ||
        !identical(files, _localDrawingAtMount) ||
        !identical(files.owner.controller, owner)) {
      return false;
    }
    try {
      files.guard();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _localDrawingActionAvailable {
    final files = widget.localDrawingFiles;
    return files != null &&
        !_drawingResourceFailed &&
        _localDrawingCurrent(files) &&
        !_attachmentBusy &&
        !_sourceIoBusy &&
        !_saving &&
        !_editingMetadata &&
        !_leaving &&
        !_retiringSurface &&
        _transport != null &&
        _transport!.generation != null &&
        owner.editable &&
        !owner.busy;
  }

  bool _presentationResourceFailed = false;
  bool get _presentationBodyIncomplete {
    final files = widget.localPresentationFiles;
    if (files == null) return false;
    try {
      return !files.owner.currentBody.complete;
    } catch (_) {
      return true;
    }
  }

  LocalPresentationSelectedImage? _selectedLocalPresentationImage;
  late final LocalPresentationLocalFiles? _localPresentationAtMount;
  void _localPresentationRetired() {
    if (mounted) setState(() => _selectedLocalPresentationImage = null);
  }

  bool _localPresentationCurrent(LocalPresentationLocalFiles files) {
    if (!mounted ||
        !identical(files, widget.localPresentationFiles) ||
        !identical(files, _localPresentationAtMount) ||
        !identical(files.owner.controller, owner)) {
      return false;
    }
    try {
      files.guard();
      return true;
    } catch (_) {
      return false;
    }
  }

  bool get _localPresentationActionAvailable {
    final files = widget.localPresentationFiles;
    return files != null &&
        !_presentationResourceFailed &&
        _localPresentationCurrent(files) &&
        !_attachmentBusy &&
        !_sourceIoBusy &&
        !_saving &&
        !_editingMetadata &&
        !_leaving &&
        !_retiringSurface &&
        _transport != null &&
        _transport!.generation != null &&
        owner.editable &&
        !owner.busy;
  }

  bool get _attachmentArticle => _markdownArticle && widget.attachments != null;
  String t(String zh, String en) => widget.english ? en : zh;
  bool get _markdownArticle =>
      owner.baseline.collection == 'article' &&
      owner.edit.document.kind == ComplexEditorKind.markdown;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _localRichdocAtMount = widget.localRichdocFiles;
    _localRichdocAtMount?.owner.addRetirementListener(_localRichdocRetired);
    _localDrawingAtMount = widget.localDrawingFiles;
    _localDrawingAtMount?.owner.addRetirementListener(_localDrawingRetired);
    _localDrawingAtMount?.owner.onReadFailure = () {
      if (mounted &&
          identical(widget.localDrawingFiles, _localDrawingAtMount)) {
        setState(() {
          _drawingResourceFailed = true;
          _notice = t(
            '图片未能完整读取，原正文保留；请导出或重新加载后再保存。',
            'An image could not be fully read. Source retained; export or reload before Save.',
          );
        });
      }
    };
    _localPresentationAtMount = widget.localPresentationFiles;
    _localPresentationAtMount?.owner.addRetirementListener(
      _localPresentationRetired,
    );
    _localPresentationAtMount?.owner.onReadFailure = () {
      if (mounted &&
          identical(widget.localPresentationFiles, _localPresentationAtMount)) {
        setState(() {
          _presentationResourceFailed = true;
          _notice = t(
            '图片未能完整读取，原正文保留；请导出或重新加载后再保存。',
            'An image could not be fully read. Source retained; export or reload before Save.',
          );
        });
      }
    };
    _localMindmapAtMount = widget.localMindmapFiles;
    _localMindmapAtMount?.owner.addRetirementListener(_localMindmapRetired);
    _surface = owner.edit.document;
    _activeRetirementController = widget.retirementController;
    owner.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sourceIoJob?.dispose();
    unawaited(widget.ownedImages?.retireAndDrain().catchError((Object _) {}));
    _localRichdocAtMount?.owner.removeRetirementListener(_localRichdocRetired);
    final localFiles = widget.localRichdocFiles;
    unawaited(localFiles?.retireAndDrain().catchError((Object _) {}));
    unawaited(localFiles?.owner.retireAndDrain().catchError((Object _) {}));
    _localDrawingAtMount?.owner.removeRetirementListener(_localDrawingRetired);
    _localDrawingAtMount?.owner.onReadFailure = null;
    final drawingFiles = widget.localDrawingFiles;
    unawaited(drawingFiles?.retireAndDrain().catchError((Object _) {}));
    unawaited(drawingFiles?.owner.retireAndDrain().catchError((Object _) {}));
    _localPresentationAtMount?.owner.removeRetirementListener(
      _localPresentationRetired,
    );
    _localPresentationAtMount?.owner.onReadFailure = null;
    final presentationFiles = widget.localPresentationFiles;
    unawaited(presentationFiles?.retireAndDrain().catchError((Object _) {}));
    unawaited(
      presentationFiles?.owner.retireAndDrain().catchError((Object _) {}),
    );
    _localMindmapAtMount?.owner.removeRetirementListener(_localMindmapRetired);
    final mindmapFiles = widget.localMindmapFiles;
    unawaited(mindmapFiles?.retireAndDrain().catchError((Object _) {}));
    unawaited(mindmapFiles?.owner.retireAndDrain().catchError((Object _) {}));
    _attachmentCancellation?.cancel();
    unawaited(_nativeAttachmentPicker?.dispose().catchError((Object _) {}));
    _timer?.cancel();
    owner.removeListener(_changed);
    owner.dispose();
    widget.onDisposed?.call();
    super.dispose();
  }

  ComplexNoteEdit _edit(ComplexEditorSnapshot snapshot) => ComplexNoteEdit(
    title: owner.edit.title,
    document: snapshot.document,
    labels: owner.edit.labels,
  );
  void _state(ComplexEditorState state) {
    if (!mounted) return;
    setState(() {
      _webDirty = state.dirty;
      _drawingResourceFailed =
          state.localDrawingResourceFailed ||
          (state.ready && _drawingBodyIncomplete);
      _presentationResourceFailed =
          state.localPresentationResourceFailed ||
          (state.ready && _presentationBodyIncomplete);
    });
    if (state.dirty &&
        !state.inputLocked &&
        owner.editable &&
        !_saving &&
        !_sourceIoBusy &&
        !_editingMetadata &&
        !_attachmentBusy &&
        !_leaving &&
        !_retiringSurface) {
      _captureAgain = true;
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 650), () {
        unawaited(_draft());
      });
    }
  }

  Future<void> _draft() async {
    final pending = _draftJob;
    if (pending != null) return pending;
    final work = _draftNow();
    _draftJob = work;
    try {
      await work;
    } finally {
      if (identical(work, _draftJob)) _draftJob = null;
    }
  }

  Future<void> _draftNow() async {
    while (mounted &&
        _captureAgain &&
        !_saving &&
        !_sourceIoBusy &&
        owner.editable) {
      _captureAgain = false;
      final transport = _transport;
      if (transport == null) return;
      ComplexEditorSnapshot? snapshot;
      try {
        snapshot = await transport.capture();
        if (!mounted || _sourceIoBusy || _saving || !owner.editable) return;
        await owner.checkpoint(_edit(snapshot));
      } catch (_) {
        if (mounted) {
          setState(
            () => _notice = t(
              '本机草稿尚未确认写入，请保留当前页面。',
              'Draft durability is unconfirmed. Keep this page open.',
            ),
          );
        }
        return;
      } finally {
        if (snapshot != null) {
          try {
            await transport.release(snapshot);
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _beforeRetire(ComplexEditorTransport transport) async {
    final retained = _retirementEdit;
    final retainedOwner = _retirementEditOwner;
    if (retained != null && retainedOwner != null) {
      if (!identical(owner, retainedOwner) || !mounted) {
        throw StateError('Retirement checkpoint owner unavailable');
      }
      await retainedOwner.checkpoint(retained);
      _retirementEdit = null;
      _retirementEditOwner = null;
      if (identical(_transport, transport)) _transport = null;
      return;
    }
    final localFiles = widget.localRichdocFiles;
    if (localFiles != null && !localFiles.owner.rootCurrent) {
      // Real Root transition invalidates the owner before closing native views.
      // A temporary SAF/background view retirement keeps the true owner valid.
      final fileDrain = localFiles.retireAndDrain();
      final imageDrain = localFiles.owner.retireAndDrain();
      await fileDrain;
      await imageDrain;
    }
    final mindmapFiles = widget.localMindmapFiles;
    if (mindmapFiles != null && !mindmapFiles.owner.rootCurrent) {
      // Real Root transition invalidates the owner before closing native views.
      // A temporary SAF/background view retirement keeps the true owner valid.
      final fileDrain = mindmapFiles.retireAndDrain();
      final imageDrain = mindmapFiles.owner.retireAndDrain();
      await fileDrain;
      await imageDrain;
    }
    final drawingFiles = widget.localDrawingFiles;
    if (drawingFiles != null && !drawingFiles.owner.rootCurrent) {
      // Real Root transition invalidates the owner before closing native views.
      // A temporary SAF/background view retirement keeps the true owner valid.
      final fileDrain = drawingFiles.retireAndDrain();
      final imageDrain = drawingFiles.owner.retireAndDrain();
      await fileDrain;
      await imageDrain;
    }
    final presentationFiles = widget.localPresentationFiles;
    if (presentationFiles != null && !presentationFiles.owner.rootCurrent) {
      // Real Root transition invalidates the owner before closing native views.
      // A temporary SAF/background view retirement keeps the true owner valid.
      final fileDrain = presentationFiles.retireAndDrain();
      final imageDrain = presentationFiles.owner.retireAndDrain();
      await fileDrain;
      await imageDrain;
    }
    final images = widget.ownedImages;
    if (images != null && !images.lease.current) await images.retireAndDrain();

    if (!mounted || _skipCheckpoint || owner.requiresReview) return;
    _retiringSurface = true;
    _captureAgain = false;
    _timer?.cancel();
    final pending = _draftJob;
    if (pending != null) await pending;
    if (_sourceIoBusy && _sourceIoHandoff) {
      _transport = null;
      return;
    }
    if (_attachmentBusy) {
      final barrier = _attachmentCheckpoint;
      if (barrier != null && await barrier) return;
    }
    // A save already has its own frozen/pending record and must never be
    // overwritten by an ordinary draft during cookie or lifecycle retirement.
    if (_saving) {
      final barrier = _saveCheckpoint;
      if (barrier != null && await barrier) return;
    }
    if (!mounted || !owner.editable || _skipCheckpoint) return;
    if ((widget.localDrawingFiles != null ||
            widget.localPresentationFiles != null) &&
        transport.generation == null &&
        _transport == null &&
        owner.edit.document.same(_surface)) {
      // This mode keeps the SDK input gate/inert root locked throughout initial
      // data loading. No editable body was acknowledged or exposed to the page.
      // Preserve the unchanged original controller/draft and still close native.
      return;
    }
    await transport.setInputLocked(true);
    final snapshot = await transport.capture();
    try {
      if (!mounted) throw StateError('Retirement checkpoint owner unavailable');
      final capturedOwner = owner;
      final capturedEdit = _edit(snapshot);
      _retirementEditOwner = capturedOwner;
      _retirementEdit = capturedEdit;
      await capturedOwner.checkpoint(capturedEdit);
      _retirementEdit = null;
      _retirementEditOwner = null;
    } finally {
      await transport.release(snapshot);
    }
    if (identical(_transport, transport)) _transport = null;
  }

  Future<void> _chooseLocalRichdocImage() async {
    final files = widget.localRichdocFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    if (!_localRichdocActionAvailable || files == null || transport == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var pickerOpened = false;
    try {
      await _draftJob;
      if (!mounted || !_localRichdocCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localRichdocCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable local draft required');
      }
      await transport.release(snapshot);
      snapshot = null;
      barrier.complete(true);
      if (!mounted || !_localRichdocCurrent(files)) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('添加本地图片', 'Add local image'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              Text(
                t(
                  '图片留在当前本地空间，不上传服务器；导入不会保存正文。',
                  'Images stay in this local space; nothing is uploaded. Import does not save the body.',
                ),
              ),
              ListTile(
                title: Text(t('从设备文件导入', 'Import from device')),
                leading: const Icon(Icons.folder_open_outlined),
                onTap: () => Navigator.pop(sheet, 'device'),
              ),
              ListTile(
                title: Text(t('从本地文件库选择', 'Choose from local file library')),
                leading: const Icon(Icons.collections_bookmark_outlined),
                onTap: () => Navigator.pop(sheet, 'library'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !_localRichdocCurrent(files) || action == null) return;
      LocalRichdocSelectedImage? selected;
      if (action == 'device') {
        pickerOpened = true;
        await HtmlBrowserSession.closeActive();
        if (!mounted || !_localRichdocCurrent(files)) return;
        _sourceIoPickerExpected = true;
        final file = await (widget.pickAttachment?.call() ?? openFile());
        if (!mounted || !_localRichdocCurrent(files) || file == null) return;
        selected = await files.importDeviceFile(file);
      } else if (action == 'library') {
        final node = await showModalBottomSheet<DriveNode>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => LocalRichdocImageLibrarySheet(
            owner: files,
            english: widget.english,
          ),
        );
        if (!mounted || !_localRichdocCurrent(files) || node == null) return;
        selected = await files.selectLibraryFile(node);
      }
      if (!mounted || !_localRichdocCurrent(files) || selected == null) return;
      setState(() {
        _selectedLocalRichdocImage = selected;
        _notice = pickerOpened
            ? t(
                '图片已保留在本地文件库。重新载入编辑器，选择新位置后明确插入。',
                'Image retained in the local library. Reload, choose a new position, then insert explicitly.',
              )
            : t(
                '图片已选中。选择当前位置后明确插入，正文仍需保存。',
                'Image selected. Choose the current position, insert explicitly, then Save the body.',
              );
      });
    } catch (_) {
      if (_localRichdocCurrent(files)) {
        setState(
          () => _notice = t(
            '图片处理未完成，原正文保留。请检查 PNG/JPEG/GIF/WebP 和 5 MiB 限制。',
            'Image handling did not finish. Original body retained. Check PNG/JPEG/GIF/WebP and the 5 MiB limit.',
          ),
        );
      }
    } finally {
      if (pickerOpened) _sourceIoPickerExpected = false;
      if (!barrier.isCompleted) barrier.complete(false);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (!pickerOpened &&
          _localRichdocCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _insertLocalRichdocImage() async {
    final files = widget.localRichdocFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    final selected = _selectedLocalRichdocImage;
    if (!_localRichdocActionAvailable ||
        files == null ||
        transport == null ||
        selected == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var attempted = false, durable = false;
    try {
      await _draftJob;
      if (!mounted || !_localRichdocCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localRichdocCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable source checkpoint required');
      }
      final body = files.owner.currentBody;
      await files.prepareExplicitInsertion(body, selected, snapshot.document);
      if (!mounted || !_localRichdocCurrent(files)) return;
      // One actual user command: an interrupted acknowledgement never resends it.
      attempted = true;
      _selectedLocalRichdocImage = null;
      await transport.insertLocalRichdocImage(
        snapshot,
        uri: selected.attachment.uri,
        width: selected.width,
        height: selected.height,
        scope: files.owner.sourceOwner.scope,
        scopeEpoch: files.owner.sourceOwner.epoch,
        resourceIdentity: body.identity,
      );
      snapshot = null;
      final changed = await transport.capture();
      try {
        await editor.checkpoint(capturedEdit(changed));
        durable = editor.draftDurable;
      } finally {
        await transport.release(changed);
      }
      if (!durable) {
        throw StateError('Inserted local draft durability unconfirmed');
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '图片已插入并保留草稿，仍需明确保存正文。',
            'Image inserted and draft retained. Explicit body Save is still required.',
          ),
        );
      }
    } catch (_) {
      if (attempted &&
          mounted &&
          identical(editor, owner) &&
          editor.editable &&
          transport.generation != null) {
        try {
          final changed = await transport.capture();
          try {
            await editor.checkpoint(capturedEdit(changed));
            durable = editor.draftDurable;
          } finally {
            await transport.release(changed);
          }
        } catch (_) {}
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '插入结果未确认，请核对正文。不会自动再次插入，图片仍在本地文件库。',
            'Insertion is unconfirmed. Inspect the body; nothing is reinserted automatically. Image remains in the local library.',
          ),
        );
      }
    } finally {
      if (!barrier.isCompleted) barrier.complete(durable);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (_localRichdocCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted && identical(editor, owner)) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Widget _localRichdocSelection() {
    final selected = _selectedLocalRichdocImage!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .24,
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.memory(selected.preview, height: 64, cacheWidth: 320),
              Text(selected.attachment.name),
              Text(
                '${selected.width} × ${selected.height} · ${selected.preview.length} bytes',
              ),
              Text(
                t(
                  '文件已保留在本地；插入后仍需保存正文。',
                  'File retained locally. Insertion still requires body Save.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _localRichdocActionAvailable
                        ? _insertLocalRichdocImage
                        : null,
                    child: Text(t('插入图片', 'Insert image')),
                  ),
                  TextButton(
                    onPressed: _attachmentBusy
                        ? null
                        : () =>
                              setState(() => _selectedLocalRichdocImage = null),
                    child: Text(t('仅保留文件', 'Keep file only')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseLocalMindmapImage() async {
    final files = widget.localMindmapFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    if (!_localMindmapActionAvailable || files == null || transport == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var pickerOpened = false;
    try {
      await _draftJob;
      if (!mounted || !_localMindmapCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localMindmapCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable local draft required');
      }
      await transport.release(snapshot);
      snapshot = null;
      barrier.complete(true);
      if (!mounted || !_localMindmapCurrent(files)) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('添加本地图片', 'Add local image'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              Text(
                t(
                  '图片留在当前本地空间，不上传服务器；导入不会保存正文。',
                  'Images stay in this local space; nothing is uploaded. Import does not save the body.',
                ),
              ),
              ListTile(
                title: Text(t('从设备文件导入', 'Import from device')),
                leading: const Icon(Icons.folder_open_outlined),
                onTap: () => Navigator.pop(sheet, 'device'),
              ),
              ListTile(
                title: Text(t('从本地文件库选择', 'Choose from local file library')),
                leading: const Icon(Icons.collections_bookmark_outlined),
                onTap: () => Navigator.pop(sheet, 'library'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !_localMindmapCurrent(files) || action == null) return;
      LocalMindmapSelectedImage? selected;
      if (action == 'device') {
        pickerOpened = true;
        await HtmlBrowserSession.closeActive();
        if (!mounted || !_localMindmapCurrent(files)) return;
        _sourceIoPickerExpected = true;
        final file = await (widget.pickAttachment?.call() ?? openFile());
        if (!mounted || !_localMindmapCurrent(files) || file == null) return;
        selected = await files.importDeviceFile(file);
      } else if (action == 'library') {
        final node = await showModalBottomSheet<DriveNode>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => LocalMindmapImageLibrarySheet(
            owner: files,
            english: widget.english,
          ),
        );
        if (!mounted || !_localMindmapCurrent(files) || node == null) return;
        selected = await files.selectLibraryFile(node);
      }
      if (!mounted || !_localMindmapCurrent(files) || selected == null) return;
      setState(() {
        _selectedLocalMindmapImage = selected;
        _notice = pickerOpened
            ? t(
                '图片已保留在本地文件库。重新载入编辑器，选择一个节点后明确插入。',
                'Image retained in the local library. Reload, select one node, then insert explicitly.',
              )
            : t(
                '图片已选中。在思维导图中选择一个节点后插入，正文仍需保存。',
                'Image selected. Select one node in the mind map, insert explicitly, then Save the body.',
              );
      });
    } catch (_) {
      if (_localMindmapCurrent(files)) {
        setState(
          () => _notice = t(
            '图片处理未完成，原正文保留。请检查 PNG/JPEG/GIF/WebP 和 5 MiB 限制。',
            'Image handling did not finish. Original body retained. Check PNG/JPEG/GIF/WebP and the 5 MiB limit.',
          ),
        );
      }
    } finally {
      if (pickerOpened) _sourceIoPickerExpected = false;
      if (!barrier.isCompleted) barrier.complete(false);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (!pickerOpened &&
          _localMindmapCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _insertLocalMindmapImage() async {
    final files = widget.localMindmapFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    final selected = _selectedLocalMindmapImage;
    if (!_localMindmapActionAvailable ||
        files == null ||
        transport == null ||
        selected == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var attempted = false, durable = false;
    var insertionStage = 'draft_wait';
    try {
      await _draftJob;
      if (!mounted || !_localMindmapCurrent(files)) return;
      insertionStage = 'lock';
      await transport.setInputLocked(true);
      insertionStage = 'capture';
      snapshot = await transport.capture();
      if (!mounted ||
          !_localMindmapCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      insertionStage = 'checkpoint';
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable source checkpoint required');
      }
      insertionStage = 'resource_approval';
      final body = files.owner.currentBody;
      await files.prepareExplicitInsertion(body, selected, snapshot.document);
      if (!mounted || !_localMindmapCurrent(files)) return;
      // One actual user command: an interrupted acknowledgement never resends it.
      attempted = true;
      _selectedLocalMindmapImage = null;
      insertionStage = 'bridge';
      await transport.insertLocalMindmapImage(
        snapshot,
        uri: selected.attachment.uri,
        width: selected.width,
        height: selected.height,
        scope: files.owner.sourceOwner.scope,
        scopeEpoch: files.owner.sourceOwner.epoch,
        resourceIdentity: body.identity,
      );
      insertionStage = 'inserted_checkpoint';
      snapshot = null;
      final changed = await transport.capture();
      try {
        await editor.checkpoint(capturedEdit(changed));
        durable = editor.draftDurable;
      } finally {
        await transport.release(changed);
      }
      if (!durable) {
        throw StateError('Inserted local draft durability unconfirmed');
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '图片已插入并保留草稿，仍需明确保存正文。',
            'Image inserted and draft retained. Explicit body Save is still required.',
          ),
        );
      }
    } catch (error) {
      const safeHostCodes = {
        'mindmap_preflight_mode',
        'mindmap_preflight_context',
        'mindmap_preflight_args',
        'mindmap_preflight_scope',
        'mindmap_preflight_dimensions',
        'mindmap_preflight_reference',
        'mindmap_preflight_queue',
        'mindmap_preflight_gate',
        'invalid_local_mindmap_image',
        'invalid_local_mindmap_reference',
        'local_mindmap_image_capacity',
        'local_mindmap_selection_changed',
        'retired_local_mindmap_image',
        'local_mindmap_image_not_observed',
      };
      final detail = error is PlatformException ? error.details : null;
      final hostCode = detail is String && safeHostCodes.contains(detail)
          ? detail
          : error is PlatformException
          ? (const {
                  'editor_command_failed',
                  'editor_timeout',
                  'invalid_command',
                }.contains(error.code)
                ? error.code
                : 'platform_error')
          : error is StateError
          ? 'state_error'
          : error is FormatException
          ? 'format_error'
          : 'failure';
      debugPrint('mindmap_insert:$insertionStage:$hostCode');
      if (attempted &&
          mounted &&
          identical(editor, owner) &&
          editor.editable &&
          transport.generation != null) {
        try {
          final changed = await transport.capture();
          try {
            await editor.checkpoint(capturedEdit(changed));
            durable = editor.draftDurable;
          } finally {
            await transport.release(changed);
          }
        } catch (_) {}
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '插入结果未确认，请核对正文。不会自动再次插入，图片仍在本地文件库。',
            'Insertion is unconfirmed. Inspect the body; nothing is reinserted automatically. Image remains in the local library.',
          ),
        );
      }
    } finally {
      if (!barrier.isCompleted) barrier.complete(durable);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (_localMindmapCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted && identical(editor, owner)) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Widget _localMindmapSelection() {
    final selected = _selectedLocalMindmapImage!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .24,
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.memory(selected.preview, height: 64, cacheWidth: 320),
              Text(selected.attachment.name),
              Text(
                '${selected.width} × ${selected.height} · ${selected.preview.length} bytes',
              ),
              Text(
                t(
                  '文件已保留在本地；插入后仍需保存正文。',
                  'File retained locally. Insertion still requires body Save.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _localMindmapActionAvailable
                        ? _insertLocalMindmapImage
                        : null,
                    child: Text(t('插入图片', 'Insert image')),
                  ),
                  TextButton(
                    onPressed: _attachmentBusy
                        ? null
                        : () =>
                              setState(() => _selectedLocalMindmapImage = null),
                    child: Text(t('仅保留文件', 'Keep file only')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportUnloadedDrawing() async {
    final files = widget.localDrawingFiles;
    final scope = widget.sourceIoScope;
    if (!_drawingInitializationFailed ||
        files == null ||
        scope == null ||
        !_localDrawingCurrent(files) ||
        _saving ||
        _sourceIoBusy ||
        _attachmentBusy ||
        _retiringSurface)
      return;
    final editor = owner;
    final document = editor.edit.document;
    final record = LocalDrawingRetainedExport(
      document: document,
      verifyFresh: () async {
        scope.guard();
        files.guard();
        if (!mounted ||
            !identical(editor, owner) ||
            !identical(widget.sourceIoScope, scope) ||
            !_localDrawingCurrent(files) ||
            !editor.edit.document.same(document)) {
          throw StateError('Retained drawing source changed');
        }
      },
    );
    await record.verifyFresh();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LocalDrawingRetainedExportPage(
          record: record,
          sourceIoScope: scope,
          isCurrent: () =>
              mounted &&
              _localDrawingCurrent(files) &&
              identical(owner, editor) &&
              editor.edit.document.same(document),
          english: widget.english,
        ),
      ),
    );
  }

  Future<void> _chooseLocalDrawingImage() async {
    final files = widget.localDrawingFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    if (!_localDrawingActionAvailable || files == null || transport == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var pickerOpened = false;
    try {
      await _draftJob;
      if (!mounted || !_localDrawingCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localDrawingCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable local draft required');
      }
      await transport.release(snapshot);
      snapshot = null;
      barrier.complete(true);
      if (!mounted || !_localDrawingCurrent(files)) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('添加本地图片', 'Add local image'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              Text(
                t(
                  '图片留在当前本地空间，不上传服务器；导入不会保存正文。',
                  'Images stay in this local space; nothing is uploaded. Import does not save the body.',
                ),
              ),
              ListTile(
                title: Text(t('从设备文件导入', 'Import from device')),
                leading: const Icon(Icons.folder_open_outlined),
                onTap: () => Navigator.pop(sheet, 'device'),
              ),
              ListTile(
                title: Text(t('从本地文件库选择', 'Choose from local file library')),
                leading: const Icon(Icons.collections_bookmark_outlined),
                onTap: () => Navigator.pop(sheet, 'library'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !_localDrawingCurrent(files) || action == null) return;
      LocalDrawingSelectedImage? selected;
      if (action == 'device') {
        pickerOpened = true;
        await HtmlBrowserSession.closeActive();
        if (!mounted || !_localDrawingCurrent(files)) return;
        _sourceIoPickerExpected = true;
        final file = await (widget.pickAttachment?.call() ?? openFile());
        if (!mounted || !_localDrawingCurrent(files) || file == null) return;
        selected = await files.importDeviceFile(file);
      } else if (action == 'library') {
        final node = await showModalBottomSheet<DriveNode>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => LocalDrawingImageLibrarySheet(
            owner: files,
            english: widget.english,
          ),
        );
        if (!mounted || !_localDrawingCurrent(files) || node == null) return;
        selected = await files.selectLibraryFile(node);
      }
      if (!mounted || !_localDrawingCurrent(files) || selected == null) return;
      setState(() {
        _selectedLocalDrawingImage = selected;
        _notice = pickerOpened
            ? t(
                '图片已保留在本地文件库。重新载入画板后明确插入。',
                'Image retained in the local library. Reload the drawing, then insert explicitly.',
              )
            : t(
                '图片已选中。返回画板后明确插入，正文仍需保存。',
                'Image selected. Return to the drawing, insert explicitly, then Save the body.',
              );
      });
    } catch (_) {
      if (_localDrawingCurrent(files)) {
        setState(
          () => _notice = t(
            '图片处理未完成，原正文保留。请检查 PNG/JPEG/GIF/WebP 和 5 MiB 限制。',
            'Image handling did not finish. Original body retained. Check PNG/JPEG/GIF/WebP and the 5 MiB limit.',
          ),
        );
      }
    } finally {
      if (pickerOpened) _sourceIoPickerExpected = false;
      if (!barrier.isCompleted) barrier.complete(false);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (!pickerOpened &&
          _localDrawingCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _insertLocalDrawingImage() async {
    final files = widget.localDrawingFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    final selected = _selectedLocalDrawingImage;
    if (!_localDrawingActionAvailable ||
        files == null ||
        transport == null ||
        selected == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var attempted = false, durable = false;
    try {
      await _draftJob;
      if (!mounted || !_localDrawingCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localDrawingCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable source checkpoint required');
      }
      final body = files.owner.currentBody;
      final resourceId = await files.prepareExplicitInsertion(
        body,
        selected,
        snapshot.document,
      );
      if (!mounted || !_localDrawingCurrent(files)) return;
      // One actual user command: an interrupted acknowledgement never resends it.
      attempted = true;
      _selectedLocalDrawingImage = null;
      await transport.insertLocalDrawingImage(
        snapshot,
        uri: selected.attachment.uri,
        resourceId: resourceId,
        width: selected.width,
        height: selected.height,
        scope: files.owner.sourceOwner.scope,
        scopeEpoch: files.owner.sourceOwner.epoch,
        resourceIdentity: body.identity,
      );
      snapshot = null;
      final changed = await transport.capture();
      try {
        await editor.checkpoint(capturedEdit(changed));
        durable = editor.draftDurable;
      } finally {
        await transport.release(changed);
      }
      if (!durable) {
        throw StateError('Inserted local draft durability unconfirmed');
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '图片已插入并保留草稿，仍需明确保存正文。',
            'Image inserted and draft retained. Explicit body Save is still required.',
          ),
        );
      }
    } catch (_) {
      if (attempted &&
          mounted &&
          identical(editor, owner) &&
          editor.editable &&
          transport.generation != null) {
        try {
          final changed = await transport.capture();
          try {
            await editor.checkpoint(capturedEdit(changed));
            durable = editor.draftDurable;
          } finally {
            await transport.release(changed);
          }
        } catch (_) {}
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '插入结果未确认，请核对正文。不会自动再次插入，图片仍在本地文件库。',
            'Insertion is unconfirmed. Inspect the body; nothing is reinserted automatically. Image remains in the local library.',
          ),
        );
      }
    } finally {
      if (!barrier.isCompleted) barrier.complete(durable);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (_localDrawingCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted && identical(editor, owner)) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Widget _localDrawingSelection() {
    final selected = _selectedLocalDrawingImage!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .24,
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.memory(selected.preview, height: 64, cacheWidth: 320),
              Text(selected.attachment.name),
              Text(
                '${selected.width} × ${selected.height} · ${selected.preview.length} bytes',
              ),
              Text(
                t(
                  '文件已保留在本地；插入后仍需保存正文。',
                  'File retained locally. Insertion still requires body Save.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _localDrawingActionAvailable
                        ? _insertLocalDrawingImage
                        : null,
                    child: Text(t('插入图片', 'Insert image')),
                  ),
                  TextButton(
                    onPressed: _attachmentBusy
                        ? null
                        : () =>
                              setState(() => _selectedLocalDrawingImage = null),
                    child: Text(t('仅保留文件', 'Keep file only')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseLocalPresentationImage() async {
    final files = widget.localPresentationFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    if (!_localPresentationActionAvailable ||
        files == null ||
        transport == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var pickerOpened = false;
    try {
      await _draftJob;
      if (!mounted || !_localPresentationCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localPresentationCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable local draft required');
      }
      await transport.release(snapshot);
      snapshot = null;
      barrier.complete(true);
      if (!mounted || !_localPresentationCurrent(files)) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(sheet).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('添加本地图片', 'Add local image'),
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
              Text(
                t(
                  '图片留在当前本地空间，不上传服务器；导入不会保存正文。',
                  'Images stay in this local space; nothing is uploaded. Import does not save the body.',
                ),
              ),
              ListTile(
                title: Text(t('从设备文件导入', 'Import from device')),
                leading: const Icon(Icons.folder_open_outlined),
                onTap: () => Navigator.pop(sheet, 'device'),
              ),
              ListTile(
                title: Text(t('从本地文件库选择', 'Choose from local file library')),
                leading: const Icon(Icons.collections_bookmark_outlined),
                onTap: () => Navigator.pop(sheet, 'library'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(t('取消', 'Cancel')),
              ),
            ],
          ),
        ),
      );
      if (!mounted || !_localPresentationCurrent(files) || action == null)
        return;
      LocalPresentationSelectedImage? selected;
      if (action == 'device') {
        pickerOpened = true;
        await HtmlBrowserSession.closeActive();
        if (!mounted || !_localPresentationCurrent(files)) return;
        _sourceIoPickerExpected = true;
        final file = await (widget.pickAttachment?.call() ?? openFile());
        if (!mounted || !_localPresentationCurrent(files) || file == null)
          return;
        selected = await files.importDeviceFile(file);
      } else if (action == 'library') {
        final node = await showModalBottomSheet<DriveNode>(
          context: context,
          useSafeArea: true,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => LocalPresentationImageLibrarySheet(
            owner: files,
            english: widget.english,
          ),
        );
        if (!mounted || !_localPresentationCurrent(files) || node == null)
          return;
        selected = await files.selectLibraryFile(node);
      }
      if (!mounted || !_localPresentationCurrent(files) || selected == null)
        return;
      setState(() {
        _selectedLocalPresentationImage = selected;
        _notice = pickerOpened
            ? t(
                '图片已保留在本地文件库。重新载入演示文稿，选择当前幻灯片后明确插入。',
                'Image retained in the local library. Reload the presentation, select the current slide, then insert explicitly.',
              )
            : t(
                '图片已选中。选择当前幻灯片后明确插入，正文仍需保存。',
                'Image selected. Select the current slide, insert explicitly, then Save the body.',
              );
      });
    } catch (_) {
      if (_localPresentationCurrent(files)) {
        setState(
          () => _notice = t(
            '图片处理未完成，原正文保留。请检查 PNG/JPEG/GIF/WebP 和 5 MiB 限制。',
            'Image handling did not finish. Original body retained. Check PNG/JPEG/GIF/WebP and the 5 MiB limit.',
          ),
        );
      }
    } finally {
      if (pickerOpened) _sourceIoPickerExpected = false;
      if (!barrier.isCompleted) barrier.complete(false);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (!pickerOpened &&
          _localPresentationCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _insertLocalPresentationImage() async {
    final files = widget.localPresentationFiles, transport = _transport;
    final editor = owner;
    ComplexNoteEdit capturedEdit(ComplexEditorSnapshot snapshot) =>
        ComplexNoteEdit(
          title: editor.edit.title,
          document: snapshot.document,
          labels: editor.edit.labels,
        );
    final selected = _selectedLocalPresentationImage;
    if (!_localPresentationActionAvailable ||
        files == null ||
        transport == null ||
        selected == null) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    ComplexEditorSnapshot? snapshot;
    var attempted = false, durable = false;
    try {
      await _draftJob;
      if (!mounted || !_localPresentationCurrent(files)) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted ||
          !_localPresentationCurrent(files) ||
          !identical(editor, owner)) {
        return;
      }
      await editor.checkpoint(capturedEdit(snapshot));
      if (editor.dirty && !editor.draftDurable) {
        throw StateError('Durable source checkpoint required');
      }
      final body = files.owner.currentBody;
      final resourceId = await files.prepareExplicitInsertion(
        body,
        selected,
        snapshot.document,
      );
      if (!mounted || !_localPresentationCurrent(files)) return;
      // One actual user command: an interrupted acknowledgement never resends it.
      attempted = true;
      _selectedLocalPresentationImage = null;
      await transport.insertLocalPresentationImage(
        snapshot,
        uri: selected.attachment.uri,
        resourceId: resourceId,
        width: selected.width,
        height: selected.height,
        scope: files.owner.sourceOwner.scope,
        scopeEpoch: files.owner.sourceOwner.epoch,
        resourceIdentity: body.identity,
      );
      snapshot = null;
      final changed = await transport.capture();
      try {
        await editor.checkpoint(capturedEdit(changed));
        durable = editor.draftDurable;
      } finally {
        await transport.release(changed);
      }
      if (!durable) {
        throw StateError('Inserted local draft durability unconfirmed');
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '图片已插入并保留草稿，仍需明确保存正文。',
            'Image inserted and draft retained. Explicit body Save is still required.',
          ),
        );
      }
    } catch (_) {
      if (attempted &&
          mounted &&
          identical(editor, owner) &&
          editor.editable &&
          transport.generation != null) {
        try {
          final changed = await transport.capture();
          try {
            await editor.checkpoint(capturedEdit(changed));
            durable = editor.draftDurable;
          } finally {
            await transport.release(changed);
          }
        } catch (_) {}
      }
      if (mounted && identical(editor, owner)) {
        setState(
          () => _notice = t(
            '插入结果未确认，请核对正文。不会自动再次插入，图片仍在本地文件库。',
            'Insertion is unconfirmed. Inspect the body; nothing is reinserted automatically. Image remains in the local library.',
          ),
        );
      }
    } finally {
      if (!barrier.isCompleted) barrier.complete(durable);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (_localPresentationCurrent(files) &&
          !_retiringSurface &&
          identical(_transport, transport) &&
          transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (identical(_attachmentCheckpoint, barrier.future)) {
        _attachmentCheckpoint = null;
      }
      if (mounted && identical(editor, owner)) {
        setState(() => _attachmentBusy = false);
      }
    }
  }

  Widget _localPresentationSelection() {
    final selected = _selectedLocalPresentationImage!;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .24,
      child: Card(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.memory(selected.preview, height: 64, cacheWidth: 320),
              Text(selected.attachment.name),
              Text(
                '${selected.width} × ${selected.height} · ${selected.preview.length} bytes',
              ),
              Text(
                t(
                  '文件已保留在本地；插入后仍需保存正文。',
                  'File retained locally. Insertion still requires body Save.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: _localPresentationActionAvailable
                        ? _insertLocalPresentationImage
                        : null,
                    child: Text(t('插入图片', 'Insert image')),
                  ),
                  TextButton(
                    onPressed: _attachmentBusy
                        ? null
                        : () => setState(
                            () => _selectedLocalPresentationImage = null,
                          ),
                    child: Text(t('仅保留文件', 'Keep file only')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _attachment() async {
    final attachments = widget.attachments;
    if (!_attachmentArticle ||
        attachments == null ||
        _attachmentBusy ||
        _sourceIoBusy ||
        _saving ||
        owner.busy ||
        !owner.editable ||
        _retiringSurface) {
      return;
    }
    final action = await chooseLocalArticleAttachment(
      context,
      english: widget.english,
    );
    if (!mounted ||
        action == null ||
        _transport == null ||
        _retiringSurface ||
        owner.busy ||
        !owner.editable) {
      return;
    }
    setState(() => _attachmentBusy = true);
    _captureAgain = false;
    _timer?.cancel();
    final barrier = Completer<bool>();
    _attachmentCheckpoint = barrier.future;
    final transport = _transport!;
    ComplexEditorSnapshot? snapshot;
    var pickerOpened = false;
    NativeLocalArticleAttachmentPicker? nativePicker;
    PickedLocalArticleAttachment? pickedInbox;
    final cancellation = AttachmentCancellation();
    _attachmentCancellation = cancellation;
    try {
      await _draftJob;
      if (!mounted || _retiringSurface) return;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      final selection = snapshot.markdownSelection;
      if (selection == null) {
        throw StateError('Local article selection unavailable');
      }
      final source = snapshot.document;
      await owner.checkpoint(_edit(snapshot));
      barrier.complete(true);
      if (!mounted) return;
      if (action == LocalArticleAttachmentAction.device) {
        await transport.release(snapshot);
        snapshot = null;
        // The old runtime ends before the system activity opens. The selection
        // is now bound to the exact durable source, not an old JS object.
        await HtmlBrowserSession.closeActive();
        if (!mounted) return;
        pickerOpened = true;
        XFile? file;
        if (widget.pickAttachment != null) {
          file = await widget.pickAttachment!();
        } else {
          final picker = NativeLocalArticleAttachmentPicker();
          nativePicker = picker;
          _nativeAttachmentPicker = picker;
          pickedInbox = await picker.pick();
          if (mounted && pickedInbox != null) {
            file = await picker.open(pickedInbox);
          }
        }
        if (!mounted || file == null) return;
        final attachment = await importLocalArticleAttachment(
          attachments,
          file,
          cancellation: cancellation,
        );
        if (!mounted) return;
        final markup = markdownAttachment(
          attachment.name,
          attachment.uri,
          image: attachment.image,
        );
        setState(() {
          _importedSizes[attachment.uri] = attachment.size;
          _pendingAttachmentMarkup = markup;
        });
        if (!owner.editable || owner.edit.document.digest != source.digest) {
          setState(
            () => _notice = t(
              '附件已导入，正文已变化；请复制链接后选择插入位置。',
              'Attachment imported. The source changed; copy its link and choose an insertion position.',
            ),
          );
          return;
        }
        await owner.checkpoint(
          ComplexNoteEdit(
            title: owner.edit.title,
            document: selection.insert(source, markup),
            labels: owner.edit.labels,
          ),
        );
        if (mounted) {
          setState(() {
            _pendingAttachmentMarkup = null;
            _notice = t(
              '附件已插入，文章尚未保存。',
              'Attachment inserted. The article is not saved yet.',
            );
          });
        }
      } else {
        final markup = await enterLocalArticleLink(
          context,
          english: widget.english,
        );
        if (!mounted || markup == null) return;
        if (_retiringSurface ||
            transport.generation == null ||
            !identical(_transport, transport) ||
            owner.edit.document.digest != source.digest) {
          setState(() {
            _pendingAttachmentMarkup = markup;
            _notice = t(
              '链接已保留，请重新打开编辑器后复制插入。',
              'The link is retained. Reopen the editor and copy it to insert.',
            );
          });
          return;
        }
        await transport.insertMarkdown(snapshot, text: markup);
        snapshot = null;
        final inserted = await transport.capture();
        try {
          await owner.checkpoint(_edit(inserted));
        } finally {
          await transport.release(inserted);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '附件处理未完成，正文和已有文件已保留，请重试。',
            'Attachment handling is incomplete. Source and existing files are retained; retry.',
          ),
        );
      }
    } finally {
      if (!barrier.isCompleted) barrier.complete(false);
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (!pickerOpened && !_retiringSurface && transport.generation != null) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      final picked = pickedInbox, picker = nativePicker;
      if (picked != null && picker != null) {
        try {
          await picker.release(picked);
        } catch (_) {}
      }
      if (picker != null) {
        try {
          await picker.dispose();
        } catch (_) {}
      }
      if (identical(_nativeAttachmentPicker, picker)) {
        _nativeAttachmentPicker = null;
      }
      _attachmentCheckpoint = null;
      _attachmentCancellation = null;
      if (mounted) {
        setState(() => _attachmentBusy = false);
        if (pickerOpened) {
          _attachmentResumePending = true;
          await _resumeAttachment();
        }
      }
    }
  }

  Future<void> _resumeAttachment() async {
    if (!_attachmentResumePending ||
        !mounted ||
        owner.busy ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _attachmentResumePending = false;
    await _reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_sourceIoPickerExpected) {
      _sourceIoJob?.retire();
      final retire = widget.onUnplannedBackground;
      if (retire != null) unawaited(retire().catchError((Object _) {}));
    }
    if (state == AppLifecycleState.resumed && _attachmentResumePending) {
      unawaited(_resumeAttachment());
    }
  }

  List<Attachment> get _localAttachmentReferences {
    final attachments = widget.attachments;
    if (!_attachmentArticle || attachments == null) return const [];
    final document = owner.edit.document;
    if (_attachmentReferenceDigest != document.digest) {
      _attachmentReferenceDigest = document.digest;
      _attachmentReferences = noteAttachments(document.source, attachments.owns)
          .where((attachment) => attachments.owns(attachment.uri))
          .toList(growable: false);
    }
    return _attachmentReferences;
  }

  Future<void> _shareAttachment(Attachment attachment) async {
    final attachments = widget.attachments;
    if (attachments == null || _attachmentBusy) return;
    await openBookstarkLink(
      context,
      attachment.name,
      attachment.uri.toString(),
      repository: attachments,
      english: widget.english,
      onShare: (value) async {
        try {
          await HtmlBrowserSession.closeActive();
          if (mounted) {
            await shareBookstarkAttachment(context, attachments, value);
          }
        } catch (_) {
          if (mounted) {
            setState(
              () => _notice = t(
                '附件暂时无法打开，原文件和正文已保留。',
                'Attachment unavailable. Original file and source are retained.',
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _openAttachment(Attachment attachment) async {
    final attachments = widget.attachments;
    if (attachments == null || _attachmentBusy) return;
    if (!attachment.image) {
      await _shareAttachment(attachment);
      return;
    }
    final generation = _surfaceKey;
    final scope = LocalMarkdownResources(attachments);
    try {
      final image = await scope.read(attachment.uri);
      if (!mounted ||
          generation != _surfaceKey ||
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Scaffold(
            appBar: AppBar(title: Text(attachment.name)),
            body: Center(
              child: NativeImage(
                bytes: image.bytes,
                label: attachment.name,
                english: widget.english,
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) setState(() => _localImageFailures = 1);
    } finally {
      scope.close();
    }
  }

  bool get _imageActionAvailable =>
      widget.ownedImages != null &&
      widget.ownedImages!.lease.current &&
      widget.ownedImages!.insertionSupported &&
      !widget.ownedImages!.initializationFailed &&
      !_sourceIoBusy &&
      !_saving &&
      !owner.busy &&
      owner.editable &&
      _transport != null &&
      !_retiringSurface;

  Future<void> _uploadOwnedImage() async {
    final images = widget.ownedImages, transport = _transport;
    if (!_imageActionAvailable ||
        images == null ||
        transport == null ||
        !images.upload.canUpload) {
      return;
    }
    if (owner.ephemeralDrafts) {
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
    setState(() => _sourceIoBusy = true);
    _timer?.cancel();
    _captureAgain = false;
    try {
      final result = await images.picker.pickAndUpload(
        verifyFreshBinding: images.verifyFreshSource,
        confirm: (selection) async {
          if (!mounted || !images.lease.current) return false;
          return confirmOwnedImageUpload(
            context,
            selection,
            english: widget.english,
            protectedDocument: owner.ephemeralDrafts,
          );
        },
        preparePickerHandoff: () async {
          final pending = _draftJob;
          if (pending != null) await pending;
          images.lease.guard();
          await transport.setInputLocked(true);
          final captured = await transport.capture();
          try {
            await owner.checkpoint(_edit(captured));
          } finally {
            await transport.release(captured);
          }
          _sourceIoHandoff = true;
          await HtmlBrowserSession.closeActive();
        },
        resumeEditor: () async {
          if (mounted && images.lease.current) {
            _sourceIoHandoff = false;
            await _replaceSurface();
          }
        },
      );
      if (mounted) {
        setState(
          () => _notice = result == OwnedImagePickResult.cancelled
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
          () => _notice = t(
            '图片操作未完成。正文和上传核对记录已保留，不会自动重传。',
            'Image operation incomplete. Source and upload review retained; no automatic reupload.',
          ),
        );
      }
    } finally {
      _sourceIoHandoff = false;
      if (mounted) setState(() => _sourceIoBusy = false);
    }
  }

  Future<void> _insertOwnedImage({bool existing = false}) async {
    final images = widget.ownedImages, transport = _transport;
    if (!_imageActionAvailable || images == null || transport == null) return;
    setState(() => _sourceIoBusy = true);
    _timer?.cancel();
    _captureAgain = false;
    ComplexEditorSnapshot? frozen;
    try {
      final library = images.serverImages;
      final choice = existing
          ? await chooseOwnedServerImage(
              context,
              library: library,
              english: widget.english,
              protectedDocument: owner.ephemeralDrafts,
            )
          : null;
      if (existing && choice == null) return;
      if (!mounted ||
          !images.lease.current ||
          !identical(_transport, transport)) {
        return;
      }
      final pending = _draftJob;
      if (pending != null) await pending;
      await transport.setInputLocked(true);
      frozen = await transport.capture();
      final snapshot = frozen;
      await owner.checkpoint(_edit(snapshot));
      Future<bool> verify() async =>
          mounted &&
          identical(_transport, transport) &&
          images.lease.current &&
          await images.verifyFreshSource();
      Future<void> insert(Uri url, int id) async {
        final actual = await images.prepareExplicitInsertion(id: id, url: url);
        if (!await verify()) throw StateError('Image insertion source changed');
        await transport.insertOwnedImage(
          snapshot,
          url: actual.url,
          width: actual.width,
          height: actual.height,
        );
        frozen = null;
        final changed = await transport.capture();
        try {
          await owner.checkpoint(_edit(changed));
        } finally {
          await transport.release(changed);
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
          () => _notice = t(
            '图片已插入草稿，仍需明确保存。',
            'Image inserted into draft. Explicit Save is still required.',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
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
      if (mounted && identical(_transport, transport) && !_retiringSurface) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (mounted) setState(() => _sourceIoBusy = false);
    }
  }

  Future<void> _retryOwnedImageStorage() async {
    final images = widget.ownedImages;
    if (!_imageActionAvailable || images == null) return;
    setState(() => _sourceIoBusy = true);
    try {
      if (images.upload.needsStorageRetry) {
        await images.upload.retryKnownStorage();
      }
      if (images.upload.record?.phase == OwnedImageUploadPhase.inserted) {
        await images.upload.dismissInserted();
      }
    } catch (_) {
      if (mounted) {
        _notice = t(
          '图片记录清理未确认；不会重新上传。',
          'Image record cleanup unconfirmed; no reupload.',
        );
      }
    } finally {
      if (mounted) setState(() => _sourceIoBusy = false);
    }
  }

  Future<void> _runSourceIo() async {
    final scope = widget.sourceIoScope, transport = _transport;
    if (scope == null ||
        transport == null ||
        _sourceIoBusy ||
        _attachmentBusy ||
        _saving ||
        owner.busy ||
        !owner.editable ||
        _retiringSurface) {
      return;
    }
    try {
      scope.guard();
    } catch (_) {
      return;
    }
    final selected = await showComplexSourceIoSheet(
      context,
      format: owner.edit.document.kind == ComplexEditorKind.markdown
          ? 'Markdown'
          : owner.edit.document.kind == ComplexEditorKind.html
          ? 'HTML'
          : '${owner.edit.document.kind.name} JSON',
      english: widget.english,
    );
    if (!mounted || selected == null || !identical(_transport, transport)) {
      return;
    }
    final memoryOnly = owner.ephemeralDrafts;
    if (memoryOnly) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          scrollable: true,
          title: Text(t('仅在本次会话保留正文', 'Body retained only in this session')),
          content: Text(
            t(
              '文件选择期间仅在内存保留草稿，关闭应用会丢失未保存正文。导出把明文写入你选择的文件；不会创建本机正文恢复备份。仍需明确保存文档。',
              'This draft stays only in memory while choosing a file. Closing the app loses unsaved text. Export writes plaintext to your chosen file; no device body recovery backup is created. Saving remains a separate explicit action.',
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
      if (!mounted ||
          confirmed != true ||
          !identical(_transport, transport) ||
          !owner.editable) {
        return;
      }
    }
    _timer?.cancel();
    _captureAgain = false;
    setState(() => _sourceIoBusy = true);
    final capturedOwner = owner;
    ComplexSourceIoController? io;
    try {
      final pending = _draftJob;
      if (pending != null) await pending;
      if (!mounted ||
          !identical(owner, capturedOwner) ||
          !identical(_transport, transport)) {
        return;
      }
      io = ComplexSourceIoController(
        editor: owner,
        owner: scope,
        allowMemoryOnlyHandoff: memoryOnly,
        isCurrent: () =>
            mounted &&
            identical(owner, capturedOwner) &&
            identical(widget.sourceIoScope, scope),
        onDurableHandoff: (value) {
          _sourceIoHandoff = value;
        },
        capture: () async {
          await transport.setInputLocked(true);
          final snapshot = await transport.capture();
          try {
            return snapshot.document;
          } finally {
            await transport.release(snapshot);
          }
        },
        prepareNative: () async {
          final grant = await transport.sourceIoIdentity();
          return NativeComplexSourceIo(
            owner: scope,
            lease: grant['lease'] as String,
            generation: grant['generation'] as int,
            allowMarkdown:
                capturedOwner.edit.document.kind == ComplexEditorKind.markdown,
            onPickerVisibility: (visible) {
              _sourceIoPickerExpected = visible;
            },
          );
        },
        replaceSurface: _replaceSurface,
      );
      _sourceIoJob = io;
      if (selected == ComplexSourceIoAction.importSource) {
        await io.importSource(
          confirm: (file) => confirmComplexSourceImport(
            context,
            file,
            english: widget.english,
          ),
        );
      } else {
        final suffix = owner.edit.document.kind == ComplexEditorKind.markdown
            ? 'md'
            : owner.edit.document.kind == ComplexEditorKind.html
            ? 'html'
            : 'json';
        final name = '${owner.edit.document.kind.name}-source.$suffix';
        final navigator = Navigator.of(context);
        final progress = MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => ComplexSourceExportProgress(
            controller: io!,
            name: name,
            english: widget.english,
          ),
        );
        unawaited(navigator.push(progress));
        try {
          await io.exportSource(name: name);
        } finally {
          if (progress.isActive) navigator.removeRoute(progress);
        }
      }
      if (mounted) {
        setState(
          () => _notice =
              io!.safeError ??
              (io.phase == ComplexSourceIoPhase.completed
                  ? (selected == ComplexSourceIoAction.importSource
                        ? t(
                            '源文件已导入草稿，仍需保存。',
                            'Source imported into draft. Explicit Save is still required.',
                          )
                        : t(
                            '文件已写全并关闭；未读取目标回验。文档未保存。',
                            'File fully transferred and closed; destination was not read back. Editor document was not saved.',
                          ))
                  : (memoryOnly
                        ? t(
                            '操作已取消；草稿仅在本次会话内存中。',
                            'Operation cancelled; draft remains only in session memory.',
                          )
                        : t(
                            '操作已取消，草稿保留。',
                            'Operation cancelled. Draft retained.',
                          ))),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '源文件操作未完成，草稿与已保存内容保留。',
            'Source file operation incomplete. Draft and saved content retained.',
          ),
        );
      }
    } finally {
      _sourceIoJob = null;
      io?.dispose();
      _sourceIoHandoff = false;
      _sourceIoPickerExpected = false;
      if (mounted && identical(_transport, transport) && !_retiringSurface) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (mounted) setState(() => _sourceIoBusy = false);
    }
  }

  Future<void> _metadata() async {
    if (_bodyOnly) return;
    if (!_metadataAllowed ||
        _attachmentBusy ||
        _editingMetadata ||
        _sourceIoBusy ||
        _saving ||
        _leaving ||
        _retiringSurface ||
        owner.busy ||
        !owner.editable ||
        _transport == null) {
      return;
    }
    final metadataOwner = owner;
    final transport = _transport;
    _editingMetadata = true;
    _timer?.cancel();
    try {
      _captureAgain = true;
      await _draft();
      if (!mounted ||
          !identical(owner, metadataOwner) ||
          _retiringSurface ||
          !owner.editable ||
          owner.phase == ComplexSavePhase.draftFailed ||
          !identical(_transport, transport)) {
        return;
      }
      final result = await showDialog<ArticleMetadata>(
        context: context,
        builder: (context) => Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: const Color(0xff6530ad)),
          ),
          child: ArticleMetadataDialog(
            title: owner.edit.title,
            labels: owner.edit.labels,
            document: owner.edit.document,
            english: widget.english,
            noteMetadata: !_markdownArticle,
          ),
        ),
      );
      if (!mounted ||
          !identical(owner, metadataOwner) ||
          result == null ||
          _retiringSurface ||
          !owner.editable ||
          !identical(_transport, transport)) {
        return;
      }
      await metadataOwner.checkpoint(
        ComplexNoteEdit(
          title: result.title,
          document: owner.edit.document,
          labels: result.labels,
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '信息草稿尚未确认写入，请保留当前页面后重试。',
            'Metadata draft durability is unconfirmed. Keep this page and retry.',
          ),
        );
      }
    } finally {
      _editingMetadata = false;
    }
  }

  Future<bool> _save({bool leave = false}) async {
    if (_drawingResourceFailed ||
        _presentationResourceFailed ||
        _attachmentBusy ||
        _sourceIoBusy ||
        _saving ||
        _editingMetadata ||
        _retiringSurface ||
        !owner.editable ||
        _transport == null) {
      return false;
    }
    _timer?.cancel();
    setState(() {
      _saving = true;
      _notice = null;
    });
    final checkpoint = Completer<bool>();
    _saveCheckpoint = checkpoint.future;
    final transport = _transport!;
    ComplexEditorSnapshot? snapshot;
    var success = false;
    try {
      final pending = _draftJob;
      if (pending != null) await pending;
      await transport.setInputLocked(true);
      snapshot = await transport.capture();
      if (!mounted) return false;
      // Retirement may proceed only after this exact frozen body is durable.
      // The controller subsequently upgrades it to pending before any SQL.
      await owner.checkpoint(_edit(snapshot));
      checkpoint.complete(true);
      if (widget.localDrawingFiles != null) {
        final files = widget.localDrawingFiles!;
        if (!_localDrawingCurrent(files) || !files.owner.currentBody.complete) {
          throw StateError(
            'Drawing image source is incomplete; source retained',
          );
        }
        await transport.verifyLocalDrawingReadyForSave(snapshot);
        if (!mounted || !_localDrawingCurrent(files)) return false;
      }
      if (widget.localPresentationFiles != null) {
        final files = widget.localPresentationFiles!;
        if (!_localPresentationCurrent(files) ||
            !files.owner.currentBody.complete) {
          throw StateError(
            'Presentation image source is incomplete; source retained',
          );
        }
        await transport.verifyLocalPresentationReadyForSave(snapshot);
        if (!mounted || !_localPresentationCurrent(files)) return false;
      }
      final receipt = await owner.save(_edit(snapshot));
      if (!mounted) return false;
      if (receipt != null) {
        // Only a real repository receipt permits the engine's saved marker.
        var acknowledged = false;
        try {
          await transport.acknowledgeSaved(
            snapshot,
            committed: receipt.document,
          );
          acknowledged = true;
        } catch (_) {
          await _replaceSurface(); // Known SQL commit: never resubmit it.
        }
        success =
            owner.phase == ComplexSavePhase.ready && (!leave || acknowledged);
        if (success && leave && identical(_transport, transport)) {
          final latest = await transport.capture();
          try {
            if (!latest.document.same(receipt.document)) {
              await owner.checkpoint(_edit(latest));
              _webDirty = true;
              success = false;
            }
          } finally {
            await transport.release(latest);
          }
        }
        _notice = owner.phase == ComplexSavePhase.ready
            ? null
            : t('内容已保存，本机恢复记录待清理。', 'Saved. Recovery cleanup is pending.');
      } else {
        _notice = owner.requiresReview
            ? t('保存结果待核对', 'Save needs verification')
            : t('保存未确认，请保留当前页面。', 'Save unconfirmed. Keep this page open.');
        if (owner.requiresReview) await _replaceSurface();
      }
      if (success && leave && mounted) {
        _skipCheckpoint = true;
        _allowPop = true;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context, true);
        });
      }
      return success;
    } catch (_) {
      if (mounted) {
        _notice = t('无法完成保存，请保留当前页面。', 'Unable to save. Keep this page open.');
      }
      return false;
    } finally {
      if (snapshot != null) {
        try {
          await transport.release(snapshot);
        } catch (_) {}
      }
      if (!(success && leave) && owner.editable) {
        try {
          await transport.setInputLocked(false);
        } catch (_) {}
      }
      if (mounted) setState(() => _saving = false);
      if (!checkpoint.isCompleted) checkpoint.complete(false);
      if (mounted &&
          _webDirty &&
          owner.editable &&
          !(success && leave) &&
          !_retiringSurface) {
        _captureAgain = true;
        unawaited(_draft());
      }
    }
  }

  Future<void> _renewPreviewIfNeeded() async {
    final previous = _activeRetirementController;
    if (previous == null || !previous.retired) return;
    final renew = widget.renewRetirementController;
    if (renew == null) {
      return; // Legacy callers retain their existing strict deny.
    }
    final next = await renew();
    if (!mounted || identical(previous, next) || next.retired) {
      throw StateError('Preview renewal denied');
    }
    _activeRetirementController = next;
  }

  Future<void> _replaceSurface() async {
    _skipCheckpoint = true;
    try {
      await HtmlBrowserSession.closeActive();
      await _renewPreviewIfNeeded();
      if (!mounted) return;
      setState(() {
        _transport = null;
        _surface = owner.edit.document;
        _surfaceKey++;
        _localImageFailures = 0;
      });
    } finally {
      // A failed native close/renewal must not disable all later checkpoints.
      if (mounted) _skipCheckpoint = false;
    }
  }

  Future<void> _reload() async {
    if (_attachmentBusy || _sourceIoBusy || _saving || owner.busy) return;
    // Background retirement already checkpoints before destroying the surface.
    // Explicit reload also flushes the live surface before recreating it.
    try {
      await HtmlBrowserSession.closeActive();
      await _renewPreviewIfNeeded();
      if (!mounted) return;
      setState(() {
        _transport = null;
        _surface = owner.edit.document;
        _surfaceKey++;
        _localImageFailures = 0;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _notice = t('草稿尚未确认，请重试。', 'Draft unconfirmed. Retry.'));
      }
    }
  }

  Future<void> _review() async {
    if (_sourceIoBusy || _saving || owner.busy) return;
    try {
      final current = await owner.observe();
      await HtmlBrowserSession.closeActive();
      if (!mounted) return;
      final choice = await Navigator.push<ComplexRecoveryChoice>(
        context,
        MaterialPageRoute(
          builder: (_) => ComplexRecoveryReviewPage(
            saved: current,
            draft: owner.edit,
            english: widget.english,
          ),
        ),
      );
      if (!mounted) return;
      if (choice != null) {
        await owner.adoptReviewed(
          current,
          keepDraft: choice == ComplexRecoveryChoice.keepDraft,
        );
        _notice = null;
        _webDirty = false;
      }
      await _replaceSurface();
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '内容可能已变化，请重新核对。',
            'Content may have changed. Review again.',
          ),
        );
      }
    }
  }

  Future<void> _leave() async {
    if (_attachmentBusy || _leaving || _sourceIoBusy || _saving || owner.busy) {
      return;
    }
    _leaving = true;
    ComplexEditorTransport? leavingTransport;
    try {
      _timer?.cancel();
      _captureAgain = false;
      final draft = _draftJob;
      if (draft != null) await draft;
      // Dirty callbacks are asynchronous. Freeze and inspect the real engine
      // before deciding that leaving is clean, even if no callback arrived.
      if (owner.editable && _transport != null) {
        leavingTransport = _transport!;
        await leavingTransport.setInputLocked(true);
        final snapshot = await leavingTransport.capture();
        try {
          await owner.checkpoint(_edit(snapshot));
        } finally {
          await leavingTransport.release(snapshot);
        }
      }
      if (owner.requiresReview ||
          owner.phase == ComplexSavePhase.committedCleanupFailed) {
        setState(
          () => _notice = t(
            '请先核对保存结果或完成恢复记录清理。',
            'Review the save or finish recovery cleanup first.',
          ),
        );
        return;
      }
      if (!mounted) return;
      if (_webDirty || owner.dirty) {
        final choice = await showDialog<int>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t('离开前保存修改？', 'Save before leaving?')),
            content: Text(
              t('保存失败时将保留当前页面。', 'If saving fails, this page stays open.'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 0),
                child: Text(t('继续编辑', 'Keep editing')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 1),
                child: Text(t('放弃修改', 'Discard')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, 2),
                child: Text(t('保存并离开', 'Save and leave')),
              ),
            ],
          ),
        );
        if (!mounted || choice == null || choice == 0) return;
        if (choice == 2) {
          await _save(leave: true);
          return;
        }
        _timer?.cancel();
        _captureAgain = false;
        final pending = _draftJob;
        if (pending != null) await pending;
        await owner.discard();
        _skipCheckpoint = true;
      } else {
        _timer?.cancel();
        final pending = _draftJob;
        if (pending != null) await pending;
        if (owner.dirty) return; // A capture completed after the initial check.
        _skipCheckpoint = true;
      }
      if (!mounted) return;
      setState(() => _allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _notice = t(
            '操作尚未确认，当前页面已保留。',
            'Operation unconfirmed. Page retained.',
          ),
        );
      }
    } finally {
      if (!_allowPop && owner.editable && leavingTransport != null) {
        try {
          await leavingTransport.setInputLocked(false);
        } catch (_) {}
      }
      _leaving = false;
    }
  }

  double get _attachmentFooterExtent {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return 96.0 + 40.0 * (scale.clamp(1.0, 2.0) - 1.0);
  }

  Widget _body({required List<Widget> children}) {
    if (widget.localRichdocFiles != null ||
        widget.localMindmapFiles != null ||
        widget.localDrawingFiles != null ||
        widget.localPresentationFiles != null) {
      final editorIndex = children.indexWhere(
        (child) => child.key == const ValueKey('local-article-editor-area'),
      );
      if (editorIndex >= 0) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxHeight;
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            final minimumEditor = (140.0 * scale)
                .clamp(140.0, 280.0)
                .clamp(0.0, available * .4);
            final footer = children.sublist(editorIndex + 1);
            final footerExtent = footer.isEmpty
                ? 0.0
                : (MediaQuery.sizeOf(context).height * .24).clamp(
                    0.0,
                    available * .32,
                  );
            final headerExtent = (available - minimumEditor - footerExtent)
                .clamp(0.0, available);
            return Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: headerExtent),
                  child: SingleChildScrollView(
                    key: ValueKey(
                      widget.localMindmapFiles != null
                          ? 'local-mindmap-information-scroll'
                          : widget.localDrawingFiles != null
                          ? 'local-drawing-information-scroll'
                          : widget.localPresentationFiles != null
                          ? 'local-presentation-information-scroll'
                          : 'local-richdoc-information-scroll',
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: children.sublist(0, editorIndex),
                    ),
                  ),
                ),
                children[editorIndex],
                if (footer.isNotEmpty)
                  SizedBox(
                    height: footerExtent,
                    child: Column(
                      children: [
                        for (final item in footer) Flexible(child: item),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      }
    }
    if (!_attachmentArticle) return Column(children: children);
    final editorIndex = children.indexWhere(
      (child) => child.key == const ValueKey('local-article-editor-area'),
    );
    if (editorIndex < 0) return Column(children: children);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
        final minimumEditor = (140.0 * scale).clamp(140.0, 280.0);
        final footer = children.sublist(editorIndex + 1);
        final footerExtent = _attachmentFooterExtent;
        final showFooter =
            footer.isNotEmpty &&
            constraints.maxHeight >= minimumEditor + footerExtent;
        final maximumHeader =
            (constraints.maxHeight -
                    minimumEditor -
                    (showFooter ? footerExtent : 0))
                .clamp(0.0, constraints.maxHeight);
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maximumHeader),
              child: SingleChildScrollView(
                key: const ValueKey('local-article-information-scroll'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: children.sublist(0, editorIndex),
                ),
              ),
            ),
            children[editorIndex],
            if (showFooter) ...footer,
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) unawaited(_leave());
    },
    child: Scaffold(
      backgroundColor: _attachmentArticle ? const Color(0xfffcfaff) : null,
      appBar: AppBar(
        backgroundColor: _attachmentArticle
            ? const Color(0xff6530ad)
            : _markdownArticle
            ? Colors.white
            : null,
        foregroundColor: _attachmentArticle ? Colors.white : null,
        centerTitle: _attachmentArticle ? true : null,
        surfaceTintColor: _markdownArticle ? Colors.transparent : null,
        title: _attachmentArticle
            ? Text(
                t('本地文章', 'Local article'),
                style: const TextStyle(color: Colors.white),
              )
            : _metadataAllowed
            ? Tooltip(
                message: _markdownArticle
                    ? t('文章信息', 'Article information')
                    : t('笔记信息', 'Note information'),
                child: TextButton(
                  onPressed:
                      owner.busy ||
                          !owner.editable ||
                          _transport == null ||
                          _retiringSurface
                      ? null
                      : _metadata,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xff172033),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          owner.edit.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (!_markdownArticle) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_outlined, size: 18),
                      ],
                    ],
                  ),
                ),
              )
            : Text(owner.edit.title),
        actions: [
          if (widget.sourceIoScope != null)
            IconButton(
              tooltip: t('源文件导入与导出', 'Source file import and export'),
              onPressed:
                  _sourceIoBusy ||
                      _attachmentBusy ||
                      _saving ||
                      owner.busy ||
                      !owner.editable ||
                      _transport == null ||
                      _retiringSurface
                  ? null
                  : _runSourceIo,
              icon: const Icon(Icons.import_export),
            ),
          if (widget.localRichdocFiles != null)
            IconButton(
              tooltip: t('添加本地图片', 'Add local image'),
              onPressed: _localRichdocActionAvailable
                  ? _chooseLocalRichdocImage
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          if (widget.localMindmapFiles != null)
            IconButton(
              tooltip: t('添加本地图片', 'Add local image'),
              onPressed: _localMindmapActionAvailable
                  ? _chooseLocalMindmapImage
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          if (_drawingInitializationFailed && widget.localDrawingFiles != null)
            IconButton(
              tooltip: t('导出保留的画板源码', 'Export retained drawing source'),
              onPressed: _sourceIoBusy || _saving || _retiringSurface
                  ? null
                  : _exportUnloadedDrawing,
              icon: const Icon(Icons.file_download_outlined),
            ),
          if (widget.localDrawingFiles != null)
            IconButton(
              tooltip: t('添加本地图片', 'Add local image'),
              onPressed: _localDrawingActionAvailable
                  ? _chooseLocalDrawingImage
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          if (widget.localPresentationFiles != null)
            IconButton(
              tooltip: t('添加本地图片', 'Add local image'),
              onPressed: _localPresentationActionAvailable
                  ? _chooseLocalPresentationImage
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          if (widget.ownedImages != null)
            IconButton(
              tooltip: t('上传图片', 'Upload image'),
              onPressed:
                  _imageActionAvailable && widget.ownedImages!.upload.canUpload
                  ? _uploadOwnedImage
                  : null,
              icon: const Icon(Icons.add_photo_alternate_outlined),
            ),
          if (_attachmentArticle)
            IconButton(
              tooltip: t('插入附件', 'Insert attachment'),
              onPressed:
                  _attachmentBusy ||
                      _sourceIoBusy ||
                      _saving ||
                      owner.busy ||
                      !owner.editable ||
                      _transport == null ||
                      _retiringSurface
                  ? null
                  : _attachment,
              icon: const Icon(Icons.attach_file),
            ),
          if (owner.requiresReview)
            TextButton(
              onPressed: owner.busy ? null : _review,
              child: Text(t('核对', 'Review')),
            )
          else if (owner.phase == ComplexSavePhase.committedCleanupFailed)
            TextButton(
              onPressed: owner.busy
                  ? null
                  : () async {
                      try {
                        await owner.retryCleanup();
                        _notice = t('已保存', 'Saved');
                        await _replaceSurface();
                      } catch (_) {
                        if (mounted) {
                          setState(
                            () => _notice = t(
                              '清理未确认，请重试。',
                              'Cleanup unconfirmed. Retry.',
                            ),
                          );
                        }
                      }
                    },
              child: Text(t('重试清理', 'Retry cleanup')),
            )
          else if (_markdownArticle)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  height: 40,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      backgroundColor: _attachmentArticle
                          ? Colors.transparent
                          : _webDirty || owner.dirty
                          ? const Color(0xff6530ad)
                          : const Color(0xfff1e8fc),
                      foregroundColor: _attachmentArticle
                          ? Colors.white
                          : _webDirty || owner.dirty
                          ? Colors.white
                          : const Color(0xff6530ad),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed:
                        _attachmentBusy ||
                            _sourceIoBusy ||
                            _saving ||
                            owner.busy ||
                            _transport == null ||
                            _retiringSurface ||
                            _drawingResourceFailed ||
                            _presentationResourceFailed
                        ? null
                        : () => _save(),
                    child: Text(t('保存', 'Save')),
                  ),
                ),
              ),
            )
          else
            IconButton(
              onPressed:
                  _sourceIoBusy ||
                      _saving ||
                      owner.busy ||
                      _transport == null ||
                      _retiringSurface ||
                      _drawingResourceFailed ||
                      _presentationResourceFailed
                  ? null
                  : () => _save(),
              tooltip: t('保存', 'Save'),
              icon: const Icon(Icons.save_outlined),
            ),
        ],
      ),
      body: _body(
        children: [
          if (_attachmentArticle &&
              MediaQuery.viewInsetsOf(context).bottom == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xffe3ddea)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton(
                            onPressed:
                                owner.busy ||
                                    _attachmentBusy ||
                                    !owner.editable ||
                                    _transport == null ||
                                    _retiringSurface
                                ? null
                                : _metadata,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              alignment: Alignment.centerLeft,
                              foregroundColor: const Color(0xff172033),
                            ),
                            child: Text(
                              owner.edit.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(t('本地空间 · Markdown', 'Local space · Markdown')),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Chip(
                        avatar: Icon(
                          _webDirty || owner.dirty
                              ? Icons.circle_outlined
                              : Icons.done,
                          size: 18,
                        ),
                        label: Text(
                          _saving
                              ? t('保存中', 'Saving')
                              : owner.requiresReview
                              ? t('待核对', 'Review required')
                              : _webDirty || owner.dirty
                              ? t('未保存', 'Unsaved')
                              : t('已保存', 'Saved'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_markdownArticle && !_attachmentArticle)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff6530ad),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.article_outlined,
                          size: 19,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t('本地文章', 'Local article'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    _webDirty || owner.dirty
                        ? Icons.circle_outlined
                        : Icons.check_circle_outline,
                    size: 18,
                    color: _webDirty || owner.dirty
                        ? const Color(0xff475569)
                        : const Color(0xff6530ad),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _saving
                          ? t('保存中', 'Saving')
                          : owner.requiresReview
                          ? t('待核对', 'Review required')
                          : _webDirty || owner.dirty
                          ? t('未保存', 'Unsaved')
                          : t('已保存', 'Saved'),
                    ),
                  ),
                ],
              ),
            ),
          if (!_markdownArticle || _notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _notice ??
                      t(
                        '${_markdownArticle ? '本地文章' : (widget.originLabel ?? '本地空间')} · ${_saving
                            ? '保存中'
                            : owner.requiresReview
                            ? '待核对'
                            : _webDirty || owner.dirty
                            ? '未保存'
                            : '已保存'}',
                        '${_markdownArticle ? 'Local article' : (widget.originLabel ?? 'Local')} · ${_saving
                            ? 'Saving'
                            : owner.requiresReview
                            ? 'Review required'
                            : _webDirty || owner.dirty
                            ? 'Unsaved'
                            : 'Saved'}',
                      ),
                ),
              ),
            ),
          if (_attachmentArticle && _localImageFailures > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                color: const Color(0xfffff4df),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xffb45b00),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t('图片暂时无法读取', 'Image unavailable'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        t(
                          '正文和附件引用已保留，可重试或查看原文。',
                          'Source and attachment references are retained. Retry or inspect the source.',
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _attachmentBusy || owner.busy || _saving
                                ? null
                                : _reload,
                            child: Text(t('重试', 'Retry')),
                          ),
                          if (_localAttachmentReferences.isNotEmpty)
                            TextButton.icon(
                              onPressed: () => Clipboard.setData(
                                ClipboardData(
                                  text: _localAttachmentReferences.first.uri
                                      .toString(),
                                ),
                              ),
                              icon: const Icon(Icons.copy, size: 18),
                              label: Text(t('复制附件链接', 'Copy attachment link')),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_pendingAttachmentMarkup != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(_pendingAttachmentMarkup!, maxLines: 3),
                  TextButton.icon(
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: _pendingAttachmentMarkup!),
                    ),
                    icon: const Icon(Icons.copy, size: 18),
                    label: Text(t('复制附件链接', 'Copy attachment link')),
                  ),
                ],
              ),
            ),
          if (widget.ownedImages != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.ownedImages!.resourceReferencesUnavailable)
                    Text(
                      t(
                        '部分图片引用不在允许范围或超限，正文保留。',
                        'Some image references are outside the allowed scope or limits. Source retained.',
                      ),
                    ),
                  if (widget.ownedImages!.initializationFailed)
                    Text(
                      t(
                        '图片恢复记录暂不可读，上传已禁用；正文保留。',
                        'Image recovery record unreadable. Upload disabled; source retained.',
                      ),
                    )
                  else if (widget.ownedImages!.upload.record?.phase ==
                      OwnedImageUploadPhase.unknown)
                    Text(
                      t(
                        '上传结果待核对。不会自动重传；选择已有图片不会确认原上传结果。',
                        'Upload result unknown. No automatic reupload. Selecting an existing image does not confirm it.',
                      ),
                    )
                  else if (widget.ownedImages!.upload.record != null)
                    Text(
                      t(
                        '图片地址已确认，插入和保存仍需明确完成。',
                        'Image URL confirmed. Insertion and Save remain explicit.',
                      ),
                    ),
                  if (!widget.ownedImages!.insertionSupported)
                    Text(
                      t(
                        '此引擎暂不支持插图；已有图片可按原文读取。',
                        'Image insertion is not yet supported by this engine; existing source images may load.',
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (widget.ownedImages!.upload.record?.phase ==
                              OwnedImageUploadPhase.confirmedUrl &&
                          !widget.ownedImages!.upload.needsStorageRetry)
                        TextButton(
                          onPressed: _imageActionAvailable
                              ? () => _insertOwnedImage()
                              : null,
                          child: Text(t('插入已确认图片', 'Insert confirmed image')),
                        ),
                      if (widget.ownedImages!.upload.needsStorageRetry ||
                          widget.ownedImages!.upload.record?.phase ==
                              OwnedImageUploadPhase.inserted)
                        TextButton(
                          onPressed: _imageActionAvailable
                              ? _retryOwnedImageStorage
                              : null,
                          child: Text(
                            t('重试图片记录清理', 'Retry image record cleanup'),
                          ),
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
              ),
            ),
          if (widget.retentionActions != null) widget.retentionActions!,
          if (widget.retentionNotice != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(widget.retentionNotice!),
                ),
              ),
            ),
          Expanded(
            key: const ValueKey('local-article-editor-area'),
            child: Padding(
              padding: _attachmentArticle
                  ? const EdgeInsets.fromLTRB(16, 0, 16, 8)
                  : _markdownArticle
                  ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
                  : EdgeInsets.zero,
              child: ComplexEditorBrowser(
                onInitializationFailed: () {
                  if (mounted && widget.localPresentationFiles != null) {
                    setState(() {
                      _presentationResourceFailed = true;
                      _transport = null;
                    });
                  }
                  if (mounted && widget.localDrawingFiles != null) {
                    setState(() {
                      _drawingInitializationFailed = true;
                      _drawingResourceFailed = true;
                      _transport = null;
                    });
                  }
                },
                ownedResourceFactory: widget.ownedImages?.resourceFactory,
                generationResourceFactory: widget.generationResourceFactory,
                localRichdocResourceFactory: owner.editable
                    ? widget.localRichdocFiles?.owner.resourceFactory
                    : null,
                localDrawingResourceFactory: owner.editable
                    ? widget.localDrawingFiles?.owner.resourceFactory
                    : null,
                localPresentationResourceFactory: owner.editable
                    ? widget.localPresentationFiles?.owner.resourceFactory
                    : null,
                localMindmapResourceFactory: owner.editable
                    ? widget.localMindmapFiles?.owner.resourceFactory
                    : null,
                onOwnedResourceFailure: () {
                  if (mounted) {
                    setState(
                      () => _notice = t(
                        '部分图片未加载：超限、不支持或读取已结束；正文保留。',
                        'Some images were not loaded: unsupported, over limit, or read ended. Source retained.',
                      ),
                    );
                  }
                },
                ownedMarkdownSourceIo:
                    widget.sourceIoScope != null &&
                    owner.edit.document.kind == ComplexEditorKind.markdown &&
                    widget.anonymousSharedServer == null &&
                    owner.editable,
                retirementController: _activeRetirementController,
                key: ValueKey(_surfaceKey),
                document: _surface,
                publicServer: widget.anonymousSharedServer,
                sharedComplexEditing: widget.anonymousSharedServer != null,
                localImageAttachments: _attachmentArticle
                    ? widget.attachments
                    : null,
                onLocalImageStatus: (loaded, failed) {
                  if (mounted && failed != _localImageFailures) {
                    setState(() => _localImageFailures = failed);
                  }
                },
                title: owner.edit.title,
                english: widget.english,
                readOnly: !owner.editable,
                onReady: (transport) async {
                  if (!mounted) return;
                  setState(() {
                    _transport = transport;
                    _drawingInitializationFailed = false;
                    _drawingResourceFailed =
                        transport.localDrawingResourceFailed ||
                        _drawingBodyIncomplete;
                    _presentationResourceFailed =
                        transport.localPresentationResourceFailed ||
                        _presentationBodyIncomplete;
                    _retiringSurface = false;
                    _webDirty = false;
                  });
                },
                onState: _state,
                onSaveRequested: () async {
                  await _save();
                },
                beforeRetire: _beforeRetire,
                onReloadRequested: _reload,
                canRenewRetirement: widget.renewRetirementController != null,
              ),
            ),
          ),
          if (_selectedLocalRichdocImage != null &&
              widget.localRichdocFiles != null &&
              _localRichdocCurrent(widget.localRichdocFiles!))
            _localRichdocSelection(),
          if (_selectedLocalMindmapImage != null &&
              widget.localMindmapFiles != null &&
              _localMindmapCurrent(widget.localMindmapFiles!))
            _localMindmapSelection(),
          if (_selectedLocalDrawingImage != null &&
              widget.localDrawingFiles != null &&
              _localDrawingCurrent(widget.localDrawingFiles!))
            _localDrawingSelection(),
          if (_selectedLocalPresentationImage != null &&
              widget.localPresentationFiles != null &&
              _localPresentationCurrent(widget.localPresentationFiles!))
            _localPresentationSelection(),
          if (_attachmentArticle &&
              _localAttachmentReferences.isNotEmpty &&
              MediaQuery.viewInsetsOf(context).bottom == 0)
            SizedBox(
              height: _attachmentFooterExtent,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                scrollDirection: Axis.horizontal,
                itemCount: _localAttachmentReferences.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final value = _localAttachmentReferences[index];
                  final size = _importedSizes[value.uri];
                  return SizedBox(
                    width: 280,
                    child: Card(
                      child: ListTile(
                        leading: Icon(
                          value.image
                              ? Icons.image_outlined
                              : Icons.description_outlined,
                        ),
                        title: Text(
                          value.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          size == null
                              ? t('本机附件', 'Local attachment')
                              : '${(size / 1024).ceil()} KB · ${t('本机附件', 'Local attachment')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          tooltip: t('附件操作', 'Attachment actions'),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          onSelected: (action) async {
                            if (action == 'copy') {
                              await Clipboard.setData(
                                ClipboardData(text: value.uri.toString()),
                              );
                            } else {
                              await _shareAttachment(value);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'open',
                              child: Text(t('打开或分享文件', 'Open or share file')),
                            ),
                            PopupMenuItem(
                              value: 'copy',
                              child: Text(t('复制附件链接', 'Copy attachment link')),
                            ),
                          ],
                        ),
                        onTap: () => _openAttachment(value),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    ),
  );
}
