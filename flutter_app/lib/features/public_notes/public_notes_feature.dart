import '../speech/local_speech_provider_page.dart';
import '../../core/public_complex_source.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/public_notes_repository.dart';
import '../../core/public_share_attachments.dart';
import '../../core/public_shares_repository.dart';
import '../../core/share_comments_repository.dart';
import '../public_shares/share_reader_page.dart';
import '../public_shares/share_comments_page.dart';
import 'public_notes_page.dart';

class PublicNotesFeature extends StatefulWidget {
  const PublicNotesFeature({
    super.key,
    required this.client,
    required this.onSpeak,
    this.english = false,
    this.onSpeakSelection,
    this.dispatchSourceFactory,
    this.anonymousClientFactory,
    this.isCurrentScope,
  });
  final AnonymousPublicComplexSource Function(bool Function())?
  dispatchSourceFactory;
  final BookstarkClient Function(Uri)? anonymousClientFactory;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final BookstarkClient client;
  final Future<void> Function(String, String, String) onSpeak;
  final bool english;
  final bool Function()? isCurrentScope;
  @override
  State<PublicNotesFeature> createState() => _PublicNotesFeatureState();
}

class _PublicNotesFeatureState extends State<PublicNotesFeature> {
  late final _anonymousClient =
      widget.anonymousClientFactory?.call(widget.client.baseUri) ??
      BookstarkClient(widget.client.baseUri.toString());
  late final _attachments = PublicShareAttachments(widget.client.baseUri);
  @override
  void dispose() {
    _attachments.close();
    _anonymousClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PublicNotesPage(
    repository: RemotePublicNotesRepository(_anonymousClient),
    english: widget.english,
    onOpen: (item) async {
      if (!mounted || !(widget.isCurrentScope?.call() ?? true)) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ShareReaderPage(
            dispatchSourceFactory: widget.dispatchSourceFactory,
            reference: item.reference,
            isCurrentScope: () =>
                mounted && (widget.isCurrentScope?.call() ?? true),
            repository: RemotePublicSharesRepository(_anonymousClient),
            attachments: _attachments,
            english: widget.english,
            onSpeak: widget.onSpeak,
            onSpeakSelection: widget.onSpeakSelection,
            onComments: (detail) async {
              if (!mounted) {
                return;
              }
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ShareCommentsPage(
                    detail: detail,
                    repository: RemoteShareCommentsRepository(widget.client),
                    english: widget.english,
                  ),
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
