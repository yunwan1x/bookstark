import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_remote_dav_models.dart';

Map<String, dynamic> davServer({int id = 42}) => {
  'id': id,
  'name': 'Owned DAV',
  'url': 'https://dav.invalid/prefix',
  'root_path': '/root',
  'credential_id': 7,
  'created_by': 1,
  'status': 'unknown',
  'create_time': '2026-11-08T00:00:00.000000001Z',
  'modify_time': '2026-11-08T00:00:00.000000002Z',
};
Map<String, dynamic> davEntry({
  String name = 'a.txt',
  String? path,
  int size = 3,
  String type = 'file',
}) => {
  'name': name,
  'path': path ?? name,
  'size': size,
  'type': type,
  'mode': type == 'dir' ? 'drwxr-xr-x' : '-rw-r--r--',
  'mod_time': '2026-11-08T00:00:00.123456789Z',
};
void main() {
  test(
    'stored URL parameters are hidden without losing exact target comparison',
    () {
      final a = AdminDavServer.parse({
        ...davServer(),
        'url': 'https://user:secret@dav.invalid/prefix?ak=hidden#fragment',
      });
      final b = AdminDavServer.parse({
        ...davServer(),
        'url': 'https://user:secret@dav.invalid/prefix?ak=changed#fragment',
      });
      expect(a.url, 'https://dav.invalid/prefix');
      expect(a.urlNeedsReplacement, true);
      expect(a.fingerprint, isNot(b.fingerprint));
      for (final value in [a.url, a.fingerprint, a.toString()]) {
        expect(value, isNot(contains('secret')));
        expect(value, isNot(contains('hidden')));
        expect(value, isNot(contains('fragment')));
      }
    },
  );
  test('builtin string local stays separate from remote numeric identity', () {
    expect(
      AdminDavConnection.parse({
        'id': 'local',
        'built_in': true,
        'name': 'BookStark',
      }),
      isA<AdminDavBuiltin>(),
    );
    expect(AdminDavConnection.parse(davServer()), isA<AdminDavServer>());
    for (final data in [
      {...davServer(), 'id': '42'},
      {...davServer(), 'id': 'local'},
      {...davServer(), 'built_in': true},
      {...davServer(), 'id': 0},
    ]) {
      expect(() => AdminDavConnection.parse(data), throwsFormatException);
    }
  });
  test(
    'URL rejects inline secrets, query, fragment, controls and dot retargeting',
    () {
      for (final value in [
        'https://user:password@dav.invalid/root',
        'https://dav.invalid?ak=secret',
        'https://dav.invalid/#secret',
        'https://dav.invalid/a/../b',
        'https://dav.invalid/a/%2e%2e/b',
        'https://dav.invalid/a/%2F/b',
        'https://dav.invalid/a//b',
        ' https://dav.invalid',
        'file:///etc/passwd',
        'https://dav.invalid/\npath',
      ]) {
        expect(() => adminDavUrl(value), throwsFormatException, reason: value);
      }
      expect(
        adminDavUrl('https://dav.invalid:8443/prefix/%E4%B8%AD').host,
        'dav.invalid',
      );
    },
  );
  test('remote API paths do not duplicate configured URL prefix or root', () {
    expect(adminDavJoin('.', '中文.txt'), '中文.txt');
    expect(adminDavJoin('docs', 'a.txt'), 'docs/a.txt');
    expect(adminDavParent('docs/a.txt'), 'docs');
    expect(adminDavParent('a.txt'), '.');
    expect(adminDavRoot('/root'), '/root');
    for (final path in ['/root/a', 'a/../b', 'a//b', './a', 'a/', ' a', 'a ']) {
      expect(() => adminDavPath(path), throwsFormatException, reason: path);
    }
    expect(() => adminDavPath('.', mutation: true), throwsFormatException);
  });
  test('name bound uses UTF8 bytes and refuses invalid Unicode or NUL', () {
    expect(utf8.encode('中' * 33).length, 99);
    AdminDavDraft(
      name: '中' * 33,
      url: 'https://dav.invalid',
      root: '/',
      credentialId: 7,
    );
    for (final name in [
      '中' * 34,
      'x\u0000y',
      String.fromCharCode(0xd800),
      ' name',
    ]) {
      expect(
        () => AdminDavDraft(
          name: name,
          url: 'https://dav.invalid',
          root: '/',
          credentialId: 7,
        ),
        throwsFormatException,
      );
    }
  });
  test(
    'server fingerprints retain nanoseconds and exclude test-only status',
    () {
      final a = AdminDavServer.parse(davServer());
      final b = AdminDavServer.parse({
        ...davServer(),
        'status': 'offline',
        'last_check_time': '2026-11-08T01:00:00Z',
      });
      final c = AdminDavServer.parse({
        ...davServer(),
        'modify_time': '2026-11-08T00:00:00.000000003Z',
      });
      expect(a.fingerprint, b.fingerprint);
      expect(a.fingerprint, isNot(c.fingerprint));
      expect(a.toString(), isNot(contains('https://')));
    },
  );
  test('DAV symbolic mode cannot become SSH chmod metadata', () {
    final file = AdminDavEntry.parse(davEntry(), '.');
    expect(file.type, AdminDavEntryType.file);
    expect(
      () => AdminDavEntry.parse({...davEntry(), 'mode': '0644'}, '.'),
      throwsFormatException,
    );
    expect(
      AdminDavEntry.parse(davEntry(name: 'docs', type: 'dir'), '.').type,
      AdminDavEntryType.directory,
    );
  });
  test(
    'reported zero remains zero without inventing known empty-file proof',
    () {
      expect(AdminDavEntry.parse(davEntry(size: 0), '.').size, 0);
      expect(
        () => AdminDavEntry.parse(davEntry(size: -1), '.'),
        throwsFormatException,
      );
      expect(
        () => AdminDavEntry.parse(davEntry(size: 9007199254740992), '.'),
        throwsFormatException,
      );
    },
  );
  test('noncanonical names can be displayed but have no mutation action', () {
    final row = AdminDavEntry.parse(davEntry(name: 'trailing.txt '), '.');
    expect(row.addressable, false);
    expect(
      () => AdminDavEntry.parse(davEntry(name: 'a', path: 'another'), '.'),
      throwsFormatException,
    );
  });
  test('listing validates duplicates, bound and explicit truncation', () {
    final data = {
      'items': [davEntry()],
      'limit': 1000,
      'truncated': true,
    };
    expect(AdminDavListing.parse(data, '.').truncated, true);
    expect(AdminDavListing.parse(data, '.').find('a.txt')?.name, 'a.txt');
    expect(
      () => AdminDavListing.parse({
        ...data,
        'items': [davEntry(), davEntry()],
      }, '.'),
      throwsFormatException,
    );
    expect(
      () => AdminDavListing.parse({...data, 'truncated': 'false'}, '.'),
      throwsFormatException,
    );
    expect(
      () => AdminDavListing.parse({...data, 'limit': 1001}, '.'),
      throwsFormatException,
    );
  });
  test('directory DELETE cannot pretend to be empty-directory-only', () {
    final dir = AdminDavEntry.parse(davEntry(name: 'docs', type: 'dir'), '.');
    expect(
      () => AdminDavFilePlan(
        action: AdminDavFileAction.delete,
        path: dir.path,
        baseline: dir,
      ),
      throwsFormatException,
    );
    expect(
      AdminDavFilePlan(
        action: AdminDavFileAction.delete,
        path: dir.path,
        baseline: dir,
        recursive: true,
      ).recursive,
      true,
    );
  });
  test('write plans bind original target and do not allow root mutations', () {
    final entry = AdminDavEntry.parse(davEntry(), '.');
    expect(
      () => AdminDavFilePlan(
        action: AdminDavFileAction.delete,
        path: '.',
        baseline: entry,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminDavFilePlan(
        action: AdminDavFileAction.copy,
        path: entry.path,
        baseline: entry,
        target: entry.path,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminDavFilePlan(
        action: AdminDavFileAction.save,
        path: entry.path,
        baseline: entry,
      ),
      throwsFormatException,
    );
    expect(
      () => AdminDavFilePlan(
        action: AdminDavFileAction.rename,
        path: entry.path,
        target: 'next',
      ),
      throwsFormatException,
    );
  });
}
