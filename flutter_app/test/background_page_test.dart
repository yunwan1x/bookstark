import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart' show CupertinoSlider;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/background_repository.dart';
import 'package:bookstark_flutter/features/profile/background_page.dart';
import 'package:bookstark_flutter/widgets/background_surface.dart';
import 'background_controller_test.dart' as fixture;

Future<void> click(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> open(
  WidgetTester tester,
  fixture.Repo repo, {
  bool english = false,
  Future<void> Function(BackgroundPreference)? apply,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: BackgroundPage(
        repository: repo,
        preference: repo.current,
        english: english,
        onApplied: (p, _) async {
          await apply?.call(p);
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'fade slider keyboard changes real value and persists only on explicit save',
    (tester) async {
      final r = fixture.Repo();
      await open(tester, r);
      final slider = find.byType(CupertinoSlider);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(slider);
      await tester.tapAt(
        Offset(bounds.left + bounds.width * .65, bounds.center.dy),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.text('64%'), findsOneWidget);
      expect(r.writes, 0);
      await click(tester, find.text('保存背景设置'));
      expect(r.current.fade, 64);
      expect(r.writes, 1);
    },
  );

  testWidgets(
    'fade slider supports real drag without changing remote preference before save',
    (tester) async {
      final r = fixture.Repo();
      await open(tester, r);
      final slider = find.byType(CupertinoSlider);
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(slider);
      await tester.dragFrom(
        Offset(bounds.left + bounds.width * .65, bounds.center.dy),
        const Offset(-100, 0),
      );
      await tester.pumpAndSettle();
      expect(r.writes, 0);
      expect(r.current.fade, 65);
      await click(tester, find.text('保存背景设置'));
      expect(r.writes, 1);
      expect(r.current.fade, lessThan(65));
    },
  );

  testWidgets(
    'preview is local until explicit save, actual readback applies background callback',
    (tester) async {
      final r = fixture.Repo();
      BackgroundPreference? applied;
      await open(
        tester,
        r,
        apply: (p) async {
          applied = p;
        },
      );
      await click(tester, find.text('纯色'));
      expect(r.writes, 0);
      expect(applied, isNull);
      await click(tester, find.text('保存背景设置'));
      expect(r.writes, 1);
      expect(applied?.mode, 'solid');
      expect(find.text('实际背景设置已核对。'), findsOneWidget);
    },
  );
  testWidgets(
    'restore defaults is only a draft; unknown save only reads and never repeats upload',
    (tester) async {
      final r = fixture.Repo()
        ..current = const BackgroundPreference(
          mode: 'solid',
          animated: false,
          fade: 20,
        )
        ..lose = true;
      await open(tester, r);
      await click(tester, find.text('恢复默认并移除图片'));
      expect(r.writes, 0);
      expect(r.current.mode, 'solid');
      await click(tester, find.text('保存背景设置'));
      expect(r.writes, 1);
      expect(find.text('保存结果未知，不会自动重发图片。'), findsOneWidget);
      await click(tester, find.text('只读核对背景结果'));
      expect(r.writes, 1);
      expect(find.text('实际背景设置已核对。'), findsOneWidget);
    },
  );
  testWidgets(
    'custom image without actual file cannot save; server conflicts offer observed adoption',
    (tester) async {
      final r = fixture.Repo();
      await open(tester, r);
      await click(tester, find.widgetWithText(ChoiceChip, '自定义图片'));
      await click(tester, find.text('保存背景设置'));
      expect(r.writes, 0);
      expect(find.text('请先选择有效图片和背景设置。'), findsOneWidget);
      await click(tester, find.text('纯色'));
      r.current = const BackgroundPreference(fade: 30);
      await click(tester, find.text('保存背景设置'));
      expect(r.writes, 0);
      await click(tester, find.text('采用服务器背景'));
      expect(find.text('30%'), findsOneWidget);
      expect(r.writes, 0);
    },
  );
  testWidgets(
    'English narrow 200 percent keeps save and native unsaved dialog reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final r = fixture.Repo();
      await open(tester, r, english: true);
      await click(tester, find.text('Solid'));
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Leave background settings?'), findsOneWidget);
      await click(tester, find.text('Cancel'));
      expect(r.writes, 0);
      await click(tester, find.text('Save background preferences'));
      expect(r.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'reduced motion pauses real gradient ticker and private scope makes only outer canvas transparent',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: BackgroundSurface(
              preference: BackgroundPreference(),
              child: SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
