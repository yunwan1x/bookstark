import 'anonymous_shared_capability.dart';
import 'api_client.dart';
import 'complex_editor_document.dart';
import 'protected_shared_identity.dart';
import 'protected_shared_journal.dart';
import 'protected_shared_lifetime.dart';
import 'public_edit_link.dart';
import 'public_edit_repository.dart';
import 'public_edit_snapshot.dart';
import 'public_share_models.dart';

/// Exact anonymous capability transport; no account BookstarkClient argument.
class ProtectedSharedMarkdownRepository
    implements PublicEditRepository, RetirablePublicEditRepository {
  ProtectedSharedMarkdownRepository({
    required this.owner,
    required this.journal,
    required this.initial,
    required this.password,
  });
  final ProtectedSharedLifetime owner;
  final ProtectedSharedJournal journal;
  final SharedCapabilitySource initial;
  String? password;
  final _owned = Expando<SharedCapabilitySource>();
  void _guard(PublicEditLink link) {
    if (!owner.current || link != owner.transport.link) {
      throw StateError('Protected shared Markdown owner retired');
    }
  }

  @override
  Future<PublicEditSnapshot> read(
    PublicEditLink link, {
    String? password,
    Future<void>? abortTrigger,
  }) async {
    _guard(link);
    abortTrigger?.then((_) {
      if (owner.current) owner.transport.close();
    });
    final source = await owner.transport.read(password: this.password);
    _guard(link);
    if (!source.identity.same(initial.identity) ||
        protectedSharedIdentity(source.identity) != journal.identity ||
        source.identity.kind != ComplexEditorKind.markdown ||
        !source.identity.protected) {
      throw StateError('Protected shared Markdown identity changed');
    }
    final key = source.identity;
    var detail = PublicShareDetail.fromJson(link.reference, {
      'share_type': key.shareType,
      'share_id': key.shareId,
      'target_id': key.targetId,
      'share_identify': link.reference.identify,
      'has_password': true,
      'doc_type': 'markdown',
      'blog_type': key.collection,
      'title': source.title,
      'content': '',
    });
    detail = detail.unlockMarkdown(source.document.source);
    final snapshot = PublicEditSnapshot.parse(detail, {
      'editable': true,
      'has_password': true,
      'share_type': key.shareType,
      'doc_type': 'markdown',
      'blog_type': key.collection,
      'title': source.title,
      'content': source.document.source,
      'modify_time': source.modified,
    });
    _owned[snapshot] = source;
    return snapshot;
  }

  @override
  Future<PublicEditReceipt> save(
    PublicEditLink link,
    PublicEditSnapshot baseline,
    String content, {
    String? password,
  }) async {
    _guard(link);
    validateSharedMarkdown(content);
    final source = _owned[baseline];
    if (source == null || baseline.locked) {
      throw StateError('Exact protected baseline required');
    }
    final document = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      content,
    );
    final prepared = await owner.transport.prepare(
      source,
      document,
      password: this.password,
    );
    try {
      final receipt = await prepared.sendAfter(
        onSubmit: () async {
          _guard(link);
          await journal.claimUnknown(
            expectedSource: source.document.digest,
            submittedSource: document.digest,
          );
          _guard(link);
        },
      );
      _guard(link);
      final modified = receipt['modify_time'];
      if (receipt['source_sha256'] != document.digest ||
          modified is! String ||
          modified.isEmpty ||
          modified.length > 128 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(modified)) {
        throw StateError(
          'Protected Markdown receipt requires read-only review',
        );
      }
      journal.rememberKnown(sourceDigest: document.digest, modified: modified);
      await journal.persistKnown();
      return PublicEditReceipt(link.reference, modified);
    } on SharedCapabilityFailure catch (error) {
      throw ApiFailure(error.status, 'Protected shared save needs review');
    } finally {
      prepared.retire();
    }
  }

  @override
  void retire(PublicEditLink link) {
    if (link != owner.transport.link) return;
    password = null;
    owner.transport.close();
  }
}
