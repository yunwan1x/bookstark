import 'dart:async';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/bookmark_draft_vault.dart';
import 'package:bookstark_flutter/core/bookmarks_repository.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmark_editor_page.dart';
import 'package:bookstark_flutter/features/bookmarks/bookmarks_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../tool/fixtures/bookmarks.dart';

void main() {
  testWidgets(
    'bookmark list exposes public rows as read-only for other owners',
    (tester) async {
      final repo = BookmarksFixture();
      repo.items[4] = const BookmarkItem(
        id: 4,
        memberId: 8,
        title: '他人公开书签',
        url: 'https://other.test/',
        isPublic: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: BookmarksPage(repository: repo, labelsRepository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flutter 开发文档'), findsOneWidget);
      expect(find.byTooltip('书签操作'), findsNWidgets(3));
      await tester.tap(find.text('公开').first);
      await tester.pumpAndSettle();
      expect(find.text('他人公开书签'), findsOneWidget);
      expect(find.byTooltip('书签操作'), findsOneWidget);
      expect(repo.saves, 0);
    },
  );
  testWidgets('metadata cannot overwrite typing during fetch or change URL', (
    tester,
  ) async {
    final repo = BookmarksFixture();
    var pending = Completer<BookmarkMetadata>();
    repo.onMetadata = (_) => pending.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: BookmarkEditorPage(
          repository: repo,
          bookmark: repo.items[1]!,
          labelsRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('获取网页信息'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '用户正在输入');
    pending.complete(
      const BookmarkMetadata(title: '不能覆盖', description: '新的说明'),
    );
    await tester.pumpAndSettle();
    expect(find.text('用户正在输入'), findsOneWidget);
    expect(find.text('不能覆盖'), findsNothing);
    expect(find.text('新的说明'), findsOneWidget);
    pending = Completer<BookmarkMetadata>();
    await tester.tap(find.text('获取网页信息'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).first,
      'https://changed.test/',
    );
    pending.complete(const BookmarkMetadata(title: '过期网页标题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('网址已变化'), findsOneWidget);
    expect(find.text('过期网页标题'), findsNothing);
    expect(repo.saves, 0);
  });
  testWidgets(
    'duplicate opens existing without overwriting privacy and keeps new draft',
    (tester) async {
      final values = <String, String>{};
      final vault = BookmarkDraftVault(
        namespace: 'test',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
        deleteValue: (key) async {
          values.remove(key);
        },
      );
      final repo = BookmarksFixture();
      await tester.pumpWidget(
        MaterialApp(
          theme: bookstarkTheme(),
          home: BookmarkEditorPage(
            repository: repo,
            bookmark: const BookmarkItem(
              title: '未确认输入',
              url: 'https://flutter.dev',
              isPublic: true,
            ),
            labelsRepository: repo,
            vault: vault,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('网址已存在'), findsOneWidget);
      expect(repo.saves, 0);
      await tester.tap(find.text('编辑已有书签'));
      await tester.pumpAndSettle();
      expect(find.text('编辑书签'), findsOneWidget);
      expect(find.text('Flutter 开发文档'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      expect(
        (await vault.read(const BookmarkItem(title: '', url: '')))?.title,
        '未确认输入',
      );
      expect(repo.saves, 0);
    },
  );
  testWidgets('English bookmark editor supports 320dp at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = BookmarksFixture();
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: BookmarkEditorPage(
          repository: repo,
          bookmark: repo.items[1]!,
          labelsRepository: repo,
          english: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Make public'),
      150,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Make public'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
