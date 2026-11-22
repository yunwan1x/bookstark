import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_legacy_upload_alias_policy.dart';

void main() {
  final origin = Uri.parse('https://${'a' * 32}.bookstark-local.invalid');
  final policy = LegacyUploadAliasPolicy(isolatedOrigin: origin);
  test('relative and exact-origin requests select the same root file', () {
    expect(
      policy.canonicalPath('/upload-files/editor/a.png'),
      '/upload-files/editor/a.png',
    );
    expect(
      policy.canonicalPath('$origin/upload-files/editor/a.png'),
      '/upload-files/editor/a.png',
    );
    expect(
      policy.canonicalPath('${origin.origin}:443/upload-files/editor/a.png'),
      '/upload-files/editor/a.png',
    );
    expect(
      policy.canonicalPath('/upload-files/editor/a.png?v=123#image'),
      '/upload-files/editor/a.png',
    );
  });
  test(
    'existing editor origin is supported without trusting any other session',
    () {
      final editor = LegacyUploadAliasPolicy(
        isolatedOrigin: Uri.parse(
          'https://${'b' * 32}.bookstark-editor.invalid',
        ),
      );
      expect(editor.canonicalPath('/upload-files/x'), '/upload-files/x');
      expect(editor.canonicalPath('$origin/upload-files/x'), isNull);
    },
  );
  test(
    'Unicode spaces plus and literal pchar names use the same construction as the upload plan',
    () {
      for (final name in [
        '预览🙂.png',
        'space plus+.png',
        'a@b.png',
        'literal!()name.png',
        '∕fullwidth／.png',
      ]) {
        final expected = Uri(
          pathSegments: ['', 'upload-files', 'editor', name],
        ).path;
        expect(policy.canonicalPath(expected), expected, reason: name);
      }
    },
  );
  test('all initial BOMs survive strict decoding in every path segment', () {
    for (final name in ['\ufeffx.png', '\ufeff\ufeffx🙂.png']) {
      final expected = Uri(pathSegments: ['', 'upload-files', name]).path;
      expect(policy.canonicalPath(expected), expected);
      expect(policy.canonicalPath(expected.toLowerCase()), expected);
    }
  });
  test(
    'percent escape case is canonical while ordinary filename case remains exact',
    () {
      expect(
        policy.canonicalPath('/upload-files/%e6%b1%89.PNG'),
        '/upload-files/%E6%B1%89.PNG',
      );
      expect(
        policy.canonicalPath('/upload-files/File.PNG'),
        '/upload-files/File.PNG',
      );
    },
  );
  for (final url in [
    'https://evil.invalid/upload-files/x',
    'https://${'c' * 32}.bookstark-local.invalid/upload-files/x',
    'http://${origin.host}/upload-files/x',
    'https://${origin.host}:444/upload-files/x',
    'https://user:pass@${origin.host}/upload-files/x',
    '//${origin.host}/upload-files/x',
    'file:///upload-files/x',
    'content:///upload-files/x',
    'data:image/png;base64,AA==',
    'upload-files/x',
    '../upload-files/x',
    '/UPLOAD-FILES/x',
    '/upload-files/',
    '/upload-files//x',
    '/upload-files/a/',
    '/upload-files/../x',
    '/upload-files/a/../x',
    '$origin/upload-files/a/../x',
    '$origin/upload-files/./x',
    '/upload-files/./x',
    '/upload-files/%2e%2E/x',
    '/upload-files/%252e%252e/x',
    '/upload-files/a%2fb.png',
    '/upload-files/a%5Cb.png',
    '/upload-files/a%00b.png',
    '/upload-files/a%1fb.png',
    '/upload-files/a%7Fb.png',
    '/upload-files/a%25b.png',
    '/upload-files/a%3Fb.png',
    '/upload-files/a%23b.png',
    '/upload-files/a%3Ab.png',
    '/upload-files/%C0%AF.png',
    '/upload-files/%ED%A0%80.png',
    '/upload-files/%FF.png',
    '/upload-files/%',
    '/upload-files/%0',
    '/upload-files/%xy',
    '/upload-files/a\\b.png',
    '/upload-files/a\nb.png',
    '/upload-files/\uD800.png',
    '/upload-files/\uDC00.png',
    'https://@${origin.host}/upload-files/x',
  ]) {
    test('rejects unsafe alias $url', () {
      expect(policy.canonicalPath(url), isNull);
    });
  }
  test('overlong inputs are rejected before URI decoding', () {
    expect(policy.canonicalPath('/upload-files/${'x' * 8192}'), isNull);
    expect(policy.canonicalPath('/upload-files/${'x' * 4096}'), isNull);
  });
  test(
    'external, nonrandom, credentialed or path-bearing origins are invalid configuration',
    () {
      for (final value in [
        'https://example.com',
        'https://bookstark-local.invalid',
        'http://${origin.host}',
        'https://${origin.host}/sub',
        'https://${origin.host}?x=1',
        'https://user:pass@${origin.host}',
        'https://${origin.host}:444',
      ]) {
        expect(
          () => LegacyUploadAliasPolicy(isolatedOrigin: Uri.parse(value)),
          throwsArgumentError,
        );
      }
    },
  );
}
