import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:mime/mime.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/attachments.dart';
import 'attachment_image.dart';

Future<void> shareBookstarkAttachment(
  BuildContext context,
  AttachmentRepository repository,
  Attachment attachment, {
  Uint8List? bytes,
  Future<void> Function(Attachment, Uint8List)? override,
}) async {
  final data = bytes ?? await repository.read(attachment.uri);
  if (!context.mounted) {
    return;
  }
  if (override != null) {
    await override(attachment, data);
    return;
  }
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize
      ? box.localToGlobal(Offset.zero) & box.size
      : const Rect.fromLTWH(0, 0, 1, 1);
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          data,
          mimeType: lookupMimeType(attachment.name, headerBytes: data),
        ),
      ],
      fileNameOverrides: [attachmentName(attachment.name)],
      sharePositionOrigin: origin,
    ),
  );
}

Future<void> openBookstarkLink(
  BuildContext context,
  String label,
  String? href, {
  AttachmentRepository? repository,
  bool english = false,
  Future<void> Function(Attachment)? onShare,
}) async {
  if (href == null) {
    return;
  }
  String t(String zh, String en) => english ? en : zh;
  try {
    final uri = Uri.parse(href);
    if (repository != null && repository.owns(uri)) {
      final share = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: Text(label),
          content: Text(
            t(
              '通过系统分享面板打开或发送此附件',
              'Use the system share sheet to open or send this attachment.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('分享文件', 'Share file')),
            ),
          ],
        ),
      );
      if (share == true && context.mounted) {
        final attachment = Attachment(uri: uri, name: label, image: false);
        if (onShare != null) {
          await onShare(attachment);
        } else {
          await shareBookstarkAttachment(context, repository, attachment);
        }
      }
      return;
    }
    final target = repository?.resolve(uri) ?? uri;
    if (!['http', 'https'].contains(target.scheme) ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty) {
      throw const FormatException('不支持的链接 / Unsupported link');
    }
    if (!context.mounted) {
      return;
    }
    final open = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(t('打开链接？', 'Open link?')),
        content: SelectableText(target.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('打开', 'Open')),
          ),
        ],
      ),
    );
    if (open == true &&
        !await launchUrl(target, mode: LaunchMode.externalApplication)) {
      throw StateError(t('无法打开链接', 'Unable to open link'));
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

/// Shared native renderer for note previews, AI replies and resource excerpts.
/// File access, cookies and bounds remain owned by AttachmentRepository.
class BookstarkMarkdown extends StatelessWidget {
  const BookstarkMarkdown({
    super.key,
    required this.data,
    this.attachments,
    this.english = false,
    this.scrollable = false,
    this.onShare,
    this.onLink,
    this.paragraphStyle,
    this.onExcerpt,
    this.imageBuilder,
  });
  final String data;
  final Widget Function(Uri, String?, String?)? imageBuilder;
  final TextStyle? paragraphStyle;
  final Future<void> Function(String selected)? onExcerpt;
  final AttachmentRepository? attachments;
  final bool english, scrollable;
  final Future<void> Function(Attachment, Uint8List)? onShare;
  final Future<void> Function(String text, String? href)? onLink;
  @override
  Widget build(BuildContext context) {
    final repository = attachments;
    final body = MarkdownBody(
      data: data,
      selectable: true,
      contextMenuBuilder: (context, state) {
        final value = state.textEditingValue;
        final selection = value.selection;
        final selected =
            selection.isValid &&
                !selection.isCollapsed &&
                selection.end <= value.text.length
            ? selection.textInside(value.text)
            : '';
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: state.contextMenuAnchors,
          buttonItems: [
            ...state.contextMenuButtonItems,
            if (onExcerpt != null && selected.trim().isNotEmpty)
              ContextMenuButtonItem(
                label: english ? 'Save excerpt as note' : '摘录为笔记',
                onPressed: () {
                  state.hideToolbar();
                  onExcerpt!(selected);
                },
              ),
          ],
        );
      },
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: paragraphStyle,
        blockquoteDecoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          border: Border(
            left: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.all(12),
      ),
      onTapLink: (text, href, title) {
        if (onLink != null) {
          onLink!(text, href);
        } else {
          openBookstarkLink(
            context,
            text,
            href,
            repository: repository,
            english: english,
          );
        }
      },
      imageBuilder:
          imageBuilder ??
          (uri, title, alt) => repository == null
              ? Text(alt ?? uri.toString())
              : AttachmentImage(
                  repository: repository,
                  uri: uri,
                  label: alt ?? uri.toString(),
                  english: english,
                  onShare: (bytes) => shareBookstarkAttachment(
                    context,
                    repository,
                    Attachment(uri: uri, name: alt ?? 'image', image: true),
                    bytes: bytes,
                    override: onShare,
                  ),
                ),
    );
    return scrollable
        ? SingleChildScrollView(padding: const EdgeInsets.all(16), child: body)
        : body;
  }
}
