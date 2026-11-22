import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/drive_models.dart';
import '../../core/local_html_note_attachments.dart';

/// Bounded, paged view of the real current-space local drive library.
class LocalHtmlAttachmentLibrarySheet extends StatefulWidget {
  const LocalHtmlAttachmentLibrarySheet({
    super.key, required this.owner, this.english = false,
  });
  final LocalHtmlNoteAttachments owner;
  final bool english;
  @override
  State<LocalHtmlAttachmentLibrarySheet> createState() =>
      _LocalHtmlAttachmentLibrarySheetState();
}

class _LocalHtmlAttachmentLibrarySheetState
    extends State<LocalHtmlAttachmentLibrarySheet> {
  final _search = TextEditingController();
  List<DriveNode> _rows = const [];
  bool _loading = false, _failed = false;
  int _page = 1, _request = 0;
  String _keyword = '';
  @override
  void initState() { super.initState(); unawaited(_load(1)); }

  Future<void> _load(int page, {bool search = false}) async {
    if (_loading || page < 1) return;
    final owner = widget.owner;
    final request = ++_request;
    final keyword = search ? _search.text.trim() : _keyword;
    if (keyword.length > 200) {
      setState(() => _failed = true);
      return;
    }
    setState(() { _loading = true; _failed = false; _rows = const []; });
    try {
      final rows = await owner.available(keyword: keyword, page: page);
      if (!mounted || request != _request || !identical(owner, widget.owner)) return;
      owner.guard();
      setState(() { _rows = rows; _page = page; _keyword = keyword; });
    } catch (_) {
      if (mounted && request == _request) setState(() => _failed = true);
    } finally {
      if (mounted && request == _request) setState(() => _loading = false);
    }
  }

  void _select(DriveNode node) {
    try {
      widget.owner.guard();
      Navigator.pop(context, node);
    } catch (_) { setState(() { _failed = true; _rows = const []; }); }
  }

  @override
  void didUpdateWidget(covariant LocalHtmlAttachmentLibrarySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.owner, widget.owner)) {
      _request++; _loading = false; _rows = const [];
      unawaited(_load(1, search: true));
    }
  }
  @override
  void dispose() { _request++; _search.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    String t(String zh, String en) => widget.english ? en : zh;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .9),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16, 8, 16,
          16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('本地文件库', 'Local file library'),
            style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(t('选择文件不会保存正文，也不会上传服务器。',
            'Selecting a file does not save the body or upload anything.')),
          const SizedBox(height: 12),
          TextField(controller: _search, maxLength: 200,
            decoration: InputDecoration(labelText: t('搜索文件', 'Search files')),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) { if (!_loading) unawaited(_load(1, search: true)); }),
          OutlinedButton(onPressed: _loading ? null :
            () => _load(1, search: true), child: Text(t('搜索', 'Search'))),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_failed) Text(t('文件列表不可用，原稿保留。',
            'File list unavailable. The original draft is retained.')),
          for (final row in _rows) ListTile(
            leading: Icon(row.mime.startsWith('image/')
              ? Icons.image_outlined : Icons.description_outlined),
            title: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text('${row.path} · ${row.size} B',
              maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: _loading ? null : () => _select(row),
          ),
          if (!_loading && !_failed && _rows.isEmpty)
            Text(t('没有匹配文件', 'No matching files')),
          Wrap(spacing: 8, runSpacing: 8, children: [
            TextButton(onPressed: () => Navigator.pop(context),
              child: Text(t('返回', 'Back'))),
            TextButton(onPressed: _loading || _page <= 1 ? null :
              () => _load(_page - 1), child: Text(t('上一页', 'Previous'))),
            TextButton(onPressed: _loading || _page >= 1000 || _rows.length < 50
              ? null : () => _load(_page + 1), child: Text(t('下一页', 'Next'))),
          ]),
        ]),
      ),
    );
  }
}
