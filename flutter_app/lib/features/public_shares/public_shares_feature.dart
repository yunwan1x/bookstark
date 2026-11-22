import '../../core/protected_shared_services.dart';
import '../speech/local_speech_provider_page.dart';
import '../../core/native_complex_source_io.dart';
import '../../core/anonymous_shared_capability.dart';
import '../../core/public_edit_link.dart';
import '../../core/public_complex_source.dart';
import 'open_shared_complex.dart';
import '../../core/public_edit_repository.dart';
import 'share_edit_link_page.dart';
import '../../core/share_comments_repository.dart';
import 'share_comments_page.dart';
import 'package:flutter/material.dart';
import '../../core/api_client.dart';
import '../../core/public_feed_models.dart';
import '../../core/public_feed_repository.dart';
import '../../core/public_share_attachments.dart';
import '../../core/public_share_models.dart';
import '../../core/public_shares_repository.dart';
import '../../widgets/bookstark_markdown.dart';
import '../public_feed/public_feed_page.dart';
import 'share_reader_page.dart';
import 'share_book_page.dart';
import 'share_chapter_page.dart';

class PublicSharesFeature extends StatefulWidget {
  const PublicSharesFeature({
    super.key,
    required this.client,
    required this.onCreate,
    required this.onSpeak,
    this.english = false,
    this.onSpeakSelection,
    this.dispatchSourceFactory,
    this.anonymousClientFactory,
    this.sharedCapabilityFactory,
    this.initialReference,
    this.isCurrentScope,
    this.sourceIoScope,
    this.protectedServices,
  });
  final AnonymousPublicComplexSource Function(bool Function())?
  dispatchSourceFactory;
  final BookstarkClient Function(Uri)? anonymousClientFactory;
  final AnonymousSharedCapability Function(PublicEditLink, bool Function())?
  sharedCapabilityFactory;
  final Future<void> Function(LocalSpeechSelection, String, String)?
  onSpeakSelection;
  final BookstarkClient client;
  final Future<void> Function() onCreate;
  final Future<void> Function(String markdown, String title, String context)
  onSpeak;
  final bool english;
  final PublicShareReference? initialReference;
  final bool Function()? isCurrentScope;
  final ComplexSourceIoScope? sourceIoScope;
  final ProtectedSharedServices? protectedServices;
  @override
  State<PublicSharesFeature> createState() => _PublicSharesFeatureState();
}

class _PublicSharesFeatureState extends State<PublicSharesFeature> {
  late final _anonymousClient =
      widget.anonymousClientFactory?.call(widget.client.baseUri) ??
      BookstarkClient(widget.client.baseUri.toString());
  late final _repository = RemotePublicSharesRepository(_anonymousClient);
  late final _attachments = PublicShareAttachments(widget.client.baseUri);
  @override
  void initState() {
    super.initState();
    final reference = widget.initialReference;
    if (reference != null) {
      if (reference.server != widget.client.baseUri) {
        throw const FormatException('Share server mismatch');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openReference(reference);
      });
    }
  }

  @override
  void dispose() {
    _attachments.close();
    _anonymousClient.close();
    super.dispose();
  }

  bool _current() => mounted && (widget.isCurrentScope?.call() ?? true);

  Future<void> _edit() async {
    if (!_current()) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareEditLinkPage(
          server: widget.client.baseUri,
          repository: RemotePublicEditRepository(
            widget.client,
            isCurrentScope: _current,
            capabilityFactory: widget.sharedCapabilityFactory,
            sourceFactory: widget.dispatchSourceFactory,
          ),
          openComplex: (context, link) => openSharedComplex(
            context,
            link: link,
            isCurrentScope: _current,
            onReturnToReader: () => _openReference(link.reference),
            sourceFactory: widget.dispatchSourceFactory,
            sourceIoScope: widget.sourceIoScope,
            protectedServices: widget.protectedServices,
            markdownAttachments: _attachments,
            capabilityFactory: widget.sharedCapabilityFactory,
            english: widget.english,
          ),
          shares: _repository,
          attachments: _attachments,
          english: widget.english,
        ),
      ),
    );
  }

  Future<void> _comments(PublicShareDetail detail) async {
    if (!_current()) return;
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
  }

  Future<void> _book(PublicShareDetail book) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareBookPage(
          reference: book.reference,
          repository: _repository,
          english: widget.english,
          onOpen: (current, node) async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => ShareChapterPage(
                  book: current,
                  identify: node.identify,
                  repository: _repository,
                  attachments: _attachments,
                  english: widget.english,
                  onSpeak: widget.onSpeak,
                  onSpeakSelection: widget.onSpeakSelection,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _open(PublicFeedItem item) async {
    if (item.kind == PublicFeedKind.bookmark) {
      await openBookstarkLink(
        context,
        item.title,
        item.externalUri.toString(),
        repository: _attachments,
        english: widget.english,
      );
      return;
    }
    final reference = PublicShareReference(
      widget.client.baseUri,
      item.shareIdentify!,
    );
    await _openReference(reference);
  }

  Future<void> _openReference(PublicShareReference reference) async {
    if (!_current()) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ShareReaderPage(
          dispatchSourceFactory: widget.dispatchSourceFactory,
          reference: reference,
          isCurrentScope: _current,
          repository: _repository,
          attachments: _attachments,
          english: widget.english,
          onSpeak: widget.onSpeak,
          onSpeakSelection: widget.onSpeakSelection,
          onBook: _book,
          onComments: _comments,
          onEditLink: _edit,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PublicFeedPage(
    repository: RemotePublicFeedRepository(_anonymousClient),
    english: widget.english,
    onOpen: _open,
    onCreate: widget.onCreate,
  );
}
