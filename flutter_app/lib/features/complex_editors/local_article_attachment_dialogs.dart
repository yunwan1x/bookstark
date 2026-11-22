import 'package:flutter/material.dart';
import '../../core/attachments.dart';

enum LocalArticleAttachmentAction { device, link }

Future<LocalArticleAttachmentAction?> chooseLocalArticleAttachment(
  BuildContext context, {
  required bool english,
}) => showModalBottomSheet<LocalArticleAttachmentAction>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          english ? 'Insert attachment' : '插入附件',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(english ? 'Files stay on this device.' : '文件仅保存在本机。'),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.smartphone_outlined),
          title: Text(english ? 'Import from device' : '从设备导入'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.pop(context, LocalArticleAttachmentAction.device),
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: Text(english ? 'Insert public link' : '插入公开链接'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () =>
              Navigator.pop(context, LocalArticleAttachmentAction.link),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(english ? 'Cancel' : '取消'),
        ),
      ],
    ),
  ),
);

Future<String?> enterLocalArticleLink(
  BuildContext context, {
  required bool english,
}) => showDialog<String>(
  context: context,
  builder: (_) => _LocalArticleLinkDialog(english: english),
);

class _LocalArticleLinkDialog extends StatefulWidget {
  const _LocalArticleLinkDialog({required this.english});
  final bool english;
  @override
  State<_LocalArticleLinkDialog> createState() =>
      _LocalArticleLinkDialogState();
}

class _LocalArticleLinkDialogState extends State<_LocalArticleLinkDialog> {
  final _name = TextEditingController(), _url = TextEditingController();
  String? _error;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _insert() {
    final value = _url.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.port < 1 ||
        uri.port > 65535 ||
        value.length > 8192 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value) ||
        _name.text.trim().isEmpty ||
        _name.text.trim().length > 180) {
      setState(
        () => _error = t(
          '请填写名称和公开 HTTP(S) 地址。',
          'Enter a name and public HTTP(S) URL.',
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      markdownAttachment(_name.text.trim(), uri, image: false),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(t('插入公开链接', 'Insert public link')),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(
              '链接会插入正文；本地预览不会自动读取远端图片。',
              'The link is inserted into the source. Local preview does not automatically fetch remote images.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: t('名称', 'Name')),
          ),
          TextField(
            controller: _url,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(labelText: t('公开地址', 'Public URL')),
          ),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('取消', 'Cancel')),
      ),
      FilledButton(onPressed: _insert, child: Text(t('插入', 'Insert'))),
    ],
  );
}
