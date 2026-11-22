import '../../core/app_theme.dart';
import 'package:flutter/material.dart';
import '../../core/drive_models.dart';
import '../../core/drive_repository.dart';

/// Read-only directory navigation shared by upload and move/copy workflows.
class DriveDirectoryPicker extends StatefulWidget {
  const DriveDirectoryPicker({
    super.key,
    required this.repository,
    this.initial = '',
    this.exclude,
  });
  final DriveRepository repository;
  final String initial;
  final String? exclude;
  @override
  State<DriveDirectoryPicker> createState() => _DriveDirectoryPickerState();
}

class _DriveDirectoryPickerState extends State<DriveDirectoryPicker> {
  late String path;
  List<DriveNode> folders = [];
  Object? error;
  bool loading = true, leaving = false;
  int generation = 0;
  bool excluded(String value) =>
      widget.exclude != null &&
      (value == drivePath(widget.exclude!) ||
          value.startsWith('${drivePath(widget.exclude!)}/'));
  @override
  void initState() {
    super.initState();
    path = drivePath(widget.initial);
    if (excluded(path)) path = driveParent(drivePath(widget.exclude!));
    load(path);
  }

  Future<void> load(String value) async {
    if (excluded(value)) return;
    final epoch = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.repository.list(value);
      if (!mounted || epoch != generation) return;
      setState(() {
        path = value;
        folders = rows.where((n) => n.directory && !excluded(n.path)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      });
    } catch (e) {
      if (mounted && epoch == generation) setState(() => error = e);
    } finally {
      if (mounted && epoch == generation) setState(() => loading = false);
    }
  }

  void back() {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          leading: IconButton(
            tooltip: '返回',
            onPressed: back,
            icon: const Icon(Icons.arrow_back),
          ),
          title: const Text('选择目录'),
        ),
        body: Column(
          children: [
            if (loading) const LinearProgressIndicator(),
            Expanded(
              child: CustomScrollView(
                key: PageStorageKey(path),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                ActionChip(
                                  label: const Text('全部文件'),
                                  onPressed: loading ? null : () => load(''),
                                ),
                                for (var i = 0; i < parts.length; i++) ...[
                                  const Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text('/'),
                                  ),
                                  ActionChip(
                                    label: Text(parts[i]),
                                    onPressed: loading
                                        ? null
                                        : () =>
                                              load(parts.take(i + 1).join('/')),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              '选择保存位置，只显示文件夹',
                              style: TextStyle(color: Color(0xff64748b)),
                            ),
                          ),
                          Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: const Icon(
                                Icons.folder_outlined,
                                size: 32,
                              ),
                              title: const Text(
                                '当前目录',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Text(
                                path.isEmpty ? '全部文件' : '全部文件 / $path',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: loading || path.isEmpty
                                  ? null
                                  : () => load(driveParent(path)),
                              icon: const Icon(Icons.arrow_upward),
                              label: const Text('返回上一级'),
                            ),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text('$error'),
                                  TextButton(
                                    onPressed: () => load(path),
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                          if (!loading && error == null && folders.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('此目录没有可选的子文件夹'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: folders.length,
                      itemBuilder: (context, index) {
                        final folder = folders[index];
                        return Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            leading: const Icon(
                              Icons.folder,
                              color: Colors.amber,
                              size: 36,
                            ),
                            title: Text(
                              folder.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: const Text('文件夹'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: loading ? null : () => load(folder.path),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.exclude != null)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          '移动或复制时不能选择源文件夹及其子目录',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xff64748b),
                          ),
                        ),
                      ),
                    FilledButton(
                      onPressed: loading || error != null || excluded(path)
                          ? null
                          : () {
                              setState(() => leaving = true);
                              Navigator.pop(context, path);
                            },
                      child: const Text('选择此目录'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
