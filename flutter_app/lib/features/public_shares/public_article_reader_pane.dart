import 'package:flutter/material.dart';
import '../../core/public_share_models.dart';

/// Flutter metadata/actions surrounding a read-only public article body.
class PublicArticleReaderPane extends StatelessWidget {
  const PublicArticleReaderPane({
    super.key,
    required this.detail,
    required this.body,
    required this.onUnlock,
    this.english = false,
    this.busy = false,
    this.unlocking = false,
    this.onSpeak,
    this.onComments,
  });
  final PublicShareDetail detail;
  final Widget? body;
  final VoidCallback onUnlock;
  final VoidCallback? onSpeak, onComments;
  final bool english, busy, unlocking;
  String t(String zh, String en) => english ? en : zh;
  static const purple = Color(0xff6530ad), lavender = Color(0xfff1e8fc);
  Widget _chip(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: lavender,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      text,
      style: const TextStyle(color: purple, fontWeight: FontWeight.w600),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final compatible = detail.blogType == null;
    final status = detail.locked
        ? t('需要密码', 'Password required')
        : detail.protected
        ? t('已解锁', 'Unlocked')
        : compatible
        ? t('分享阅读 · 兼容', 'Shared reading · Compatibility')
        : t('公开文章', 'Public article');
    final metadata = [
      if (detail.author.isNotEmpty) detail.author,
      if (detail.sharedAt != null)
        MaterialLocalizations.of(
          context,
        ).formatMediumDate(detail.sharedAt!.toLocal()),
    ].join(' · ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(alignment: Alignment.centerLeft, child: _chip(status)),
              const SizedBox(height: 16),
              Text(
                detail.title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xff0f172a),
                ),
              ),
              if (metadata.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  metadata,
                  style: const TextStyle(color: Color(0xff64748b)),
                ),
              ],
              if (!detail.locked && detail.labels.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: detail.labels.map(_chip).toList(),
                ),
              ],
              if (compatible && !detail.locked) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xfff1f3f7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    t(
                      '服务器未提供内容分类，以只读模式打开。',
                      'This server does not provide a content category. Opening read only.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (detail.locked)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xffe3ddea)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.lock_outline, size: 48, color: purple),
                      const SizedBox(height: 16),
                      Text(
                        t('输入分享密码后查看文章。', 'Enter the share password to read.'),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: purple,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: unlocking ? null : onUnlock,
                        child: Text(t('解锁阅读', 'Unlock and read')),
                      ),
                    ],
                  ),
                )
              else
                body ?? const SizedBox.shrink(),
              if (!detail.locked &&
                  (onSpeak != null || onComments != null)) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (onSpeak != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: purple,
                          side: const BorderSide(color: purple),
                        ),
                        onPressed: busy ? null : onSpeak,
                        icon: const Icon(Icons.headphones_outlined),
                        label: Text(t('听文章', 'Listen')),
                      ),
                    if (onComments != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: purple,
                          side: const BorderSide(color: purple),
                        ),
                        onPressed: busy ? null : onComments,
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(t('查看评论', 'View comments')),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
