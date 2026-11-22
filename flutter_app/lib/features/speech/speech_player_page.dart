import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/speech_controller.dart';
import '../../core/speech_playback.dart';

class SpeechRequest {
  const SpeechRequest(
    this.markdown, {
    required this.title,
    this.context = '',
    this.verifyBeforeStart,
    this.isCurrent,
  });
  final String markdown, title, context;
  final Future<bool> Function()? verifyBeforeStart;
  final bool Function()? isCurrent;
}

class SpeechPlayerPage extends StatefulWidget {
  const SpeechPlayerPage({
    super.key,
    required this.controller,
    this.request,
    this.english = false,
    this.onStop,
  });
  final SpeechController controller;
  final SpeechRequest? request;
  final bool english;
  final Future<void> Function()? onStop;
  @override
  State<SpeechPlayerPage> createState() => _SpeechPlayerPageState();
}

class _SpeechPlayerPageState extends State<SpeechPlayerPage> {
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    if (widget.request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _prepare());
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (mounted) setState(() => _error = null);
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  void _prepare() {
    final request = widget.request;
    if (!mounted || request == null) return;
    unawaited(
      _run(() async {
        final controller = widget.controller;
        bool current() =>
            mounted &&
            identical(widget.request, request) &&
            identical(widget.controller, controller) &&
            (request.isCurrent?.call() ?? true);
        if (!current()) return;
        final verify = request.verifyBeforeStart;
        if (verify != null && (!await verify() || !current())) {
          throw StateError(
            t(
              '选区或原文已变化，请返回重新捕获。',
              'Selection or source changed. Return and capture again.',
            ),
          );
        }
        if (!current()) return;
        await controller.prepare(
          request.markdown,
          title: request.title,
          context: request.context,
          english: widget.english,
          autoPlay: true,
        );
      }),
    );
  }

  String _status(SpeechController engine) {
    if (engine.closed) {
      return t('朗读已关闭，请返回重新开始', 'Reading closed; return to start again');
    }
    if (engine.preparing || engine.phase == SpeechPlaybackPhase.loading) {
      return t('正在合成…', 'Preparing speech…');
    }
    if (engine.phase == SpeechPlaybackPhase.error) {
      return t('朗读中断', 'Reading interrupted');
    }
    if (engine.phase == SpeechPlaybackPhase.completed) {
      return t('朗读结束', 'Reading complete');
    }
    if (engine.phase == SpeechPlaybackPhase.buffering) {
      return t('正在缓冲…', 'Buffering…');
    }
    return engine.wantsPlayback
        ? t('正在朗读', 'Reading')
        : engine.active
        ? t('已暂停', 'Paused')
        : t('准备朗读', 'Ready to read');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final engine = widget.controller, theme = Theme.of(context);
      final error = _error ?? engine.error;
      return Scaffold(
        appBar: AppBar(title: Text(t('听书', 'Listen'))),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                engine.title.isEmpty
                    ? widget.request?.title ?? ''
                    : engine.title,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                engine.context,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              if (engine.preparing ||
                  engine.phase == SpeechPlaybackPhase.loading ||
                  engine.phase == SpeechPlaybackPhase.buffering)
                const LinearProgressIndicator(),
              if (error != null) ...[
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
                TextButton(
                  onPressed: engine.closed || engine.preparing
                      ? null
                      : () {
                          if (engine.voices.isEmpty && widget.request != null) {
                            _prepare();
                          } else {
                            _run(engine.play);
                          }
                        },
                  child: Text(t('重试朗读', 'Retry reading')),
                ),
              ],
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t('音色', 'Voice'), style: theme.textTheme.titleSmall),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(engine.voice),
                        initialValue:
                            engine.voices.any((item) => item.id == engine.voice)
                            ? engine.voice
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: t('选择音色', 'Choose a voice'),
                        ),
                        items: engine.voices
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.id,
                                child: Tooltip(
                                  message: '${item.name} (${item.id})',
                                  child: Text(
                                    widget.english
                                        ? '${item.id.split('-').last.replaceFirst(RegExp(r'Neural$'), '')} · ${item.locale}'
                                        : item.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: engine.closed || engine.preparing
                            ? null
                            : (id) {
                                if (id != null) _run(() => engine.setVoice(id));
                              },
                      ),
                      const SizedBox(height: 24),
                      Text(t('倍速', 'Speed'), style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final speed in [0.75, 1.0, 1.25, 1.5])
                            ChoiceChip(
                              label: Text('${speed == 1 ? '1.0' : speed}×'),
                              selected: engine.speed == speed,
                              showCheckmark: false,
                              selectedColor: theme.colorScheme.primary,
                              labelStyle: TextStyle(
                                color: engine.speed == speed
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onSelected: (_) =>
                                  _run(() => engine.setSpeed(speed)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _status(engine),
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (engine.segments.isNotEmpty)
                            Text(
                              t(
                                '第${engine.index + 1}段 / 共${engine.segments.length}段',
                                '${engine.index + 1} / ${engine.segments.length} passages',
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SelectableText(
                        engine.paragraph,
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: t('上一段', 'Previous passage'),
                                onPressed:
                                    engine.index > 0 &&
                                        !engine.closed &&
                                        !engine.closed &&
                                        !engine.preparing
                                    ? () => _run(engine.previous)
                                    : null,
                                icon: const Icon(Icons.skip_previous),
                              ),
                              Text(t('上一段', 'Previous passage')),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton.filled(
                                tooltip: engine.wantsPlayback
                                    ? t('暂停', 'Pause')
                                    : t('播放', 'Play'),
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(72, 72),
                                  shape: const CircleBorder(),
                                ),
                                onPressed:
                                    engine.closed || engine.segments.isEmpty
                                    ? null
                                    : () => _run(
                                        engine.wantsPlayback
                                            ? engine.pause
                                            : engine.play,
                                      ),
                                iconSize: 40,
                                icon: Icon(
                                  engine.wantsPlayback
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                ),
                              ),
                              Text(
                                engine.wantsPlayback
                                    ? t('暂停', 'Pause')
                                    : t('播放', 'Play'),
                              ),
                            ],
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: t('下一段', 'Next passage'),
                                onPressed:
                                    engine.index + 1 < engine.segments.length &&
                                        !engine.closed &&
                                        !engine.preparing
                                    ? () => _run(engine.next)
                                    : null,
                                icon: const Icon(Icons.skip_next),
                              ),
                              Text(t('下一段', 'Next passage')),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton.icon(
                        onPressed: engine.active || engine.wantsPlayback
                            ? () => _run(widget.onStop ?? engine.stop)
                            : null,
                        icon: const Icon(Icons.stop),
                        label: Text(t('停止朗读', 'Stop reading')),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        t(
                          '返回后保持后台播放，可在通知栏控制',
                          'Playback continues after returning; use notification controls',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
