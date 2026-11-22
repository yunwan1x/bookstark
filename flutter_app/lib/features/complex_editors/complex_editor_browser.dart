import '../../core/local_presentation_image_resources.dart';
import '../../core/local_mindmap_image_resources.dart';
import '../../core/local_drawing_image_resources.dart';
import '../../core/local_richdoc_image_resources.dart';
import '../../core/owned15_generation_resources.dart';
import '../../core/owned_complex_resources.dart';
import '../../core/public_selection_protocol.dart';
import '../../core/complex_reading_protocol.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_html_resources.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_markdown_resources.dart';
import 'package:bookstark_flutter/core/owned_preview_controller.dart';
import '../../core/complex_editor_transport.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';

class ComplexEditorState {
  const ComplexEditorState({
    required this.generation,
    required this.revision,
    required this.ready,
    required this.dirty,
    required this.inputLocked,
    this.localDrawingResourceFailed = false,
    this.localPresentationResourceFailed = false,
  });
  final int generation, revision;
  final bool ready, dirty, inputLocked;
  final bool localDrawingResourceFailed;
  final bool localPresentationResourceFailed;
  static ComplexEditorState? parse(Object? value, ComplexEditorKind kind) {
    if (value is! Map ||
        value['version'] != 1 ||
        value['kind'] != kind.name ||
        value['generation'] is! int ||
        (value['generation'] as int) < 1 ||
        value['revision'] is! int ||
        (value['revision'] as int) < 0 ||
        value['ready'] is! bool ||
        value['dirty'] is! bool ||
        value['inputLocked'] is! bool ||
        (value.containsKey('localDrawingResourceFailed') &&
            value['localDrawingResourceFailed'] is! bool) ||
        (value.containsKey('localPresentationResourceFailed') &&
            value['localPresentationResourceFailed'] is! bool)) {
      return null;
    }
    return ComplexEditorState(
      generation: value['generation'] as int,
      revision: value['revision'] as int,
      ready: value['ready'] as bool,
      dirty: value['dirty'] as bool,
      inputLocked: value['inputLocked'] as bool,
      localDrawingResourceFailed: value['localDrawingResourceFailed'] == true,
      localPresentationResourceFailed:
          value['localPresentationResourceFailed'] == true,
    );
  }
}

/// Existing engines and one exclusive native lease. Read-only remains the
/// default; editable owners must handle snapshots, durability and retirement.
class ComplexEditorBrowser extends StatefulWidget {
  const ComplexEditorBrowser({
    super.key,
    required this.document,
    this.title = '',
    this.english = false,
    this.readOnly = true,
    this.sourceReadOnly = false,
    this.onReady,
    this.onInitializationFailed,
    this.readingIdentity,
    this.publicSelectionIdentity,
    this.ownedMarkdownSourceIo = false,
    this.ownedReviewExport = false,
    this.ownedReviewExportDigest,
    this.ownedReviewExportBytes,
    this.onState,
    this.onSaveRequested,
    this.beforeRetire,
    this.onReloadRequested,
    this.canRenewRetirement = false,
    this.onExternalLink,
    this.retirementController,
    this.publicServer,
    this.sharedMarkdownEditing = false,
    this.publicComplexReadOnly = false,
    this.sharedComplexEditing = false,
    this.publicResourceFactory,
    this.localImageAttachments,
    this.ownedResourceFactory,
    this.generationResourceFactory,
    this.localRichdocResourceFactory,
    this.localMindmapResourceFactory,
    this.localDrawingResourceFactory,
    this.localPresentationResourceFactory,
    this.onOwnedResourceFailure,
    this.localResourceFactory,
    this.onLocalImageStatus,
    this.onPublicResourceStatus,
  }) : assert(
         readOnly ||
             (onReady != null &&
                 onState != null &&
                 onSaveRequested != null &&
                 beforeRetire != null &&
                 onReloadRequested != null),
       ),
       assert(!sourceReadOnly || !readOnly),
       assert(
         publicServer == null ||
             !sourceReadOnly &&
                 (readOnly || sharedMarkdownEditing || sharedComplexEditing),
       ),
       assert(
         !sharedMarkdownEditing || publicServer != null && !sourceReadOnly,
       );
  final OwnedComplexResources Function(ComplexEditorDocument document)?
  ownedResourceFactory;
  final Future<Owned15GenerationResources?> Function(
    ComplexEditorDocument document,
  )?
  generationResourceFactory;
  final LocalRichdocImageResources Function(ComplexEditorDocument)?
  localRichdocResourceFactory;
  final LocalMindmapImageResources Function(ComplexEditorDocument)?
  localMindmapResourceFactory;
  final LocalDrawingImageResources Function(ComplexEditorDocument)?
  localDrawingResourceFactory;
  final VoidCallback? onOwnedResourceFailure;
  final LocalAttachments? localImageAttachments;
  final LocalMarkdownResources Function(LocalAttachments)? localResourceFactory;
  final void Function(int loaded, int failed)? onLocalImageStatus;
  final ComplexEditorDocument document;
  final PublicSelectionIdentity? publicSelectionIdentity;
  final Uri? publicServer;
  final bool sharedMarkdownEditing;
  final bool publicComplexReadOnly;
  final bool sharedComplexEditing;
  final LocalPresentationImageResources Function(ComplexEditorDocument)?
  localPresentationResourceFactory;
  final PublicHtmlResources Function(Uri)? publicResourceFactory;
  final void Function(int loaded, int failed)? onPublicResourceStatus;
  final OwnedPreviewController? retirementController;
  final String title;
  final bool english, readOnly, sourceReadOnly;
  final Future<void> Function(ComplexEditorTransport)? onReady;
  final void Function()? onInitializationFailed;
  final bool ownedMarkdownSourceIo;
  final bool ownedReviewExport;
  final String? ownedReviewExportDigest;
  final int? ownedReviewExportBytes;
  final bool canRenewRetirement;
  final ComplexReadingIdentity? readingIdentity;
  final void Function(ComplexEditorState)? onState;
  final Future<void> Function()? onSaveRequested, onReloadRequested;
  final Future<void> Function(ComplexEditorTransport)? beforeRetire;
  final Future<void> Function(Uri)? onExternalLink;
  @override
  State<ComplexEditorBrowser> createState() => _ComplexEditorBrowserState();
}

class _ComplexEditorBrowserState extends State<ComplexEditorBrowser>
    with WidgetsBindingObserver {
  HtmlBrowserSession? _session;
  Uri? _publicRoot;
  PublicHtmlResources? _publicResources;
  LocalMarkdownResources? _localImages;
  OwnedComplexResources? _ownedResources;
  Owned15GenerationResources? _generationResources;
  LocalRichdocImageResources? _localRichdocResources;
  LocalMindmapImageResources? _localMindmapResources;
  LocalDrawingImageResources? _localDrawingResources;
  LocalPresentationImageResources? _localPresentationResources;
  bool _localImageFailed = false;
  String get _viewType => _generationResources != null
      ? 'bookstark/owned15_generation_view'
      : _localPresentationResources != null
      ? 'bookstark/local_presentation_view'
      : _localDrawingResources != null
      ? 'bookstark/local_drawing_view'
      : _localMindmapResources != null
      ? 'bookstark/local_mindmap_view'
      : _localRichdocResources != null
      ? 'bookstark/local_richdoc_view'
      : widget.localImageAttachments != null
      ? 'bookstark/local_markdown_view'
      : widget.ownedResourceFactory != null
      ? 'bookstark/owned_complex_view'
      : widget.publicServer == null
      ? 'bookstark/complex_editor_view'
      : widget.sharedComplexEditing
      ? 'bookstark/shared_complex_view'
      : widget.publicComplexReadOnly
      ? 'bookstark/public_complex_readonly_view'
      : widget.sharedMarkdownEditing
      ? 'bookstark/shared_markdown_view'
      : 'bookstark/public_markdown_view';
  MethodChannel? _channel;
  ComplexEditorTransport? _transport;
  Timer? _deadline;
  Future<void>? _retiring, _opening;
  Future<void> Function(ComplexEditorTransport)? _retirementHook;
  int _epoch = 0;
  bool _publicImageFailed = false;
  bool _disposed = false;
  bool _keepViewForSnapshot = false;
  bool _nativeCloseAcknowledged = true;
  bool _closed = false, _failed = false, _ready = false, _loading = false;
  String _startupPhase = 'opening';
  void _diagnoseStartup(Object? cause) {
    if (!kDebugMode) return;
    const codes = {
      'editor_timeout',
      'editor_command_failed',
      'editor_retired',
      'invalid_command',
      'editor_unavailable',
    };
    final kind = cause is PlatformException
        ? (codes.contains(cause.code) ? cause.code : 'platform_error')
        : cause == null
        ? 'no_exception'
        : cause.runtimeType.toString();
    debugPrint('complex_editor_startup_failure:$_startupPhase:$kind');
  }

  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindController(widget.retirementController);
    unawaited(_startOpen());
  }

  void _bindController(OwnedPreviewController? controller) {
    controller?.bind(this, () => _closeOwned(controller));
  }

  Future<void> _startOpen() {
    if (widget.retirementController?.retired == true) {
      if (mounted && !_disposed) setState(() => _closed = true);
      return Future<void>.value();
    }
    return _opening = _open();
  }

  Future<void> _closeOwned(OwnedPreviewController? controller) async {
    _epoch++;
    _deadline?.cancel();
    _keepViewForSnapshot = _transport != null && _retirementHook != null;
    _closed = true;
    _ready = false;
    final opening = _opening, session = _session;
    if (mounted && !_disposed) setState(() {});
    if (session != null) {
      await session.close();
    } else {
      await _retire(controller);
    }
    await opening;
  }

  Future<void> _retire([OwnedPreviewController? controller]) async {
    final pending = _retiring;
    if (pending != null) return pending;
    final work = _retireNow();
    _retiring = work;
    controller?.ownerRetiring(this, _session?.closed ?? work);
    try {
      await work;
    } finally {
      if (identical(_retiring, work)) _retiring = null;
    }
  }

  Future<void> _retireNow() async {
    _deadline?.cancel();
    _localImages?.close();
    _publicResources?.close();
    _ownedResources?.close();
    final generationResources = _generationResources;
    _generationResources = null;
    final generationDrain = generationResources?.retire();
    final localRichdoc = _localRichdocResources;
    _localRichdocResources = null;
    final localRichdocDrain = localRichdoc?.retireAndDrain();
    final localDrawing = _localDrawingResources;
    _localDrawingResources = null;
    final localDrawingDrain = localDrawing?.retireAndDrain();
    final localPresentation = _localPresentationResources;
    _localPresentationResources = null;
    final localPresentationDrain = localPresentation?.retireAndDrain();
    final localMindmap = _localMindmapResources;
    _localMindmapResources = null;
    final localMindmapDrain = localMindmap?.retireAndDrain();
    _closed = true;
    _ready = false;
    final session = _session;
    _nativeCloseAcknowledged = session == null;
    if (session != null) {
      unawaited(
        session.closed.then<void>((_) {
          if (!mounted || _disposed || !identical(_session, session)) return;
          setState(() => _nativeCloseAcknowledged = true);
        }, onError: (Object _, StackTrace _) {}),
      );
    }
    final transport = _transport, hook = _retirementHook;
    _keepViewForSnapshot = transport != null && hook != null;
    _transport = null;
    _retirementHook = null;
    try {
      if (transport != null) {
        try {
          await hook?.call(transport);
        } catch (_, stack) {
          _failed = true;
          // Storage retry must retain its owner hook after closing the runtime.
          // The Page retries its exact captured edit, never this dead browser.
          _transport = transport;
          _retirementHook = hook;
          Error.throwWithStackTrace(
            StateError('Editor draft checkpoint failed'),
            stack,
          );
        } finally {
          try {
            await transport.retire();
          } on PlatformException {
            // Session close still revokes the native lease. Preserve any
            // earlier checkpoint error instead of replacing it with this one.
          } on MissingPluginException {
            // Session close remains mandatory for an already disposed view.
          }
        }
      } else {
        await _channel?.invokeMethod<void>('retire');
      }
    } on PlatformException {
      // Native close also destroys owned views before cookies change.
    } on MissingPluginException {
      // The platform view may already have been disposed.
    } finally {
      await generationDrain;
      await localRichdocDrain;
      await localMindmapDrain;
      await localDrawingDrain;
      await localPresentationDrain;
      _keepViewForSnapshot = false;
      if (mounted && !_disposed) setState(() {});
    }
  }

  Future<void> _open() async {
    final epoch = ++_epoch;
    _deadline?.cancel();
    setState(() {
      _ready = false;
      _failed = false;
      _closed = false;
    });
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _failed = true);
      return;
    }
    HtmlBrowserSession? acquired;
    PublicHtmlResources? openedResources;
    try {
      await _session?.close();
      if (!mounted ||
          epoch != _epoch ||
          widget.retirementController?.retired == true) {
        return;
      }
      final root = widget.publicServer == null
          ? null
          : BookstarkClient.normalizeServer(widget.publicServer.toString());
      if (widget.sharedComplexEditing &&
          (root == null ||
              widget.document.kind == ComplexEditorKind.markdown ||
              widget.sourceReadOnly ||
              widget.publicComplexReadOnly ||
              widget.sharedMarkdownEditing ||
              widget.localImageAttachments != null)) {
        throw ArgumentError('Isolated shared complex mode required');
      }
      if (widget.publicComplexReadOnly &&
          (root == null ||
              !widget.readOnly ||
              widget.sourceReadOnly ||
              widget.sharedMarkdownEditing ||
              widget.localImageAttachments != null)) {
        throw ArgumentError('Anonymous read-only complex mode required');
      }
      if (root != null &&
          ((!widget.publicComplexReadOnly &&
                  !widget.sharedComplexEditing &&
                  widget.document.kind != ComplexEditorKind.markdown) ||
              (!widget.readOnly &&
                  !widget.sharedMarkdownEditing &&
                  !widget.sharedComplexEditing) ||
              widget.sourceReadOnly ||
              widget.document.byteLength >
                  ((widget.publicComplexReadOnly ||
                              widget.sharedComplexEditing) &&
                          widget.document.kind != ComplexEditorKind.markdown
                      ? widget.document.kind.maxBytes
                      : 4 * 1024 * 1024))) {
        throw ArgumentError('Public Markdown view is read-only and bounded');
      }
      _localImages?.close();
      _publicResources?.close();
      _ownedResources?.close();
      _ownedResources = null;
      final ownedFactory = widget.ownedResourceFactory;
      if (ownedFactory != null) {
        if (widget.localPresentationResourceFactory != null ||
            widget.localDrawingResourceFactory != null ||
            widget.localMindmapResourceFactory != null ||
            widget.localRichdocResourceFactory != null ||
            root != null ||
            widget.localImageAttachments != null ||
            widget.sharedComplexEditing ||
            widget.sharedMarkdownEditing ||
            widget.publicComplexReadOnly ||
            widget.document.kind == ComplexEditorKind.markdown) {
          throw ArgumentError('Isolated owned complex resource mode required');
        }
        final resources = ownedFactory(widget.document);
        if (resources.sourceDigest != widget.document.digest) {
          resources.close();
          throw ArgumentError('Owned source resource binding changed');
        }
        resources.lease.guard();
        _ownedResources = resources;
      }
      await _generationResources?.retire();
      _generationResources = null;
      final generationFactory = widget.generationResourceFactory;
      if (generationFactory != null) {
        if (widget.localPresentationResourceFactory != null ||
            widget.localDrawingResourceFactory != null ||
            widget.localMindmapResourceFactory != null ||
            widget.localRichdocResourceFactory != null ||
            root != null ||
            widget.localImageAttachments != null ||
            ownedFactory != null ||
            widget.sharedComplexEditing ||
            widget.sharedMarkdownEditing ||
            widget.publicComplexReadOnly) {
          throw ArgumentError(
            'Isolated local generation resource mode required',
          );
        }
        final resources = await generationFactory(widget.document);
        if (!mounted ||
            _closed ||
            epoch != _epoch ||
            widget.retirementController?.retired == true ||
            resources != null &&
                (!resources.current ||
                    resources.sourceDigest != widget.document.digest)) {
          await resources?.retire();
          return;
        }
        _generationResources = resources;
        if (resources == null) widget.onOwnedResourceFailure?.call();
      }
      await _localRichdocResources?.retireAndDrain();
      _localRichdocResources = null;
      await _localMindmapResources?.retireAndDrain();
      _localMindmapResources = null;
      final localRichdocFactory = widget.localRichdocResourceFactory;
      if (localRichdocFactory != null) {
        if (widget.localPresentationResourceFactory != null ||
            widget.localDrawingResourceFactory != null ||
            widget.localMindmapResourceFactory != null ||
            root != null ||
            ownedFactory != null ||
            generationFactory != null ||
            widget.localImageAttachments != null ||
            widget.readOnly ||
            widget.sourceReadOnly ||
            widget.publicComplexReadOnly ||
            widget.sharedComplexEditing ||
            widget.sharedMarkdownEditing ||
            widget.document.kind != ComplexEditorKind.richdoc) {
          throw ArgumentError(
            'Ordinary local rich-document resource mode required',
          );
        }
        final resources = localRichdocFactory(widget.document);
        if (!resources.current ||
            resources.references.sourceDigest != widget.document.digest) {
          await resources.retireAndDrain();
          throw StateError('Actual rich-document resource source changed');
        }
        _localRichdocResources = resources;
        if (resources.referencesUnavailable) {
          widget.onOwnedResourceFailure?.call();
        }
      }
      await _localMindmapResources?.retireAndDrain();
      _localMindmapResources = null;
      final localMindmapFactory = widget.localMindmapResourceFactory;
      if (localMindmapFactory != null) {
        if (widget.localPresentationResourceFactory != null ||
            widget.localDrawingResourceFactory != null ||
            widget.localRichdocResourceFactory != null ||
            root != null ||
            ownedFactory != null ||
            generationFactory != null ||
            widget.localImageAttachments != null ||
            widget.readOnly ||
            widget.sourceReadOnly ||
            widget.publicComplexReadOnly ||
            widget.sharedComplexEditing ||
            widget.sharedMarkdownEditing ||
            widget.document.kind != ComplexEditorKind.mindmap) {
          throw ArgumentError(
            'Ordinary local rich-document resource mode required',
          );
        }
        final resources = localMindmapFactory(widget.document);
        if (!resources.current ||
            resources.references.sourceDigest != widget.document.digest) {
          await resources.retireAndDrain();
          throw StateError('Actual rich-document resource source changed');
        }
        _localMindmapResources = resources;
        if (resources.referencesUnavailable) {
          widget.onOwnedResourceFailure?.call();
        }
      }
      await _localDrawingResources?.retireAndDrain();
      _localDrawingResources = null;
      final localDrawingFactory = widget.localDrawingResourceFactory;
      if (localDrawingFactory != null) {
        if (widget.localPresentationResourceFactory != null ||
            widget.localMindmapResourceFactory != null ||
            widget.localRichdocResourceFactory != null ||
            root != null ||
            ownedFactory != null ||
            generationFactory != null ||
            widget.localImageAttachments != null ||
            widget.readOnly ||
            widget.sourceReadOnly ||
            widget.publicComplexReadOnly ||
            widget.sharedComplexEditing ||
            widget.sharedMarkdownEditing ||
            widget.document.kind != ComplexEditorKind.drawing) {
          throw ArgumentError('Ordinary local drawing resource mode required');
        }
        final resources = localDrawingFactory(widget.document);
        if (!resources.current ||
            resources.references.sourceDigest != widget.document.digest) {
          await resources.retireAndDrain();
          throw StateError('Actual drawing resource source changed');
        }
        _localDrawingResources = resources;
        if (resources.referencesUnavailable) {
          widget.onOwnedResourceFailure?.call();
        }
      }
      await _localPresentationResources?.retireAndDrain();
      _localPresentationResources = null;
      final localPresentationFactory = widget.localPresentationResourceFactory;
      if (localPresentationFactory != null) {
        if (widget.localDrawingResourceFactory != null ||
            widget.localMindmapResourceFactory != null ||
            widget.localRichdocResourceFactory != null ||
            root != null ||
            ownedFactory != null ||
            generationFactory != null ||
            widget.localImageAttachments != null ||
            widget.readOnly ||
            widget.sourceReadOnly ||
            widget.publicComplexReadOnly ||
            widget.sharedComplexEditing ||
            widget.sharedMarkdownEditing ||
            widget.document.kind != ComplexEditorKind.presentation) {
          throw ArgumentError(
            'Ordinary local presentation resource mode required',
          );
        }
        final resources = localPresentationFactory(widget.document);
        if (!resources.current ||
            resources.references.sourceDigest != widget.document.digest) {
          await resources.retireAndDrain();
          throw StateError('Actual presentation resource source changed');
        }
        _localPresentationResources = resources;
        if (resources.referencesUnavailable) {
          widget.onOwnedResourceFailure?.call();
        }
      }
      if (widget.localImageAttachments != null &&
          (root != null ||
              widget.sharedMarkdownEditing ||
              widget.sourceReadOnly ||
              widget.document.kind != ComplexEditorKind.markdown)) {
        throw ArgumentError('Local image resources require local Markdown');
      }
      final controller = widget.retirementController;
      final session = await (root == null
          ? HtmlBrowserSession.openLocal(retire: () => _retire(controller))
          : HtmlBrowserSession.openPublic(retire: () => _retire(controller)));
      acquired = session;
      if (!mounted ||
          epoch != _epoch ||
          widget.retirementController?.retired == true) {
        await session.close();
        return;
      }
      _publicRoot = root;
      _publicImageFailed = false;
      if (root != null) {
        final scope =
            widget.publicResourceFactory?.call(root) ??
            PublicHtmlResources(root);
        openedResources = scope;
        _publicResources = scope;
        scope.onChanged = () {
          if (mounted &&
              !_disposed &&
              !_closed &&
              identical(_publicResources, scope)) {
            widget.onPublicResourceStatus?.call(
              scope.loaded,
              scope.failed + (_publicImageFailed ? 1 : 0),
            );
          }
        };
      } else {
        _publicResources = null;
      }
      _localImageFailed = false;
      final localAttachments = widget.localImageAttachments;
      if (localAttachments != null) {
        final local =
            widget.localResourceFactory?.call(localAttachments) ??
            LocalMarkdownResources(localAttachments);
        if (!identical(local.attachments, localAttachments)) {
          local.close();
          throw ArgumentError('Local image resource owner mismatch');
        }
        _localImages = local;
        local.onChanged = () {
          if (mounted &&
              !_disposed &&
              !_closed &&
              identical(_localImages, local)) {
            widget.onLocalImageStatus?.call(
              local.loaded,
              local.failed + (_localImageFailed ? 1 : 0),
            );
          }
        };
      } else {
        _localImages = null;
      }

      _channel?.setMethodCallHandler(null);
      _channel = null;
      _transport = null;
      setState(() {
        _session = session;
        _closed = false;
        _loading = false;
        _failed = false;
        _retirementHook = widget.readOnly ? null : widget.beforeRetire;
      });
      _deadline = Timer(const Duration(seconds: 60), () {
        if (mounted && epoch == _epoch && !_ready) unawaited(_fail());
      });
    } catch (_) {
      await _generationResources?.retire();
      _generationResources = null;
      _ownedResources?.close();
      await _localRichdocResources?.retireAndDrain();
      _localRichdocResources = null;
      openedResources?.close();
      try {
        await acquired?.close();
      } catch (_) {}
      if (mounted && epoch == _epoch) setState(() => _failed = true);
    }
  }

  Future<void> _fail([Object? cause]) async {
    _diagnoseStartup(cause);
    _failed = true;
    await _session?.close();
    if (mounted && !_disposed) {
      widget.onInitializationFailed?.call();
      setState(() {});
    }
  }

  void _created(int id, HtmlBrowserSession session) {
    if (!mounted || _closed || _session != session) return;
    _startupPhase = 'native-created';
    final channel = MethodChannel('$_viewType/$id');
    _channel?.setMethodCallHandler(null);
    _channel = channel;
    final transport = ComplexEditorTransport.channel(channel);
    _transport = transport;
    channel.setMethodCallHandler((call) async {
      if (!mounted ||
          _closed ||
          _session != session ||
          call.arguments is! Map ||
          call.arguments['lease'] != session.lease) {
        if (call.method == 'localDrawingImageResource') {
          debugPrint('drawing_resource_callback:session_rejected');
        }
        return null;
      }
      if (call.method == 'localRichdocImageResource' &&
          widget.localRichdocResourceFactory != null) {
        final args = call.arguments;
        final scope = _localRichdocResources;
        if (args is! Map ||
            scope == null ||
            !scope.current ||
            args.length != 4 ||
            args['lease'] != session.lease ||
            args['scope'] != scope.identity ||
            args['sourceDigest'] != scope.references.sourceDigest ||
            args['url'] is! String) {
          return null;
        }
        final uri = Uri.tryParse(args['url'] as String);
        if (uri == null) return null;
        try {
          final image = await scope.read(uri);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !scope.current ||
              !identical(_localRichdocResources, scope)) {
            return null;
          }
          return {'bytes': image.bytes, 'mime': image.mime};
        } catch (_) {
          return null;
        }
      }
      if (call.method == 'localMindmapImageResource' &&
          widget.localMindmapResourceFactory != null) {
        final args = call.arguments;
        final scope = _localMindmapResources;
        if (args is! Map ||
            scope == null ||
            !scope.current ||
            args.length != 4 ||
            args['lease'] != session.lease ||
            args['scope'] != scope.identity ||
            args['sourceDigest'] != scope.references.sourceDigest ||
            args['url'] is! String) {
          return null;
        }
        final uri = Uri.tryParse(args['url'] as String);
        if (uri == null) return null;
        try {
          final image = await scope.read(uri);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !scope.current ||
              !identical(_localMindmapResources, scope)) {
            return null;
          }
          return {'bytes': image.bytes, 'mime': image.mime};
        } catch (_) {
          return null;
        }
      }
      if (call.method == 'localDrawingImageResource' &&
          widget.localDrawingResourceFactory != null) {
        final args = call.arguments;
        final scope = _localDrawingResources;
        if (args is! Map ||
            scope == null ||
            !scope.current ||
            args.length != 4 ||
            args['lease'] != session.lease ||
            args['scope'] != scope.identity ||
            args['sourceDigest'] != scope.references.sourceDigest ||
            args['resourceId'] is! String) {
          debugPrint('drawing_resource_callback:grant_rejected');
          return null;
        }
        final resourceId = args['resourceId'] as String;
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceId)) {
          debugPrint('drawing_resource_callback:resource_id_rejected');
          return null;
        }
        try {
          final image = await scope.read(resourceId);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !scope.current ||
              !identical(_localDrawingResources, scope)) {
            debugPrint('drawing_resource_callback:retired_after_read');
            return null;
          }
          return {'bytes': image.bytes, 'mime': image.mime};
        } catch (error) {
          final kind = error is StateError
              ? 'StateError'
              : error is FormatException
              ? 'FormatException'
              : error is PlatformException
              ? 'PlatformException'
              : 'Other';
          debugPrint('drawing_resource_callback:read_failed:$kind');
          return null;
        }
      }
      if (call.method == 'localPresentationImageResource' &&
          widget.localPresentationResourceFactory != null) {
        final args = call.arguments;
        final scope = _localPresentationResources;
        if (args is! Map ||
            scope == null ||
            !scope.current ||
            args.length != 4 ||
            args['lease'] != session.lease ||
            args['scope'] != scope.identity ||
            args['sourceDigest'] != scope.references.sourceDigest ||
            args['resourceId'] is! String) {
          return null;
        }
        final resourceId = args['resourceId'] as String;
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(resourceId)) return null;
        try {
          final image = await scope.read(resourceId);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !scope.current ||
              !identical(_localPresentationResources, scope)) {
            return null;
          }
          return {'bytes': image.bytes, 'mime': image.mime};
        } catch (_) {
          return null;
        }
      }
      if (call.method == 'generationResource' &&
          widget.generationResourceFactory != null) {
        final scope = _generationResources;
        final raw = call.arguments['url'];
        if (scope == null ||
            !scope.current ||
            raw is! String ||
            raw.length > 4096 ||
            call.arguments['resourceScope'] != scope.scopeIdentity) {
          return null;
        }
        final uri = Uri.tryParse(raw);
        if (uri == null) return null;
        final resource = await scope.read(uri);
        if (resource == null &&
            mounted &&
            !_disposed &&
            !_closed &&
            _session == session &&
            identical(_generationResources, scope) &&
            scope.current) {
          widget.onOwnedResourceFailure?.call();
        }
        if (!mounted ||
            _disposed ||
            _closed ||
            _session != session ||
            !identical(_generationResources, scope) ||
            !scope.current ||
            resource == null ||
            call.arguments['lease'] != session.lease) {
          return null;
        }
        return {
          'bytes': resource.bytes,
          'mime': resource.mime,
          'sha256': resource.sha256Hex,
          'resourceScope': scope.scopeIdentity,
        };
      }
      if (call.method == 'ownedResource' &&
          widget.ownedResourceFactory != null) {
        final scope = _ownedResources;
        final raw = call.arguments['url'];
        if (scope == null ||
            raw is! String ||
            raw.length > 4096 ||
            call.arguments['resourceScope'] != scope.identity) {
          return null;
        }
        final uri = Uri.tryParse(raw);
        if (uri == null) return null;
        try {
          scope.lease.guard();
          final resource = await scope.read(uri);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !identical(_ownedResources, scope) ||
              !scope.lease.current ||
              call.arguments['lease'] != session.lease) {
            return null;
          }
          return {
            'bytes': resource.bytes,
            'mime': resource.mime,
            'resourceScope': scope.identity,
          };
        } catch (_) {
          if (mounted &&
              !_disposed &&
              !_closed &&
              _session == session &&
              identical(_ownedResources, scope)) {
            widget.onOwnedResourceFailure?.call();
          }
          return null;
        }
      }
      if (call.method == 'localImageFailure' &&
          widget.localImageAttachments != null) {
        _localImageFailed = true;
        final scope = _localImages;
        widget.onLocalImageStatus?.call(
          scope?.loaded ?? 0,
          (scope?.failed ?? 0) + 1,
        );
        return null;
      }
      if (call.method == 'localImageResource' &&
          widget.localImageAttachments != null) {
        final uri = Uri.tryParse(call.arguments['url'] as String? ?? '');
        final scope = _localImages;
        if (uri == null || scope == null) return null;
        try {
          final image = await scope.read(uri);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !identical(_localImages, scope)) {
            return null;
          }
          return {'bytes': image.bytes, 'mime': image.mime};
        } catch (_) {
          return null;
        }
      }
      if (call.method == 'publicImageFailure' && _publicRoot != null) {
        if (!_publicImageFailed) {
          _publicImageFailed = true;
          final scope = _publicResources;
          widget.onPublicResourceStatus?.call(
            scope?.loaded ?? 0,
            (scope?.failed ?? 0) + 1,
          );
        }
        return null;
      }
      if (call.method == 'resource' && _publicRoot != null) {
        final uri = Uri.tryParse(call.arguments['url'] as String? ?? '');
        final scope = _publicResources;
        if (uri == null || scope == null) return null;
        try {
          final resource = await scope.read(uri);
          if (!mounted ||
              _disposed ||
              _closed ||
              _session != session ||
              !identical(_publicResources, scope) ||
              call.arguments['lease'] != session.lease) {
            return null;
          }
          return {'bytes': resource.bytes, 'mime': resource.mime};
        } catch (_) {
          return null;
        }
      }
      if (call.method == 'hostReady' && !_loading) {
        _startupPhase = 'document-load';
        _loading = true;
        try {
          await transport.load(
            widget.document,
            title: widget.title,
            english: widget.english,
            readOnly: widget.readOnly,
            sourceReadOnly: widget.sourceReadOnly,
            publicResourceRoot: _publicRoot,
            sharedMarkdownEditing: widget.sharedMarkdownEditing,
            publicComplexReadOnly: widget.publicComplexReadOnly,
            sharedComplexEditing: widget.sharedComplexEditing,
            localMarkdownImages: widget.localImageAttachments != null,
            localDrawingScope: _localDrawingResources?.identity,
            localPresentationScope: _localPresentationResources?.identity,
            localDrawingResources: _localDrawingResources?.sourceFileResources,
            localPresentationResources:
                _localPresentationResources?.sourceFileResources,
            ownedMarkdownSourceIo: widget.ownedMarkdownSourceIo,
            ownedReviewExport: widget.ownedReviewExport,
            ownedReviewExportDigest: widget.ownedReviewExportDigest,
            ownedReviewExportBytes: widget.ownedReviewExportBytes,
          );
          if (!mounted || _closed || _session != session) return null;
          final readingIdentity = widget.readingIdentity;
          if (readingIdentity != null) {
            await transport.bindReading(
              readingIdentity,
              runtimeLease: session.lease,
            );
          }
          if (!mounted || _closed || _session != session) return null;
          final publicIdentity = widget.publicSelectionIdentity;
          if (publicIdentity != null) {
            await transport.bindPublicSelection(
              publicIdentity,
              runtimeLease: session.lease,
            );
          }
          _startupPhase = 'owner-ready';
          await widget.onReady?.call(transport);
          if (!mounted || _closed || _session != session) return null;
          _deadline?.cancel();
          _startupPhase = 'ready';
          setState(() => _ready = true);
        } catch (error) {
          if (mounted && !_closed && _session == session) await _fail(error);
        }
      } else if (call.method == 'state' && _ready) {
        final state = ComplexEditorState.parse(
          call.arguments['state'],
          widget.document.kind,
        );
        if (state != null) {
          if (state.dirty) {
            final scope = _generationResources;
            if (scope != null) {
              await scope.retire();
              if (mounted && !_closed && _session == session) {
                widget.onOwnedResourceFailure?.call();
              }
            }
          }
          if (mounted && !_closed && _session == session) {
            widget.onState?.call(state);
          }
        }
      } else if (call.method == 'saveRequested' &&
          _ready &&
          !widget.readOnly &&
          !widget.sourceReadOnly) {
        await widget.onSaveRequested?.call();
      } else if (call.method == 'externalLink' && _ready) {
        final uri = Uri.tryParse(call.arguments['url'] as String? ?? '');
        if (uri != null &&
            {'http', 'https'}.contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            uri.userInfo.isEmpty &&
            !uri.host.endsWith('.bookstark-editor.invalid')) {
          await widget.onExternalLink?.call(uri);
        }
      } else if (call.method == 'hostFailed') {
        _startupPhase = 'host-check';
        await _fail();
      }
    });
  }

  @override
  void didUpdateWidget(covariant ComplexEditorBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previousReading = oldWidget.readingIdentity,
        nextReading = widget.readingIdentity;
    final readingChanged = previousReading == null
        ? nextReading != null
        : nextReading == null || !previousReading.same(nextReading);
    final changed =
        !identical(
          oldWidget.ownedResourceFactory,
          widget.ownedResourceFactory,
        ) ||
        !identical(
          oldWidget.generationResourceFactory,
          widget.generationResourceFactory,
        ) ||
        !identical(
          oldWidget.localRichdocResourceFactory,
          widget.localRichdocResourceFactory,
        ) ||
        !identical(
          oldWidget.localMindmapResourceFactory,
          widget.localMindmapResourceFactory,
        ) ||
        !identical(
          oldWidget.localDrawingResourceFactory,
          widget.localDrawingResourceFactory,
        ) ||
        !identical(
          oldWidget.localPresentationResourceFactory,
          widget.localPresentationResourceFactory,
        ) ||
        readingChanged ||
        oldWidget.publicSelectionIdentity?.identityDigest !=
            widget.publicSelectionIdentity?.identityDigest ||
        oldWidget.publicSelectionIdentity?.sourceDigest !=
            widget.publicSelectionIdentity?.sourceDigest ||
        !oldWidget.document.same(widget.document) ||
        oldWidget.ownedReviewExport != widget.ownedReviewExport ||
        oldWidget.ownedReviewExportDigest != widget.ownedReviewExportDigest ||
        oldWidget.ownedReviewExportBytes != widget.ownedReviewExportBytes ||
        oldWidget.readOnly != widget.readOnly ||
        oldWidget.sourceReadOnly != widget.sourceReadOnly ||
        oldWidget.publicServer != widget.publicServer ||
        oldWidget.publicComplexReadOnly != widget.publicComplexReadOnly ||
        oldWidget.sharedComplexEditing != widget.sharedComplexEditing ||
        oldWidget.sharedMarkdownEditing != widget.sharedMarkdownEditing ||
        !identical(
          oldWidget.localImageAttachments,
          widget.localImageAttachments,
        ) ||
        !identical(oldWidget.localResourceFactory, widget.localResourceFactory);
    final controllerChanged = !identical(
      oldWidget.retirementController,
      widget.retirementController,
    );
    if (controllerChanged) {
      oldWidget.retirementController?.unbind(this);
      _bindController(widget.retirementController);
    } else if (changed && widget.retirementController != null) {
      unawaited(widget.retirementController!.retire());
      return;
    }
    if (changed || controllerChanged) unawaited(_startOpen());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (widget.retirementController != null) {
        unawaited(
          widget.retirementController!.retire().catchError((Object _) {}),
        );
        return;
      }
      _epoch++;
      _deadline?.cancel();
      _closed = true;
      if (mounted && !_disposed) setState(() {});
      unawaited(
        (_session?.close() ?? HtmlBrowserSession.closeActive()).catchError(
          (Object _) {},
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _localImages?.close();
    unawaited(_localRichdocResources?.retireAndDrain());
    unawaited(_localMindmapResources?.retireAndDrain());
    unawaited(_localDrawingResources?.retireAndDrain());
    unawaited(_localPresentationResources?.retireAndDrain());
    _publicResources?.close();
    _closed = true;
    _ready = false;
    widget.retirementController?.unbind(this);
    _epoch++;
    _deadline?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    final session = _session;
    if (session != null) unawaited(session.close().catchError((Object _) {}));
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if ((_failed || _closed) && !_keepViewForSnapshot) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.publicServer != null
                    ? t(
                        _failed
                            ? '正文暂不可用'
                            : widget.sharedMarkdownEditing
                            ? '编辑已暂停'
                            : '阅读已暂停',
                        _failed
                            ? 'Content unavailable'
                            : widget.sharedMarkdownEditing
                            ? 'Editing paused'
                            : 'Reading paused',
                      )
                    : t(
                        '编辑器已关闭或暂不可用，原始内容已保留。',
                        'Editor closed or unavailable. Original content preserved.',
                      ),
              ),
              if (_nativeCloseAcknowledged &&
                  (widget.retirementController?.retired != true ||
                      widget.canRenewRetirement &&
                          widget.onReloadRequested != null ||
                      widget.publicServer != null &&
                          widget.onReloadRequested != null))
                TextButton.icon(
                  onPressed: widget.onReloadRequested ?? _startOpen,
                  icon: const Icon(Icons.refresh),
                  label: Text(t('重新加载', 'Reload')),
                ),
            ],
          ),
        ),
      );
    }
    final session = _session;
    if (session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Stack(
      children: [
        Positioned.fill(
          child: PlatformViewLink(
            key: ValueKey(session.lease),
            viewType: _viewType,
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                Factory<OneSequenceGestureRecognizer>(
                  () => EagerGestureRecognizer(),
                ),
              },
            ),
            onCreatePlatformView: (params) {
              final controller = PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: _viewType,
                layoutDirection: Directionality.of(context),
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: {
                  'lease': session.lease,
                  if (_publicRoot != null) 'server': _publicRoot.toString(),
                  if (_localRichdocResources != null) ...{
                    'resourceScope': _localRichdocResources!.identity,
                    'sourceDigest':
                        _localRichdocResources!.references.sourceDigest,
                  },
                  if (_localDrawingResources != null) ...{
                    'resourceScope': _localDrawingResources!.identity,
                    'sourceDigest':
                        _localDrawingResources!.references.sourceDigest,
                  },
                  if (_localPresentationResources != null) ...{
                    'resourceScope': _localPresentationResources!.identity,
                    'sourceDigest':
                        _localPresentationResources!.references.sourceDigest,
                  },
                  if (_localMindmapResources != null) ...{
                    'resourceScope': _localMindmapResources!.identity,
                    'sourceDigest':
                        _localMindmapResources!.references.sourceDigest,
                  },
                  if (_generationResources != null)
                    'resourceScope': _generationResources!.scopeIdentity,
                  if (_ownedResources != null) ...{
                    'server': _ownedResources!.lease.client.baseUri.toString(),
                    'resourceScope': _ownedResources!.identity,
                  },
                },
                onFocus: () => params.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                params.onPlatformViewCreated,
              );
              controller.addOnPlatformViewCreatedListener(
                (id) => _created(id, session),
              );
              unawaited(controller.create());
              return controller;
            },
          ),
        ),
        if (!_ready)
          const Positioned.fill(
            child: ColoredBox(
              color: Colors.white,
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}
