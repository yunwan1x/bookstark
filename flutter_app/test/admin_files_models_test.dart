import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_files_models.dart';

Map<String, dynamic> row({
  String name = '中文😀.txt',
  String? path,
  String type = 'file',
  String mode = '0640',
  Object size = 8,
}) => {
  'name': name,
  'path': path ?? '/work/$name',
  'type': type,
  'mode': mode,
  'size': size,
  'mod_time': '2026-11-07T12:30:45.123456789+08:00',
};
void main() {
  test(
    'Remote names preserve quotes shell metacharacters and embedded newline',
    () {
      for (final name in [
        "quote'\$.txt",
        '\u0060cmd\u0060',
        'line\nbreak',
        '-file',
        '中文😀.txt',
      ]) {
        final item = AdminFileEntry.parse(row(name: name), '/work');
        expect(item.name, name);
        expect(item.path, '/work/$name');
      }
    },
  );
  test('Reject silently trimmed or escaping paths and root mutations', () {
    for (final path in [
      '',
      ' /work',
      '/work\u00a0',
      '/a/../b',
      '/a\u0000b',
      '\ud800',
    ]) {
      expect(() => adminFilePath(path), throwsFormatException);
    }
    for (final path in ['.', '/', './']) {
      expect(adminFilePath(path), path);
      expect(() => adminFilePath(path, mutation: true), throwsFormatException);
    }
  });
  test('Child paths match server path.Join for normal directories', () {
    expect(adminFileJoin('.', 'a'), 'a');
    expect(adminFileJoin('/', 'a'), '/a');
    expect(adminFileJoin('/work/', 'a'), '/work/a');
    expect(adminFileParent('/work/a'), '/work');
    expect(adminFileParent('/work'), '/');
    expect(adminFileParent('a'), '.');
    for (final name in ['..', 'a/b', 'a\\b', ' a', 'a ']) {
      expect(() => adminFileJoin('/work', name), throwsFormatException);
    }
  });
  test(
    'Listing requires exact paths timestamps unique rows and truncation metadata',
    () {
      final good = {
        'items': [row()],
        'limit': 1000,
        'truncated': true,
      };
      final list = AdminFileListing.parse('/work', good);
      expect(list.truncated, true);
      expect(list.items.single.modified.raw, contains('.123456789'));
      for (final data in [
        {
          ...good,
          'items': [row(path: '/other/中文😀.txt')],
        },
        {
          ...good,
          'items': [row(), row()],
        },
        {...good, 'limit': 999},
        {...good, 'truncated': 'false'},
        {
          ...good,
          'items': [row(size: 9007199254740992)],
        },
        {
          ...good,
          'items': [row(type: 'unknown')],
        },
      ]) {
        expect(
          () => AdminFileListing.parse('/work', data),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Text preserves BOM mixed newlines empty content and exact byte bound',
    () {
      const content = '\ufeff中文\r\none\ntwo\r\n';
      expect(AdminFileText('/work/a', content).content, content);
      expect(AdminFileText('/work/a', '').content, '');
      final atLimit = 'a' * (adminFileTextLimit - 3) + '中';
      expect(
        utf8.encode(AdminFileText('/work/a', atLimit).content).length,
        adminFileTextLimit,
      );
      for (final content in [
        'a' * (adminFileTextLimit - 2) + '中',
        '\u0000',
        '\udfff',
      ]) {
        expect(() => AdminFileText('/work/a', content), throwsFormatException);
      }
      expect(
        () =>
            AdminFileText.parse('/work/a', {'path': '/work/b', 'content': ''}),
        throwsFormatException,
      );
    },
  );
  test(
    'Writes require reviewed normal targets and explicit recursive directory',
    () {
      final file = AdminFileEntry.parse(
        row(name: 'a', path: '/work/a'),
        '/work',
      );
      expect(
        AdminFileWritePlan(
          action: AdminFileAction.save,
          path: file.path,
          baseline: file,
          content: '',
        ).content,
        '',
      );
      expect(
        () => AdminFileWritePlan(
          action: AdminFileAction.save,
          path: file.path,
          content: 'x',
        ),
        throwsFormatException,
      );
      expect(
        () => AdminFileWritePlan(
          action: AdminFileAction.delete,
          path: file.path,
          baseline: file,
          recursive: true,
        ),
        throwsFormatException,
      );
      expect(
        () => AdminFileWritePlan(
          action: AdminFileAction.chmod,
          path: file.path,
          baseline: file,
          mode: '4640',
        ),
        throwsFormatException,
      );
      final link = AdminFileEntry.parse(
        row(name: 'link', type: 'symlink'),
        '/work',
      );
      expect(
        () => AdminFileWritePlan(
          action: AdminFileAction.delete,
          path: link.path,
          baseline: link,
        ),
        throwsFormatException,
      );
      expect(file.fingerprint, contains('123456789'));
    },
  );
  test(
    'Unaddressable whitespace filename remains visible without sending altered target',
    () {
      final item = AdminFileEntry.parse(row(name: 'trailing.txt '), '/work');
      expect(item.name, 'trailing.txt ');
      expect(item.addressable, false);
      expect(
        AdminFileEntry.parse(row(name: ' leading.txt'), '/work').addressable,
        true,
      );
    },
  );
}
