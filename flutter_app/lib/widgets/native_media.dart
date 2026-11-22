import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Plays a completed cached file; it does not claim streamed network playback.
class NativeMedia extends StatefulWidget {
  const NativeMedia({
    super.key,
    required this.path,
    required this.audioOnly,
    this.english = false,
    this.beforePlay,
  });
  final String path;
  final bool audioOnly, english;
  final Future<void> Function()? beforePlay;
  @override
  State<NativeMedia> createState() => _NativeMediaState();
}

class _NativeMediaState extends State<NativeMedia> with WidgetsBindingObserver {
  VideoPlayerController? _player;
  bool _loading = true, _handling = false;
  String? _error;
  int _generation = 0;
  double? _seek;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didUpdateWidget(covariant NativeMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.audioOnly != widget.audioOnly) {
      _init();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (ModalRoute.isCurrentOf(context) == false) unawaited(_pause());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_pause());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    final player = _player;
    _player = null;
    if (player != null) {
      unawaited(() async {
        try {
          await player.pause();
        } catch (_) {}
        await player.dispose();
      }());
    }
    super.dispose();
  }

  Future<void> _pause() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  Future<void> _init() async {
    final generation = ++_generation, old = _player;
    _player = null;
    setState(() {
      _loading = true;
      _error = null;
      _seek = null;
    });
    try {
      await old?.dispose();
      if (!mounted || generation != _generation) return;
      final options = VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      );
      final player = kIsWeb
          ? VideoPlayerController.networkUrl(
              Uri.parse(widget.path),
              videoPlayerOptions: options,
            )
          : VideoPlayerController.file(
              File(widget.path),
              videoPlayerOptions: options,
            );
      _player = player;
      await player.initialize();
      if (!mounted || generation != _generation) {
        await player.dispose();
        return;
      }
      setState(() => _loading = false);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _action(
    Future<void> Function(VideoPlayerController) action,
  ) async {
    final player = _player;
    if (_handling || player == null || !player.value.isInitialized) return;
    setState(() {
      _handling = true;
      _error = null;
    });
    try {
      await action(player);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  Future<void> _toggle() => _action((player) async {
    if (player.value.isPlaying) {
      await player.pause();
      return;
    }
    if (ModalRoute.isCurrentOf(context) == false) return;
    await widget.beforePlay?.call();
    if (!mounted || !identical(player, _player)) return;
    if (player.value.duration > Duration.zero &&
        player.value.position >= player.value.duration) {
      await player.seekTo(Duration.zero);
    }
    await player.play();
  });
  void _jump(int seconds) => _action((player) async {
    final value = player.value,
        position = (value.position.inMilliseconds + seconds * 1000).clamp(
          0,
          value.duration.inMilliseconds,
        );
    await player.seekTo(Duration(milliseconds: position));
  });
  String _time(Duration value) {
    final seconds = value.inSeconds;
    return seconds >= 3600
        ? '${seconds ~/ 3600}:${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    if (_loading) {
      return SizedBox(
        height: 200,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(t('正在打开媒体文件…', 'Opening media file…')),
            ],
          ),
        ),
      );
    }
    if (player == null) return _failure();
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (context, value, _) {
        if (!value.isInitialized || value.hasError) {
          return _failure(value.errorDescription);
        }
        final duration = value.duration.inMilliseconds,
            seekable = duration > 0,
            position = (_seek ?? value.position.inMilliseconds.toDouble())
                .clamp(0, mathMax(duration));
        final validSpeed =
            value.playbackSpeed.isFinite && value.playbackSpeed > 0;
        final speeds = <double>{
          0.75,
          1,
          1.25,
          1.5,
          2,
          if (validSpeed) value.playbackSpeed,
        }.toList()..sort();
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            if (widget.audioOnly)
              const SizedBox(
                height: 160,
                child: Center(
                  child: Icon(
                    Icons.audio_file_outlined,
                    size: 64,
                    color: Color(0xff2563eb),
                  ),
                ),
              )
            else
              Container(
                color: Colors.black,
                constraints: const BoxConstraints(maxHeight: 280),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: value.aspectRatio > 0
                        ? value.aspectRatio
                        : 16 / 9,
                    child: VideoPlayer(player),
                  ),
                ),
              ),
            if (value.isBuffering) const LinearProgressIndicator(),
            const SizedBox(height: 12),
            Text(
              '${_time(Duration(milliseconds: position.toInt()))} / ${seekable ? _time(value.duration) : t('时长未知', 'Duration unknown')}',
              textAlign: TextAlign.center,
            ),
            if (seekable)
              Slider(
                value: position.toDouble(),
                max: duration.toDouble(),
                onChanged: _handling
                    ? null
                    : (value) => setState(() => _seek = value),
                onChangeEnd: _handling
                    ? null
                    : (value) async {
                        await _action(
                          (player) => player.seekTo(
                            Duration(milliseconds: value.toInt()),
                          ),
                        );
                        if (mounted) setState(() => _seek = null);
                      },
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: t('后退10秒', 'Back 10 seconds'),
                  onPressed: _handling || !seekable ? null : () => _jump(-10),
                  icon: const Icon(Icons.replay_10),
                ),
                FilledButton.icon(
                  onPressed: _handling ? null : _toggle,
                  icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  label: Text(
                    value.isPlaying ? t('暂停', 'Pause') : t('播放', 'Play'),
                  ),
                ),
                IconButton(
                  tooltip: t('前进10秒', 'Forward 10 seconds'),
                  onPressed: _handling || !seekable ? null : () => _jump(10),
                  icon: const Icon(Icons.forward_10),
                ),
                SizedBox(
                  width: (100 * MediaQuery.textScalerOf(context).scale(14) / 14)
                      .clamp(100, 200),
                  child: DropdownButton<double>(
                    isExpanded: true,
                    value: validSpeed ? value.playbackSpeed : null,
                    hint: Text(
                      t('速度未知', 'Speed unknown'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: [
                      for (final speed in speeds)
                        DropdownMenuItem(value: speed, child: Text('$speed×')),
                    ],
                    onChanged: _handling
                        ? null
                        : (speed) {
                            if (speed != null) {
                              _action(
                                (player) => player.setPlaybackSpeed(speed),
                              );
                            }
                          },
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  double mathMax(int duration) => duration > 0 ? duration.toDouble() : 0;
  Widget _failure([String? details]) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline),
        Text(
          t(
            '无法播放此媒体，可重试或保存文件。',
            'This media cannot be played. Retry or save the file.',
          ),
        ),
        if (details != null || _error != null) Text(details ?? _error!),
        TextButton(onPressed: _init, child: Text(t('重试', 'Retry'))),
      ],
    ),
  );
}
