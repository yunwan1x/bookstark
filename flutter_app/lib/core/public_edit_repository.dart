import 'dart:convert';
import 'api_client.dart';
import 'public_edit_link.dart';
import 'public_edit_snapshot.dart';
import 'public_share_models.dart';
import 'public_complex_source.dart';
import 'anonymous_shared_capability.dart';
import 'complex_editor_document.dart';

void validateSharedMarkdown(String content) {
  for (var i = 0; i < content.length; i++) {
    final unit = content.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= content.length ||
          content.codeUnitAt(i) < 0xdc00 ||
          content.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid shared Markdown Unicode');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid shared Markdown Unicode');
    }
  }
  if (utf8.encode(content).length > 500 * 1024) {
    throw const FormatException('Shared Markdown exceeds 500 KiB');
  }
}

class PublicEditReceipt {
  const PublicEditReceipt(this.reference, this.modified);
  final PublicShareReference reference;
  final String modified;
}

abstract interface class PublicEditRepository {
  Future<PublicEditSnapshot> read(
    PublicEditLink link, {
    String? password,
    Future<void>? abortTrigger,
  });
  Future<PublicEditReceipt> save(
    PublicEditLink link,
    PublicEditSnapshot baseline,
    String content, {
    String? password,
  });
}

abstract interface class RetirablePublicEditRepository {
  void retire(PublicEditLink link);
}

class RemotePublicEditRepository
    implements PublicEditRepository, RetirablePublicEditRepository {
  RemotePublicEditRepository(
    this.client, {
    bool Function()? isCurrentScope,
    AnonymousSharedCapability Function(PublicEditLink, bool Function())?
    capabilityFactory,
    this._sourceFactory,
  }) : _isCurrent = isCurrentScope ?? (() => true),
       _factory = capabilityFactory;
  final BookstarkClient
  client; // configured server identity ONLY, no cookies copied
  final bool Function() _isCurrent;
  final AnonymousPublicComplexSource Function(bool Function())? _sourceFactory;
  final AnonymousSharedCapability Function(PublicEditLink, bool Function())?
  _factory;
  final _active = <PublicEditLink, AnonymousSharedCapability>{};
  final _owned = Expando<SharedCapabilitySource>();
  AnonymousSharedCapability _cap(PublicEditLink link) {
    if (link.reference.server != client.baseUri || !_isCurrent()) {
      throw StateError('Shared scope changed');
    }
    return _active.putIfAbsent(link, () {
      late final AnonymousSharedCapability value;
      bool current() => _isCurrent() && identical(_active[link], value);
      value =
          _factory?.call(link, current) ??
          AnonymousSharedCapability(link, isCurrent: current);
      return value;
    });
  }

  PublicEditSnapshot _snapshot(
    PublicEditLink link,
    SharedCapabilitySource source,
  ) {
    if (source.identity.kind != ComplexEditorKind.markdown) {
      throw StateError('Use shared complex editor');
    }
    final key = source.identity;
    var detail = PublicShareDetail.fromJson(link.reference, {
      'share_type': key.shareType,
      'share_id': key.shareId,
      'target_id': key.targetId,
      'share_identify': link.reference.identify,
      'has_password': key.protected,
      'doc_type': 'markdown',
      'blog_type': key.collection,
      'title': source.title,
      'content': key.protected ? '' : source.document.source,
    });
    if (key.protected) detail = detail.unlockMarkdown(source.document.source);
    final snapshot = PublicEditSnapshot.parse(detail, {
      'editable': true,
      'has_password': key.protected,
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
  Future<PublicEditSnapshot> read(
    PublicEditLink link, {
    String? password,
    Future<void>? abortTrigger,
  }) async {
    final cap = _cap(link);
    // Caller close/abort retires only this exact capability transport.
    abortTrigger?.then((_) {
      if (identical(_active[link], cap)) retire(link);
    });
    try {
      return _snapshot(link, await cap.read(password: password));
    } on SharedCapabilityFailure catch (error) {
      if (error.status == 423 && password == null) {
        bool current() => _isCurrent() && identical(_active[link], cap);
        final probe =
            _sourceFactory?.call(current) ??
            AnonymousPublicComplexSource(isCurrent: current);
        try {
          final detail = await probe.inspect(link.reference);
          return PublicEditSnapshot.parse(detail, await cap.lockedMetadata());
        } finally {
          probe.close();
        }
      }
      throw ApiFailure(
        error.status,
        'Shared editing unavailable; review capability and source',
      );
    }
  }

  @override
  Future<PublicEditReceipt> save(
    PublicEditLink link,
    PublicEditSnapshot baseline,
    String content, {
    String? password,
  }) async {
    final original = _owned[baseline];
    if (original == null ||
        baseline.detail.reference != link.reference ||
        baseline.locked ||
        baseline.format != 'markdown') {
      throw StateError('Verified shared baseline required');
    }
    validateSharedMarkdown(content);
    final cap = _cap(link);
    final doc = ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      content,
    );
    final prepared = await cap.prepare(original, doc, password: password);
    try {
      final row = await prepared.sendOnce();
      final modified = row['modify_time'];
      if (row['source_sha256'] != doc.digest ||
          modified is! String ||
          modified.isEmpty ||
          modified.length > 128 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(modified)) {
        throw const FormatException(
          'Shared save receipt requires read-only review',
        );
      }
      return PublicEditReceipt(link.reference, modified);
    } on SharedCapabilityFailure catch (error) {
      throw ApiFailure(
        error.status,
        'Shared save unavailable; use read-only review',
      );
    } finally {
      prepared.retire();
    }
  }

  @override
  void retire(PublicEditLink link) {
    _active.remove(link)?.close();
  }
}
