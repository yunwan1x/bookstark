import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/local_legacy_format_selection.dart';
import '../admin/admin_asset_secure_window.dart';
import 'legacy_format_ui.dart';
import 'local_legacy_preview_page.dart';

/// Edits a source-bound recipe only. The parent owns inspection/candidate writes.
class LocalLegacyFormatPage extends StatefulWidget {
  const LocalLegacyFormatPage({
    super.key,
    required this.source,
    required this.isCurrentScope,
    required this.onResolved,
    this.initial,
    this.english = false,
    this.unlocker,
    this.windowGuardFactory,
  });
  final LegacyFormatSource source;
  final LegacyFormatSelection? initial;
  final bool Function() isCurrentScope;
  final Future<void> Function(LegacyFormatSelection) onResolved;
  final bool english;
  final LegacyPreviewUnlocker? unlocker;
  final AdminAssetWindowGuard Function()? windowGuardFactory;
  @override
  State<LocalLegacyFormatPage> createState() => _LocalLegacyFormatPageState();
}

class _LocalLegacyFormatPageState extends State<LocalLegacyFormatPage> {
  late LegacyFormatSelection selection;
  final _routes = <Route<dynamic>>{};
  var _epoch = 0, _page = 0;
  bool _submitting = false,
      _submitted = false,
      _failed = false,
      _scopeRetired = false;
  static const _pageSize = 20;
  String t(String zh, String en) => widget.english ? en : zh;
  bool current(int epoch) =>
      mounted && !_scopeRetired && epoch == _epoch && widget.isCurrentScope();

  LegacyFormatSelection initial() {
    final value = widget.initial;
    if (value != null &&
        (value.source.archiveSha256 != widget.source.archiveSha256 ||
            value.source.scopeKey != widget.source.scopeKey)) {
      throw ArgumentError(
        'Format selections belong to another source lifetime',
      );
    }
    return LegacyFormatSelection(
      widget.source,
      choices: value?.choices ?? const {},
    );
  }

  @override
  void initState() {
    super.initState();
    selection = initial();
    _scopeRetired = !widget.isCurrentScope();
  }

  @override
  void didUpdateWidget(covariant LocalLegacyFormatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.source, widget.source)) {
      _epoch++;
      _retireRoutes();
      selection = initial();
      _page = 0;
      _submitting = false;
      _submitted = false;
      _failed = false;
      _scopeRetired = !widget.isCurrentScope();
    } else if (!widget.isCurrentScope()) {
      _retireScope();
    }
  }

  void _retireScope() {
    if (_scopeRetired) return;
    _scopeRetired = true;
    _epoch++;
    _retireRoutes();
  }

  void _remove(Route<dynamic> route) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    });
  }

  void _retireRoutes() {
    for (final route in _routes.toList()) {
      _remove(route);
    }
    _routes.clear();
  }

  @override
  void dispose() {
    _epoch++;
    _retireRoutes();
    super.dispose();
  }

  Future<void> _choose(LegacyFormatItem item) async {
    final epoch = _epoch;
    if (!current(epoch) || _submitting || _submitted || _routes.isNotEmpty) {
      return;
    }
    Route<dynamic>? owned;
    final value = await showModalBottomSheet<LegacyContentFormat>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        owned = ModalRoute.of(context);
        if (owned != null) {
          _routes.add(owned!);
          if (!current(epoch)) _remove(owned!);
        }
        return !current(epoch)
            ? const SizedBox.shrink()
            : Theme(
                data: legacyFormatTheme(Theme.of(context)),
                child: _FormatSheet(
                  initial: selection.choices[item.id],
                  english: widget.english,
                ),
              );
      },
    );
    if (owned != null) _routes.remove(owned);
    if (value != null && current(epoch)) {
      setState(() => selection = selection.choose(item.id, value));
    }
  }

  Future<T?> _push<T>(Widget child) async {
    final route = MaterialPageRoute<T>(builder: (_) => child);
    _routes.add(route);
    try {
      return await Navigator.of(context).push(route);
    } finally {
      _routes.remove(route);
    }
  }

  Future<void> _bulk() async {
    final epoch = _epoch;
    if (!current(epoch) ||
        _submitting ||
        _submitted ||
        _routes.isNotEmpty ||
        selection.complete) {
      return;
    }
    final format = await _push<LegacyContentFormat>(
      _BulkFormatPage(
        english: widget.english,
        selected: selection.choices.length,
        total: widget.source.items.length,
        missing: selection.unresolved,
      ),
    );
    if (format != null && current(epoch)) {
      setState(() => selection = selection.chooseMissing(format));
    }
  }

  Future<void> _preview(LegacyFormatItem item) async {
    final epoch = _epoch;
    if (!current(epoch) || _submitting || _submitted || _routes.isNotEmpty) {
      return;
    }
    final value = await _push<LegacyContentFormat>(
      LocalLegacyPreviewPage(
        item: item,
        english: widget.english,
        selectedFormat: selection.choices[item.id],
        isCurrentScope: () => current(epoch),
        unlocker: widget.unlocker,
        windowGuardFactory: widget.windowGuardFactory,
      ),
    );
    if (value != null && current(epoch)) {
      setState(() => selection = selection.choose(item.id, value));
    }
  }

  Future<void> _submit() async {
    final epoch = _epoch;
    if (!current(epoch) || !selection.complete || _submitting || _submitted) {
      return;
    }
    setState(() {
      _submitting = true;
      _failed = false;
    });
    try {
      await widget.onResolved(selection);
      if (current(epoch)) setState(() => _submitted = true);
    } catch (_) {
      if (current(epoch)) setState(() => _failed = true);
    } finally {
      if (current(epoch)) setState(() => _submitting = false);
    }
  }

  Widget _item(LegacyFormatItem item) {
    final chosen = selection.choices[item.id];
    final title = item.title.isEmpty ? t('未命名', 'Untitled') : item.title;
    final enabled = !_submitting && !_submitted;
    final action = chosen == null
        ? TextButton.icon(
            onPressed: enabled ? () => _choose(item) : null,
            label: Text(t('选择格式', 'Choose format')),
            icon: const Icon(Icons.chevron_right, size: 20),
            iconAlignment: IconAlignment.end,
          )
        : IconButton(
            color: legacyBlue,
            onPressed: enabled ? () => _choose(item) : null,
            tooltip: t('修改格式：', 'Change format: ') + title,
            icon: const Icon(Icons.edit_outlined, size: 20),
          );
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          chosen != null
              ? t('格式：', 'Format: ') + legacyFormatName(chosen, widget.english)
              : item.isProtected
              ? t('密码保护', 'Password protected')
              : item.collection == 'article'
              ? t('文章', 'Article')
              : t('笔记', 'Note'),
          style: const TextStyle(color: Color(0xff576374), fontSize: 14),
        ),
        if (item.isProtected && !selection.complete)
          TextButton(
            onPressed: enabled ? () => _preview(item) : null,
            child: Text(t('使用原密码预览', 'Preview with original password')),
          ),
      ],
    );
    return Container(
      key: ValueKey('legacy-format-item:${item.id}'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffb4bac4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 320 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.3;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.isProtected) ...[
                const Icon(Icons.lock_outline, color: legacyInk, size: 24),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: stacked
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          detail,
                          Align(
                            alignment: Alignment.centerRight,
                            child: action,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: detail),
                          const SizedBox(width: 8),
                          action,
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_scopeRetired || !widget.isCurrentScope()) {
      _retireScope();
      return LegacyFormatFrame(
        title: t('确认编辑器类型', 'Confirm content formats'),
        content: [
          Text(
            t('来源已失效，请返回重新选择', 'Source expired. Go back and choose it again.'),
          ),
        ],
      );
    }
    final total = widget.source.items.length;
    final pages = math.max(1, (total / _pageSize).ceil());
    final start = math.min(_page * _pageSize, total);
    final end = math.min(start + _pageSize, total);
    return LegacyFormatFrame(
      title: selection.complete
          ? t('核对内容格式', 'Review content formats')
          : t('确认编辑器类型', 'Confirm content formats'),
      scrollIdentity: (widget.source.scopeKey, _page),
      content: [
        LegacyFormatInfo(
          selection.complete
              ? t(
                  '已选择 ${selection.choices.length} / $total 项',
                  'Chosen ${selection.choices.length} / $total',
                )
              : t(
                  '旧备份未记录内容格式，请逐项选择',
                  'This backup did not record content formats. Choose each format.',
                ),
          checked: selection.complete,
        ),
        if (!selection.complete)
          Text(
            t(
              '尚有 ${selection.unresolved} 项未选择',
              '${selection.unresolved} items still need a format',
            ),
          ),
        if (total == 0)
          Text(t('此备份无需选择笔记格式', 'No note formats need to be selected.')),
        for (final item in widget.source.items.getRange(start, end))
          _item(item),
        if (pages > 1) ...[
          Text(t('第 ${_page + 1} / $pages 页', 'Page ${_page + 1} / $pages')),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _page > 0 && !_submitting && !_submitted
                      ? () => setState(() => _page--)
                      : null,
                  child: Text(t('上一页', 'Previous')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _page + 1 < pages && !_submitting && !_submitted
                      ? () => setState(() => _page++)
                      : null,
                  child: Text(t('下一页', 'Next')),
                ),
              ),
            ],
          ),
        ],
        if (selection.complete &&
            widget.source.items.any((item) => item.isProtected))
          LegacyFormatInfo(
            t(
              '受保护的内容仍需原密码解锁',
              'Protected content still requires its original password.',
            ),
          ),
        if (_failed)
          Text(
            t('无法保存选择，请重试', 'Could not save choices. Try again.'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
      actions: [
        if (!selection.complete)
          OutlinedButton(
            onPressed: !_submitting && !_submitted ? _bulk : null,
            child: Text(
              t('批量选择格式', 'Choose missing formats together'),
              textAlign: TextAlign.center,
            ),
          ),
        FilledButton(
          onPressed: selection.complete && !_submitting && !_submitted
              ? _submit
              : null,
          child: Text(
            _submitting
                ? t('正在保存选择', 'Saving choices')
                : _submitted
                ? t('已保存选择', 'Choices saved')
                : selection.complete
                ? t('保存选择并继续', 'Save choices and continue')
                : t('继续核对', 'Continue review'),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _FormatSheet extends StatefulWidget {
  const _FormatSheet({required this.initial, required this.english});
  final LegacyContentFormat? initial;
  final bool english;
  @override
  State<_FormatSheet> createState() => _FormatSheetState();
}

class _FormatSheetState extends State<_FormatSheet> {
  LegacyContentFormat? selected;
  @override
  void initState() {
    super.initState();
    selected = widget.initial;
  }

  String t(String zh, String en) => widget.english ? en : zh;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t('选择内容格式', 'Choose a content format'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: legacyInk,
                ),
              ),
              const SizedBox(height: 12),
              RadioGroup<LegacyContentFormat>(
                groupValue: selected,
                onChanged: (value) => setState(() => selected = value),
                child: Column(
                  children: [
                    for (final format in LegacyContentFormat.values) ...[
                      RadioListTile(
                        value: format,
                        activeColor: legacyBlue,
                        contentPadding: EdgeInsets.zero,
                        title: Text(legacyFormatName(format, widget.english)),
                      ),
                      if (format != LegacyContentFormat.values.last)
                        const Divider(height: 1, indent: 48),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                t(
                  '选择格式不会改写原文',
                  'Choosing a format does not rewrite the source.',
                ),
                style: const TextStyle(fontSize: 14, color: Color(0xff576374)),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: selected == null
                    ? null
                    : () => Navigator.of(context).pop(selected),
                child: Text(
                  t('确认选择', 'Confirm choice'),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _BulkFormatPage extends StatefulWidget {
  const _BulkFormatPage({
    required this.english,
    required this.selected,
    required this.total,
    required this.missing,
  });
  final bool english;
  final int selected, total, missing;
  @override
  State<_BulkFormatPage> createState() => _BulkFormatPageState();
}

class _BulkFormatPageState extends State<_BulkFormatPage> {
  LegacyContentFormat? selected;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  Widget build(BuildContext context) => LegacyFormatFrame(
    title: t('批量选择格式', 'Choose missing formats together'),
    content: [
      LegacyFormatInfo(
        t(
          '已选择 ${widget.selected} / ${widget.total} 项',
          'Chosen ${widget.selected} / ${widget.total}',
        ),
      ),
      LegacyFormatDropdown(
        value: selected,
        english: widget.english,
        onChanged: (value) => setState(() => selected = value),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_box, color: legacyBlue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              t(
                '仅应用于尚未选择的 ${widget.missing} 项',
                'Apply only to ${widget.missing} items without a format',
              ),
            ),
          ),
        ],
      ),
      Text(t('已选择的项目保持原格式', 'Existing choices stay unchanged.')),
    ],
    actions: [
      FilledButton(
        onPressed: selected == null
            ? null
            : () => Navigator.of(context).pop(selected),
        child: Text(t('应用选择', 'Apply choice'), textAlign: TextAlign.center),
      ),
      OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(t('返回', 'Back')),
      ),
    ],
  );
}
