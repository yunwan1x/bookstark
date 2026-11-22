import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'admin_terminal_controller.dart';

class AdminTerminalBrowser extends StatefulWidget {
  const AdminTerminalBrowser({
    super.key,
    required this.controller,
    required this.generation,
    required this.scrollback,
    this.english = false,
  });
  final AdminTerminalController controller;
  final int generation, scrollback;
  final bool english;
  @override
  State<AdminTerminalBrowser> createState() => AdminTerminalBrowserState();
}

class AdminTerminalBrowserState extends State<AdminTerminalBrowser> {
  late final String _lease = List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  MethodChannel? _channel;
  bool _ready = false, _retired = false, _writing = false, _failed = false;
  bool? _enabled;
  Timer? _deadline;
  bool get _live => mounted && !_retired && !widget.controller.disposed;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _deadline = Timer(const Duration(seconds: 15), () {
      if (!_ready) _fail();
    });
  }

  void _created(int id) {
    if (!_live) return;
    final channel = MethodChannel('bookstark/admin_terminal/$id');
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
          _deadline?.cancel();
          if (_ready) {
            _fail();
            return;
          }
          setState(() {
            _ready = true;
          });
          _changed();
        case 'input':
          final data = args['data'];
          if (data is String) widget.controller.input(widget.generation, data);
        case 'resize':
          final cols = args['cols'], rows = args['rows'];
          if (cols is int && rows is int) {
            widget.controller.resize(widget.generation, cols, rows);
          }
        case 'failed':
          _fail();
      }
    });
  }

  Future<void> _command(
    String type, [
    Map<String, Object?> args = const {},
  ]) async {
    if (!_live || !_ready) return;
    await _channel?.invokeMethod<void>('command', {
      'lease': _lease,
      'generation': widget.generation,
      'type': type,
      ...args,
    });
  }

  void _changed() {
    if (!_live || !_ready) return;
    final enabled =
        widget.controller.canInput &&
        widget.controller.generation == widget.generation;
    if (_enabled != enabled) {
      _enabled = enabled;
      unawaited(
        _command('enabled', {'value': enabled}).catchError((Object _) {
          _fail();
        }),
      );
    }
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (!_live || !_ready || _writing) return;
    _writing = true;
    try {
      while (_live &&
          _ready &&
          widget.controller.presentationOwnsOutput(widget.generation)) {
        final chunk = widget.controller.output.take();
        if (chunk == null) break;
        // Native resolves only after xterm parsed this frame. At most one in flight.
        await _command('output', {'data': chunk});
      }
    } catch (_) {
      if (_live) _fail();
    } finally {
      _writing = false;
    }
  }

  void _fail() {
    if (!_live || _failed) return;
    _failed = true;
    _deadline?.cancel();
    widget.controller.presentationFailed(widget.generation);
    unawaited(_channel?.invokeMethod<void>('retire').catchError((Object _) {}));
    if (mounted) {
      setState(() {
        _retired = true;
      });
    }
  }

  Future<void> focus() async {
    try {
      await _command('focus');
    } catch (_) {
      _fail();
    }
  }

  Future<void> shortcut(String key) async {
    try {
      await _command('shortcut', {'key': key});
    } catch (_) {
      _fail();
    }
  }

  @override
  void dispose() {
    _retired = true;
    _deadline?.cancel();
    widget.controller.removeListener(_changed);
    final channel = _channel;
    _channel = null;
    channel?.setMethodCallHandler(null);
    unawaited(channel?.invokeMethod<void>('retire').catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || _failed) {
      return Center(
        child: Text(
          widget.english
              ? 'Terminal requires Android WebView.'
              : '终端需要 Android WebView。',
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: PlatformViewLink(
            viewType: 'bookstark/admin_terminal',
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
                viewType: 'bookstark/admin_terminal',
                layoutDirection: Directionality.of(context),
                creationParamsCodec: const StandardMessageCodec(),
                creationParams: {
                  'lease': _lease,
                  'generation': widget.generation,
                  'scrollback': widget.scrollback,
                  'english': widget.english,
                },
                onFocus: () => params.onFocusChanged(true),
              );
              controller.addOnPlatformViewCreatedListener(
                params.onPlatformViewCreated,
              );
              controller.addOnPlatformViewCreatedListener(_created);
              unawaited(controller.create());
              return controller;
            },
          ),
        ),
        if (!_ready) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
