import 'package:crypto/crypto.dart';

import 'local_legacy_json.dart';
import 'local_content_protection_format.dart';
import 'local_legacy_go_issue.dart';
import 'local_legacy_go_references.dart';
export 'local_legacy_go_issue.dart';
import 'local_legacy_zip_stage.dart';

/// Read-only inspection of the genuine Go v1 export contract. It preserves
/// every parsed field; issues block migration until an explicit recipe resolves
/// them. Successful inspection alone never means the data is ready to activate.
final class LegacyGoExport {
  const LegacyGoExport._({
    required this.sections,
    required this.counts,
    required this.issues,
    required this.sourceSha256,
  });
  final Map<String, Object?> sections;
  final Map<String, int> counts;
  final List<LegacyGoIssue> issues;
  final String sourceSha256;
  bool get requiresResolution => issues.isNotEmpty;

  static const _requiredFiles = [
    'manifest.json',
    'books.json',
    'blogs.json',
    'bookmarks.json',
    'tasks.json',
    'topics.json',
    'labels.json',
    'friend_links.json',
  ];
  static const maxJsonBytes = 64 * 1024 * 1024;

  static Future<LegacyGoExport> inspect(
    LegacyZipStage stage, {
    bool Function()? isCancelled,
  }) async {
    void check() {
      if (isCancelled?.call() == true) throw const LegacyZipStageCancelled();
    }

    check();
    final issues = <LegacyGoIssue>[];
    final sections = <String, Object?>{};
    final jsonNames = {..._requiredFiles, 'uploads.json'};
    var totalJsonBytes = 0;
    for (final name in _requiredFiles) {
      if (!stage.files.containsKey(name)) {
        _fail('Missing required legacy section');
      }
    }
    for (final file in stage.files.values) {
      if (jsonNames.contains(file.logicalName)) {
        totalJsonBytes += file.bytes;
        if (totalJsonBytes > maxJsonBytes) {
          _fail('Legacy JSON exceeds aggregate limit');
        }
      } else if (!file.logicalName.startsWith('uploads/')) {
        issues.add(
          const LegacyGoIssue(LegacyGoIssueCode.unknownEntry, 'archive'),
        );
      }
    }
    for (final name in jsonNames) {
      check();
      final file = stage.files[name];
      if (file == null) continue;
      // Check again before allocation; stage ownership is held throughout.
      if (await file.file.length() != file.bytes) {
        _fail('Legacy staged file changed');
      }
      final bytes = await file.file.readAsBytes();
      if (bytes.length != file.bytes ||
          sha256.convert(bytes).toString() != file.sha256Hex) {
        _fail('Legacy staged JSON digest changed');
      }
      sections[name] = decodeLegacyJson(bytes);
    }
    final reader = _GoReader(issues);
    final manifest = reader.object(sections['manifest.json'], 'manifest');
    reader.fields(
      manifest,
      {'version': 'i', 'export_time': 's', 'source': 's', 'stats': 'o'},
      {},
      'manifest',
    );
    if (manifest['version'] != 1 || manifest['source'] != 'bookstark') {
      _fail('Unsupported legacy export version or source');
    }
    final stats = reader.object(manifest['stats'], 'manifest.stats');
    reader.fields(
      stats,
      {
        for (final name in [
          'books',
          'documents',
          'blogs',
          'bookmarks',
          'tasks',
          'topics',
          'labels',
          'friend_links',
          'uploads',
        ])
          name: 'i',
      },
      {},
      'manifest.stats',
    );
    if (stats.values.any((value) => value is! int || value < 0)) {
      _fail('Invalid legacy export counts');
    }
    final counts = <String, int>{};
    for (final kind in [
      'books',
      'blogs',
      'bookmarks',
      'tasks',
      'topics',
      'friend_links',
    ]) {
      final rows = reader.rows(sections['$kind.json'], kind);
      counts[kind] = rows.length;
      sections['$kind.json'] = rows;
      for (var i = 0; i < rows.length; i++) {
        check();
        reader.row(kind, rows[i], '$kind[$i]');
      }
    }
    final books = sections['books.json'] as List<Map<String, Object?>>;
    counts['documents'] = books.fold<int>(
      0,
      (sum, book) => sum + (book['documents'] as List).length,
    );
    final labels = reader.object(sections['labels.json'], 'labels');
    reader.fields(labels, {'labels': 'a', 'relations': 'a'}, {}, 'labels');
    final labelRows = reader.rows(labels['labels'], 'labels.labels');
    final relations = reader.rows(labels['relations'], 'labels.relations');
    labels['labels'] = labelRows;
    labels['relations'] = relations;
    for (var i = 0; i < labelRows.length; i++) {
      reader.fields(labelRows[i], {'label_name': 's'}, {}, 'labels.labels[$i]');
    }
    for (var i = 0; i < relations.length; i++) {
      reader.fields(
        relations[i],
        {'label_name': 's', 'resource_type': 's', 'resource_identify': 's'},
        {},
        'labels.relations[$i]',
      );
    }
    counts['labels'] = labelRows.length;
    final uploads = reader.rows(sections['uploads.json'], 'uploads');
    counts['uploads'] = uploads.length;
    if (!sections.containsKey('uploads.json')) {
      issues.add(
        const LegacyGoIssue(LegacyGoIssueCode.uploadsNotIncluded, 'uploads'),
      );
    } else {
      sections['uploads.json'] = uploads;
    }
    final referencedFiles = <String>{};
    final declaredUploads = <String>{};
    for (var i = 0; i < uploads.length; i++) {
      check();
      final upload = uploads[i];
      final location = 'uploads[$i]';
      reader.fields(
        upload,
        {
          'file_name': 's',
          'storage_path': 's',
          'file_hash': 's',
          'file_size': 'i',
          'mime_type': 's',
          'width': 'i',
          'height': 'i',
          'thumb_path': 's',
          'thumb_size': 'i',
          'category': 's',
          'create_time': 's',
        },
        {},
        location,
      );
      final storage = upload['storage_path'] as String;
      if (!_relative(storage) || !declaredUploads.add(storage.toLowerCase())) {
        _fail('Invalid or duplicated legacy upload identity');
      }
      for (final pair in [
        ('storage_path', 'file_size'),
        ('thumb_path', 'thumb_size'),
      ]) {
        final path = upload[pair.$1] as String;
        final size = upload[pair.$2] as int;
        if (size < 0 || (path.isNotEmpty && !_relative(path))) {
          _fail('Invalid legacy upload path or size');
        }
        if (path.isEmpty) {
          if (size != 0) _fail('Legacy thumbnail size has no path');
          continue;
        }
        final logical = 'uploads/$path';
        referencedFiles.add(logical);
        final file = stage.files[logical];
        if (file == null) {
          issues.add(
            LegacyGoIssue(
              LegacyGoIssueCode.missingUpload,
              '$location.${pair.$1}',
            ),
          );
        } else if (file.bytes != size) {
          issues.add(
            LegacyGoIssue(
              LegacyGoIssueCode.uploadSizeMismatch,
              '$location.${pair.$1}',
            ),
          );
        }
        if (pair.$1 == 'storage_path') {
          final hash = upload['file_hash'] as String;
          if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
              (file != null && hash.toLowerCase() != file.sha256Hex)) {
            issues.add(
              LegacyGoIssue(LegacyGoIssueCode.uploadHashMismatch, location),
            );
          }
        }
      }
    }
    for (final file in stage.files.values) {
      if (file.logicalName.startsWith('uploads/') &&
          !referencedFiles.contains(file.logicalName)) {
        issues.add(
          const LegacyGoIssue(LegacyGoIssueCode.unreferencedUpload, 'uploads'),
        );
      }
    }
    for (final count in counts.entries) {
      if (stats[count.key] != count.value) {
        _fail('Legacy manifest count mismatch');
      }
    }
    issues.addAll(inspectLegacyGoReferences(sections));
    check();
    return LegacyGoExport._(
      sections: _freeze(sections) as Map<String, Object?>,
      counts: Map.unmodifiable(counts),
      issues: List.unmodifiable(issues),
      sourceSha256: stage.sourceSha256,
    );
  }
}

Never _fail(String message) => throw FormatException(message);

Object? _freeze(Object? value) {
  if (value is Map<String, Object?>) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key, _freeze(item))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}

bool _relative(String value) =>
    value.isNotEmpty &&
    !value.contains('\\') &&
    !value.contains(':') &&
    !value.codeUnits.any((c) => c < 32 || c == 127) &&
    !value
        .split('/')
        .any((part) => part.isEmpty || part == '.' || part == '..');

final class _GoReader {
  _GoReader(this.issues);
  final List<LegacyGoIssue> issues;
  Map<String, Object?> object(Object? value, String location) {
    if (value is! Map<String, Object?>) {
      _fail('Invalid legacy object at $location');
    }
    return value;
  }

  List<Map<String, Object?>> rows(Object? value, String location) {
    // Go nil slices are null. Declared count validation below distinguishes
    // genuine empty sections from absent/nonempty data.
    if (value == null) return [];
    if (value is! List) _fail('Invalid legacy array at $location');
    return [
      for (var i = 0; i < value.length; i++) object(value[i], '$location[$i]'),
    ];
  }

  void fields(
    Map<String, Object?> value,
    Map<String, String> required,
    Map<String, String> optional,
    String location,
  ) {
    for (final entry in required.entries) {
      if (!value.containsKey(entry.key) ||
          !_type(value[entry.key], entry.value)) {
        _fail('Invalid legacy field at $location.${entry.key}');
      }
    }
    for (final entry in value.entries) {
      final expected = required[entry.key] ?? optional[entry.key];
      if (expected == null) {
        issues.add(LegacyGoIssue(LegacyGoIssueCode.unknownField, location));
      } else if (!_type(entry.value, expected)) {
        // Do not include untrusted keys or values in diagnostics.
        _fail('Invalid optional legacy field at $location');
      }
    }
  }

  bool _type(Object? value, String type) => switch (type) {
    's' => value is String,
    'i' => value is int,
    'b' => value is bool,
    'o' => value is Map<String, Object?>,
    'a' => value == null || value is List,
    _ => false,
  };

  static const _time = {'create_time': 's', 'modify_time': 's'};

  void row(String kind, Map<String, Object?> value, String location) {
    switch (kind) {
      case 'books':
        fields(
          value,
          {
            'book_name': 's',
            'identify': 's',
            'description': 's',
            'label': 's',
            'order_index': 'i',
            'is_use_first_document': 'i',
            ..._time,
            'documents': 'a',
          },
          {},
          location,
        );
        final docs = rows(value['documents'], '$location.documents');
        value['documents'] = docs;
        for (var i = 0; i < docs.length; i++) {
          fields(
            docs[i],
            {
              'document_name': 's',
              'identify': 's',
              'parent_identify': 's',
              'order_sort': 'i',
              'doc_type': 's',
              'markdown': 's',
              'is_open': 'i',
              ..._time,
            },
            {},
            '$location.documents[$i]',
          );
        }
      case 'blogs':
        fields(
          value,
          {
            'blog_title': 's',
            'blog_identify': 's',
            'blog_content': 's',
            'password': 's',
            'blog_type': 's',
            'visibility': 'i',
            'is_pinned': 'i',
            'pin_order': 'i',
            'version': 'i',
            ..._time,
          },
          {'blog_desc': 's'},
          location,
        );
        issues.add(
          LegacyGoIssue(LegacyGoIssueCode.editorTypeMissing, location),
        );
        final password = value['password'] as String;
        final content = value['blog_content'] as String;
        if (password.isNotEmpty || content.startsWith('ENC:')) {
          issues.add(
            LegacyGoIssue(LegacyGoIssueCode.protectedContent, location),
          );
          if (!localProtectedRecordSupported(password, content)) {
            issues.add(
              LegacyGoIssue(LegacyGoIssueCode.unsupportedProtection, location),
            );
          }
        }
      case 'bookmarks':
        fields(
          value,
          {
            'title': 's',
            'url': 's',
            'description': 's',
            'favicon': 's',
            'order_sort': 'i',
            'label': 's',
            'is_public': 'i',
            'is_pinned': 'i',
            'nav_visible': 'i',
            ..._time,
          },
          {},
          location,
        );
      case 'tasks':
        fields(
          value,
          {
            'task_id': 'i',
            'content': 's',
            'due_date': 's',
            'done': 'b',
            'parent_id': 'i',
            'complete_time': 's',
            ..._time,
          },
          {'topic_id': 'i'},
          location,
        );
      case 'topics':
        fields(
          value,
          {
            'topic_id': 'i',
            'title': 's',
            'question': 's',
            'is_pinned': 'b',
            ..._time,
            'summaries': 'a',
            'resources': 'a',
          },
          {'comments': 'a'},
          location,
        );
        for (final section in ['summaries', 'resources', 'comments']) {
          if (!value.containsKey(section)) continue;
          final children = rows(value[section], '$location.$section');
          value[section] = children;
          for (var i = 0; i < children.length; i++) {
            final child = children[i];
            final childLocation = '$location.$section[$i]';
            if (section == 'summaries') {
              fields(
                child,
                {
                  'content': 's',
                  'summary_type': 's',
                  'order_sort': 'i',
                  ..._time,
                },
                {'summary_id': 'i'},
                childLocation,
              );
            } else if (section == 'resources') {
              fields(
                child,
                {
                  'resource_type': 's',
                  'target_identify': 's',
                  'title_snapshot': 's',
                  'desc_snapshot': 's',
                  'order_sort': 'i',
                  'create_time': 's',
                },
                {'topic_resource_id': 'i'},
                childLocation,
              );
            } else {
              fields(
                child,
                {
                  'target_type': 's',
                  'target_id': 'i',
                  'content': 's',
                  ..._time,
                },
                {'comment_id': 'i', 'parent_comment_id': 'i'},
                childLocation,
              );
            }
          }
        }
      case 'friend_links':
        fields(
          value,
          {
            'link_name': 's',
            'link_url': 's',
            'sort_weight': 'i',
            'is_enabled': 'i',
            ..._time,
          },
          {
            'group_name': 's',
            'group_order': 'i',
            'qr_code': 's',
            'description': 's',
          },
          location,
        );
    }
  }
}
