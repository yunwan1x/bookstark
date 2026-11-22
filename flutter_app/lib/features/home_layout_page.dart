import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/api_client.dart';
import '../core/home_dashboard_models.dart';
import 'home_dashboard_controller.dart';

class HomeLayoutPage extends StatefulWidget {
  const HomeLayoutPage({
    super.key,
    required this.controller,
    required this.english,
    required this.scopeLabel,
    this.local = false,
  });
  final HomeDashboardController controller;
  final bool english;
  final bool local;
  final String scopeLabel;
  @override
  State<HomeLayoutPage> createState() => _HomeLayoutPageState();
}

class _HomeLayoutPageState extends State<HomeLayoutPage> {
  late List<HomeLayoutItem> _draft, _baseline;
  bool _allowExit = false;
  String? _readback;
  HomeDashboardController get state => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  String name(String key) {
    const names = {
      'notes': ['笔记', 'Notes'],
      'articles': ['文章', 'Articles'],
      'tasks': ['待办', 'Tasks'],
      'books': ['书籍', 'Books'],
      'bookmarks': ['书签', 'Bookmarks'],
      'topics': ['专题', 'Topics'],
      'nav': ['导航', 'Navigation'],
      'shares': ['我的分享', 'My shares'],
      'assets': ['资产', 'Assets'],
    };
    return names[key]![widget.english ? 1 : 0];
  }

  String signature(List<HomeLayoutItem> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());
  bool get dirty => signature(_draft) != signature(_baseline);
  bool get busy => !state.retired && (state.loading || state.writing);
  Set<String> get available =>
      state.snapshot?.sections.map((e) => e.key).toSet() ?? {};
  @override
  void initState() {
    super.initState();
    _baseline = List.of(state.snapshot?.layout ?? const []);
    _draft = List.of(_baseline);
    state.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    state.removeListener(_changed);
    super.dispose();
  }

  Future<void> _finish() async {
    if (!mounted) return;
    setState(() => _allowExit = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _leave() async {
    if (state.retired) {
      await _finish();
      return;
    }
    if (busy) return;
    if (dirty) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(t('放弃未保存的布局？', 'Discard unsaved layout?')),
          content: Text(t('首页布局尚未保存。', 'Your home layout has not been saved.')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('继续编辑', 'Keep editing')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('放弃修改', 'Discard changes')),
            ),
          ],
        ),
      );
      if (yes != true) return;
    }
    await _finish();
  }

  void _replace(HomeLayoutItem item) {
    setState(() {
      _draft[_draft.indexWhere((e) => e.key == item.key)] = item;
      _readback = null;
    });
  }

  void _move(String key, int delta) {
    final shown = _draft.where((e) => available.contains(e.key)).toList();
    final index = shown.indexWhere((e) => e.key == key), next = index + delta;
    if (index < 0 || next < 0 || next >= shown.length) return;
    setState(() {
      final from = _draft.indexWhere((e) => e.key == key),
          to = _draft.indexWhere((e) => e.key == shown[next].key);
      final item = _draft.removeAt(from);
      _draft.insert(to, item);
      _readback = null;
    });
  }

  Future<void> _save() async {
    final saved = await state.saveLayout(List.unmodifiable(_draft));
    if (mounted && (saved || state.retired)) await _finish();
  }

  Future<void> _readCurrent() async {
    if (!await state.load() || !mounted) return;
    setState(() {
      _baseline = List.of(state.snapshot!.layout);
      _readback = dirty
          ? t(
              widget.local
                  ? '本机布局与草稿不同，草稿仍保留。保存将替换当前布局。'
                  : '服务器布局与草稿不同，草稿仍保留。保存将替换当前布局。',
              widget.local
                  ? 'The local layout differs. Your draft is retained; saving will replace the current layout.'
                  : 'The server layout differs. Your draft is retained; saving will replace the current layout.',
            )
          : t(
              widget.local ? '已重新读取，本机布局与草稿一致。' : '已重新读取，服务器布局与草稿一致。',
              widget.local
                  ? 'Readback confirms that the local layout matches your draft.'
                  : 'Readback confirms that the server layout matches your draft.',
            );
    });
  }

  Widget _card(HomeLayoutItem item, int index, int count) => Container(
    key: ValueKey('home-layout-${item.key}'),
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xffe2e8f0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.dashboard_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name(item.key),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Semantics(
              label: '${t('显示', 'Show')} ${name(item.key)}',
              child: Switch(
                value: !item.hidden,
                onChanged: busy
                    ? null
                    : (value) => _replace(item.copyWith(hidden: !value)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final field = DropdownButtonFormField<int>(
              key: ValueKey('${item.key}-width-${item.width}'),
              initialValue: item.width,
              isExpanded: true,
              isDense: false,
              itemHeight: null,
              decoration: InputDecoration(
                labelText: t('模块宽度', 'Module width'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final width in [1, 2, 3])
                  DropdownMenuItem(
                    value: width,
                    child: Text(
                      [
                        t('标准', 'Standard'),
                        t('宽', 'Wide'),
                        t('整行', 'Full row'),
                      ][width - 1],
                    ),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) _replace(item.copyWith(width: value));
                    },
            );
            final arrows = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '${t('上移', 'Move up')} ${name(item.key)}',
                  onPressed: busy || index == 0
                      ? null
                      : () => _move(item.key, -1),
                  icon: const Icon(Icons.arrow_upward),
                ),
                IconButton(
                  tooltip: '${t('下移', 'Move down')} ${name(item.key)}',
                  onPressed: busy || index == count - 1
                      ? null
                      : () => _move(item.key, 1),
                  icon: const Icon(Icons.arrow_downward),
                ),
              ],
            );
            if (MediaQuery.textScalerOf(context).scale(14) > 18 ||
                constraints.maxWidth < 280) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  field,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: arrows),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: field),
                const SizedBox(width: 8),
                arrows,
              ],
            );
          },
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final shown = _draft.where((e) => available.contains(e.key)).toList();
    final error = state.problem;
    final message = state.needsReadback
        ? t(
            '保存结果尚未确认，请先重新读取核对。',
            'The save result is unknown. Read back the current layout first.',
          )
        : error is ApiFailure && error.status == 401
        ? t(
            '登录已失效，请返回首页重新登录。',
            'Your session expired. Return home and sign in again.',
          )
        : error != null
        ? t(
            '无法完成操作，草稿仍保留。',
            'The operation could not be completed. Your draft is retained.',
          )
        : null;
    final defaults = OutlinedButton(
      onPressed: busy || state.snapshot == null
          ? null
          : () => setState(() {
              _draft = readHomeLayout(null);
              _readback = null;
            }),
      child: Text(t('恢复默认', 'Restore defaults')),
    );
    final save = FilledButton(
      onPressed: busy || state.needsReadback || (!dirty && _readback == null)
          ? null
          : dirty
          ? _save
          : _finish,
      child: Text(
        busy
            ? t('正在处理…', 'Working…')
            : dirty
            ? t('保存布局', 'Save layout')
            : t('返回首页', 'Return home'),
      ),
    );
    return PopScope<Object?>(
      canPop: _allowExit || (!dirty && !busy),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: MediaQuery.textScalerOf(context).scale(20) > 28
              ? 112
              : 56,
          leading: BackButton(onPressed: _leave),
          title: Text(t('自定义首页', 'Customize home')),
        ),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              t('调整模块顺序、显示和宽度。', 'Adjust module order, visibility and width.'),
            ),
            const SizedBox(height: 12),
            Text(
              widget.scopeLabel,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (dirty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(t('未保存的修改', 'Unsaved changes')),
              ),
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Semantics(liveRegion: true, child: Text(message)),
              ),
            if (state.needsReadback)
              OutlinedButton(
                onPressed: busy ? null : _readCurrent,
                child: Text(t('重新读取核对', 'Read back current layout')),
              ),
            if (_readback != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_readback!),
              ),
            const SizedBox(height: 20),
            for (var i = 0; i < shown.length; i++)
              _card(shown[i], i, shown.length),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
            child: MediaQuery.textScalerOf(context).scale(14) > 18
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [defaults, const SizedBox(height: 8), save],
                  )
                : Row(
                    children: [
                      Expanded(child: defaults),
                      const SizedBox(width: 12),
                      Expanded(child: save),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
