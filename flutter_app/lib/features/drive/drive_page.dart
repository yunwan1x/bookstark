import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/drive_models.dart';
import '../../core/drive_repository.dart';
import '../../core/file_draft_vault.dart';
import '../images/image_format.dart';
import 'file_editor_page.dart';
import 'file_preview_page.dart';
import 'file_public_page.dart';
import 'file_upload_page.dart';
import 'drive_directory_picker.dart';

class DrivePage extends StatefulWidget {
  const DrivePage({
    super.key,
    required this.repository,
    required this.vault,
    this.beforePlay,
    this.mutationBlocked,
  });
  final bool Function()? mutationBlocked;
  final DriveRepository repository;
  final FileDraftVault vault;
  final Future<void> Function()? beforePlay;
  @override
  State<DrivePage> createState() => _DrivePageState();
}

class _DrivePageState extends State<DrivePage> {
  String path = '', query = '', sort = 'name';
  List<DriveNode> rows = [];
  DriveProfile? profile;
  Object? error, profileError;
  bool loading = true, writing = false, leaving = false;
  String? uncertain;
  int generation = 0;
  final search = TextEditingController();
  @override
  void initState() {
    super.initState();
    load('');
  }

  Future<void> load(String target) async {
    final epoch = ++generation;
    final moved = target != path;
    setState(() {
      loading = true;
      error = null;
      if (moved) {
        path = target;
        rows = [];
        query = '';
        search.clear();
      }
    });
    final stats = widget.repository.profile().then<void>(
      (value) {
        if (mounted && epoch == generation) {
          setState(() {
            profile = value;
            profileError = null;
          });
        }
      },
      onError: (Object e) {
        if (mounted && epoch == generation) setState(() => profileError = e);
      },
    );
    try {
      final result = await widget.repository.list(target);
      if (mounted && epoch == generation) {
        setState(() {
          rows = result;
          path = target;
        });
      }
    } catch (e) {
      if (mounted && epoch == generation) setState(() => error = e);
    } finally {
      if (mounted && epoch == generation) setState(() => loading = false);
    }
    await stats;
  }

  Future<String?> name(String title, {String initial = ''}) async {
    // The dialog owns its controller through a separate StatefulWidget.
    return showDialog<String>(
      context: context,
      builder: (_) => _DriveNameDialog(title: title, initial: initial),
    );
  }

  Future<void> write(
    String description,
    Future<void> Function() operation,
  ) async {
    if (writing ||
        uncertain != null ||
        (widget.mutationBlocked?.call() ?? false)) {
      return;
    }
    setState(() {
      writing = true;
      error = null;
    });
    try {
      await operation();
    } on DriveConflict catch (e) {
      error = e;
    } catch (e) {
      error = e;
      uncertain = '$description 的结果待核对，请先刷新检查源路径与目标路径；不会自动重新提交。';
    } finally {
      if (mounted) {
        setState(() => writing = false);
        await load(path);
      }
    }
  }

  Future<void> mkdir() async {
    if (widget.mutationBlocked?.call() ?? false) return;
    final value = await name('新建文件夹');
    if (value == null || !mounted) return;
    await write('新建文件夹 $value', () async {
      await widget.repository.mkdir(path, value);
    });
  }

  Future<void> open(DriveNode node) async {
    if (node.directory) {
      await load(node.path);
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => FilePreviewPage(
          repository: widget.repository,
          file: node,
          beforePlay: widget.beforePlay,
        ),
      ),
    );
  }

  Future<void> menu(DriveNode node) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(node.name), subtitle: Text(node.path)),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(node.directory ? '打开目录' : '预览文件'),
                onTap: () => Navigator.pop(context, 'open'),
              ),
              if (!node.directory)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('编辑 UTF-8 文本'),
                  onTap: () => Navigator.pop(context, 'edit'),
                ),
              if (!node.directory && !widget.repository.local)
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('公开设置'),
                  onTap: () => Navigator.pop(context, 'public'),
                ),
              if (!writing &&
                  uncertain == null &&
                  !(widget.mutationBlocked?.call() ?? false)) ...[
                for (final item in [
                  ('rename', '重命名', Icons.drive_file_rename_outline),
                  ('move', '移动到', Icons.drive_file_move_outline),
                  ('copy', '复制到', Icons.copy_outlined),
                  ('delete', '永久删除', Icons.delete_outline),
                ])
                  ListTile(
                    leading: Icon(item.$3),
                    title: Text(item.$2),
                    onTap: () => Navigator.pop(context, item.$1),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'open') {
      await open(node);
      return;
    }
    if (action == 'edit') {
      await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => FileEditorPage(
            repository: widget.repository,
            file: node,
            vault: widget.vault,
          ),
        ),
      );
      if (mounted) await load(path);
      return;
    }
    if (action == 'public') {
      await Navigator.push<FilePublicOutcome>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              FilePublicPage(repository: widget.repository, file: node),
        ),
      );
      if (mounted) await load(path);
      return;
    }
    if (action == 'rename') {
      final value = await name('重命名', initial: node.name);
      if (value != null && value != node.name && mounted) {
        await write(
          '重命名 ${node.path}',
          () => widget.repository.rename(
            node,
            driveChild(driveParent(node.path), value),
          ),
        );
      }
    } else if (action == 'move' || action == 'copy') {
      final target = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => DriveDirectoryPicker(
            repository: widget.repository,
            initial: driveParent(node.path),
            exclude: node.directory ? node.path : null,
          ),
        ),
      );
      if (target != null && mounted) {
        final destination = driveChild(target, node.name);
        if (destination == node.path) return;
        await write(
          '${action == 'copy' ? '复制' : '移动'} ${node.path} → $destination',
          () => action == 'copy'
              ? widget.repository.copy(node, destination)
              : widget.repository.rename(node, destination),
        );
      }
    } else if (action == 'delete') {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('永久删除？'),
          content: Text(
            '${node.path}\n${node.directory ? '此文件夹及全部内容将被永久删除。' : '此文件将被永久删除。'}不会进入回收站，引用它的内容可能失效。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('永久删除'),
            ),
          ],
        ),
      );
      if (yes == true && mounted) {
        await write('永久删除 ${node.path}', () => widget.repository.remove(node));
      }
    }
  }

  Future<void> upload() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FileUploadPage(repository: widget.repository, directory: path),
      ),
    );
    if (mounted) await load(path);
  }

  void back() {
    if (writing) return;
    if (path.isNotEmpty) {
      load(driveParent(path));
    } else {
      setState(() => leaving = true);
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible =
        rows
            .where((n) => n.name.toLowerCase().contains(query.toLowerCase()))
            .toList()
          ..sort((a, b) {
            if (a.directory != b.directory) return a.directory ? -1 : 1;
            return switch (sort) {
              'size' => b.size.compareTo(a.size),
              'time' => b.modified.compareTo(a.modified),
              _ => a.name.compareTo(b.name),
            };
          });
    final parts = path.isEmpty ? <String>[] : path.split('/');
    return PopScope(
      canPop: leaving,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) back();
      },
      child: Scaffold(
        backgroundColor: accountCanvas(context, const Color(0xfff8fafc)),
        appBar: AppBar(
          backgroundColor: Colors.white,
          title: const Text('网盘'),
          leading: IconButton(
            tooltip: '返回',
            onPressed: writing ? null : back,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: '刷新',
              onPressed: loading || writing ? null : () => load(path),
              icon: const Icon(Icons.refresh),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'mkdir') mkdir();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'mkdir',
                  enabled:
                      !writing &&
                      uncertain == null &&
                      !(widget.mutationBlocked?.call() ?? false),
                  child: const Text('新建文件夹'),
                ),
              ],
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: writing || uncertain != null ? null : upload,
          icon: const Icon(Icons.upload),
          label: const Text('上传文件'),
        ),
        body: CustomScrollView(
          key: PageStorageKey(path),
          slivers: [
            if (loading || writing)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (profile != null)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '已用 ${imageSizeLabel(profile!.usage.storedBytes)} / ${profile!.usage.unlimited ? '不限额' : imageSizeLabel(profile!.usage.quotaBytes)}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 12),
                              if (!profile!.usage.unlimited)
                                LinearProgressIndicator(
                                  value: profile!.usage.fraction,
                                ),
                              const SizedBox(height: 12),
                              Text('按去重压缩后大小统计 · ${profile!.usage.files} 个文件'),
                            ],
                          ),
                        ),
                      ),
                    if (profileError != null) Text('容量读取失败：$profileError'),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => load(''),
                            child: const Text('全部文件'),
                          ),
                          for (var i = 0; i < parts.length; i++) ...[
                            const Text('/'),
                            TextButton(
                              onPressed: () =>
                                  load(parts.take(i + 1).join('/')),
                              child: Text(parts[i]),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: search,
                      onChanged: (value) => setState(() => query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: '搜索当前目录',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${visible.where((n) => n.directory).length} 个文件夹 · ${visible.where((n) => !n.directory).length} 个文件',
                        ),
                        DropdownButton<String>(
                          value: sort,
                          items: const [
                            DropdownMenuItem(
                              value: 'name',
                              child: Text('名称 ↑'),
                            ),
                            DropdownMenuItem(
                              value: 'size',
                              child: Text('大小 ↓'),
                            ),
                            DropdownMenuItem(
                              value: 'time',
                              child: Text('修改时间 ↓'),
                            ),
                          ],
                          onChanged: (value) => setState(() => sort = value!),
                        ),
                      ],
                    ),
                    if (error != null) Text('读取或操作失败：$error'),
                    if (uncertain != null) Text(uncertain!),
                    if (!loading && error == null && visible.isEmpty)
                      Text(rows.isEmpty ? '此目录为空' : '当前目录没有匹配文件'),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final node = visible[index];
                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      leading: Icon(
                        node.directory ? Icons.folder : Icons.insert_drive_file,
                        color: node.directory
                            ? Colors.amber
                            : const Color(0xff2563eb),
                        size: 36,
                      ),
                      title: Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(node.name),
                          if (node.isPublic)
                            const Text(
                              '公开',
                              style: TextStyle(color: Color(0xff2563eb)),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        node.directory
                            ? '文件夹'
                            : '${imageSizeLabel(node.size)} · ${node.modified.isEmpty ? '时间未知' : node.modified}',
                      ),
                      onTap: writing ? null : () => open(node),
                      trailing: IconButton(
                        tooltip: '${node.name} 操作',
                        onPressed: writing ? null : () => menu(node),
                        icon: const Icon(Icons.more_vert),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 120),
                child: Text('私人空间，公开文件除外。'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriveNameDialog extends StatefulWidget {
  const _DriveNameDialog({required this.title, required this.initial});
  final String title, initial;
  @override
  State<_DriveNameDialog> createState() => _DriveNameDialogState();
}

class _DriveNameDialogState extends State<_DriveNameDialog> {
  late final input = TextEditingController(text: widget.initial);
  String? error;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: input,
      autofocus: true,
      decoration: InputDecoration(labelText: '名称', errorText: error),
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
          } catch (e) {
            setState(() => error = '$e');
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
}
