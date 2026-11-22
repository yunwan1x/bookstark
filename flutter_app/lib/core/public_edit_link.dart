import 'public_share_models.dart';

/// A capability, not an owner session. Never log or persist requestPath.
class PublicEditLink {
  PublicEditLink._(this.reference, this._token);
  final PublicShareReference reference;
  final String _token;
  factory PublicEditLink.parse(Uri server, String input) {
    try {
      return _parse(server, input);
    } on FormatException {
      throw const FormatException('Invalid shared editing link');
    }
  }
  static PublicEditLink _parse(Uri suppliedServer, String input) {
    final server = PublicShareReference(suppliedServer, 'link-context').server;
    final text = input.trim();
    if (text.length > 16000 || RegExp(r'[\x00-\x1f\x7f]').hasMatch(text)) {
      throw const FormatException('Invalid shared editing link');
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        !uri.hasScheme ||
        !uri.hasAuthority ||
        uri.scheme != server.scheme ||
        uri.host != server.host ||
        uri.port != server.port ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('Editing links must use the current server');
    }
    final expected = [...server.pathSegments, 'shares'],
        actual = uri.pathSegments;
    if (actual.length != expected.length + 1 ||
        List.generate(
          expected.length,
          (i) => expected[i] != actual[i],
        ).any((changed) => changed)) {
      throw const FormatException('Invalid shared editing path');
    }
    final values = uri.queryParametersAll;
    if (values.length != 1 ||
        values['token']?.length != 1 ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(values['token']!.single)) {
      throw const FormatException('Missing or invalid editing capability');
    }
    return PublicEditLink._(
      PublicShareReference(server, actual.last),
      values['token']!.single,
    );
  }

  String get requestPath =>
      '${reference.detailPath}/edit?token=${Uri.encodeQueryComponent(_token)}';
  Uri get publicUri => reference.canonicalUri;
  @override
  String toString() => 'PublicEditLink(<redacted>)';
  @override
  bool operator ==(Object other) =>
      other is PublicEditLink &&
      other.reference == reference &&
      other._token == _token;
  @override
  int get hashCode => Object.hash(reference, _token);
}
