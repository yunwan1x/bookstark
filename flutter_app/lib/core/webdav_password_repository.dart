import 'package:xml/xml.dart';
import 'api_client.dart';
import 'profile_repository.dart';
import 'account_password_repository.dart';

void validateWebdavAppPassword(String value) {
  validateLoginPassword(value, newPassword: true);
  if (value.runes.length < 8 ||
      value.runes.length > 64 ||
      value.trim().isEmpty) {
    throw const FormatException('Invalid DAV app password length');
  }
}

class WebdavCredentialProfile {
  const WebdavCredentialProfile({
    required this.account,
    required this.endpoint,
    required this.hasPassword,
  });
  final String account;
  final Uri endpoint;
  final bool hasPassword;
}

class WebdavPasswordPreflightFailure implements Exception {
  const WebdavPasswordPreflightFailure();
}

abstract interface class WebdavPasswordRepository {
  Future<WebdavCredentialProfile> read();
  Future<String> reset({String? password});
  Future<void> verify(String candidate);
  Future<void> revoke();
  void dispose();
}

class RemoteWebdavPasswordRepository implements WebdavPasswordRepository {
  RemoteWebdavPasswordRepository(this.client, {required this.memberId});
  final BookstarkClient client;
  final int memberId;
  String? _account;
  bool _closed = false;
  Future<String?> _owner() async {
    if (_closed) {
      throw const WebdavPasswordPreflightFailure();
    }
    final token = client.exportSession()['token'];
    try {
      final profile = await RemoteProfileRepository(
        client,
        memberId: memberId,
      ).read();
      _account = profile.account;
    } catch (_) {
      throw const WebdavPasswordPreflightFailure();
    }
    if (_closed || client.exportSession()['token'] != token) {
      throw const WebdavPasswordPreflightFailure();
    }
    return token;
  }

  void _current(String? token) {
    if (_closed || client.exportSession()['token'] != token) {
      throw StateError('DAV credential owner context changed');
    }
  }

  @override
  Future<WebdavCredentialProfile> read() async {
    final token = await _owner();
    final row = await client.webdavCredentialsProfileJson();
    _current(token);
    final account = row['account'],
        endpoint = row['endpoint'],
        has = row['has_app_password'];
    final uri = endpoint is String ? Uri.tryParse(endpoint) : null;
    if (account is! String ||
        account != _account ||
        has is! bool ||
        row['built_in'] != true ||
        uri == null ||
        !uri.isAbsolute ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Invalid actual WebDAV credential profile');
    }
    return WebdavCredentialProfile(
      account: account,
      endpoint: uri,
      hasPassword: has,
    );
  }

  @override
  Future<String> reset({String? password}) async {
    if (password != null) {
      validateWebdavAppPassword(password);
    }
    final token = await _owner();
    final row = await client.resetWebdavAppPasswordJson(password: password);
    _current(token);
    final actual = row['app_password'];
    if (actual is! String) {
      throw const FormatException(
        'Missing actual one-time DAV app password receipt',
      );
    }
    validateWebdavAppPassword(actual);
    if (password != null && actual != password) {
      throw const FormatException('DAV app password receipt differs');
    }
    return actual;
  }

  @override
  Future<void> verify(String candidate) async {
    validateWebdavAppPassword(candidate);
    final token = await _owner();
    final xml = await client.probeWebdavAppPassword(_account!, candidate);
    _current(token);
    if (RegExp(
      r'<!\s*(?:DOCTYPE|ENTITY)',
      caseSensitive: false,
    ).hasMatch(xml)) {
      throw const FormatException('Unexpected DAV XML declaration');
    }
    final root = XmlDocument.parse(xml).rootElement;
    if (root.name.local != 'multistatus' || root.name.namespaceUri != 'DAV:') {
      throw const FormatException('Missing actual DAV multistatus');
    }
    final responses = root.childElements
        .where(
          (e) => e.name.local == 'response' && e.name.namespaceUri == 'DAV:',
        )
        .toList();
    if (responses.length != 1) {
      throw const FormatException('Expected only the actual DAV root response');
    }
    final hrefs = responses.single.childElements
        .where((e) => e.name.local == 'href' && e.name.namespaceUri == 'DAV:')
        .toList();
    if (hrefs.length != 1) {
      throw const FormatException('Missing actual DAV root href');
    }
    final href = Uri.tryParse(hrefs.single.innerText);
    final expected = Uri.parse(
      '${client.baseUri.toString().replaceFirst(RegExp(r'/$'), '')}/dav',
    );
    if (href == null ||
        href.hasQuery ||
        href.hasFragment ||
        href.userInfo.isNotEmpty ||
        href.path.replaceFirst(RegExp(r'/$'), '') != expected.path ||
        href.hasAuthority &&
            (!href.isAbsolute || href.origin != expected.origin)) {
      throw const FormatException('DAV verification escaped the current root');
    }
    final statuses = responses.single.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'status' && e.name.namespaceUri == 'DAV:')
        .map((e) => e.innerText.trim())
        .toList();
    if (!statuses.any(
      (value) => RegExp(r'^HTTP/\d(?:\.\d)?\s+200(?:\s|$)').hasMatch(value),
    )) {
      throw const FormatException(
        'DAV root credential verification incomplete',
      );
    }
  }

  @override
  Future<void> revoke() async {
    final token = await _owner();
    final row = await client.revokeWebdavAppPasswordJson();
    _current(token);
    if (!{0, 200}.contains(row['code']) || row['message'] is! String) {
      throw const FormatException('Missing actual DAV revocation receipt');
    }
  }

  @override
  void dispose() {
    _closed = true;
    _account = null;
  }
}
