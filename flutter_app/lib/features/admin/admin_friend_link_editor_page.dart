import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'admin_community_scope.dart';
import 'admin_community_strings.dart';
import 'admin_community_widgets.dart';
import 'admin_friend_links_models.dart';
import 'admin_settings_widgets.dart';

class AdminFriendLinkEditorPage extends StatefulWidget {
  const AdminFriendLinkEditorPage({
    super.key,
    required this.scope,
    required this.initial,
    required this.strings,
    required this.onReturn,
    required this.onApply,
    required this.onDirtyChanged,
    this.qrTransportFactory,
    this.qrMode = false,
    this.isNew = false,
    this.onRemove,
    this.enabled = true,
  });
  final AdminCommunityScope scope;
  final http.Client Function()? qrTransportFactory;
  final AdminFriendLink initial;
  final AdminCommunityStrings strings;
  final VoidCallback onReturn;
  final bool Function(AdminFriendLink) onApply;
  final ValueChanged<bool> onDirtyChanged;
  final VoidCallback? onRemove;
  final bool qrMode, isNew, enabled;
  @override
  State<AdminFriendLinkEditorPage> createState() =>
      _AdminFriendLinkEditorPageState();
}

class _AdminFriendLinkEditorPageState extends State<AdminFriendLinkEditorPage> {
  late TextEditingController _name,
      _url,
      _group,
      _qr,
      _description,
      _groupOrder,
      _weight;
  late bool _enabled;
  String? _error, _previewPath;
  AdminCommunityStrings get s => widget.strings;
  List<TextEditingController> get _fields => [
    _name,
    _url,
    _group,
    _qr,
    _description,
    _groupOrder,
    _weight,
  ];
  void _install() {
    final row = widget.initial;
    _name = TextEditingController(text: row.name);
    _url = TextEditingController(text: row.url);
    _group = TextEditingController(text: row.group);
    _qr = TextEditingController(text: row.qr);
    _description = TextEditingController(text: row.description);
    _groupOrder = TextEditingController(text: '${row.groupOrder}');
    _weight = TextEditingController(text: '${row.weight}');
    _enabled = row.enabled;
    _previewPath = row.qr.trim().isEmpty ? null : row.qr.trim();
  }

  void _clear() {
    for (final controller in _fields) {
      controller.clear();
      controller.dispose();
    }
    _previewPath = null;
  }

  @override
  void initState() {
    super.initState();
    _install();
  }

  @override
  void didUpdateWidget(covariant AdminFriendLinkEditorPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope ||
        oldWidget.initial != widget.initial) {
      _clear();
      _install();
      _error = null;
    }
  }

  bool get _dirty {
    final row = widget.initial;
    return _name.text != row.name ||
        _url.text != row.url ||
        _group.text != row.group ||
        _qr.text != row.qr ||
        _description.text != row.description ||
        _groupOrder.text != '${row.groupOrder}' ||
        _weight.text != '${row.weight}' ||
        _enabled != row.enabled;
  }

  void _edited(String value) {
    setState(() {
      _error = null;
      if (_previewPath != null && _previewPath != _qr.text.trim()) {
        _previewPath = null;
      }
    });
    widget.onDirtyChanged(_dirty);
  }

  void _apply() {
    if (!widget.enabled || !widget.scope.guard()) return;
    final groupOrder = int.tryParse(_groupOrder.text),
        weight = int.tryParse(_weight.text);
    if (groupOrder == null || weight == null) {
      setState(
        () => _error = s.t(
          '分组顺序和组内排序必须是整数。',
          'Group order and item order must be integers.',
        ),
      );
      return;
    }
    try {
      final row = widget.initial.edit(
        name: _name.text,
        url: _url.text,
        group: _group.text,
        qr: _qr.text,
        description: _description.text,
        groupOrder: groupOrder,
        weight: weight,
        enabled: _enabled,
      );
      row.validate();
      if (!widget.onApply(row) && mounted) {
        setState(
          () => _error = s.t(
            '列表草稿已变化，请返回重新进入编辑。',
            'The draft changed. Return to the list and open the editor again.',
          ),
        );
      }
    } on FormatException {
      setState(
        () => _error = s.t(
          '请检查名称、HTTP(S)地址、UTF-8字节长度和本站二维码图片路径。',
          'Check the name, HTTP(S) URL, UTF-8 byte limits and local QR image path.',
        ),
      );
    }
  }

  Widget _card(String id, Widget child) => Padding(
    key: ValueKey('friend-editor-card-$id'),
    padding: const EdgeInsets.only(bottom: 14),
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xffedf4ff), Color(0xffe3eeff)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    ),
  );
  Widget _field(
    String id,
    TextEditingController controller,
    String label, {
    String? helper,
    TextInputType keyboard = TextInputType.text,
    int minLines = 1,
    int? maxLines = 1,
  }) => AdminSettingsField(
    fieldKey: ValueKey('friend-editor-$id'),
    controller: controller,
    label: label,
    enabled: widget.enabled && widget.scope.active,
    onChanged: _edited,
    helper: helper,
    keyboardType: keyboard,
    minLines: minLines,
    maxLines: maxLines,
  );
  Widget _orders() => _card(
    'orders',
    LayoutBuilder(
      builder: (context, box) {
        final group = _field(
          'group-order',
          _groupOrder,
          s.t('分组顺序', 'Group order'),
          keyboard: const TextInputType.numberWithOptions(signed: true),
        );
        final weight = _field(
          'weight',
          _weight,
          s.t('组内排序', 'Item order'),
          keyboard: const TextInputType.numberWithOptions(signed: true),
        );
        if (box.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(16) > 24) {
          return Column(children: [group, weight]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: group),
            const SizedBox(width: 14),
            Expanded(child: weight),
          ],
        );
      },
    ),
  );
  Widget _enabledCard() => _card(
    'enabled',
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.t('启用', 'Enabled'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          Semantics(
            label: s.t('启用此链接', 'Enable this link'),
            child: Switch(
              value: _enabled,
              onChanged: widget.enabled
                  ? (value) {
                      setState(() => _enabled = value);
                      widget.onDirtyChanged(_dirty);
                    }
                  : null,
            ),
          ),
        ],
      ),
    ),
  );
  Widget _preview() => _card(
    'preview',
    Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_previewPath != null)
            AdminFriendQrThumbnail(
              key: ValueKey(_previewPath),
              scope: widget.scope,
              path: _previewPath!,
              strings: s,
              transportFactory: widget.qrTransportFactory,
            )
          else
            Row(
              children: [
                const Icon(Icons.qr_code_2, size: 64, color: Color(0xff536482)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    s.t('填写本站图片路径后预览', 'Enter a local image path to preview'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: widget.enabled
                ? () {
                    final path = _qr.text.trim();
                    if (!canonicalFriendQr(path)) {
                      setState(
                        () => _error = s.t(
                          '二维码必须使用规范的本站 /upload-files/ 图片路径。',
                          'Use a canonical /upload-files/ image path from this server.',
                        ),
                      );
                    } else {
                      setState(() => _previewPath = path);
                    }
                  }
                : null,
            icon: const Icon(Icons.image_outlined),
            label: Text(s.t('加载预览', 'Load preview')),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qr = widget.qrMode;
    final title = widget.isNew
        ? (qr
              ? s.t('新增二维码条目', 'Add QR entry')
              : s.t('新增友情链接', 'Add friend link'))
        : qr
        ? s.t('编辑二维码条目', 'Edit QR entry')
        : s.t('编辑友情链接', 'Edit friend link');
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: adminSettingsAppBar(
        context,
        title: title,
        subtitle: s.t('仅修改本地草稿', 'Local draft only'),
        dirty: _dirty,
        onReturn: widget.onReturn,
        backLabel: s.t('返回', 'Back'),
        dirtyLabel: s.t('未保存', 'Unsaved'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Semantics(
                  liveRegion: true,
                  child: AdminCommunityInfo(
                    text: _error!,
                    tone: AdminCommunityTone.warning,
                  ),
                ),
              ),
            Column(
              key: const ValueKey('friend-editor-form'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (qr) ...[
                  AdminCommunityInfo(
                    text: s.t(
                      '二维码分组的标题和描述须一致。',
                      'QR entries in the same group must use the same title and description.',
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _card('name', _field('name', _name, s.t('名称', 'Name'))),
                if (!qr)
                  _card(
                    'url',
                    _field(
                      'url',
                      _url,
                      s.t('链接地址', 'Link URL'),
                      keyboard: TextInputType.url,
                    ),
                  ),
                if (qr)
                  _card(
                    'qr',
                    _field(
                      'qr',
                      _qr,
                      s.t('二维码图片路径', 'QR image path'),
                      helper: s.t(
                        '本站 /upload-files/ 图片路径；清空后保留有效链接可改为普通链接。',
                        'Use a local /upload-files/ image path. Clearing it while keeping a valid URL creates a regular link.',
                      ),
                    ),
                  ),
                _card(
                  'group',
                  _field('group', _group, s.t('分组名称', 'Group name')),
                ),
                if (qr) _preview() else _orders(),
                _enabledCard(),
                _card(
                  'description',
                  _field(
                    'description',
                    _description,
                    s.t('描述（可选）', 'Description (optional)'),
                    keyboard: TextInputType.multiline,
                    minLines: 3,
                    maxLines: 6,
                  ),
                ),
                if (qr) ...[
                  _card(
                    'url',
                    _field(
                      'url',
                      _url,
                      s.t('链接地址（可选）', 'Link URL (optional)'),
                      keyboard: TextInputType.url,
                    ),
                  ),
                  _orders(),
                ] else
                  ExpansionTile(
                    key: const ValueKey('friend-editor-extra-qr'),
                    title: Text(s.t('二维码（可选）', 'QR image (optional)')),
                    children: [
                      _card(
                        'qr',
                        _field('qr', _qr, s.t('二维码图片路径', 'QR image path')),
                      ),
                      _preview(),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: widget.enabled ? _apply : null,
              child: Text(s.t('应用到草稿', 'Apply to draft')),
            ),
            const SizedBox(height: 12),
            Text(
              s.t(
                '返回列表后，明确保存全部链接才会更新服务器。',
                'The server updates only after you explicitly save the complete list.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xff64748b)),
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: widget.enabled ? widget.onRemove : null,
                icon: const Icon(Icons.delete_outline),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xffbf2637),
                ),
                label: Text(s.t('移除这条草稿', 'Remove this draft entry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
