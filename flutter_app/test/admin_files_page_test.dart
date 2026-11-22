import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_files_page.dart';
import 'support/admin_files_harness.dart';

class OwnedGuard implements AdminAssetWindowGuard {
  int acquired = 0, released = 0;
  Completer<void>? gate;
  @override
  Future<void> acquire() async {
    acquired++;
    await gate?.future;
  }

  @override
  Future<void> close() async {
    released++;
  }
}

void main() {
  late AdminFilesHarness h;
  late OwnedGuard secure;
  var returned = 0;
  setUp(() {
    h = AdminFilesHarness();
    secure = OwnedGuard();
    returned = 0;
  });
  tearDown(() {
    h.close();
  });
  Future<void> mount(
    WidgetTester tester, {
    bool english = false,
    double scale = 1,
    Size size = const Size(390, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AdminFilesPage(
          scope: h.scope,
          host: AdminAssetHostMetadata.parse(h.host),
          secureWindow: secure,
          english: english,
          onReturn: () {
            returned++;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'No remote read before window protection; catalog is actual data',
    (tester) async {
      secure.gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminFilesPage(
            scope: h.scope,
            host: AdminAssetHostMetadata.parse(h.host),
            secureWindow: secure,
            onReturn: () {},
          ),
        ),
      );
      await tester.pump();
      expect(h.requests, isEmpty);
      secure.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('a.txt'), findsOneWidget);
      expect(secure.acquired, 1);
      expect(h.mutations, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(secure.released, greaterThanOrEqualTo(1));
    },
  );
  testWidgets(
    'Delete cancellation sends nothing; confirmation uses reviewed target once',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      expect(find.textContaining('/work/a.txt'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.mutations, 0);
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认操作'));
      await tester.pumpAndSettle();
      expect(h.mutations, 1);
      expect(h.requests.last.method, 'DELETE');
      expect(h.requests.last.url.queryParameters, {
        'path': '/work/a.txt',
        'recursive': 'false',
      });
      expect(find.textContaining('已收到服务器确认'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('Permission matrix cancellation never writes', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('文件操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('权限'));
    await tester.pumpAndSettle();
    expect(find.text('0640'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(9));
    await tester.tap(find.byType(Checkbox).last);
    await tester.pump();
    expect(find.text('0641'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(h.mutations, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final layout in [
    (english: false, size: const Size(320, 480), scale: 2.0),
    (english: true, size: const Size(320, 480), scale: 2.0),
    (english: true, size: const Size(780, 260), scale: 2.0),
  ]) {
    testWidgets(
      'Catalog large text remains scrollable ${layout.size} ${layout.english}',
      (tester) async {
        await mount(
          tester,
          english: layout.english,
          size: layout.size,
          scale: layout.scale,
        );
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('a.txt'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('a.txt'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets('Owner revocation removes catalog and releases protection', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('a.txt'), findsOneWidget);
    h.scope.close();
    await tester.pumpAndSettle();
    expect(find.text('a.txt'), findsNothing);
    expect(find.text('管理员会话已失效，请返回重新登录。'), findsOneWidget);
    expect(secure.released, greaterThanOrEqualTo(1));
    expect(h.mutations, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets('Returning from catalog releases window protection', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(returned, 1);
    expect(secure.released, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  for (final permission in [false, true]) {
    testWidgets(
      'Background dismisses typed dialog without writing: $permission',
      (tester) async {
        await mount(tester);
        if (permission) {
          await tester.tap(find.byTooltip('文件操作'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('权限'));
        } else {
          await tester.tap(find.text('新建目录'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        expect(h.mutations, 0);
        expect(tester.takeException(), isNull);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(h.mutations, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }
  testWidgets(
    'Octal field and matrix synchronize; special bits are not silently accepted',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('文件操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('权限'));
      await tester.pumpAndSettle();
      final field = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '0755');
      await tester.pump();
      expect(
        tester
            .widgetList<Checkbox>(find.byType(Checkbox))
            .map((box) => box.value)
            .toList(),
        [true, true, true, true, false, true, true, false, true],
      );
      await tester.enterText(field, '4777');
      await tester.pump();
      final next = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '下一步'),
      );
      expect(next.onPressed, isNull);
      expect(h.mutations, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(h.mutations, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
