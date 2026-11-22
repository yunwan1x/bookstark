import 'dart:async';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_format_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_preview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

class WindowGuard implements AdminAssetWindowGuard {
  WindowGuard({this.ready, this.fail = false});
  final Completer<void>? ready;
  final bool fail;
  int acquired = 0, closed = 0;
  @override
  Future<void> acquire() async {
    acquired++;
    if (fail) throw StateError('synthetic-provider-detail');
    await ready?.future;
  }

  @override
  Future<void> close() async {
    if (closed == 0) closed++;
  }
}

LegacyFormatSource data({String scope = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'}) =>
    LegacyFormatSource(
      archiveSha256: 'a' * 64,
      scopeKey: scope,
      items: const [
        LegacyFormatItem(
          id: 'note',
          title: '旅行手记',
          collection: 'note',
          originalBody: '\uFEFF# exact\r\n',
          passwordHash: '',
        ),
        LegacyFormatItem(
          id: 'article',
          title: '网页收藏',
          collection: 'article',
          originalBody: '<p>exact</p>',
          passwordHash: '',
        ),
        LegacyFormatItem(
          id: 'protected',
          title: '会议纪要',
          collection: 'note',
          originalBody: 'ENC:v1:synthetic-original-ciphertext',
          passwordHash: 'synthetic-original-hash',
        ),
      ],
    );

Future<void> tap(WidgetTester tester, Finder target) async {
  for (var i = 0; i < 16 && target.evaluate().isEmpty; i++) {
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -600),
    );
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> size(WidgetTester tester, {double width = 390}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> close(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

Future<void> preview(
  WidgetTester tester, {
  required WindowGuard Function() guard,
  LegacyPreviewUnlocker? unlocker,
  LegacyContentFormat? selected,
  bool english = false,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocalLegacyPreviewPage(
                  item: data().byId['protected']!,
                  isCurrentScope: () => true,
                  english: english,
                  selectedFormat: selected,
                  unlocker: unlocker,
                  windowGuardFactory: guard,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tap(tester, find.text('open'));
}

void main() {
  testWidgets(
    'review places selected format below title and edit changes only its item',
    (tester) async {
      await size(tester);
      final original = data();
      LegacyFormatSelection? result;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalLegacyFormatPage(
            source: original,
            initial: LegacyFormatSelection(
              original,
              choices: const {
                'note': LegacyContentFormat.markdown,
                'article': LegacyContentFormat.html,
                'protected': LegacyContentFormat.markdown,
              },
            ),
            isCurrentScope: () => true,
            onResolved: (value) async {
              result = value;
            },
          ),
        ),
      );
      final card = find.byKey(const ValueKey('legacy-format-item:note'));
      final title = find.descendant(of: card, matching: find.text('旅行手记'));
      final format = find.descendant(
        of: card,
        matching: find.text('格式：Markdown'),
      );
      expect(
        tester.getTopLeft(format).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
      );
      expect(tester.getTopLeft(format).dx, tester.getTopLeft(title).dx);
      expect(find.text('使用原密码预览'), findsNothing);
      await tap(tester, find.byTooltip('修改格式：旅行手记'));
      await tap(tester, find.text('HTML 网页'));
      await tap(tester, find.text('确认选择'));
      expect(
        find.descendant(of: card, matching: find.text('格式：HTML 网页')),
        findsOneWidget,
      );
      await tap(tester, find.text('保存选择并继续'));
      expect(result!.choices, {
        'note': LegacyContentFormat.html,
        'article': LegacyContentFormat.html,
        'protected': LegacyContentFormat.markdown,
      });
      expect(original.byId['note']!.originalBody, '\uFEFF# exact\r\n');
      await close(tester);
    },
  );

  testWidgets(
    'initial page never guesses formats or submits incomplete choices',
    (tester) async {
      await size(tester);
      var submitted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalLegacyFormatPage(
            source: data(),
            isCurrentScope: () => true,
            onResolved: (_) async {
              submitted++;
            },
          ),
        ),
      );
      expect(find.text('尚有 3 项未选择'), findsOneWidget);
      expect(find.text('选择格式'), findsNWidgets(3));
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '继续核对'),
      );
      expect(button.onPressed, isNull);
      expect(submitted, 0);
      await close(tester);
    },
  );

  testWidgets(
    'single choice then batch preserves prior choice and submits one body-free recipe',
    (tester) async {
      await size(tester);
      LegacyFormatSelection? result;
      var submitted = 0;
      final original = data();
      await tester.pumpWidget(
        MaterialApp(
          home: LocalLegacyFormatPage(
            source: original,
            isCurrentScope: () => true,
            onResolved: (value) async {
              submitted++;
              result = value;
            },
          ),
        ),
      );
      await tap(tester, find.text('选择格式').first);
      expect(
        tester
            .widget<RadioGroup<LegacyContentFormat>>(
              find.byType(RadioGroup<LegacyContentFormat>),
            )
            .groupValue,
        isNull,
      );
      await tap(tester, find.text('Markdown'));
      await tap(tester, find.text('确认选择'));
      expect(find.text('尚有 2 项未选择'), findsOneWidget);
      await tap(tester, find.text('批量选择格式'));
      expect(find.text('仅应用于尚未选择的 2 项'), findsOneWidget);
      await tap(
        tester,
        find.byType(DropdownButtonFormField<LegacyContentFormat>),
      );
      await tap(tester, find.text('HTML 网页').last);
      await tap(tester, find.text('应用选择'));
      await tap(tester, find.text('保存选择并继续'));
      expect(submitted, 1);
      expect(result!.choices, {
        'note': LegacyContentFormat.markdown,
        'article': LegacyContentFormat.html,
        'protected': LegacyContentFormat.html,
      });
      expect(
        result!.toJson().toString(),
        isNot(contains('synthetic-original')),
      );
      expect(original.byId['note']!.originalBody, '\uFEFF# exact\r\n');
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '已保存选择'))
            .onPressed,
        isNull,
      );
      await close(tester);
    },
  );

  testWidgets(
    'source replacement closes only its owned sheet and clears choices',
    (tester) async {
      await size(tester);
      var original = data();
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return LocalLegacyFormatPage(
                source: original,
                isCurrentScope: () => true,
                onResolved: (_) async {},
              );
            },
          ),
        ),
      );
      await tap(tester, find.text('选择格式').first);
      await tap(tester, find.text('Markdown'));
      await tap(tester, find.text('确认选择'));
      await tap(tester, find.text('选择格式').first);
      update(() => original = data(scope: 'c' * 32));
      await tester.pumpAndSettle();
      expect(find.byType(RadioGroup<LegacyContentFormat>), findsNothing);
      expect(find.text('尚有 3 项未选择'), findsOneWidget);
      expect(find.text('选择格式'), findsNWidgets(3));
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'retired source scope closes a live preview and cannot revive in place',
    (tester) async {
      await size(tester);
      final original = data();
      var active = true;
      late StateSetter update;
      final guard = WindowGuard();
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, set) {
              update = set;
              return LocalLegacyFormatPage(
                source: original,
                isCurrentScope: () => active,
                onResolved: (_) async {},
                windowGuardFactory: () => guard,
                unlocker: (item, password, owner) async => 'private preview',
              );
            },
          ),
        ),
      );
      await tap(tester, find.text('使用原密码预览'));
      await tester.enterText(find.byType(TextField), 'pw');
      await tap(tester, find.text('解锁并预览'));
      expect(find.byType(SelectableText), findsOneWidget);
      update(() => active = false);
      await tester.pumpAndSettle();
      expect(find.byType(LocalLegacyPreviewPage), findsNothing);
      expect(find.textContaining('private preview'), findsNothing);
      expect(guard.closed, 1);
      expect(find.text('来源已失效，请返回重新选择'), findsOneWidget);
      update(() => active = true);
      await tester.pumpAndSettle();
      expect(find.text('来源已失效，请返回重新选择'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('large sources paginate without building every resource row', (
    tester,
  ) async {
    await size(tester);
    final original = LegacyFormatSource(
      archiveSha256: 'a' * 64,
      scopeKey: 'b' * 32,
      items: List.generate(
        45,
        (i) => LegacyFormatItem(
          id: '$i',
          title: 'item $i',
          collection: 'note',
          originalBody: 'body',
          passwordHash: '',
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LocalLegacyFormatPage(
          source: original,
          isCurrentScope: () => true,
          onResolved: (_) async {},
        ),
      ),
    );
    expect(find.text('item 44'), findsNothing);
    await tap(tester, find.text('下一页'));
    await tap(tester, find.text('下一页'));
    expect(find.text('第 3 / 3 页'), findsOneWidget);
    expect(find.text('item 44'), findsOneWidget);
    expect(
      find
          .byWidgetPredicate((widget) {
            final key = widget.key;
            return key is ValueKey<String> &&
                key.value.startsWith('legacy-format-item:');
          })
          .evaluate()
          .length,
      lessThanOrEqualTo(20),
    );
    await close(tester);
  });

  testWidgets(
    '320dp English 200 percent supports last format and complete toolbar text',
    (tester) async {
      await size(tester, width: 320);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: LocalLegacyFormatPage(
            source: data(),
            english: true,
            isCurrentScope: () => true,
            onResolved: (_) async {},
          ),
        ),
      );
      final title = tester.renderObject<RenderParagraph>(
        find.text('Confirm content formats'),
      );
      expect(title.didExceedMaxLines, isFalse);
      await tap(
        tester,
        find.descendant(
          of: find.byKey(const ValueKey('legacy-format-item:note')),
          matching: find.text('Choose format'),
        ),
      );
      await tap(tester, find.text('Presentation'));
      await tap(tester, find.text('Confirm choice'));
      // Return to the progress row; the selected source row stays at its
      // previous scroll position rather than jumping the user to the top.
      await tester.drag(
        find.byType(CustomScrollView).last,
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 items still need a format'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'secure acquisition precedes password input and repeated resume does not leak leases',
    (tester) async {
      await size(tester);
      final ready = Completer<void>();
      final guard = WindowGuard(ready: ready);
      var leases = 0;
      await preview(
        tester,
        guard: () {
          leases++;
          return guard;
        },
      );
      expect(find.byType(TextField), findsNothing);
      ready.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      (tester.state(find.byType(LocalLegacyPreviewPage))
              as WidgetsBindingObserver)
          .didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(leases, 1);
      await tap(tester, find.text('返回选择'));
      expect(guard.closed, 1);
      await close(tester);
    },
  );

  testWidgets(
    'failed secure acquisition never exposes an input or original protected body',
    (tester) async {
      await size(tester);
      final guard = WindowGuard(fail: true);
      await preview(tester, guard: () => guard);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('synthetic'), findsNothing);
      expect(find.text('无法开启受保护预览，请返回后重试'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'wrong password has fixed text; success shows inert exact excerpt with explicit format',
    (tester) async {
      await size(tester);
      var count = 0;
      final passwords = <String>[];
      await preview(
        tester,
        guard: () => WindowGuard(),
        unlocker: (item, password, cancellation) async {
          passwords.add(password);
          if (++count == 1) {
            throw const LocalContentCryptoFailure(
              LocalContentCryptoReason.wrongPassword,
            );
          }
          return '\uFEFF<script>literal</script>\r\n# 原文😀';
        },
      );
      await tester.enterText(find.byType(TextField), ' original password ');
      await tap(tester, find.text('解锁并预览'));
      expect(find.text('密码不正确，请重试'), findsOneWidget);
      expect(passwords.single, ' original password ');
      await tap(tester, find.text('解锁并预览'));
      expect(find.byType(TextField), findsNothing);
      expect(
        tester.widget<SelectableText>(find.byType(SelectableText)).data,
        '\uFEFF<script>literal</script>\r\n# 原文😀',
      );
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '使用此格式'))
            .onPressed,
        isNull,
      );
      expect(passwords.length, 2);
      await close(tester);
    },
  );

  testWidgets(
    'preview takes 2048 Unicode runes without rewriting encrypted source',
    (tester) async {
      await size(tester);
      await preview(
        tester,
        guard: () => WindowGuard(),
        unlocker: (item, password, cancellation) async => '😀' * 3000,
      );
      await tester.enterText(find.byType(TextField), 'pw');
      await tap(tester, find.text('解锁并预览'));
      final text = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(text.runes.length, 2048);
      expect(text, '😀' * 2048);
      await close(tester);
    },
  );

  testWidgets(
    'background cancels, clears input, masks again and discards late plaintext',
    (tester) async {
      await size(tester);
      final guards = <WindowGuard>[];
      final pending = Completer<String>();
      AttachmentCancellation? cancellation;
      var calls = 0;
      await preview(
        tester,
        guard: () {
          final guard = WindowGuard();
          guards.add(guard);
          return guard;
        },
        unlocker: (item, password, owner) {
          calls++;
          cancellation = owner;
          return pending.future;
        },
      );
      await tester.enterText(find.byType(TextField), 'private input');
      await tap(tester, find.byTooltip('显示密码'));
      await tap(tester, find.text('解锁并预览'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(cancellation!.cancelled, isTrue);
      expect(find.byType(TextField), findsNothing);
      expect(guards.first.closed, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, '');
      expect(field.obscureText, isTrue);
      expect(guards.length, 2);
      pending.complete('late private plaintext');
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('late private'), findsNothing);
      expect(calls, 1);
      await close(tester);
    },
  );

  testWidgets(
    'back during unlock cancels and late success cannot reopen preview',
    (tester) async {
      await size(tester);
      final pending = Completer<String>();
      AttachmentCancellation? cancellation;
      final guard = WindowGuard();
      await preview(
        tester,
        guard: () => guard,
        unlocker: (item, password, owner) {
          cancellation = owner;
          return pending.future;
        },
      );
      await tester.enterText(find.byType(TextField), 'pw');
      await tap(tester, find.text('解锁并预览'));
      await tap(tester, find.text('返回选择'));
      expect(cancellation!.cancelled, isTrue);
      pending.complete('late secret');
      await tester.pumpAndSettle();
      expect(find.byType(LocalLegacyPreviewPage), findsNothing);
      expect(find.textContaining('late secret'), findsNothing);
      expect(guard.closed, 1);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'quick back before acquisition closes late lease without exposing password',
    (tester) async {
      await size(tester);
      final ready = Completer<void>();
      final guard = WindowGuard(ready: ready);
      await preview(tester, guard: () => guard);
      await tap(tester, find.text('返回选择'));
      ready.complete();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(guard.closed, 1);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('English large text unlock error and return remain reachable', (
    tester,
  ) async {
    await size(tester, width: 320);
    await preview(
      tester,
      guard: () => WindowGuard(),
      english: true,
      scale: 2,
      unlocker: (item, password, cancellation) async {
        throw const LocalContentCryptoFailure(
          LocalContentCryptoReason.wrongPassword,
        );
      },
    );
    await tester.enterText(find.byType(TextField), 'pw');
    await tap(tester, find.text('Unlock and preview'));
    expect(find.text('Incorrect password. Try again.'), findsOneWidget);
    await tap(tester, find.text('Back to choices'));
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
