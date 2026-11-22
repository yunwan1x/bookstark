import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/content_password_repository.dart';
import '../../core/public_share_models.dart';
import '../../core/public_share_attachments.dart';
import '../../core/public_shares_repository.dart';
import '../../core/share_comments_repository.dart';
import '../../core/share_settings_repository.dart';
import '../public_shares/share_reader_page.dart';
import '../public_shares/share_book_page.dart';
import '../public_shares/share_chapter_page.dart';
import '../public_shares/share_comments_page.dart';
import 'content_password_page.dart';
import 'share_settings_page.dart';

Future<void> openOwnerSharing(
  BuildContext context, {
  required BookstarkClient client,
  required PublicShareKind kind,
  required int id,
  required String title,
  bool english = false,
  required Future<void> Function(String, String, String) onSpeak,
}) async {
  final passwords = RemoteContentPasswordRepository(client);
  final protection = kind == PublicShareKind.blog
      ? await passwords.read(id)
      : null;
  if (!context.mounted) {
    return;
  }
  final target = OwnerShareTarget(
    kind: kind,
    id: id,
    title: protection?.title ?? title,
    protected: protection?.protected ?? false,
  );
  final public = RemotePublicSharesRepository(client),
      attachments = PublicShareAttachments(client.baseUri);
  Future<void> openBook(PublicShareDetail book) async {
    if (!context.mounted) {
      return;
    }
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareBookPage(
          reference: book.reference,
          repository: public,
          english: english,
          onOpen: (current, node) async {
            if (!context.mounted) {
              return;
            }
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ShareChapterPage(
                  book: current,
                  identify: node.identify,
                  repository: public,
                  attachments: attachments,
                  english: english,
                  onSpeak: onSpeak,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  try {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareSettingsPage(
          target: target,
          repository: RemoteShareSettingsRepository(client),
          english: english,
          onRead: (reference) async {
            if (!context.mounted) {
              return;
            }
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ShareReaderPage(
                  reference: reference,
                  repository: public,
                  attachments: attachments,
                  english: english,
                  onSpeak: onSpeak,
                  onBook: openBook,
                  onComments: (detail) async {
                    if (!context.mounted) {
                      return;
                    }
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ShareCommentsPage(
                          detail: detail,
                          repository: RemoteShareCommentsRepository(client),
                          english: english,
                        ),
                      ),
                    );
                  },
                ),
              ),
            );
          },
          onPassword: kind != PublicShareKind.blog
              ? null
              : () async {
                  if (!context.mounted) {
                    return null;
                  }
                  return Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ContentPasswordPage(
                        id: id,
                        repository: passwords,
                        english: english,
                      ),
                    ),
                  );
                },
        ),
      ),
    );
  } finally {
    attachments.close();
  }
}
