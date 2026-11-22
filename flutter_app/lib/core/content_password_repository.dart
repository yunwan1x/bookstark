import 'dart:convert';
import 'api_client.dart';

class ContentProtection {
  const ContentProtection({
    required this.id,
    required this.title,
    required this.protected,
  });
  final int id;
  final String title;
  final bool protected;
}

void validateContentPassword(String value) {
  if (value.isEmpty || utf8.encode(value).length > 1024) {
    throw const FormatException('Password must contain 1 to 1024 UTF8 bytes');
  }
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++i >= value.length ||
          value.codeUnitAt(i) < 0xdc00 ||
          value.codeUnitAt(i) > 0xdfff) {
        throw const FormatException('Invalid password Unicode');
      }
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      throw const FormatException('Invalid password Unicode');
    }
  }
}

abstract interface class ContentPasswordRepository {
  Future<ContentProtection> read(int id);
  Future<void> change(
    ContentProtection baseline, {
    required String newPassword,
    String? currentPassword,
  });
  Future<void> verify(int id, String password);
}

class RemoteContentPasswordRepository implements ContentPasswordRepository {
  RemoteContentPasswordRepository(this.client);
  final BookstarkClient client;
  @override
  Future<ContentProtection> read(int id) async {
    final row = await client.contentPasswordJson(id);
    if (row['blog_id'] != id ||
        row['has_password'] is! bool ||
        row['blog_title'] is! String ||
        !{'note', 'article'}.contains(row['blog_type']) ||
        row['editor_type'] != 'markdown') {
      throw const FormatException('Invalid Markdown owner protection context');
    }
    return ContentProtection(
      id: id,
      title: row['blog_title'] as String,
      protected: row['has_password'] as bool,
    );
  }

  @override
  Future<void> change(
    ContentProtection baseline, {
    required String newPassword,
    String? currentPassword,
  }) async {
    if (newPassword.isNotEmpty) {
      validateContentPassword(newPassword);
    }
    if (baseline.protected) {
      if (currentPassword == null) {
        throw StateError('Current password is required');
      }
      validateContentPassword(currentPassword);
    } else if (newPassword.isEmpty || currentPassword != null) {
      throw StateError('No existing password to remove or replace');
    }
    await client.contentPasswordJson(
      baseline.id,
      newPassword: newPassword,
      currentPassword: currentPassword,
    );
  }

  @override
  Future<void> verify(int id, String password) async {
    validateContentPassword(password);
    final row = await client.contentPasswordJson(id, verifyPassword: password);
    if (row['blog_content'] is! String) {
      throw const FormatException('Missing actual verification response');
    }
    // Do not expose, retain, render or persist the decrypted body here.
  }
}
