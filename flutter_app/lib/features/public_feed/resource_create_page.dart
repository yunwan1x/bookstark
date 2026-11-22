import 'package:flutter/material.dart';

enum ResourceCreateKind { note, article, bookmark, document }

/// Selection only: no repository or write request exists in this page.
class ResourceCreatePage extends StatelessWidget {
  const ResourceCreatePage({super.key, this.english = false});
  final bool english;
  String t(String zh, String en) => english ? en : zh;
  Widget _card(BuildContext context, ResourceCreateKind kind) {
    final color = switch (kind) {
      ResourceCreateKind.note => const Color(0xff2563eb),
      ResourceCreateKind.article => const Color(0xff7c3aed),
      ResourceCreateKind.bookmark => const Color(0xfff59e0b),
      ResourceCreateKind.document => const Color(0xff22c55e),
    };
    final title = switch (kind) {
      ResourceCreateKind.note => t('笔记', 'Note'),
      ResourceCreateKind.article => t('文章', 'Article'),
      ResourceCreateKind.bookmark => t('书签', 'Bookmark'),
      ResourceCreateKind.document => t('文档', 'Document'),
    };
    final description = switch (kind) {
      ResourceCreateKind.note => t(
        '记录想法，支持 Markdown、图片和标签',
        'Capture ideas with Markdown, images and labels',
      ),
      ResourceCreateKind.article => t(
        '撰写有标题的长篇内容',
        'Write longer content with a title',
      ),
      ResourceCreateKind.bookmark => t(
        '保存网址，按需获取网页信息',
        'Save a URL and fetch page information when needed',
      ),
      ResourceCreateKind.document => t(
        '选择书籍与目录，再创建文档',
        'Choose a book and parent before creating a document',
      ),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: .3,
      shadowColor: const Color(0x100f172a),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xffe2e8f0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).pop(kind),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 100),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    switch (kind) {
                      ResourceCreateKind.note => Icons.article_rounded,
                      ResourceCreateKind.article => Icons.edit_rounded,
                      ResourceCreateKind.bookmark =>
                        Icons.bookmark_border_rounded,
                      ResourceCreateKind.document => Icons.description_rounded,
                    },
                    color: color,
                    size: 42,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: IconButton(
        tooltip: t('关闭', 'Close'),
        icon: const Icon(Icons.close),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(t('新建资源', 'Create resource')),
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            t('取消', 'Cancel'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const SizedBox(height: 8),
          Text(
            t('选择资源类型', 'Choose a resource type'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            t(
              '从想法开始，选择合适的记录方式。',
              'Start with an idea and choose how to capture it.',
            ),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          for (final kind in ResourceCreateKind.values) _card(context, kind),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    t(
                      '笔记与文章默认私有，书签可选择公开；文档继承所属书籍的访问范围。',
                      'New notes and articles are private by default. Bookmarks can be public. Documents inherit access from their book.',
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
