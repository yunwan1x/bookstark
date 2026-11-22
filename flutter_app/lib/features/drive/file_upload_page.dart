import 'dart:async';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/drive_models.dart';
import '../../core/drive_repository.dart';
import '../../core/drive_upload_controller.dart';
import 'drive_directory_picker.dart';

class FileUploadPage extends StatefulWidget {
  const FileUploadPage({
    super.key,
    required this.repository,
    required this.directory,
    this.pickFiles,
  });
  final DriveRepository repository;
  final String directory;
  final Future<List<XFile>> Function()? pickFiles;
  @override
  State<FileUploadPage> createState() => _FileUploadPageState();
}

class _FileUploadPageState extends State<FileUploadPage> {
  late final queue = DriveUploadController(
    widget.repository,
    directory: widget.directory,
  );
  Object? error;
  bool picking = false, leaving = false;
  final choices = <int, Completer<DriveCollisionChoice>>{};
  @override
  void initState() {
    super.initState();
    queue.addListener(update);
  }

  void update() {
    if (mounted) setState(() {});
  }

  Future<void> pick() async {
    setState(() {
      picking = true;
      error = null;
    });
    try {
      final files = await (widget.pickFiles?.call() ?? openFiles());
      if (mounted) queue.addFiles(files);
    } catch (e) {
      if (mounted) setState(() => error = e);
    } finally {
      if (mounted) setState(() => picking = false);
    }
  }

  Future<void> start() async {
    setState(() => error = null);
    try {
      await queue.start(
        onCollision: (entry, node) {
          final completer = Completer<DriveCollisionChoice>();
          choices[entry.id] = completer;
          update();
          return completer.future.whenComplete(() {
            choices.remove(entry.id);
            update();
          });
        },
      );
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  void stop() {
    queue.stop();
    for (final choice in choices.values) {
      if (!choice.isCompleted) {
        choice.complete(const DriveCollisionChoice(DriveCollisionAction.pause));
      }
    }
  }

  void choose(DriveUploadEntry entry, DriveCollisionChoice value) {
    final choice = choices[entry.id];
    if (choice != null && !choice.isCompleted) choice.complete(value);
  }

  Future<void> rename(DriveUploadEntry entry) async {
    final input = TextEditingController(text: entry.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('改名上传'),
        content: TextField(
          controller: input,
          autofocus: true,
          decoration: const InputDecoration(labelText: '新文件名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              try {
                Navigator.pop(context, driveName(input.text));
              } catch (_) {}
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    // Dialog closing animation may still reference the editing controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => input.dispose());
    if (name != null && choices[entry.id]?.isCompleted == false) {
      choose(
        entry,
        DriveCollisionChoice(DriveCollisionAction.rename, name: name),
      );
    }
  }

  Future<void> directory() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => DriveDirectoryPicker(
          repository: widget.repository,
          initial: queue.directory,
        ),
      ),
    );
    if (value != null && mounted) {
      try {
        queue.setDirectory(value);
      } catch (e) {
        setState(() => error = e);
      }
    }
  }

  Future<void> close() async {
    if (queue.running) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('停止并离开？'),
          content: const Text(
            '已提交的请求仍可能完成；离开不会撤销远程写入。队列尚不支持进程终止恢复，建议留在此页核对结果。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续上传'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('停止并离开'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    } else if (queue.entries.any(
      (e) => e.state == DriveUploadState.uncertain,
    )) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('仍有待核对上传'),
          content: const Text('旧请求可能已保存。离开后可在目标目录核对，本页队列尚未持久保存。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('返回核对'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('离开'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    stop();
    if (mounted) {
      setState(() => leaving = true);
      Navigator.pop(context, true);
    }
  }

  String status(DriveUploadEntry e) => switch (e.state) {
    DriveUploadState.pending => '待上传',
    DriveUploadState.preparing => '读取并校验源文件',
    DriveUploadState.conflict => '目标存在，需确认',
    DriveUploadState.uploading => '已发送 ${e.sent} 字节，等待服务端确认',
    DriveUploadState.confirmed => '已确认保存',
    DriveUploadState.reused => '已复用并确认保存',
    DriveUploadState.skipped => '已跳过',
    DriveUploadState.failed => '未完成',
    DriveUploadState.uncertain => '结果待核对',
  };
  @override
  void dispose() {
    for (final choice in choices.values) {
      if (!choice.isCompleted) {
        choice.complete(const DriveCollisionChoice(DriveCollisionAction.pause));
      }
    }
    queue.removeListener(update);
    queue.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: leaving,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) unawaited(close());
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('上传文件'),
        leading: IconButton(
          tooltip: '返回网盘',
          onPressed: close,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '保存到',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(
                            queue.directory.isEmpty
                                ? '全部文件'
                                : '全部文件 / ${queue.directory}',
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: queue.running ? null : directory,
                        ),
                        const Text('同名文件需要确认后覆盖。'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: queue.running || picking ? null : pick,
                  icon: const Icon(Icons.upload_file),
                  label: const Text('选择文件（可多选）'),
                ),
                const SizedBox(height: 16),
                Text(
                  '${queue.entries.where((e) => !e.completed && e.state != DriveUploadState.skipped).length} 项待处理 · ${queue.entries.where((e) => e.completed).length} 项已保存',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('$error'),
                  ),
                for (final entry in queue.entries)
                  Card(
                    key: ValueKey(entry.id),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.insert_drive_file_outlined,
                            ),
                            title: Text(entry.name),
                            subtitle: Text(
                              '${entry.size == null ? '大小待读取' : '${entry.size} 字节'} · ${status(entry)}',
                            ),
                            trailing:
                                queue.running ||
                                    entry.state == DriveUploadState.uncertain
                                ? null
                                : IconButton(
                                    tooltip: '移除',
                                    onPressed: () => queue.remove(entry),
                                    icon: const Icon(Icons.close),
                                  ),
                          ),
                          if (entry.error != null) Text(entry.error!),
                          if (entry.state == DriveUploadState.uploading)
                            const LinearProgressIndicator(),
                          if (choices.containsKey(entry.id))
                            Wrap(
                              spacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: () => rename(entry),
                                  child: const Text('改名'),
                                ),
                                OutlinedButton(
                                  onPressed: () => choose(
                                    entry,
                                    const DriveCollisionChoice(
                                      DriveCollisionAction.overwrite,
                                    ),
                                  ),
                                  child: const Text('覆盖'),
                                ),
                                OutlinedButton(
                                  onPressed: () => choose(
                                    entry,
                                    const DriveCollisionChoice(
                                      DriveCollisionAction.skip,
                                    ),
                                  ),
                                  child: const Text('跳过'),
                                ),
                              ],
                            ),
                          if (entry.state == DriveUploadState.uncertain)
                            TextButton(
                              onPressed: entry.verifying || queue.running
                                  ? null
                                  : () async {
                                      try {
                                        await queue.verify(entry);
                                      } catch (_) {}
                                    },
                              child: const Text('只读核对结果'),
                            ),
                        ],
                      ),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('上传进度以服务端确认保存为准。发送完成不代表保存成功。'),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: queue.running
                      ? stop
                      : !queue.entries.any(
                              (e) => e.state == DriveUploadState.uncertain,
                            ) &&
                            queue.entries.any(
                              (e) =>
                                  e.state == DriveUploadState.pending ||
                                  e.state == DriveUploadState.conflict,
                            )
                      ? start
                      : null,
                  child: Text(
                    queue.running
                        ? '停止上传'
                        : queue.entries.any(
                            (e) => e.state == DriveUploadState.uncertain,
                          )
                        ? '请先核对上传结果'
                        : '开始上传',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
