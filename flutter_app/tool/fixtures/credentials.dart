import 'package:bookstark_flutter/core/api_tokens_repository.dart';
import 'package:bookstark_flutter/core/webdav_password_repository.dart';

// Deliberately fake fixture credentials, never connected to a server.
const credentialFixtureSecret =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

class ApiTokensFixture implements ApiTokensRepository {
  ApiTokensFixture({this.loseReceipt = false});
  final bool loseReceipt;
  int _next = 1;
  final _rows = <ApiTokenEntry>[];
  @override
  Future<ApiTokensPage> read() async => ApiTokensPage(_rows);
  @override
  Future<CreatedApiToken> create(String name) async {
    final entry = ApiTokenEntry(
      id: _next++,
      memberId: 7,
      name: name.isEmpty ? 'default' : name,
      masked: maskApiToken(credentialFixtureSecret),
      createdAt: '2026-11-05T08:00:00Z',
    );
    _rows.add(entry);
    if (loseReceipt) {
      throw StateError('Fixture lost receipt');
    }
    return CreatedApiToken(entry, credentialFixtureSecret);
  }

  @override
  Future<void> revoke(ApiTokenEntry entry) async {
    _rows.removeWhere((v) => v.id == entry.id);
  }

  @override
  void dispose() {
    _rows.clear();
  }
}

class WebdavPasswordFixture implements WebdavPasswordRepository {
  WebdavPasswordFixture({this.loseReceipt = false});
  final bool loseReceipt;
  String? _password;
  @override
  Future<WebdavCredentialProfile> read() async => WebdavCredentialProfile(
    account: 'xiao.lin',
    endpoint: Uri.parse('https://fixture.example.test/dav'),
    hasPassword: _password != null,
  );
  @override
  Future<String> reset({String? password}) async {
    _password = password ?? 'fixture-only-app-password';
    if (loseReceipt) {
      throw StateError('Fixture lost receipt');
    }
    return _password!;
  }

  @override
  Future<void> verify(String candidate) async {
    if (_password != candidate) {
      throw StateError('Fixture verification failed');
    }
  }

  @override
  Future<void> revoke() async {
    _password = null;
  }

  @override
  void dispose() {
    _password = null;
  }
}
