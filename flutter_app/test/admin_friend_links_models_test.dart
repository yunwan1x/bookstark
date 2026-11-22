import 'dart:convert';

import 'package:bookstark_flutter/features/admin/admin_friend_links_models.dart';
import 'package:flutter_test/flutter_test.dart';

int checks = 0;
void check(bool value, String label) {
  if (!value) throw StateError(label);
  checks++;
}

void rejects(void Function() action, String label) {
  try {
    action();
  } on FormatException {
    checks++;
    return;
  }
  throw StateError('Expected refusal: $label');
}

Map<String, Object?> raw({int id = 1}) => {
  'link_id': id,
  'link_name': ' fixture-name ',
  'link_url': 'HTTPS://example.invalid/docs',
  'group_name': ' tools ',
  'group_order': -2,
  'sort_weight': 10,
  'is_enabled': 1,
  'qr_code': '',
  'description': ' description ',
  'create_time': '2026-11-07T00:00:00Z',
  'modify_time': '2026-11-07T00:00:00Z',
  'created_by': 1,
  'updated_by': 1,
  'future': {
    'nested': [1, ' keep ', true],
  },
};
AdminFriendLinksSnapshot snapshot(
  List<AdminFriendLink> items, {
  bool simple = false,
}) => AdminFriendLinksSnapshot(items: items, simpleMode: simple);
void checkModelContract() {
  final source = raw(), original = AdminFriendLink.parse(source);
  original.validate();
  check(true, 'upper HTTP scheme accepted like actual Go');
  check(
    original.name == ' fixture-name ' && original.group == ' tools ',
    'raw fields unchanged on read',
  );
  (source['future'] as Map)['nested'] = ['mutated'];
  check(
    ((original.raw['future'] as Map)['nested'] as List)[1] == ' keep ',
    'deep clone unknown fields',
  );
  var frozen = false;
  try {
    (original.raw['future'] as Map)['new'] = 'bad';
  } on UnsupportedError {
    frozen = true;
  }
  check(frozen, 'nested unknown object frozen');
  final renamed = original.edit(name: 'new-name');
  check(
    renamed.raw['create_time'] == original.raw['create_time'] &&
        renamed.qr == original.qr,
    'unedited server metadata retained',
  );
  check(
    jsonEncode(renamed.raw['future']) == jsonEncode(original.raw['future']),
    'unedited unknown structure retained',
  );
  check(original.name != 'new-name', 'edit immutable original');
  check(!renamed.toString().contains('new-name'), 'safe diagnostics');
  rejects(
    () => AdminFriendLink.parse({...raw(), 'link_id': 0}),
    'server id positive',
  );
  rejects(
    () => AdminFriendLink.parse({...raw(), 'sort_weight': 10.0}),
    'orders integral',
  );
  rejects(
    () => AdminFriendLink.parse({...raw(), 'is_enabled': true}),
    'enable API integer',
  );
  rejects(
    () => AdminFriendLink.parse({...raw(), 'group_order': 9007199254740992}),
    'web-safe order',
  );
  rejects(
    () => AdminFriendLink.parse({...raw(), 'future': double.nan}),
    'unknown non JSON rejected',
  );
  original.edit(name: '界' * 33).validate();
  check(true, 'name99 UTF8 bytes');
  rejects(() => original.edit(name: '界' * 34).validate(), 'name102 bytes');
  rejects(
    () => original.edit(name: ' ' * 10 + 'a' * 100).validate(),
    'raw name checked before normalization',
  );
  original
      .edit(group: ' ${'界' * 33} ', description: ' ${'界' * 333} ')
      .validate();
  check(true, 'group and description limits after normalization');
  rejects(() => original.edit(group: '界' * 34).validate(), 'group102 bytes');
  rejects(
    () => original.edit(description: '界' * 334).validate(),
    'description1002 bytes',
  );
  final prefix = 'https://example.invalid/';
  original.edit(url: prefix + 'x' * (2048 - prefix.length)).validate();
  check(true, 'URL2048 bytes');
  rejects(
    () => original.edit(url: prefix + 'x' * (2049 - prefix.length)).validate(),
    'URL2049 bytes',
  );
  for (final url in [
    '',
    'relative',
    'javascript:alert(1)',
    'ftp://example.invalid/',
    'https://',
    'https://example.invalid/%',
    'https://example.invalid/a\nb',
  ]) {
    rejects(() => original.edit(url: url).validate(), 'invalid URL');
  }
  final qr = original.edit(qr: '/upload-files/a%25.png', url: '');
  qr.validate();
  check(
    qr.url.isEmpty,
    'canonical literal percent QR permits absent URL like Go',
  );
  for (final path in [
    '/upload-files/a.png',
    '/upload-files/a.JPG',
    '/upload-files/folder/a.webp',
    '/upload-files/a%25.png',
    '/upload-files/%E5%9B%BE.png',
  ]) {
    check(canonicalFriendQr(path), 'valid canonical QR $path');
  }
  for (final path in [
    'https://example.invalid/a.png',
    '//upload-files/a.png',
    '/upload-files/../a.png',
    '/upload-files/%2e%2e/a.png',
    '/upload-files/a%2Fb.png',
    '/upload-files/%61.png',
    '/upload-files/a.png?x=1',
    '/upload-files/a.png#f',
    '/upload-files/a\\b.png',
    '/upload-files/a%5Cb.png',
    '/upload-files/a.svg',
    '/upload-files//a.png',
    '/upload-files/图.png',
  ]) {
    check(!canonicalFriendQr(path), 'invalid/noncanonical QR $path');
  }
  final body = snapshot([original, qr]).checkedBody();
  check(
    (body['items'] as List).length == 2 && body['simple_mode'] == false,
    'full exact items and explicit simple flag',
  );
  check(
    (body['items'] as List)[0]['description'] == ' description ',
    'body retains raw normalization input',
  );
  final a = qr.edit(
    name: ' contact ',
    group: ' contact ',
    description: ' QR note ',
  );
  final b = qr.edit(
    name: 'contact',
    group: 'contact',
    description: 'QR note',
    qr: '/upload-files/b.gif',
  );
  snapshot([a, b]).checkedBody();
  check(true, 'normalized QR group metadata agrees');
  rejects(
    () => snapshot([a, b.edit(description: 'different')]).checkedBody(),
    'QRgroup description mismatch',
  );
  rejects(
    () => snapshot([a, b.edit(name: 'other')]).checkedBody(),
    'QRgroup title mismatch',
  );
  snapshot(List.filled(200, original)).checkedBody();
  check(true, '200 rows');
  rejects(() => snapshot(List.filled(201, original)), '201 rows');
  rejects(
    () => snapshot([
      AdminFriendLink.parse({...raw(), 'future': 'x' * (1024 * 1024)}),
    ]).checkedBody(),
    'encoded1MiB body bound including unknown fields',
  );
  check(
    (snapshot([]).checkedBody()['items'] as List).isEmpty,
    'explicit empty list represents clear all',
  );
  check(
    AdminFriendLinksSnapshot.parse({
      'items': null,
      'simple_mode': false,
    }).items.isEmpty,
    'Go nil rows accepted',
  );
  rejects(
    () => AdminFriendLinksSnapshot.parse({'items': [], 'simple_mode': 0}),
    'no guessed boolean',
  );
  final canonical = AdminFriendLink.parse({
    ...raw(id: 99),
    'link_name': original.name.trim(),
    'group_name': original.group.trim(),
    'description': original.description.trim(),
    'create_time': 'later',
    'updated_by': 77,
  });
  check(
    snapshot([original]).semanticKey == snapshot([canonical]).semanticKey,
    'semantic readback ignores rebuilt ID/time and canonical trim',
  );
  check(
    snapshot([original]).semanticKey !=
        snapshot([original], simple: true).semanticKey,
    'simple flag is semantic',
  );
  check(
    snapshot([original]).semanticKey !=
        snapshot([original.edit(description: 'changed')]).semanticKey,
    'description is semantic',
  );
  check(
    snapshot([original]).semanticKey !=
        snapshot([
          AdminFriendLink.parse({
            ...raw(),
            'future': {'changed': true},
          }),
        ]).semanticKey,
    'unknown semantic fields retained in comparison',
  );
  final later = original.edit(groupOrder: 9),
      earlier = original.edit(groupOrder: -9);
  check(
    snapshot([later, earlier]).semanticKey ==
        snapshot([earlier, later]).semanticKey,
    'Go group ordering compared canonically',
  );
}

void main() {
  test(
    'actual friend link contract, field retention, semantic readback and bounds',
    checkModelContract,
  );
}
