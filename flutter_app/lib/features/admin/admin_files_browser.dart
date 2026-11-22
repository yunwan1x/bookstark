import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'admin_files_models.dart';
import 'admin_files_lease.dart';

class AdminFileEditorBrowser extends StatefulWidget {
  const AdminFileEditorBrowser({
    super.key,
    required this.content,
    required this.generation,
    required this.onChanged,
    required this.onFailed,
    this.english = false,
    this.enabled = true,
    this.onLimit,
    this.lease,
  });
  final String content;
  final int generation;
  final ValueChanged<bool> onChanged;
  final VoidCallback onFailed;
  final VoidCallback? onLimit;
  final bool english, enabled;
  final AdminFileEditorLease? lease;
  @override
  State<AdminFileEditorBrowser> createState() => AdminFileEditorBrowserState();
}

class AdminFileEditorBrowserState extends State<AdminFileEditorBrowser> {
  late final _handle = widget.lease ?? AdminFileEditorLease();
  late final String _lease = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  MethodChannel? _channel;
  Timer? _deadline;
  int _zoom = 100;
  bool _ready = false, _retired = false, _failed = false;
  bool get _live => mounted && !_retired && !_handle.closed;
  bool get ready => _live && _ready;
  @override
  void initState() {
    super.initState();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _deadline = Timer(const Duration(seconds: 15), () {
      if (!_ready) _fail();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final zoom = (MediaQuery.textScalerOf(context).scale(14) / 14 * 100)
        .round()
        .clamp(50, 300);
    if (_zoom != zoom) {
      _zoom = zoom;
      if (_ready) {
        unawaited(
          _command<void>('zoom', {'value': zoom}).catchError((Object _) {
            _fail();
          }),
        );
      }
    }
  }

  void _created(int id) {
    if (!_live) return;
    final channel = MethodChannel('bookstark/admin_file_editor/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      final args = call.arguments;
      if (!_live ||
          args is! Map ||
          args['lease'] != _lease ||
          args['generation'] != widget.generation) {
        return;
      }
      switch (call.method) {
        case 'ready':
          if (_ready) {
            _fail();
            return;
          }
          _deadline?.cancel();
          setState(() => _ready = true);
          await _command<void>('enabled', {'value': widget.enabled});
        case 'changed':
          if (args['dirty'] is bool) widget.onChanged(args['dirty'] as bool);
        case 'limit':
          widget.onLimit?.call();
        case 'failed':
          _fail();
      }
    });
  }

  Future<T?> _command<T>(
    String type, [
    Map<String, Object?> extra = const {},
  ]) async {
    if (!_live || !_ready || _channel == null) {
      throw StateError('File editor not ready');
    }
    return _channel!.invokeMethod<T>('command', {
      'lease': _lease,
      'generation': widget.generation,
      'type': type,
      ...extra,
    });
  }

  Future<String> snapshot() async {
    final text = await _command<String>('snapshot');
    if (!_live || text == null) throw StateError('File editor retired');
    // Exact text only; this DTO validates UTF-8, NUL and the server read limit.
    return adminFileDecodeEditorSnapshot(text);
  }

  Future<void> focus() async {
    if (!ready) return;
    try {
      await _command<void>('focus');
    } catch (_) {
      _fail();
    }
  }

  Future<void> insert(String content) async {
    AdminFileText('/owned-source', content);
    await _command<void>('insert', {'content': content});
  }

  @override
  void didUpdateWidget(covariant AdminFileEditorBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lease != widget.lease ||
        oldWidget.content != widget.content ||
        oldWidget.generation != widget.generation) {
      _fail();
    } else if (_ready && oldWidget.enabled != widget.enabled) {
      unawaited(
        _command<void>('enabled', {'value': widget.enabled}).catchError((
          Object _,
        ) {
          _fail();
        }),
      );
    }
  }

  void _fail() {
    if (!_live || _failed) return;
    _failed = true;
    _deadline?.cancel();
    unawaited(retire().catchError((Object _) {}));
    widget.onFailed();
  }

  Future<void> retire() {
    if (!_retired) {
      _retired = true;
      _deadline?.cancel();
      _channel?.setMethodCallHandler(null);
      _channel = null;
    }
    return _handle.retire();
  }

  @override
  void dispose() {
    unawaited(retire().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_handle.closed) return const SizedBox.shrink();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _failed) {
      return Center(
        child: Text(
          widget.english
              ? 'Source editor requires Android WebView.'
              : '源代码编辑器需要 Android WebView。',
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: PlatformViewLink(
            viewType: 'bookstark/admin_file_editor',
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
                viewType: 'bookstark/admin_file_editor',
                layoutDirection: Directionality.of(context),
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: {
                  'lease': _lease,
                  'generation': widget.generation,
                  'content': widget.content,
                  'enabled': widget.enabled,
                  'textZoom': _zoom,
                  'english': widget.english,
                },
                onFocus: () => params.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                params.onPlatformViewCreated,
              );
              controller.addOnPlatformViewCreatedListener(_created);
              unawaited(
                _handle.create(params.id, controller.create).catchError((
                  Object _,
                ) {
                  _fail();
                }),
              );
              return controller;
            },
          ),
        ),
        if (!_ready) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
