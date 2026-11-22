import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/documents_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';
import 'package:bookstark_flutter/core/content_password_repository.dart';

void check(bool value, String message) {
  if (!value) {
    throw StateError(message);
  }
}

Future<void> runShareSettingsContract(BookstarkClient owner) async {
  final notes = RemoteNotesRepository(owner),
      books = RemoteBooksRepository(owner),
      docs = RemoteDocumentsRepository(owner);
  final settings = RemoteShareSettingsRepository(owner),
      passwords = RemoteContentPasswordRepository(owner);
  final anonymous = BookstarkClient(owner.baseUri.toString()),
      readers = RemotePublicSharesRepository(owner);
  final id = await notes.save(
    const Note(
      title: '分享权限与正文密码契约',
      content: '# Original body remains unchanged\n\n空格中文 🙂',
    ),
  );
  final bookId = await books.save(const BookItem(name: '整书分享设置契约'));
  final target = OwnerShareTarget(
    kind: PublicShareKind.blog,
    id: id,
    title: '实际笔记',
  );
  try {
    check(!await settings.status(target), 'Actual new note is not published');
    var receipt = await settings.publish(target);
    check(await settings.status(target), 'Actual publication status');
    check(
      !receipt.editingEnabled && !receipt.reference.canonicalUri.hasQuery,
      'Default actual publication is read only',
    );
    var plain = await readers.load(receipt.reference);
    final original = plain.content;
    receipt = await settings.changeToken(
      target,
      receipt,
      ShareTokenAction.enable,
    );
    final first = receipt.editingUri!;
    final edit = RemotePublicEditRepository(anonymous);
    await edit.read(PublicEditLink.parse(owner.baseUri, first.toString()));
    receipt = await settings.changeToken(
      target,
      receipt,
      ShareTokenAction.reset,
    );
    check(receipt.editingUri != first, 'Reset actually replaces the token');
    var rejected = false;
    try {
      await edit.read(PublicEditLink.parse(owner.baseUri, first.toString()));
    } on ApiFailure catch (e) {
      rejected = e.status == 403;
    }
    check(rejected, 'Reset actual old token is forbidden');
    await edit.read(
      PublicEditLink.parse(owner.baseUri, receipt.editingUri!.toString()),
    );
    final repeated = await settings.publish(target);
    check(
      repeated.reference == receipt.reference &&
          repeated.editingUri == receipt.editingUri,
      'Explicit republish retains existing actual token rather than resetting',
    );
    var protection = await passwords.read(id);
    check(!protection.protected, 'Actual initial owner body protection');
    await passwords.change(protection, newPassword: ' 旧 密码 🙂 ');
    protection = await passwords.read(id);
    check(protection.protected, 'Actual password set');
    await passwords.verify(id, ' 旧 密码 🙂 ');
    final locked = await readers.load(receipt.reference);
    check(
      locked.locked && locked.content.isEmpty,
      'Password change masks public body',
    );
    final decrypted = await readers.unlock(locked, ' 旧 密码 🙂 ');
    check(
      decrypted.content == original,
      'Setting password preserves actual body',
    );
    rejected = false;
    try {
      await passwords.change(
        protection,
        newPassword: 'should not apply',
        currentPassword: 'wrong',
      );
    } on ApiFailure catch (e) {
      rejected = e.status == 400;
    }
    check(rejected, 'Wrong current password prevents changing the body key');
    await passwords.change(
      protection,
      newPassword: ' new raw spaces ',
      currentPassword: ' 旧 密码 🙂 ',
    );
    await passwords.verify(id, ' new raw spaces ');
    final capable = await edit.read(
      PublicEditLink.parse(owner.baseUri, receipt.editingUri!.toString()),
      password: ' new raw spaces ',
    );
    check(
      capable.content == original,
      'Existing edit capability still requires the current body password',
    );
    protection = await passwords.read(id);
    await passwords.change(
      protection,
      newPassword: '',
      currentPassword: ' new raw spaces ',
    );
    check(!(await passwords.read(id)).protected, 'Actual password removed');
    plain = await readers.load(receipt.reference);
    check(
      plain.content == original && !plain.locked,
      'Removing password preserves exact body and sharing',
    );
    receipt = await settings.changeToken(
      target,
      receipt,
      ShareTokenAction.disable,
    );
    check(!receipt.editingEnabled, 'Actual edit capability disabled');
    await settings.unpublish(target);
    check(
      !await settings.status(target),
      'Actual withdrawal removes explicit and implicit public blog visibility',
    );
    rejected = false;
    try {
      await readers.load(receipt.reference);
    } on ApiFailure catch (e) {
      rejected = e.status == 404;
    }
    check(rejected, 'Withdrawn real public link unavailable');
    final bookTarget = OwnerShareTarget(
      kind: PublicShareKind.book,
      id: bookId,
      title: 'whole book',
    );
    final publishedBook = await settings.publish(bookTarget);
    check(
      !publishedBook.editingEnabled && await settings.status(bookTarget),
      'Whole book publication has no editor capability',
    );
    final document = (await docs.tree(bookId)).single;
    final docTarget = OwnerShareTarget(
      kind: PublicShareKind.document,
      id: document.id,
      title: document.name,
    );
    final docReceipt = await settings.publish(docTarget);
    check(
      (await readers.load(docReceipt.reference)).targetId == document.id,
      'Actual document sharing target',
    );
    final docEdit = await settings.changeToken(
      docTarget,
      docReceipt,
      ShareTokenAction.enable,
    );
    check(docEdit.editingEnabled, 'Actual document edit capability enabled');
    await settings.unpublish(docTarget);
    check(!await settings.status(docTarget), 'Document actual withdrawal');
    await settings.unpublish(bookTarget);
    check(!await settings.status(bookTarget), 'Book actual withdrawal');
    rejected = false;
    try {
      await RemoteShareSettingsRepository(anonymous).publish(target);
    } on ApiFailure catch (e) {
      rejected = e.status == 401 || e.status == 403;
    }
    check(rejected, 'Anonymous publication rejected');
    stdout.writeln(
      'PASS owner sharing settings: read-only status, explicit publish, preserved actual token on republish, enable/reset/old-token403/disable, blog+book+document revoke, anonymous authorization; actual body password set/change/wrong current/remove with raw spaces and unchanged body',
    );
  } finally {
    anonymous.close();
    await notes.remove(id);
    await books.remove(bookId);
  }
}
