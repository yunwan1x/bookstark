import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_html_attachment_resources.dart';

void main() {
  test('ordinary file link is not a render grant and needs exact source href', () async {
    final dir = await Directory.systemTemp.createTemp('html-local-file-');
    try {
      const id = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
      const reference = 'bookstark-attachment:///$id/manual.pdf';
      final original = utf8.encode('%PDF-1.4 fixture');
      await File('${dir.path}/$id').writeAsBytes(original, flush: true);
      final resources = LocalHtmlAttachmentResources(
        attachments: LocalAttachments(dir),
        source: '<a href="$reference">Manual</a>',
        scopeIdentity: 'ordinary-local-note-4',
        isCurrentScope: () => true,
      );
      expect(resources.references, isEmpty);
      expect(await resources.read(Uri.parse(reference)), isNull);
      final linked = await resources.readReferencedFile(Uri.parse(reference));
      expect(linked.name, 'manual.pdf');
      expect(linked.bytes, orderedEquals(original));
      expect(linked.sha256Hex, hasLength(64));
      expect(() => resources.readReferencedFile(Uri.parse(
        'bookstark-attachment:///ffffffffffffffffffffffffffffffff/other.pdf')),
        throwsStateError);
      await resources.retireAndDrain();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('actual local raster bytes are frozen and source-bound', () async {
    final dir = await Directory.systemTemp.createTemp('html-local-raster-');
    try {
      const id = 'cccccccccccccccccccccccccccccccc';
      const reference = 'bookstark-attachment:///$id/c.png';
      final original = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jL1sAAAAASUVORK5CYII=');
      await File('${dir.path}/$id').writeAsBytes(original, flush: true);
      final resources = LocalHtmlAttachmentResources(
        attachments: LocalAttachments(dir),
        source: '<img src="$reference">',
        scopeIdentity: 'ordinary-local-note-3',
        isCurrentScope: () => true,
      );
      final result = await resources.read(Uri.parse(reference));
      expect(result, isNotNull);
      expect(result!.mime, 'image/png');
      expect(result.bytes, orderedEquals(original));
      expect(result.sha256Hex, hasLength(64));
      expect(() => result.bytes[0] = 0, throwsUnsupportedError);
      expect(await resources.read(Uri.parse(
        'bookstark-attachment:///dddddddddddddddddddddddddddddddd/d.png')), isNull);
      await resources.retireAndDrain();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('only actual image attributes grant attachment reads', () async {
    final dir = await Directory.systemTemp.createTemp('html-local-refs-');
    try {
      const uri = 'bookstark-attachment:///aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/a.png';
      final resources = LocalHtmlAttachmentResources(
        attachments: LocalAttachments(dir),
        source: '<!-- <img src="$uri"> --><script>"<img src=\\"$uri\\">"</script>'
            '<a href="$uri">file</a>',
        scopeIdentity: 'ordinary-local-note-1',
        isCurrentScope: () => true,
      );
      expect(resources.references, isEmpty);
      expect(await resources.read(Uri.parse(uri)), isNull);
      expect(await resources.read(Uri.parse('https://example.invalid/a.png')), isNull);
      await resources.retireAndDrain();
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('source reference remains exact and retirement rejects reads', () async {
    final dir = await Directory.systemTemp.createTemp('html-local-retire-');
    try {
      const uri = 'bookstark-attachment:///bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/b.png';
      var current = true;
      final resources = LocalHtmlAttachmentResources(
        attachments: LocalAttachments(dir),
        source: '<img src="$uri">',
        scopeIdentity: 'ordinary-local-article-2',
        isCurrentScope: () => current,
      );
      expect(resources.references, {uri});
      current = false;
      expect(() => resources.read(Uri.parse(uri)), throwsStateError);
      await resources.retireAndDrain();
      expect(() => resources.read(Uri.parse(uri)), throwsStateError);
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
