import 'dart:convert';
import 'dart:typed_data';
import 'package:bookstark_flutter/core/image_content.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List svg(String body) => Uint8List.fromList(utf8.encode(body));
void main() {
  test(
    'actual bytes identify converted WebP independent of original file MIME',
    () {
      expect(
        imageContentMime(
          Uint8List.fromList([
            ...ascii.encode('RIFF'),
            0,
            0,
            0,
            0,
            ...ascii.encode('WEBP'),
          ]),
        ),
        'image/webp',
      );
      expect(
        imageContentMime(svg('<svg xmlns="http://www.w3.org/2000/svg"/>')),
        'image/svg+xml',
      );
      expect(imageContentMime(svg('<html>not an image</html>')), isNull);
    },
  );
  test(
    'native preview keeps gradients and internal references while preserving original',
    () {
      const source =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><defs><linearGradient id="g"><stop offset="0" stop-color="red"/></linearGradient></defs><rect width="100" height="100" fill="url(#g)"/></svg>';
      final bytes = svg(source);
      final prepared = prepareNativeSvg(bytes);
      expect(utf8.decode(prepared.bytes), contains('url(#g)'));
      expect(utf8.decode(bytes), source);
      expect(prepared.embeddedImages, isEmpty);
    },
  );
  test(
    'external href, entity-encoded links, CSS imports and scripts fail before rendering',
    () {
      for (final body in [
        '<svg><image href="https://other.test/x.png"/></svg>',
        '<svg><image href="&#104;ttps://other.test/x.png"/></svg>',
        '<svg><style>@import "https://other.test/x.css";</style></svg>',
        '<svg><script>alert(1)</script></svg>',
        '<svg onload="alert(1)"/>',
        '<!DOCTYPE svg [<!ENTITY a "x">]><svg/>',
        '<?xml-stylesheet href="https://other.test/x.css"?><svg/>',
      ]) {
        expect(
          () => prepareNativeSvg(svg(body)),
          throwsFormatException,
          reason: body,
        );
      }
    },
  );
  test('circular use references and unsupported filters are explicit errors', () {
    expect(
      () => prepareNativeSvg(
        svg(
          '<svg><g id="a"><use href="#b"/></g><g id="b"><use href="#a"/></g></svg>',
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => prepareNativeSvg(svg('<svg><filter id="f"/></svg>')),
      throwsFormatException,
    );
  });
  test(
    'native anchor interaction is removed from preview copy without modifying original',
    () {
      const source =
          '<svg><a href="https://example.test"><rect width="10" height="10"/></a></svg>';
      final input = svg(source);
      final prepared = prepareNativeSvg(input);
      expect(utf8.decode(prepared.bytes), isNot(contains('href=')));
      expect(utf8.decode(input), source);
    },
  );
  test(
    'embedded PNG is retained for raster dimension checks and nested SVG is rejected',
    () {
      const png =
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j6VQAAAAASUVORK5CYII=';
      final result = prepareNativeSvg(
        svg('<svg><image href="data:image/png;base64,$png"/></svg>'),
      );
      expect(result.embeddedImages.length, 1);
      expect(imageContentMime(result.embeddedImages.single), 'image/png');
      expect(
        () => prepareNativeSvg(
          svg(
            '<svg><image href="data:image/svg+xml;base64,${base64.encode(svg('<svg/>'))}"/></svg>',
          ),
        ),
        throwsFormatException,
      );
    },
  );
}
