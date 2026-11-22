import 'dart:convert';

import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_public_tags.dart';
import 'package:bookstark_flutter/features/admin/admin_public_tags_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_public_tags_page.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
const original =
    ' { "mode":"manual", "labels":["技术"], "future":{"keep":[1,true]} } ';
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final kind in AdminPublicTagKind.values)
    {'key': kind.key, 'value': original, 'description': '', 'update_time': ''},
]);

class TagRepository extends AdminSettingsRepository {
  TagRepository() : super(BookstarkClient('https://example.invalid'));
  int puts = 0;
  Map<String, String>? patch;
  AdminSettingsSnapshot value = snapshot();
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => value;
  @override
  Future<void> savePublicTags(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminPublicTagChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
  }
}

void main() {
  test(
    'untouched raw JSON and nested unknown fields survive mode/label edits',
    () {
      final config = AdminPublicTagConfig.parse(original);
      expect(config.changeMode('manual'), original);
      final changed = config.changeLabels(' 技术 \n阅读\n');
      final decoded = jsonDecode(changed) as Map<String, dynamic>;
      expect(decoded['labels'], [' 技术 ', '阅读']);
      expect(decoded['future'], {
        'keep': [1, true],
      });
      expect(
        AdminPublicTagConfig.parse('{"mode":"auto","labels":null}').labels,
        isEmpty,
      );
      expect(AdminPublicTagConfig.parse('{"mode":"auto"}').labels, isEmpty);
    },
  );
  test(
    'public tag server limits reject duplicates blanks and byte overflow',
    () {
      for (final labels in [
        ['', 'a'],
        ['a', 'a'],
        List.filled(101, 'a'),
        [List.filled(67, '中').join()],
      ]) {
        expect(
          () => AdminPublicTagConfig.parse(
            jsonEncode({'mode': 'manual', 'labels': labels}),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => AdminPublicTagConfig.parse('{"mode":"other","labels":[]}'),
        throwsFormatException,
      );
      expect(
        () => AdminPublicTagConfig.parse('{"mode":"manual","labels":false}'),
        throwsFormatException,
      );
      expect(
        () => AdminPublicTagConfig.parse(
          '{"mode":"auto","future":"${List.filled(32000, 'a').join()}"}',
        ),
        throwsFormatException,
      );
      expect(
        AdminPublicTagConfig.parse('{"mode":"manual","labels":[" "]}').labels,
        [' '],
      );
    },
  );
  test(
    'scene drafts remain independent and only changed valid config saves',
    () async {
      final repo = TagRepository();
      final c = AdminPublicTagsController(repo, owner);
      await c.load();
      c.editLabels('技术\n阅读\n');
      c.select(AdminPublicTagKind.book);
      expect(c.text, original);
      await c.save();
      expect(repo.patch!.keys, ['public_feed_tags_article']);
      expect(jsonDecode(repo.patch!.values.single)['future'], {
        'keep': [1, true],
      });
      c.dispose();
    },
  );
  test(
    'invalid label draft stays editable and blocked without losing original fields',
    () async {
      final repo = TagRepository();
      final c = AdminPublicTagsController(repo, owner);
      await c.load();
      c.editLabels('技术\n技术');
      await c.save();
      expect(repo.puts, 0);
      expect(AdminPublicTagConfig.decodeForEditing(c.text).labels, [
        '技术',
        '技术',
      ]);
      c.editLabels('技术\n阅读');
      await c.save();
      expect(repo.puts, 1);
      c.dispose();
    },
  );
  test(
    'invalid/missing configuration is not silently converted to auto',
    () async {
      final repo = TagRepository()
        ..value = AdminSettingsSnapshot.parse(<Object?>[]);
      final c = AdminPublicTagsController(repo, owner);
      await c.load();
      expect(c.text, '');
      expect(c.dirty, isFalse);
      c.editMode('auto');
      expect(c.text, '');
      final oldRevision = c.revision;
      c.select(AdminPublicTagKind.book);
      c.replaceReviewedInvalid(confirmedRevision: oldRevision, mode: 'auto');
      expect(c.text, '');
      c.replaceReviewedInvalid(confirmedRevision: c.revision, mode: 'auto');
      expect(AdminPublicTagConfig.parse(c.text).mode, 'auto');
      expect(repo.puts, 0);
      c.dispose();
    },
  );
  testWidgets('large-text public tags preserves a typed trailing newline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminPublicTagsController(TagRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminPublicTagsPage(controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final labels = find.byKey(const ValueKey('public-tag-labels'));
    await tester.scrollUntilVisible(
      labels,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(labels, '技术\n');
    await tester.pump();
    expect(tester.widget<TextField>(labels).controller!.text, '技术\n');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
