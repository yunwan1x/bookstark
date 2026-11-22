import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/api_client.dart';
import '../../core/attachments.dart';
import '../../core/drive_models.dart';
import '../../core/drive_repository.dart';
import '../images/image_format.dart';

class FilePublicOutcome {
  const FilePublicOutcome({
    this.changed = false,
    this.needsVerification = false,
  });
  final bool changed, needsVerification;
}

class FilePublicPage extends StatefulWidget {
  const FilePublicPage({
    super.key,
    required this.repository,
    required this.file,
    this.english = false,
  });
  final DriveRepository repository;
  final DriveNode file;
  final bool english;
  @override
  State<FilePublicPage> createState() => _FilePublicPageState();
}

class _FilePublicPageState extends State<FilePublicPage> {
  final _path = TextEditingController();
  DriveNode? _file;
  DriveProfile? _profile;
  AttachmentCancellation? _cancel;
  bool _busy = false,
      _writing = false,
      _edited = false,
      _changed = false,
      _allowLeave = false,
      _askingLeave = false,
      _verified = false;
  String? _error, _notice, _pending;
  String _pendingPath = '';
  Uri? get _url => _file?.isPublic == true && _profile != null
      ? _profile!.publicUri(_file!.publicPath)
      : null;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _path.dispose();
    super.dispose();
  }

  Future<bool> _read() async {
    final file = await widget.repository.lookup(
      widget.file.path,
      cancellation: _cancel,
    );
    if (file == null || file.id != widget.file.id || file.directory) {
      throw DriveConflict(widget.file, file);
    }
    final profile = await widget.repository.profile(cancellation: _cancel);
    if (!mounted) return false;
    if (file.isPublic) profile.publicUri(file.publicPath);
    setState(() {
      _file = file;
      _profile = profile;
      if (!_edited) {
        _path.text = file.isPublic ? file.publicPath : file.name;
      }
      if (_pending != null) {
        _verified = true;
        final matched = _pending == 'publish'
            ? file.isPublic && file.publicPath == _pendingPath
            : !file.isPublic;
        if (matched) {
          _pending = null;
          _notice = t('已核对当前公开状态。', 'Current public state verified.');
          _changed = true;
        } else {
          _notice = t(
            '当前状态尚未匹配上次操作。原请求可能仍在处理，请先等待或核对。',
            'Current state does not match the last operation. The earlier request may still be processing; wait or verify first.',
          );
        }
      }
    });
    return true;
  }

  Future<void> _refresh() async {
    if (_busy) return;
    _cancel = AttachmentCancellation();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.repository.local) {
        throw StateError(
          t('本地空间没有公开文件服务。', 'Local space has no public file service.'),
        );
      }
      await _read();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('确认', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _publish() async {
    final file = _file;
    if (file == null || _busy || _pending != null) return;
    String path;
    try {
      path = drivePublicPath(_path.text);
    } catch (error) {
      setState(() => _error = error.toString());
      return;
    }
    if (file.isPublic && path != file.publicPath) {
      if (!await _confirm(
            t('更换公开地址？', 'Change public address?'),
            t(
              '旧地址的引用可能失效，已有缓存可能保留。',
              'References to the old address may break; existing caches may remain.',
            ),
          ) ||
          !mounted) {
        return;
      }
    }
    await _commit('publish', path);
  }

  Future<void> _unpublish() async {
    if (_file?.isPublic != true || _busy || _pending != null) return;
    if (!await _confirm(
          t('取消公开？', 'Unpublish file?'),
          t(
            '取消后新请求将无法通过公开地址访问，已有缓存可能保留。',
            'New requests will no longer access the public address. Existing caches may remain.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _commit('unpublish', '');
  }

  Future<void> _commit(String kind, String path) async {
    final file = _file;
    if (file == null || _busy) return;
    _cancel = AttachmentCancellation();
    setState(() {
      _busy = true;
      _writing = true;
      _error = null;
      _notice = null;
      _pending = kind;
      _pendingPath = path;
      _verified = false;
    });
    var acknowledged = false;
    try {
      if (kind == 'publish') {
        await widget.repository.publish(file, path, cancellation: _cancel);
      } else {
        await widget.repository.unpublish(file, cancellation: _cancel);
      }
      if (!mounted) return;
      acknowledged = true;
      _writing = false;
      _changed = true;
      await _read();
      if (mounted && _pending == null) {
        setState(
          () => _notice = kind == 'publish'
              ? t('公开设置已保存并核对。', 'Public settings saved and verified.')
              : t(
                  '已取消公开，已有缓存可能保留。',
                  'File unpublished. Existing caches may remain.',
                ),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          if (!acknowledged &&
              (error is DriveConflict ||
                  error is ApiFailure &&
                      {400, 401, 403, 405, 409, 413}.contains(error.status))) {
            _pending = null;
            _verified = false;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _writing = false;
        });
      }
    }
  }

  Future<void> _replay() async {
    final pending = _pending, path = _pendingPath;
    if (pending == null || !_verified || _busy) return;
    if (!await _confirm(
          t('仍要再次提交？', 'Submit again explicitly?'),
          t(
            '先前请求可能仍会完成。再次提交可能覆盖该文件当前公开设置。',
            'The earlier request may still complete. Resubmitting may replace the file’s current public settings.',
          ),
        ) ||
        !mounted) {
      return;
    }
    await _commit(pending, path);
  }

  Future<void> _copy() async {
    final url = _url;
    if (url == null) return;
    try {
      await Clipboard.setData(ClipboardData(text: url.toString()));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t('已复制真实公开地址', 'Saved public address copied')),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _leave() async {
    if (_askingLeave) return;
    if (_writing) {
      _askingLeave = true;
      final yes = await _confirm(
        t('离开公开设置？', 'Leave public settings?'),
        t(
          '请求可能已提交。离开不会撤回公开操作，返回后请先核对文件状态。',
          'The request may already be submitted. Leaving does not retract it; verify the file state after returning.',
        ),
      );
      _askingLeave = false;
      if (!yes || !mounted) return;
    }
    final outcome = FilePublicOutcome(
      changed: _changed,
      needsVerification: _pending != null || _writing,
    );
    _cancel?.cancel();
    setState(() => _allowLeave = true);
    Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    final file = _file ?? widget.file, url = _url;
    return PopScope(
      canPop: _allowLeave,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: t('返回', 'Back'),
            onPressed: _leave,
            icon: const Icon(Icons.arrow_back),
          ),
          title: Text(t('公开设置', 'Public settings')),
          actions: [
            IconButton(
              tooltip: t('刷新状态', 'Refresh state'),
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_busy) const LinearProgressIndicator(),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.insert_drive_file_outlined,
                        size: 40,
                        color: Color(0xff2563eb),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              file.name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${imageSizeLabel(file.size)} · ${driveParent(file.path)}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              file.isPublic
                                  ? t('已公开', 'Public')
                                  : t('私人文件', 'Private file'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                color: const Color(0xfffffbeb),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        color: Color(0xffa16207),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          t(
                            '公开后，任何知道链接的人都可访问。已有缓存可能保留。',
                            'After publishing, anyone who knows the link can access this file. Existing caches may remain.',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        t('公开路径', 'Public path'),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _path,
                        enabled: !_busy && _file != null && _pending == null,
                        onChanged: (_) => _edited = true,
                        decoration: InputDecoration(
                          labelText: t('相对公开路径', 'Relative public path'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        t(
                          '相对公开目录，不影响网盘文件位置。',
                          'Relative to the public directory; does not move the original file.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (url == null)
                Text(
                  t(
                    '完整链接将在保存后由服务器返回。',
                    'The full link is returned by the server after saving.',
                  ),
                )
              else
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          t('当前已保存的公开地址', 'Current saved public address'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        SelectableText(url.toString()),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _copy,
                          icon: const Icon(Icons.copy),
                          label: Text(t('复制公开地址', 'Copy public address')),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_notice!),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              if (_pending != null) ...[
                OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: Text(t('先核对上次操作', 'Verify last operation first')),
                ),
                if (_verified)
                  OutlinedButton(
                    onPressed: _busy ? null : _replay,
                    child: Text(t('仍要再次明确提交', 'Submit again explicitly')),
                  ),
              ] else ...[
                FilledButton(
                  onPressed: _busy || _file == null || widget.repository.local
                      ? null
                      : _publish,
                  child: Text(
                    file.isPublic
                        ? t('保存公开设置', 'Save public settings')
                        : t('确认公开', 'Confirm publish'),
                  ),
                ),
                if (file.isPublic) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _unpublish,
                    icon: const Icon(Icons.link_off),
                    label: Text(t('取消公开', 'Unpublish')),
                  ),
                ],
              ],
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _leave, child: Text(t('取消', 'Cancel'))),
              const SizedBox(height: 24),
              Text(
                t(
                  '公开地址会反映后续文件修改；删除或取消公开可能使引用失效。',
                  'The public address reflects future file edits. Deletion or unpublishing may break references.',
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
