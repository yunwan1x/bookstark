import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import '../../core/file_export.dart';
import 'admin_files_transfer.dart';
import 'admin_files_dialogs.dart';
import 'admin_files_lease.dart';
import 'admin_asset_secure_window.dart';
import 'admin_assets_scope.dart';
import 'admin_files_browser.dart';
import 'admin_remote_dav_files_controller.dart';
import 'admin_files_models.dart';
import 'admin_remote_dav_files_repository.dart';
import 'admin_remote_dav_repository.dart';
import 'admin_remote_dav_models.dart';

class AdminDavFilesPage extends StatefulWidget {
  const AdminDavFilesPage({
    super.key,
    required this.scope,
    required this.binding,
    required this.onReturn,
    this.english = false,
    this.secureWindow,
  });
  final AdminAssetsScope scope;
  final AdminDavBinding binding;
  final VoidCallback onReturn;
  final bool english;
  final AdminAssetWindowGuard? secureWindow;
  @override
  State<AdminDavFilesPage> createState() => _AdminDavFilesPageState();
}

class _AdminDavFilesPageState extends State<AdminDavFilesPage>
    with WidgetsBindingObserver {
  late final AdminDavFilesController c;
  late final AdminAssetWindowGuard secure;
  final browser = GlobalKey<AdminFileEditorBrowserState>();
  final _leases = <AdminFileEditorLease>[];
  AdminFileEditorLease? _activeLease;
  int? _leaseGeneration;
  Future<void>? _windowClosing;
  bool _leaving = false;
  AdminFileEditorLease _presentationLease() {
    if (_activeLease == null || _leaseGeneration != c.generation) {
      _leases.removeWhere((lease) => lease.retired);
      _activeLease = AdminFileEditorLease();
      _leaseGeneration = c.generation;
      _leases.add(_activeLease!);
    }
    return _activeLease!;
  }

  Future<void> _retirePresentations() async {
    await Future.wait(_leases.map((lease) => lease.retire()));
  }

  Future<void> _retireAndCloseWindow() =>
      _windowClosing ??= _closeWindowAfterViews();
  Future<void> _closeWindowAfterViews() async {
    await Future.wait([_dismissOwnedDialog(), _retirePresentations()]);
    // The opaque/expired destination must paint before FLAG_SECURE is released.
    await WidgetsBinding.instance.endOfFrame;
    await secure.close();
  }

  final query = TextEditingController();
  bool secureReady = false, secureFailed = false, dialog = false;
  String t(String zh, String en) => widget.english ? en : zh;
  ThemeData get _theme {
    final base = Theme.of(context);
    const blue = Color(0xff0b57ee), navy = Color(0xff0c192e);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: blue,
        onPrimary: Colors.white,
        onSurface: navy,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: Colors.white,
        foregroundColor: navy,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: (base.filledButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(shape),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: (base.outlinedButtonTheme.style ?? const ButtonStyle()).copyWith(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(shape),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? navy.withValues(alpha: .38)
                : blue,
          ),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? blue.withValues(alpha: .2)
                  : blue,
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    c = widget.scope.own(
      AdminDavFilesController(
        AdminDavFilesRepository(widget.scope, widget.binding),
      ),
    );
    c.addListener(_changed);
    widget.scope.addListener(_changed);
    secure = widget.secureWindow ?? AdminAssetSecureWindow();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await secure.acquire();
      if (!mounted || !widget.scope.guard() || c.suspended) return;
      setState(() => secureReady = true);
      await c.load();
    } catch (_) {
      if (mounted) setState(() => secureFailed = true);
    }
  }

  void _changed() {
    if (!mounted) return;
    if (!widget.scope.active) {
      unawaited(_retireAndCloseWindow().catchError((Object _) {}));
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _pendingPaste = null;
      unawaited(_retirePresentations().catchError((Object _) {}));
      c.suspend();
      unawaited(_dismissOwnedDialog().catchError((Object _) {}));
    }
  }

  DialogRoute<dynamic>? _ownedDialog;
  Future<T?> _showOwnedDialog<T>(WidgetBuilder builder) async {
    final theme = _theme;
    final route = DialogRoute<T>(
      context: context,
      builder: (context) => Theme(data: theme, child: builder(context)),
    );
    _ownedDialog = route;
    dialog = true;
    try {
      final value = await Navigator.of(context).push(route);
      await route.completed;
      return value;
    } finally {
      if (identical(_ownedDialog, route)) {
        _ownedDialog = null;
        dialog = false;
      }
    }
  }

  Future<void> _dismissOwnedDialog() async {
    final route = _ownedDialog;
    if (route == null) return;
    dialog = false;
    if (route.isActive) route.navigator?.removeRoute(route);
    await route.completed;
  }

  Future<bool> _confirm(String title, String text, {String? action}) async {
    if (!mounted || dialog || !widget.scope.guard()) return false;
    final value = await _showOwnedDialog<bool>(
      (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(text)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action ?? t('确认操作', 'Confirm')),
          ),
        ],
      ),
    );
    return value == true && mounted && widget.scope.guard() && !c.suspended;
  }

  Future<String?> _ask(String title, String initial) async {
    if (dialog || !c.canAct) return null;
    final result = await _showOwnedDialog<String>(
      (context) => AdminFilePathDialog(
        title: title,
        initial: initial,
        english: widget.english,
      ),
    );
    return mounted && widget.scope.guard() && !c.suspended ? result : null;
  }

  Future<void> _leave() async {
    if (c.busy) return;
    if (c.original != null) {
      if (c.dirty &&
          !await _confirm(
            t('放弃未保存的修改？', 'Discard unsaved edits?'),
            t(
              '修改只保留在当前编辑器，离开后不会自动保存。',
              'Edits exist only in this editor and will not be saved automatically.',
            ),
            action: t('放弃修改', 'Discard'),
          )) {
        return;
      }
      await _retirePresentations();
      c.closeEditor();
      return;
    }
    if (c.repository.unknown != null &&
        !await _confirm(
          t('离开结果核对？', 'Leave result review?'),
          t(
            '上次远程操作结果仍不确定。离开不会撤销或重发，请稍后重新读取目标核对。',
            'The previous result remains unknown. Leaving neither undoes nor resends it; inspect the target later.',
          ),
          action: t('离开', 'Leave'),
        )) {
      return;
    }
    if (_leaving) return;
    setState(() => _leaving = true);
    // Stop reads and clear every plaintext reference before releasing protection.
    widget.scope.release(c);
    try {
      await _retireAndCloseWindow();
      if (mounted) widget.onReturn();
    } catch (_) {
      // Protection remains held when native retirement cannot be confirmed.
      if (mounted) setState(() => secureFailed = true);
    }
  }

  Future<void> _submit(AdminDavFilePlan plan, {String? original}) async {
    final info = <String>[
      'WebDAV #${widget.binding.server.id} · ${widget.binding.server.name}',
      plan.path,
      if (plan.target != null) '${t('目标', 'Target')}: ${plan.target}',
      if (plan.action == AdminDavFileAction.delete)
        plan.recursive
            ? t(
                '递归删除目录及其内容，无法撤销。',
                'Recursively delete this directory and its contents. This cannot be undone.',
              )
            : t(
                '将向远程服务器删除此文件，应用不提供撤销或回收站。',
                'Delete this file on the remote server. This app provides no undo or trash.',
              ),
    ].join('\n');
    if (!await _confirm(_actionTitle(plan.action), info)) return;
    await c.submit(plan, baselineContent: original);
  }

  String _actionTitle(AdminDavFileAction action) => switch (action) {
    AdminDavFileAction.save => t('保存文件', 'Save file'),
    AdminDavFileAction.mkdir => t('新建目录', 'New directory'),
    AdminDavFileAction.rename => t('重命名', 'Rename'),
    AdminDavFileAction.copy => t('复制', 'Copy'),
    AdminDavFileAction.delete => t('删除', 'Delete'),
    AdminDavFileAction.upload => t('上传文件', 'Upload file'),
  };
  Future<void> _upload() async {
    if (!c.canAct) return;
    final directory = c.path;
    final selected = await openFile();
    if (!mounted || selected == null || !widget.scope.guard() || c.busy) return;
    c.resumeForReview();
    try {
      final name = adminFileName(selected.name);
      final length = await selected.length();
      if (length > adminFileTransferLimit) {
        throw const FormatException('Upload limit');
      }
      if (!mounted || !c.canAct || c.path != directory) return;
      if (!await _confirm(
        t('上传文件', 'Upload file'),
        'WebDAV #${widget.binding.server.id}\n${adminDavJoin(directory, name)}\n$length B\n'
        '${t('已发送进度不等于远端保存确认。', 'Sent progress does not confirm remote persistence.')}',
      )) {
        return;
      }
      await c.upload(name, length, selected.openRead());
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '文件名或大小不受支持（上限64 MiB），未上传。',
                'Unsupported filename or size (64 MiB maximum); no upload.',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '无法读取所选文件，请重新选择。',
                'Could not read the selected file. Choose again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _download(AdminDavEntry entry) async {
    if (!c.canAct) return;
    if (!await _confirm(
      t('下载文件', 'Download file'),
      'WebDAV #${widget.binding.server.id}\n${entry.path}\n${entry.size} B',
    )) {
      return;
    }
    final file = await c.download(entry);
    if (file == null) return;
    try {
      if (!mounted || !widget.scope.guard() || c.suspended) return;
      final outcome = await const SystemFileExporter().saveFile(
        file: file.file,
        name: file.name,
        mime: 'application/octet-stream',
        size: file.size,
        hash: file.hash,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              outcome == FileExportOutcome.cancelled
                  ? t('已取消导出。', 'Export cancelled.')
                  : t('文件已导出。', 'File exported.'),
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '导出未完成，请检查所选保存位置。',
                'Export did not complete. Check the selected destination.',
              ),
            ),
          ),
        );
      }
    } finally {
      await file.close();
    }
  }

  String? _pendingPaste;
  Future<void> _pasteText() async {
    if (!c.canEdit || dialog || browser.currentState?.ready != true) return;
    final generation = c.generation;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || !c.canEdit || c.generation != generation) return;
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    try {
      AdminFileText('/owned-paste', text);
    } on FormatException {
      return;
    }
    _pendingPaste = text;
    try {
      if (!await _confirm(
        t('确认插入文本', 'Confirm text insertion'),
        t(
          '将剪贴板文本插入当前光标位置，不额外增加换行。插入换行沿用文件格式。',
          'Insert clipboard text at the cursor without an added newline. Inserted line breaks follow this file format.',
        ),
        action: t('插入一次', 'Insert once'),
      )) {
        return;
      }
      final value = _pendingPaste;
      if (value == null || !c.canEdit || c.generation != generation) return;
      await browser.currentState?.insert(value);
    } finally {
      _pendingPaste = null;
    }
  }

  Future<void> _save() async {
    final entry = c.editing, original = c.original;
    if (entry == null || original == null || !c.canEdit) return;
    try {
      final text = await browser.currentState?.snapshot();
      if (!mounted || text == null || !c.canEdit) return;
      if (text == original.content) {
        c.changed(false);
        return;
      }
      await _submit(
        AdminDavFilePlan(
          action: AdminDavFileAction.save,
          path: entry.path,
          baseline: entry,
          content: text,
        ),
        original: original.content,
      );
    } catch (_) {
      if (mounted) c.editorFailed();
    }
  }

  Future<void> _create() async {
    final path = await _ask(
      t('新建目录', 'New directory'),
      adminDavJoin(c.path, t('新目录', 'new-folder')),
    );
    if (path == null) return;
    try {
      await _submit(
        AdminDavFilePlan(action: AdminDavFileAction.mkdir, path: path),
      );
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('路径无效，未发送请求。', 'Invalid path; no request sent.')),
          ),
        );
      }
    }
  }

  Future<void> _entryAction(AdminDavEntry entry, String action) async {
    if (!c.canAct) return;
    try {
      if (action == 'download') {
        await _download(entry);
        return;
      }
      if (action == 'open') {
        if (entry.type == AdminDavEntryType.directory) {
          await c.load(entry.path);
        } else {
          await c.open(entry);
        }
        return;
      }
      if (action == 'rename' || action == 'copy') {
        final target = await _ask(
          t('目标完整路径', 'Full destination path'),
          entry.path,
        );
        if (target == null) return;
        await _submit(
          AdminDavFilePlan(
            action: action == 'rename'
                ? AdminDavFileAction.rename
                : AdminDavFileAction.copy,
            path: entry.path,
            target: target,
            baseline: entry,
          ),
        );
      } else if (action == 'delete' || action == 'recursive') {
        await _submit(
          AdminDavFilePlan(
            action: AdminDavFileAction.delete,
            path: entry.path,
            baseline: entry,
            recursive: action == 'recursive',
          ),
        );
      }
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '此路径或操作不受支持，未发送请求。',
                'This path or operation is unsupported; no request sent.',
              ),
            ),
          ),
        );
      }
    }
  }

  String get _failure => switch (c.failure) {
    AdminDavFilesFailure.targetChanged => t(
      '目标资料或内容已变化，未写入。请重新读取核对。',
      'Target metadata or content changed. No write sent; read again.',
    ),
    AdminDavFilesFailure.unknown => t(
      '结果未确认。请只读核对，不要重复提交。',
      'Result unknown. Inspect without resending.',
    ),
    AdminDavFilesFailure.ownerLost => t(
      '管理员会话已失效，请返回重新登录。',
      'Administrator session expired. Return to sign in.',
    ),
    AdminDavFilesFailure.editor => t(
      '编辑器已关闭，请重新读取文件。',
      'Editor closed. Read the file again.',
    ),
    AdminDavFilesFailure.background => t(
      '切到后台后已关闭编辑器并清除内容。请明确重新读取。',
      'The editor and its content were cleared in background. Read again explicitly.',
    ),
    AdminDavFilesFailure.refused => t(
      '服务器拒绝了请求，请核对权限和目标。',
      'Server refused the request. Check access and target.',
    ),
    _ => t('读取失败，请重试。', 'Read failed. Retry.'),
  };
  Widget _notice(String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xffeaf2ff),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(text),
  );
  Widget _unknown() {
    final pending = c.repository.unknown!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _notice(t('上次操作结果未确认', 'Previous operation result unknown')),
        Text(
          '${_actionTitle(pending.action)} · WebDAV #${widget.binding.server.id}\n${pending.path}${pending.target == null ? '' : '\n${t('目标', 'Target')}: ${pending.target}'}',
        ),
        const SizedBox(height: 16),
        Text(
          t(
            '下面的当前观察不是上次请求成功回执。不会自动重发或清理远端结果。',
            'Current observations are not a receipt for the earlier request. Nothing is automatically resent or deleted.',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: c.busy
              ? null
              : () {
                  c.resumeForReview();
                  unawaited(c.observe());
                },
          child: Text(t('只读核对目标', 'Inspect targets only')),
        ),
        if (c.observedText != null) ...[
          const SizedBox(height: 16),
          Text(t('当前远端正文（只读）', 'Current remote content (read only)')),
          SizedBox(
            height: 280,
            child: AdminFileEditorBrowser(
              key: ValueKey('file-observation-${c.generation}'),
              content: c.observedText!.content,
              lease: _presentationLease(),
              generation: c.generation,
              enabled: false,
              english: widget.english,
              onChanged: (_) {},
              onFailed: () {},
            ),
          ),
        ],
        if (c.observationAbsenceProven)
          _notice(
            t(
              '完整目录读取显示当前目标不存在；这不是旧请求的回执。',
              'The complete directory shows the target is currently absent. This is not the previous receipt.',
            ),
          ),
        if (c.observationContentUnavailable)
          _notice(
            t(
              '尚未完整读取当前正文，请重试只读核对。',
              'Current content has not been read completely. Retry inspection.',
            ),
          ),
        if (c.observations != null) ...[
          for (final list in c.observations!) ...[
            const SizedBox(height: 16),
            Text(list.path),
            if (list.truncated)
              _notice(
                t(
                  '仅显示前1000项，不能据此判断目标不存在。',
                  'Only the first 1000 entries; absence cannot be established.',
                ),
              ),
            for (final entry in list.items)
              Text('${entry.name} · ${entry.size} B'),
          ],
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: c.busy || c.repository.unknown?.observationRead != true
                ? null
                : () {
                    c.finishReview();
                    unawaited(c.load());
                  },
            child: Text(t('结束本次核对', 'Finish this review')),
          ),
        ],
      ],
    );
  }

  Widget _catalog() {
    final list = c.listing;
    final rows =
        list?.items
            .where(
              (entry) =>
                  entry.name.toLowerCase().contains(query.text.toLowerCase()),
            )
            .toList() ??
        [];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _notice(
          'WebDAV #${widget.binding.server.id} · ${widget.binding.server.name}\n${c.path}',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: c.canAct && c.path != '/' && c.path != '.'
                  ? () => unawaited(c.load(adminDavParent(c.path)))
                  : null,
              icon: const Icon(Icons.arrow_upward),
              label: Text(t('上级目录', 'Parent')),
            ),
            FilledButton.icon(
              onPressed: c.canAct ? _upload : null,
              icon: const Icon(Icons.upload_file),
              label: Text(t('上传文件', 'Upload file')),
            ),
            FilledButton.icon(
              onPressed: c.canAct ? _create : null,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: Text(t('新建目录', 'New folder')),
            ),
            OutlinedButton.icon(
              onPressed: c.busy ? null : () => unawaited(c.load()),
              icon: const Icon(Icons.refresh),
              label: Text(t('重新读取', 'Read again')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: query,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: t('筛选已读取的条目', 'Filter loaded entries'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        if (list == null && !c.busy)
          Text(t('尚未读取目录。', 'Directory not loaded.')),
        if (list?.truncated == true)
          _notice(
            t(
              '仅载入前1000项，不是完整目录。筛选仅作用于已载入条目。',
              'Only the first 1000 entries are loaded. Filtering covers those entries only.',
            ),
          ),
        if (list != null && list.items.isEmpty)
          Text(t('目录为空', 'Directory is empty')),
        if (list != null && list.items.isNotEmpty && rows.isEmpty)
          Text(t('已读取条目中无匹配项', 'No match among loaded entries')),
        for (final entry in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xffeaf2ff),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                leading: Icon(
                  entry.type == AdminDavEntryType.directory
                      ? Icons.folder_outlined
                      : Icons.description_outlined,
                ),
                title: Text(entry.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entry.size} B\n${entry.modified.raw}'),
                    if (!entry.addressable)
                      Text(
                        t(
                          '服务器会改写此路径，已禁止操作。',
                          'The server would alter this path; operations are disabled.',
                        ),
                        style: const TextStyle(color: Color(0xffb3261e)),
                      ),
                  ],
                ),
                onTap:
                    c.canAct &&
                        entry.addressable &&
                        {
                          AdminDavEntryType.file,
                          AdminDavEntryType.directory,
                        }.contains(entry.type)
                    ? () => unawaited(_entryAction(entry, 'open'))
                    : null,
                trailing: PopupMenuButton<String>(
                  enabled: c.canAct && entry.addressable,
                  tooltip: t('文件操作', 'File actions'),
                  onSelected: (value) => unawaited(_entryAction(entry, value)),
                  itemBuilder: (context) => [
                    if ({
                      AdminDavEntryType.file,
                      AdminDavEntryType.directory,
                    }.contains(entry.type)) ...[
                      if (entry.type == AdminDavEntryType.file &&
                          entry.size <= adminFileTransferLimit)
                        PopupMenuItem(
                          value: 'download',
                          child: Text(t('下载文件', 'Download file')),
                        ),
                      PopupMenuItem(
                        value: 'rename',
                        child: Text(t('重命名', 'Rename')),
                      ),
                      PopupMenuItem(
                        value: 'copy',
                        child: Text(t('复制', 'Copy')),
                      ),
                      if (entry.type == AdminDavEntryType.file)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(t('删除文件', 'Delete file')),
                        ),
                      if (entry.type == AdminDavEntryType.directory)
                        PopupMenuItem(
                          value: 'recursive',
                          child: Text(
                            t('递归删除目录…', 'Delete directory recursively…'),
                          ),
                        ),
                    ] else
                      PopupMenuItem(
                        enabled: false,
                        child: Text(
                          t('特殊条目仅显示', 'Special entry: display only'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _editor() => LayoutBuilder(
    builder: (context, constraints) => Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: constraints.maxHeight * .45),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'WebDAV #${widget.binding.server.id} · ${c.editing!.path}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  c.dirty
                      ? t('有未保存修改', 'Unsaved edits')
                      : t('与读取内容一致', 'Matches loaded content'),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: c.canEdit && c.dirty ? _save : null,
                      child: Text(t('保存文件', 'Save file')),
                    ),
                    OutlinedButton(
                      onPressed: c.canEdit
                          ? () => unawaited(browser.currentState?.focus())
                          : null,
                      child: Text(t('键盘', 'Keyboard')),
                    ),
                    TextButton.icon(
                      onPressed: c.canEdit ? _pasteText : null,
                      icon: const Icon(Icons.content_paste),
                      label: Text(t('粘贴文本', 'Paste text')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AdminFileEditorBrowser(
            key: browser,
            content: c.original!.content,
            lease: _presentationLease(),
            generation: c.generation,
            english: widget.english,
            enabled: c.canEdit,
            onChanged: c.changed,
            onFailed: c.editorFailed,
            onLimit: () {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      t(
                        '此次编辑超过2 MiB或包含无效文本，已保留原有修改。',
                        'This edit exceeds 2 MiB or contains invalid text. Existing edits are preserved.',
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Theme(
    data: _theme,
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_leave());
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: Text(
            c.original != null
                ? t('文本编辑', 'Text editor')
                : t('WebDAV 文件', 'WebDAV files'),
          ),
          leading: IconButton(
            onPressed: c.busy ? null : _leave,
            tooltip: t('返回', 'Back'),
            icon: const Icon(Icons.arrow_back),
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Column(
              children: [
                if (c.busy) const LinearProgressIndicator(),
                if (c.uploading ||
                    c.downloading ||
                    secureFailed ||
                    secureReady && (c.failure != null || c.receipt != null))
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * .35,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if ((c.uploading || c.downloading) &&
                              c.transferPath != null)
                            Text(c.transferPath!),
                          if (c.uploading || c.downloading)
                            Wrap(
                              spacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${c.uploading ? t('已发送', 'Sent') : t('已接收', 'Received')}: ${c.transferred} / ${c.total} B',
                                ),
                                TextButton(
                                  onPressed: c.repository.cancel,
                                  child: Text(t('停止等待', 'Stop waiting')),
                                ),
                              ],
                            ),
                          if (secureFailed)
                            Text(
                              t(
                                '无法启用窗口保护，请返回。',
                                'Window protection unavailable. Return.',
                              ),
                            ),
                          if (secureReady && c.failure != null)
                            _notice(_failure),
                          if (secureReady && c.receipt != null)
                            _notice(
                              '${_actionTitle(c.receipt!)}：${t('已收到服务器确认。目录刷新状态另行显示。', 'Server confirmed. Directory refresh is a separate result.')}',
                            ),
                        ],
                      ),
                    ),
                  ),
                if (!secureReady && !secureFailed)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (secureReady)
                  Expanded(
                    child: !widget.scope.active
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              t(
                                '管理员会话已失效，请返回重新登录。',
                                'Administrator session expired. Return to sign in.',
                              ),
                            ),
                          )
                        : _leaving
                        ? const SizedBox.shrink()
                        : c.repository.unknown != null
                        ? _unknown()
                        : c.original != null
                        ? _editor()
                        : _catalog(),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.scope.removeListener(_changed);
    c.removeListener(_changed);
    widget.scope.release(c);
    _pendingPaste = null;
    query.dispose();
    unawaited(_retireAndCloseWindow().catchError((Object _) {}));
    super.dispose();
  }
}
