import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/bookmarks_repository.dart';
import '../../core/bookmark_draft_vault.dart';
import '../../core/labels_repository.dart';
import '../../widgets/label_picker.dart';

class BookmarkEditorPage extends StatefulWidget {
  const BookmarkEditorPage({
    super.key,
    required this.repository,
    required this.bookmark,
    required this.labelsRepository,
    this.vault,
    this.english = false,
    this.local = false,
    this.onSaveAcknowledged,
  });
  final BookmarksRepository repository;
  final void Function(BookmarkItem saved, bool metadataComplete, bool created)?
  onSaveAcknowledged;
  final BookmarkItem bookmark;
  final LabelsRepository labelsRepository;
  final BookmarkDraftVault? vault;
  final bool english, local;
  @override
  State<BookmarkEditorPage> createState() => _BookmarkEditorPageState();
}

class _BookmarkEditorPageState extends State<BookmarkEditorPage> {
  late final TextEditingController _url, _title, _description;
  late BookmarkItem _saved;
  late List<String> _labels;
  late bool _public;
  String _favicon = '';
  bool _ready = false,
      _busy = false,
      _fetching = false,
      _allowLeave = false,
      _wrote = false;
  String? _error;
  final _draftIds = <int?>{};
  String t(String zh, String en) => widget.english ? en : zh;
  BookmarkItem get _snapshot => _saved.copyWith(
    url: _url.text,
    title: _title.text,
    description: _description.text,
    labels: List.of(_labels),
    isPublic: _public,
    favicon: _favicon,
  );
  bool _same(BookmarkItem a, BookmarkItem b) =>
      a.title == b.title &&
      a.url == b.url &&
      a.description == b.description &&
      a.isPublic == b.isPublic &&
      a.favicon == b.favicon &&
      a.labels.length == b.labels.length &&
      a.labels.toSet().containsAll(b.labels);
  bool get _dirty => !_same(_snapshot, _saved);
  @override
  void initState() {
    super.initState();
    _saved = widget.bookmark;
    _draftIds.add(_saved.id);
    _labels = List.of(_saved.labels);
    _public = _saved.isPublic;
    _favicon = _saved.favicon;
    _url = TextEditingController(text: _saved.url)..addListener(_changed);
    _title = TextEditingController(text: _saved.title)..addListener(_changed);
    _description = TextEditingController(text: _saved.description)
      ..addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _restore());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _apply(BookmarkItem value) {
    _url.text = value.url;
    _title.text = value.title;
    _description.text = value.description;
    _labels = List.of(value.labels);
    _public = value.isPublic;
    _favicon = value.favicon;
  }

  Future<void> _restore() async {
    try {
      final value = await widget.vault?.read(_saved);
      if (!mounted) return;
      if (value != null && !_same(value, _saved)) {
        final restore = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: Text(t('发现书签草稿', 'Bookmark draft found')),
            content: Text(t('恢复未保存的修改？', 'Restore unsaved changes?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('放弃草稿', 'Discard draft')),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(t('恢复', 'Restore')),
              ),
            ],
          ),
        );
        if (!mounted) return;
        if (restore == true) {
          _apply(value);
        } else {
          await widget.vault?.remove(_saved.id);
        }
      }
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _metadata() async {
    final requested = _snapshot;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final result = await widget.repository.metadata(requested.url);
      if (!mounted) return;
      if (_url.text != requested.url) {
        throw StateError(t('网址已变化，请重新获取', 'URL changed; fetch again'));
      }
      if (result.error != null && result.error!.isNotEmpty) {
        throw StateError(result.error!);
      }
      // Respect any typing while the network request was in flight.
      if (_title.text == requested.title && result.title.isNotEmpty) {
        _title.text = result.title;
      }
      if (_description.text == requested.description &&
          result.description.isNotEmpty) {
        _description.text = result.description;
      }
      if (result.favicon.isNotEmpty) _favicon = result.favicon;
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _save() async {
    final submitted = _snapshot;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await widget.repository.save(
        submitted,
        original: _saved.id == null ? null : _saved,
      );
      _wrote = true;
      _draftIds.add(id);
      _saved = submitted.copyWith(id: id);
      widget.onSaveAcknowledged?.call(_saved, true, submitted.id == null);
      for (final key in _draftIds) {
        await widget.vault?.remove(key);
      }
      if (!mounted) return;
      _allowLeave = true;
      Navigator.pop(context, true);
    } on BookmarkAlreadyExists catch (error) {
      if (!mounted) return;
      final edit = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          scrollable: true,
          title: Text(t('网址已存在', 'URL already exists')),
          content: Text(
            '${error.bookmark.title}\n${error.bookmark.url}\n\n${t('打开已有书签继续编辑？当前输入会保留为草稿。', 'Open the existing bookmark? Current input will be kept as a draft.')}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('编辑已有书签', 'Edit existing')),
            ),
          ],
        ),
      );
      if (edit == true) {
        try {
          if (widget.vault == null) {
            throw StateError(
              t(
                '草稿存储不可用，请先复制输入内容',
                'Draft storage unavailable; copy your input first',
              ),
            );
          }
          await widget.vault!.write(submitted);
          if (!mounted) return;
          setState(() {
            _saved = error.bookmark;
            _draftIds.clear();
            _draftIds.add(_saved.id);
            _apply(_saved);
            _ready = false;
          });
          await _restore();
        } catch (failure) {
          if (mounted) setState(() => _error = failure.toString());
        }
      }
    } on BookmarkSaveFailure catch (error) {
      _wrote = true;
      _draftIds.add(error.savedId);
      _saved = _saved.copyWith(
        id: error.savedId,
        memberId: widget.repository.memberId,
      );
      widget.onSaveAcknowledged?.call(
        submitted.copyWith(id: error.savedId),
        false,
        submitted.id == null,
      );
      if (mounted) setState(() => _error = error.toString());
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    if (_busy || !_ready) return;
    if (!_dirty) {
      _allowLeave = true;
      if (mounted) Navigator.pop(context, _wrote);
      return;
    }
    final keep = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(t('保留修改？', 'Keep changes?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('放弃修改', 'Discard changes')),
          ),
          if (widget.vault != null)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('保留草稿', 'Keep draft')),
            ),
        ],
      ),
    );
    if (keep == null) return;
    try {
      if (keep) {
        await widget.vault!.write(_snapshot);
      } else {
        for (final id in _draftIds) {
          await widget.vault?.remove(id);
        }
      }
      if (!mounted) return;
      _allowLeave = true;
      Navigator.pop(context, _wrote);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope<bool>(
    canPop: _allowLeave,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        leading: IconButton(
          tooltip: t('返回', 'Back'),
          onPressed: _busy ? null : _leave,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          _saved.id == null
              ? t('新建书签', 'New bookmark')
              : t('编辑书签', 'Edit bookmark'),
        ),
        actions: [
          TextButton(
            onPressed: _ready && !_busy && !_fetching ? _save : null,
            child: Text(_busy ? t('保存中', 'Saving') : t('保存', 'Save')),
          ),
        ],
      ),
      body: SafeArea(
        child: !_ready && _error == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (!_ready)
                      TextButton(
                        onPressed: () async {
                          await widget.vault?.remove(_saved.id);
                          if (mounted) {
                            setState(() {
                              _ready = true;
                              _error = null;
                            });
                          }
                        },
                        child: Text(t('清除损坏草稿', 'Clear damaged draft')),
                      ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _url,
                    enabled: _ready && !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: t('网址', 'URL'),
                      counterText: '${utf8.encode(_url.text).length}/2048',
                    ),
                  ),
                  if (!widget.local)
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton(
                        onPressed: _ready && !_busy && !_fetching
                            ? _metadata
                            : null,
                        child: Text(
                          _fetching
                              ? t('获取中', 'Fetching')
                              : t('获取网页信息', 'Fetch page details'),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _title,
                    enabled: _ready && !_busy,
                    decoration: InputDecoration(
                      labelText: t('标题', 'Title'),
                      counterText: '${utf8.encode(_title.text).length}/500',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _description,
                    enabled: _ready && !_busy,
                    minLines: 4,
                    maxLines: 8,
                    decoration: InputDecoration(
                      labelText: t('说明', 'Description'),
                      counterText:
                          '${utf8.encode(_description.text).length}/2000',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(t('标签', 'Labels')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final label in _labels)
                        InputChip(
                          label: Text(
                            label.isEmpty
                                ? t('空名称标签', 'Empty-name label')
                                : label,
                          ),
                          onDeleted: _busy || !_ready
                              ? null
                              : () => setState(() => _labels.remove(label)),
                        ),
                      OutlinedButton(
                        onPressed: _busy || !_ready
                            ? null
                            : () async {
                                final names = await showLabelPicker(
                                  context,
                                  repository: widget.labelsRepository,
                                  selected: _labels,
                                  english: widget.english,
                                );
                                if (names != null && mounted) {
                                  setState(() => _labels = names);
                                }
                              },
                        child: Text(t('+ 添加标签', '+ Add labels')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: SwitchListTile(
                      title: Text(t('设为公开', 'Make public')),
                      subtitle: Text(
                        widget.local
                            ? t(
                                '此设置仅保存在本机，不会发布到网络。',
                                'Stored on this device; does not publish online.',
                              )
                            : t(
                                '私密书签不在公开列表中显示。',
                                'Private bookmarks are hidden from the public feed.',
                              ),
                      ),
                      value: _public,
                      onChanged: _busy || !_ready
                          ? null
                          : (value) => setState(() => _public = value),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    t(
                      '保存后可在菜单中设置导航显示。',
                      'After saving, use the menu to show it in navigation.',
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
