import 'package:flutter/material.dart';
import '../../core/local_article_draft_archive.dart';
import 'article_draft_archive_view.dart';

/// Existing-ID facade preserves the accepted v3 route and typed result.
class LocalArticleDraftArchivePage extends StatelessWidget {
  const LocalArticleDraftArchivePage({
    super.key,
    required this.archive,
    this.prepareRestore,
    this.isCurrentScope,
    this.english = false,
  });
  final LocalArchivedArticle archive;
  final Future<LocalArticleDraftRestoreApproval> Function()? prepareRestore;
  final bool Function()? isCurrentScope;
  final bool english;
  @override
  Widget build(BuildContext context) =>
      ArticleDraftArchiveView<LocalArticleDraftRestoreApproval>(
        title: archive.edit.title,
        document: archive.edit.document,
        prepareRestore: prepareRestore,
        isCurrentScope: isCurrentScope,
        english: english,
      );
}
