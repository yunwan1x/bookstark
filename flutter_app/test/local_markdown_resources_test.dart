import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:bookstark_flutter/core/local_attachments.dart';
import 'package:bookstark_flutter/core/local_markdown_resources.dart';

void main() {
  late Directory root;
  late LocalMarkdownResources resources;
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
  );
  String id(int n) => n.toRadixString(16).padLeft(32, '0');
  Uri uri(int n, [String name = 'image.png']) => Uri.parse(
    'bookstark-attachment:///${id(n)}/${Uri.encodeComponent(name)}',
  );
  Future<void> write(int n, List<int> bytes) =>
      File(p.join(root.path, id(n))).writeAsBytes(bytes).then((_) {});

  setUp(() async {
    root = await Directory.systemTemp.createTemp('bookstark-local-md-');
    resources = LocalMarkdownResources(LocalAttachments(root));
  });
  tearDown(() async {
    resources.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'private raster bytes use content type and canonical identity cache',
    () async {
      await write(1, png);
      final value = await resources.read(uri(1, 'untrusted.svg'));
      expect(value.mime, 'image/png');
      expect(value.bytes, png);
      await File(p.join(root.path, id(1))).delete();
      expect(
        identical(await resources.read(uri(1, 'alias.jpg')), value),
        isTrue,
      );
      expect(resources.loaded, 1);
      resources.close();
      await expectLater(resources.read(uri(1)), throwsStateError);
    },
  );

  test(
    'HTTP, credentials, path tricks and unknown files cannot cross boundary',
    () async {
      await write(1, png);
      final prefix = 'bookstark-attachment:///${id(1)}/';
      for (final text in [
        'https://example.test/image.png',
        'file:///etc/passwd',
        'content://provider/image',
        'bookstark-attachment://host/${id(1)}/image.png',
        '${prefix}image.png?secret=1',
        '${prefix}image.png#fragment',
        '$prefix%2e%2e',
        '${prefix}a%2fb.png',
        '${prefix}a%5cb.png',
        '${prefix}a%00.png',
      ]) {
        await expectLater(
          resources.read(Uri.parse(text)),
          throwsFormatException,
        );
      }
      await expectLater(resources.read(uri(2)), throwsFormatException);
      expect(resources.loaded, 0);
    },
  );

  test('SVG, HTML and disguised scripts are not image responses', () async {
    for (final text in [
      '<svg xmlns="http://www.w3.org/2000/svg"/>',
      '<html><script>1</script></html>',
      'GIF89',
    ]) {
      final n = text.length;
      await write(n, utf8.encode(text));
      await expectLater(resources.read(uri(n)), throwsFormatException);
    }
    expect(resources.loaded, 0);
    expect(resources.failed, 3);
  });

  test('both file and ancestor symlinks are refused', () async {
    final outside = await Directory.systemTemp.createTemp(
      'bookstark-local-md-outside-',
    );
    try {
      final file = await File(p.join(outside.path, 'image')).writeAsBytes(png);
      await Link(p.join(root.path, id(1))).create(file.path);
      await expectLater(resources.read(uri(1)), throwsFormatException);
      await Link(p.join(root.path, 'linked')).create(outside.path);
      final linked = LocalMarkdownResources(
        LocalAttachments(Directory(p.join(root.path, 'linked'))),
      );
      await File(p.join(outside.path, id(2))).writeAsBytes(png);
      await expectLater(linked.read(uri(2)), throwsFormatException);
      linked.close();
    } finally {
      await outside.delete(recursive: true);
    }
  });

  test('single image bound is enforced before returning bytes', () async {
    final bytes = Uint8List(LocalMarkdownResources.maxImageBytes + 1)
      ..setRange(0, png.length, png);
    await write(1, bytes);
    await expectLater(resources.read(uri(1)), throwsA(anything));
    expect(resources.loaded, 0);
    expect(resources.failed, 1);
  });

  test(
    'total budget cannot be bypassed by individually bounded images',
    () async {
      final bytes = Uint8List(LocalMarkdownResources.maxImageBytes)
        ..setRange(0, png.length, png);
      for (var n = 1; n <= 5; n++) {
        await write(n, bytes);
        if (n <= 4) {
          expect((await resources.read(uri(n))).bytes.length, bytes.length);
        } else {
          await expectLater(resources.read(uri(n)), throwsStateError);
        }
      }
      expect(resources.loaded, 4);
    },
  );

  test(
    'count limit cannot be bypassed with names; aliases share one slot',
    () async {
      for (var n = 1; n <= LocalMarkdownResources.maxImages; n++) {
        await write(n, png);
        await resources.read(uri(n));
      }
      await write(33, png);
      await expectLater(resources.read(uri(33)), throwsStateError);
      expect((await resources.read(uri(1, 'second-name.png'))).bytes, png);
      expect(resources.loaded, LocalMarkdownResources.maxImages);
    },
  );
  test(
    'raster header bounds reject disproportionate decode dimensions',
    () async {
      final bytes = Uint8List.fromList(png);
      ByteData.sublistView(bytes).setUint32(16, 32768);
      await write(1, bytes);
      await expectLater(resources.read(uri(1)), throwsFormatException);
      expect(resources.loaded, 0);
    },
  );

  test(
    'aggregate decoded pixels are bounded independently of compressed bytes',
    () async {
      final bytes = Uint8List.fromList(png);
      final header = ByteData.sublistView(bytes);
      header.setUint32(16, 4096);
      header.setUint32(20, 4096);
      for (var n = 1; n <= 3; n++) {
        await write(n, bytes);
        if (n < 3) {
          await resources.read(uri(n));
        } else {
          await expectLater(resources.read(uri(n)), throwsStateError);
        }
      }
      expect(resources.loaded, 2);
    },
  );
}
