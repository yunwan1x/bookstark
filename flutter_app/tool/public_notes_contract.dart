import 'dart:io';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';
import 'package:bookstark_flutter/core/public_shares_repository.dart';
import 'package:bookstark_flutter/core/share_settings_repository.dart';
import 'package:bookstark_flutter/core/content_password_repository.dart';
import 'package:bookstark_flutter/core/public_notes_repository.dart';

void check(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

Future<void> runPublicNotesContract(BookstarkClient owner) async {
  final notes = RemoteNotesRepository(owner),
      articles = RemoteNotesRepository(
        owner,
        collection: NoteCollection.article,
      );
  final settings = RemoteShareSettingsRepository(owner),
      ids = <int>[],
      anonymous = BookstarkClient(owner.baseUri.toString());
  int? article;
  try {
    final private = await notes.save(
      const Note(title: '私有时间线排除契约', content: 'must not appear'),
    );
    ids.add(private);
    for (var i = 0; i < 21; i++) {
      final id = await notes.save(
        Note(
          title: '公开时间线契约 $i',
          content:
              '# Public timeline body $i\n\nQuoted ; var container = marker',
          labels: ['时间线精确'],
        ),
      );
      ids.add(id);
      await settings.publish(
        OwnerShareTarget(kind: PublicShareKind.blog, id: id, title: 'fixture'),
      );
    }
    final protected = await notes.save(
      const Note(
        title: '公开时间线受保护契约',
        content: '# Protected timeline secret',
        labels: ['do-not-leak-protected-label'],
      ),
    );
    ids.add(protected);
    await settings.publish(
      OwnerShareTarget(
        kind: PublicShareKind.blog,
        id: protected,
        title: 'fixture',
      ),
    );
    final passwords = RemoteContentPasswordRepository(owner);
    await passwords.change(
      await passwords.read(protected),
      newPassword: ' timeline raw password ',
    );
    article = await articles.save(
      const Note(title: '文章时间线排除契约', content: 'public article is not a note'),
    );
    await settings.publish(
      OwnerShareTarget(
        kind: PublicShareKind.blog,
        id: article,
        title: 'fixture article',
      ),
    );
    final repository = RemotePublicNotesRepository(anonymous);
    final first = await repository.load(1),
        second = await repository.load(2),
        empty = await repository.load(3);
    check(
      first.items.length == 20 &&
          second.items.length == 2 &&
          empty.items.isEmpty,
      'Actual fixed20 HTML pagination without fabricated totals',
    );
    final all = [...first.items, ...second.items];
    check(
      all.map((item) => item.id).toSet().length == 22 &&
          !all.any((item) => item.id == private || item.id == article),
      'Actual private notes and public articles excluded',
    );
    final locked = all.singleWhere((item) => item.id == protected);
    check(
      locked.locked && locked.preview.isEmpty && locked.labels.isEmpty,
      'Actual locked note leaks masked in native timeline model',
    );
    final ordinary = all.firstWhere((item) => !item.locked);
    final detail = await RemotePublicSharesRepository(
      anonymous,
    ).load(ordinary.reference);
    check(
      detail.targetId == ordinary.id &&
          detail.content.startsWith('# Public timeline body'),
      'Actual full public reader uses identify and re-reads Markdown rather than preview',
    );
    stdout.writeln(
      'PASS public notes timeline: anonymous inert HTML, actual fixed20 pagination and empty third page, exact public-note IDs, private/article exclusion, locked preview/label masking and full public Markdown re-read',
    );
  } finally {
    anonymous.close();
    for (final id in ids) {
      await notes.remove(id);
    }
    if (article != null) {
      await articles.remove(article);
    }
  }
}
