import 'dart:convert';

enum PublicShareKind { blog, book, document }

bool _wellFormed(String value) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) return false;
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}

bool _validIdentifier(String value) =>
    value.isNotEmpty &&
    value.length <= 2000 &&
    value != '.' &&
    value != '..' &&
    _wellFormed(value) &&
    !value.codeUnits.any(
      (unit) => unit <= 0x1f || unit == 0x7f || unit == 0x2f || unit == 0x5c,
    );

class PublicShareReference {
  static bool validIdentify(String value) => _validIdentifier(value);
  PublicShareReference(Uri server, this.identify)
    : server = server.replace(
        path: server.path.replaceFirst(RegExp(r'/+$'), ''),
      ) {
    if (!{'http', 'https'}.contains(server.scheme) ||
        server.host.isEmpty ||
        server.userInfo.isNotEmpty ||
        server.hasQuery ||
        server.hasFragment ||
        !_validIdentifier(identify)) {
      throw const FormatException('Invalid public share reference');
    }
  }
  final Uri server;
  final String identify;
  String get detailPath => '/api/shares/${Uri.encodeComponent(identify)}';
  String get rawPath => '$detailPath/content/raw';
  Uri get canonicalUri => server.replace(
    path: '${server.path}/shares/${Uri.encodeComponent(identify)}',
  );
  String chapterPath(String identify) {
    if (!_validIdentifier(identify)) {
      throw const FormatException('Invalid public chapter identifier');
    }
    return '$detailPath/docs/${Uri.encodeComponent(identify)}';
  }

  void validateRawPath(String supplied, {String? chapterIdentify}) {
    final uri = Uri.tryParse(supplied);
    if (uri == null) throw const FormatException('Invalid public content URL');
    if (supplied.startsWith('//') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.hasAuthority &&
            (uri.scheme != server.scheme ||
                uri.host != server.host ||
                uri.port != server.port) ||
        uri.hasScheme && !uri.hasAuthority) {
      throw const FormatException('Invalid public content origin');
    }
    final expected = Uri.parse(
      chapterIdentify == null
          ? rawPath
          : '${chapterPath(chapterIdentify)}/content/raw',
    ).pathSegments;
    final actual = uri.pathSegments;
    bool same(List<String> a, List<String> b) =>
        a.length == b.length &&
        List.generate(
          a.length,
          (index) => a[index] == b[index],
        ).every((equal) => equal);
    if (!uri.path.startsWith('/') ||
        !same(actual, expected) &&
            !same(actual, [...server.pathSegments, ...expected])) {
      throw const FormatException('Public content path changed its context');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PublicShareReference &&
      other.server == server &&
      other.identify == identify;
  @override
  int get hashCode => Object.hash(server, identify);
}

class PublicShareNode {
  PublicShareNode._({
    required this.id,
    required this.parentId,
    required this.identify,
    required this.name,
    required this.format,
    required List<PublicShareNode> children,
  }) : children = List.unmodifiable(children);
  final int id, parentId;
  final String identify, name, format;
  final List<PublicShareNode> children;
}

String _text(Object? value, {int max = 4096, String? fallback}) {
  if (value == null && fallback != null) return fallback;
  if (value is! String || value.length > max || !_wellFormed(value)) {
    throw const FormatException('Invalid public share text');
  }
  return value;
}

List<PublicShareNode> _tree(Object? value) {
  final ids = <int>{}, identifies = <String>{};
  List<PublicShareNode> visit(Object? value, int parent, int depth) {
    if (value == null) return [];
    if (value is! List || depth > 256) {
      throw const FormatException('Invalid public book tree');
    }
    return value.map((row) {
      if (row is! Map ||
          row['document_id'] is! int ||
          row['parent_id'] is! int ||
          row['identify'] is! String) {
        throw const FormatException('Invalid public chapter metadata');
      }
      final id = row['document_id'] as int,
          identify = row['identify'] as String;
      if (id <= 0 ||
          row['parent_id'] != parent ||
          !ids.add(id) ||
          !_validIdentifier(identify) ||
          !identifies.add(identify) ||
          ids.length > 10000) {
        throw const FormatException('Ambiguous public chapter membership');
      }
      return PublicShareNode._(
        id: id,
        parentId: parent,
        identify: identify,
        name: _text(row['document_name']),
        format: _text(row['doc_type'], fallback: '', max: 128),
        children: visit(row['children'], id, depth + 1),
      );
    }).toList();
  }

  return List.unmodifiable(visit(value, 0, 0));
}

/// Public data is separate from owner/editor records. Protected payload fields
/// are discarded before any widget or semantic tree receives this object.
class PublicShareDetail {
  PublicShareDetail._({
    required this.reference,
    required this.kind,
    required this.shareId,
    required this.targetId,
    required this.title,
    required this.author,
    required this.format,
    required this.protected,
    required this.unlocked,
    required this.content,
    required this.description,
    required List<String> labels,
    required List<PublicShareNode> nodes,
    required this.rawAvailable,
    this.blogType,
    this.sharedAt,
    this.documentCount,
  }) : labels = List.unmodifiable(labels),
       nodes = List.unmodifiable(nodes);
  final PublicShareReference reference;
  final PublicShareKind kind;
  final int shareId, targetId;
  final String title, author, format, content, description;
  final String? blogType;
  final bool protected, unlocked, rawAvailable;
  final DateTime? sharedAt;
  final int? documentCount;
  final List<String> labels;
  final List<PublicShareNode> nodes;
  bool get locked => protected && !unlocked;
  bool get markdown => format == 'markdown';
  bool get html => format == 'html';

  factory PublicShareDetail.fromJson(
    PublicShareReference reference,
    Map<String, Object?> row,
  ) {
    final type = row['share_type'];
    if (type is! String ||
        !PublicShareKind.values.any((kind) => kind.name == type) ||
        row['share_id'] is! int ||
        row['target_id'] is! int ||
        row['has_password'] is! bool ||
        row['share_identify'] != reference.identify) {
      throw const FormatException('Invalid public share identity');
    }
    final kind = PublicShareKind.values.byName(type),
        shareId = row['share_id'] as int,
        targetId = row['target_id'] as int;
    if (targetId <= 0 ||
        shareId == 0 ||
        shareId < 0 && (kind != PublicShareKind.blog || -shareId != targetId)) {
      throw const FormatException('Invalid actual public share IDs');
    }
    final locked = row['has_password'] as bool,
        format = _text(row['doc_type'], fallback: '', max: 128);
    final rawTime = _text(row['share_time'], fallback: '', max: 128);
    final time = rawTime.isEmpty ? null : DateTime.tryParse(rawTime);
    if (rawTime.isNotEmpty && time == null) {
      throw const FormatException('Invalid public share date');
    }
    final blogType = row['blog_type'];
    if (blogType != null &&
        blogType != '' &&
        !{'note', 'article'}.contains(blogType)) {
      throw const FormatException('Unknown public blog collection');
    }
    final labels = <String>[];
    if (!locked && row['labels'] != null) {
      final values = row['labels'];
      if (values is! List || values.length > 1024) {
        throw const FormatException('Invalid public label list');
      }
      for (final value in values) {
        labels.add(_text(value, max: 1000));
      }
    }
    final count = row['doc_count'];
    if (count != null && (count is! int || count < 0)) {
      throw const FormatException('Invalid reported document count');
    }
    var raw = false;
    if (!locked &&
        {'html', 'richdoc'}.contains(format) &&
        row['content_url'] != null) {
      reference.validateRawPath(_text(row['content_url']));
      raw = true;
    }
    final content = locked
        ? ''
        : _text(row['content'], fallback: '', max: 4 * 1024 * 1024);
    if (utf8.encode(content).length > 4 * 1024 * 1024) {
      throw const FormatException('Public content exceeds the read limit');
    }
    return PublicShareDetail._(
      reference: reference,
      kind: kind,
      shareId: shareId,
      targetId: targetId,
      title: _text(row['title']),
      author: _text(row['author'], fallback: '', max: 1024),
      format: format,
      protected: locked,
      unlocked: false,
      content: content,
      description: locked ? '' : _text(row['description'], fallback: ''),
      labels: labels,
      nodes: locked || kind != PublicShareKind.book
          ? []
          : _tree(row['doc_tree']),
      rawAvailable: raw,
      blogType: blogType == null || blogType == '' ? null : blogType as String,
      sharedAt: time,
      documentCount: kind == PublicShareKind.book ? count as int? : null,
    );
  }
  PublicShareDetail withHtmlContent(String value, {bool unlocking = false}) {
    if (!html ||
        kind == PublicShareKind.book ||
        (unlocking ? !locked || kind != PublicShareKind.blog : locked) ||
        !_wellFormed(value) ||
        utf8.encode(value).length > 5 * 1024 * 1024) {
      throw const FormatException('Invalid public HTML content state');
    }
    return PublicShareDetail._(
      reference: reference,
      kind: kind,
      shareId: shareId,
      targetId: targetId,
      title: title,
      author: author,
      format: format,
      protected: protected,
      unlocked: unlocking || unlocked,
      content: value,
      description: unlocking ? '' : description,
      labels: unlocking ? [] : labels,
      nodes: [],
      rawAvailable: !unlocking && rawAvailable,
      blogType: blogType,
      sharedAt: sharedAt,
      documentCount: documentCount,
    );
  }

  /// Source-free proof from the anonymous complex loader. Never changes kind,
  /// target or grants editing; actual body stays in the readonly engine.
  PublicShareDetail withVerifiedComplexReadability() {
    if (!{
          'spreadsheet',
          'drawing',
          'mindmap',
          'richdoc',
          'presentation',
        }.contains(format) ||
        kind == PublicShareKind.book) {
      throw StateError('Not complex readable content');
    }
    return PublicShareDetail._(
      reference: reference,
      kind: kind,
      shareId: shareId,
      targetId: targetId,
      title: title,
      author: author,
      format: format,
      protected: protected,
      unlocked: protected || unlocked,
      content: '',
      description: description,
      labels: labels,
      nodes: nodes,
      rawAvailable: rawAvailable,
      blogType: blogType,
      sharedAt: sharedAt,
      documentCount: documentCount,
    );
  }

  PublicShareDetail unlockMarkdown(String content) {
    if (!locked ||
        kind != PublicShareKind.blog ||
        !markdown ||
        !_wellFormed(content) ||
        utf8.encode(content).length > 4 * 1024 * 1024) {
      throw StateError('This share cannot accept a Markdown unlock result');
    }
    return PublicShareDetail._(
      reference: reference,
      kind: kind,
      shareId: shareId,
      targetId: targetId,
      title: title,
      author: author,
      format: format,
      protected: true,
      unlocked: true,
      content: content,
      description: '',
      labels: [],
      nodes: [],
      rawAvailable: false,
      blogType: blogType,
      sharedAt: sharedAt,
    );
  }
}
