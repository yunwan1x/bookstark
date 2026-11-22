import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';

var checks = 0;
void check(bool condition) {
  checks++;
  if (!condition) throw StateError('Owned asset metadata assertion failed');
}

void rejects(void Function() action) {
  checks++;
  try {
    action();
  } on FormatException {
    return;
  }
  throw StateError('Malformed asset metadata was accepted');
}

Map<String, dynamic> credential() => {
  'id': 9,
  'name': 'owned credential',
  'username': 'fixture-user',
  'auth_type': 'password',
  'credential_hint': 'password',
  'created_by': 1,
  'create_time': '2026-11-07T04:00:00.123456789Z',
  'modify_time': '2026-11-07T04:00:00.123456789Z',
  'credential': ' owned synthetic secret ',
};
Map<String, dynamic> host() => {
  ...credential(),
  'id': 5,
  'name': 'owned host',
  'host': 'host.example.invalid',
  'port': 22,
  'shell': '/bin/sh',
  'cwd': '/workspace',
  'docker_socket_path': '/var/run/docker.sock',
  'credential_id': 9,
  'credential_name': 'owned credential',
  'status': 'unknown',
};
void verifyAssetMetadataContract() {
  final input = credential()
    ..['unknown_future_secret'] = 'PRIVATE SYNTHETIC MATERIAL';
  final c = AdminAssetCredentialMetadata.parse(input);
  check(c.id == 9 && c.username == 'fixture-user');
  check(c.auth == AdminAssetAuth.password);
  check(c.secretPresence == AdminAssetSecretPresence.supplied);
  check(!c.reviewFingerprint.contains('owned synthetic secret'));
  check(!c.reviewFingerprint.contains('PRIVATE SYNTHETIC MATERIAL'));
  check(!c.toString().contains('secret'));
  input['name'] = 'changed caller map';
  input['credential'] = 'different caller secret';
  check(c.name == 'owned credential');
  check(!c.reviewFingerprint.contains('different caller secret'));
  check(
    AdminAssetCredentialMetadata.parse(
          credential()..remove('credential'),
        ).secretPresence ==
        AdminAssetSecretPresence.notProvided,
  );
  check(
    AdminAssetCredentialMetadata.parse(
          credential()..['credential'] = '',
        ).secretPresence ==
        AdminAssetSecretPresence.empty,
  );
  check(
    AdminAssetCredentialMetadata.parse(
          credential()..['credential'] = ' ',
        ).secretPresence ==
        AdminAssetSecretPresence.supplied,
  );
  rejects(
    () =>
        AdminAssetCredentialMetadata.parse(credential()..['credential'] = null),
  );
  rejects(
    () => AdminAssetCredentialMetadata.parse(credential()..['credential'] = 1),
  );
  final h = AdminAssetHostMetadata.parse(host());
  check(h.neverChecked && h.lastCheck == null);
  check(h.host == 'host.example.invalid' && h.port == 22);
  check(h.credentialId == 9 && h.dockerSocket == '/var/run/docker.sock');
  check(!h.reviewFingerprint.contains('owned synthetic secret'));
  check(!h.toString().contains('synthetic'));
  check(
    !AdminAssetHostMetadata.parse(
      host()..['last_check_time'] = '2026-11-06T04:00:00Z',
    ).neverChecked,
  );
  check(
    AdminAssetHostMetadata.parse(
      host()..['last_check_time'] = '0001-01-01T00:00:00Z',
    ).neverChecked,
  );
  check(
    !AdminAssetHostMetadata.parse(host()..['status'] = 'online').neverChecked,
  );
  check(
    AdminAssetHostMetadata.parse(host()..['credential_id'] = 0).credentialId ==
        0,
  );
  check(
    AdminAssetHostMetadata.parse(
      host()..remove('credential_name'),
    ).credentialName.isEmpty,
  );
  final nano = AdminAssetHostMetadata.parse(
    host()..['modify_time'] = '2026-11-07T04:00:00.123456788Z',
  );
  check(nano.modified.utc == h.modified.utc);
  check(nano.reviewFingerprint != h.reviewFingerprint);
  for (final value in [null, 0, -1, 5.0, '5', 9007199254740992]) {
    rejects(() => AdminAssetHostMetadata.parse(host()..['id'] = value));
  }
  for (final value in [0, -1, 65536, 22.0, '22']) {
    rejects(() => AdminAssetHostMetadata.parse(host()..['port'] = value));
  }
  for (final value in ['', 'root', null, 1]) {
    rejects(() => AdminAssetHostMetadata.parse(host()..['auth_type'] = value));
  }
  for (final value in ['', 'connected', null, 1]) {
    rejects(() => AdminAssetHostMetadata.parse(host()..['status'] = value));
  }
  for (final stamp in [
    '2026-02-30T00:00:00Z',
    '2026-13-01T00:00:00Z',
    '2026-11-07T24:00:00Z',
    '2026-11-07T00:60:00Z',
    '2026-11-07T00:00:60Z',
    '2026-11-07T00:00:00+24:00',
    '2026-11-07T00:00:00+08:60',
    '2026-11-07 00:00:00Z',
    '2026-11-07T00:00:00.1234567890Z',
    '2026-11-07T00:00:00',
    '0000-01-01T00:00:00Z',
  ]) {
    rejects(() => AdminAssetTimestamp.parse(stamp));
  }
  check(
    AdminAssetTimestamp.parse('2024-02-29T08:00:00+08:00').utc ==
        DateTime.utc(2024, 2, 29),
  );
  final list = adminAssetMetadataList(
    {
      'code': 0,
      'data': [host()],
    },
    AdminAssetHostMetadata.parse,
    (h) => h.id,
  );
  check(list.single.id == 5);
  try {
    list.clear();
    throw StateError('List was mutable');
  } on UnsupportedError {
    checks++;
  }
  rejects(
    () => adminAssetMetadataList(
      {
        'code': 0,
        'data': [host(), host()],
      },
      AdminAssetHostMetadata.parse,
      (h) => h.id,
    ),
  );
  for (final bad in [
    {'code': 0.0, 'data': <dynamic>[]},
    {'code': false, 'data': <dynamic>[]},
    {'code': 1, 'data': <dynamic>[]},
    {'code': 0, 'data': null},
    {
      'code': 0,
      'data': [null],
    },
  ]) {
    rejects(
      () => adminAssetMetadataList(
        bad,
        AdminAssetHostMetadata.parse,
        (h) => h.id,
      ),
    );
  }
}

void main() {
  test(
    'asset metadata drops secrets, preserves nanosecond review identity and rejects malformed responses',
    () {
      checks = 0;
      verifyAssetMetadataContract();
      expect(checks, 64);
    },
  );
}
