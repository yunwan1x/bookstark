import 'dart:convert';
import 'dart:typed_data';
import 'bounded_note_text_reader.dart';

/// Canonical path selection only. No file access, network fallback, lease,
/// generation authorization, password unlock or resource execution permission.
final class LegacyUploadAliasPolicy {
  LegacyUploadAliasPolicy({required this.isolatedOrigin}) {
    if (isolatedOrigin.scheme != 'https' ||
        isolatedOrigin.userInfo.isNotEmpty ||
        isolatedOrigin.authority.contains('@') ||
        isolatedOrigin.hasQuery ||
        isolatedOrigin.hasFragment ||
        !{'', '/'}.contains(isolatedOrigin.path) ||
        isolatedOrigin.port != 443 ||
        !RegExp(
          r'^[a-f0-9]{32}\.bookstark-(local|editor)\.invalid$',
        ).hasMatch(isolatedOrigin.host)) {
      throw ArgumentError('Expected an isolated local WebView origin');
    }
  }
  final Uri isolatedOrigin;

  String? canonicalPath(String rawUrl) {
    if (rawUrl.isEmpty ||
        rawUrl.length > 8192 ||
        rawUrl.contains(r'\') ||
        rawUrl.codeUnits.any((c) => c < 32 || c == 127)) {
      return null;
    }
    try {
      final request = Uri.tryParse(rawUrl);
      if (request == null ||
          request.userInfo.isNotEmpty ||
          request.authority.contains('@')) {
        return null;
      }
      if (request.hasScheme) {
        if (request.scheme != isolatedOrigin.scheme ||
            request.host != isolatedOrigin.host ||
            request.port != isolatedOrigin.port) {
          return null;
        }
      } else if (request.hasAuthority) {
        return null;
      }
      // Uri.parse normalizes literal dot segments. Inspect the original path
      // so a rejected traversal cannot become an admitted canonical alias.
      var path = rawUrl.split(RegExp(r'[?#]')).first;
      if (request.hasScheme) {
        final authorityStart = request.scheme.length + 3;
        if (path.length < authorityStart ||
            path.substring(request.scheme.length, authorityStart) != '://') {
          return null;
        }
        final slash = path.indexOf('/', authorityStart);
        final rawAuthority = path.substring(
          authorityStart,
          slash < 0 ? path.length : slash,
        );
        if (rawAuthority.contains('@')) {
          return null;
        }
        path = slash < 0 ? '' : path.substring(slash);
      }
      if (!path.startsWith('/upload-files/') || path.length > 4096) {
        return null;
      }
      final encoded = path.split('/');
      if (encoded.length < 3 ||
          encoded.first.isNotEmpty ||
          encoded[1] != 'upload-files') {
        return null;
      }
      final decoded = <String>[];
      for (final part in encoded.skip(2)) {
        if (part.isEmpty) {
          return null;
        }
        final text = _decodeSegment(part);
        if (text == null ||
            text.isEmpty ||
            text == '.' ||
            text == '..' ||
            text.contains(RegExp(r'[/\\:%?#]')) ||
            text.codeUnits.any((c) => c < 32 || c == 127)) {
          return null;
        }
        decoded.add(text);
      }
      return Uri(pathSegments: ['', 'upload-files', ...decoded]).path;
    } catch (_) {
      return null;
    }
  }

  static String? _decodeSegment(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        if (++i >= value.length ||
            value.codeUnitAt(i) < 0xdc00 ||
            value.codeUnitAt(i) > 0xdfff) {
          return null;
        }
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        return null;
      }
    }
    final bytes = BytesBuilder(copy: false);
    for (var i = 0; i < value.length;) {
      if (value.codeUnitAt(i) == 37) {
        if (i + 2 >= value.length) {
          return null;
        }
        final high = _hex(value.codeUnitAt(i + 1)),
            low = _hex(value.codeUnitAt(i + 2));
        if (high < 0 || low < 0) {
          return null;
        }
        bytes.addByte(high * 16 + low);
        i += 3;
      } else {
        final begin = i;
        while (i < value.length && value.codeUnitAt(i) != 37) {
          i++;
        }
        bytes.add(utf8.encode(value.substring(begin, i)));
      }
    }
    return BoundedNoteTextReader.decodeUtf8PreservingBom(bytes.takeBytes());
  }

  static int _hex(int c) {
    if (c >= 48 && c <= 57) {
      return c - 48;
    }
    if (c >= 65 && c <= 70) {
      return c - 55;
    }
    if (c >= 97 && c <= 102) {
      return c - 87;
    }
    return -1;
  }
}
