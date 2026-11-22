import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_review.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/html/local_html_browser_preview.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_candidate_reader_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_candidate_review_page.dart';
import 'package:bookstark_flutter/widgets/bookstark_markdown.dart';
import 'package:bookstark_flutter/widgets/native_image.dart';

class _Guard implements AdminAssetWindowGuard {
  _Guard(this.gate);
  final Completer<void>? gate;
  bool acquired = false, closed = false;
  @override
  Future<void> acquire() async {
    await gate?.future;
    if (closed) throw StateError('closed');
    acquired = true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cryptoChannel = MethodChannel('bookstark/review-page-unit-crypto');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root, parent;
  late LegacyZipStage stage;
  late LegacyGoExport source;
  late LegacyFormatSelection selection;
  late LegacyCandidateReviewSession session;
  late Map vector;
  late String plain;
  bool current = true;
  final guards = <_Guard>[],
      viewChannels = <MethodChannel>[],
      nativeCalls = <MethodCall>[],
      viewSources = <String>[];
  Completer<void>? secureGate, unlockGate;
  int unlockCalls = 0, cancelCalls = 0;
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  Future<LegacyCandidateReviewSession> buildSession() =>
      LegacyCandidateReviewSession.build(
        stage: stage,
        selection: selection,
        privateParent: parent,
        factory: databaseFactoryFfiNoIsolate,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
        isCurrentScope: () => current,
        crypto: NativeLocalContentCrypto(channel: cryptoChannel),
      );
  setUp(() async {
    current = true;
    secureGate = null;
    unlockGate = null;
    unlockCalls = 0;
    cancelCalls = 0;
    guards.clear();
    viewChannels.clear();
    nativeCalls.clear();
    viewSources.clear();
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await base.create(recursive: true);
    root = await base.createTemp('review-page-');
    parent = await Directory('${root.path}/reviews').create();
    final file = File('test/fixtures/legacy_zip/identity-candidate-review.zip');
    stage = await LegacyZipStage.inspect(
      file,
      privateParent: root,
      expectedSha256: (await sha256.bind(file.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    source = await LegacyGoExport.inspect(stage);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'b' * 32,
    );
    selection = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items)
          item.id: item.title == '项目草稿'
              ? LegacyContentFormat.markdown
              : LegacyContentFormat.html,
      },
    );
    vector =
        (jsonDecode(
                      await File(
                        'tool/legacy_crypto_test/go-vectors.json',
                      ).readAsString(),
                    )
                    as List)
                .first
            as Map;
    plain = await File(
      'test/fixtures/legacy_zip/candidate-review-plain.html',
    ).readAsString();
    messenger.setMockMethodCallHandler(cryptoChannel, (call) async {
      if (call.method == 'cancel') {
        cancelCalls++;
        return null;
      }
      unlockCalls++;
      final args = call.arguments as Map;
      await unlockGate?.future;
      if (args['password'] != vector['password']) {
        throw PlatformException(code: 'WRONG_PASSWORD');
      }
      expect(args['hash'], vector['hash']);
      return {
        'format': 1,
        'id': args['id'],
        'body': Uint8List.fromList(utf8.encode(plain)),
      };
    });
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      nativeCalls.add(call);
      return null;
    });
    await HtmlBrowserSession.closeActive();
    nativeCalls.clear();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map?;
      if (call.method == 'create') {
        final id = args!['id'] as int;
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        if (params['source'] is String) {
          viewSources.add(params['source'] as String);
          if ((params['source'] as String).contains('周末计划')) {
            expect(guards.any((g) => g.acquired && !g.closed), isTrue);
          }
        }
        final channel = MethodChannel('bookstark/local_html_preview/$id');
        viewChannels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          nativeCalls.add(call);
          return null;
        });
        return 99;
      }
      if (call.method == 'resize') {
        return {'width': args!['width'], 'height': args['height']};
      }
      return null;
    });
    session = await buildSession();
  });
  tearDown(() async {
    if (unlockGate != null && !unlockGate!.isCompleted) unlockGate!.complete();
    try {
      await session.close();
    } catch (_) {}
    messenger.setMockMethodCallHandler(cryptoChannel, null);
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in viewChannels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await root.delete(recursive: true);
  });
  _Guard guard() {
    final value = _Guard(secureGate);
    guards.add(value);
    return value;
  }

  Widget app({bool english = false, double scale = 1}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: LocalLegacyCandidateReviewPage(
      session: session,
      english: english,
      windowGuardFactory: guard,
    ),
  );
  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  void pause(WidgetTester tester) {
    final binding = tester.binding;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  }

  void resume(WidgetTester tester) {
    final binding = tester.binding;
    if (binding.lifecycleState == AppLifecycleState.paused) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (binding.lifecycleState == AppLifecycleState.hidden) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    if (binding.lifecycleState != AppLifecycleState.resumed) {
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
  }

  Future<void> mount(
    WidgetTester tester, {
    bool english = false,
    double width = 390,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    resume(tester);
    await tester.pumpWidget(app(english: english, scale: scale));
    await waitFor(
      tester,
      () =>
          find.text(english ? 'Copy verified' : '副本已校验').evaluate().isNotEmpty,
    );
  }

  Future<void> finish(WidgetTester tester) async {
    resume(tester);
    if (unlockGate != null && !unlockGate!.isCompleted) unlockGate!.complete();
    await tester.pumpWidget(const SizedBox());
    var closed = false;
    Object? closeError;
    session.close().then(
      (_) => closed = true,
      onError: (Object error) {
        closeError = error;
        closed = true;
      },
    );
    await waitFor(tester, () => closed);
    expect(closeError, isNull);
    var nativeClosed = false;
    HtmlBrowserSession.closeActive().then((_) => nativeClosed = true);
    await waitFor(tester, () => nativeClosed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> protected(WidgetTester tester) async {
    await tester.tap(find.text('旅行计划'));
    await tester.pumpAndSettle();
    await waitFor(tester, () => find.text('内容已锁定').evaluate().isNotEmpty);
  }

  Future<void> unlock(WidgetTester tester, String password) async {
    await tester.tap(find.text('解锁查看'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.tap(find.widgetWithText(FilledButton, '解锁'));
    await tester.pump();
  }

  testWidgets(
    'prototype overview uses actual counts, order and collection filters',
    (tester) async {
      await mount(tester);
      try {
        expect(find.text('旅行计划'), findsOneWidget);
        expect(find.text('项目草稿'), findsOneWidget);
        expect(find.text('周末随笔'), findsOneWidget);
        expect(find.text('2'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(2));
        expect(find.text('已锁定'), findsOneWidget);
        expect(find.text('保存'), findsNothing);
        expect(find.text('切换当前数据'), findsNothing);
        await tester.tap(find.widgetWithText(ChoiceChip, '文章'));
        await tester.pump();
        await waitFor(tester, () => find.text('项目草稿').evaluate().isEmpty);
        expect(find.text('周末随笔'), findsOneWidget);
        expect(find.text('旅行计划'), findsNothing);
      } finally {
        await finish(tester);
      }
    },
  );
  testWidgets(
    'protected body reaches WebView only after correct unlock, then background retires it',
    (tester) async {
      await mount(tester);
      try {
        await protected(tester);
        expect(viewSources, isEmpty);
        expect(guards.single.acquired, isTrue);
        await unlock(tester, 'wrong');
        await waitFor(
          tester,
          () => find.text('密码不正确，请重试。').evaluate().isNotEmpty,
        );
        expect(viewSources, isEmpty);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        await tester.enterText(
          find.byType(TextField),
          vector['password'] as String,
        );
        await tester.tap(find.widgetWithText(FilledButton, '解锁'));
        await tester.pump();
        await waitFor(
          tester,
          () => viewSources.any((s) => s.contains('<h1>周末计划')),
        );
        expect(find.byType(LocalHtmlBrowserPreview), findsOneWidget);
        expect(unlockCalls, 2);
        pause(tester);
        await tester.pump();
        await waitFor(
          tester,
          () => find.byType(LocalHtmlBrowserPreview).evaluate().isEmpty,
        );
        resume(tester);
        await tester.pumpAndSettle();
        expect(find.text('重新解锁'), findsOneWidget);
        expect(guards.single.closed, isFalse);
        expect(nativeCalls.where((c) => c.method == 'close'), isNotEmpty);
      } finally {
        await finish(tester);
      }
      expect(guards.single.closed, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'cancel and double-tap do not expose passwords or dispatch unlock',
    (tester) async {
      await mount(tester);
      try {
        await protected(tester);
        await tester.tap(find.text('解锁查看'));
        await tester.tap(find.text('解锁查看'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'temporary-input');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(unlockCalls, 0);
        expect(viewSources, isEmpty);
        expect(find.text('内容已锁定'), findsOneWidget);
      } finally {
        await finish(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'ordinary Markdown stays native and decodes a source-bound local PNG',
    (tester) async {
      await mount(tester);
      try {
        await tester.tap(find.text('项目草稿'));
        await tester.pump();
        await waitFor(
          tester,
          () => find.byType(BookstarkMarkdown).evaluate().isNotEmpty,
        );
        await waitFor(
          tester,
          () => find.byType(NativeImage).evaluate().isNotEmpty,
        );
        expect(find.byType(LocalHtmlBrowserPreview), findsNothing);
        expect(viewSources, isEmpty);
        expect(guards, isEmpty);
      } finally {
        await finish(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'article Markdown also presents through WebView and never native Markdown',
    (tester) async {
      await tester.runAsync(() => session.close());
      selection = LegacyFormatSelection(
        selection.source,
        choices: {
          for (final item in selection.source.items)
            item.id: item.collection == 'article' || item.title == '项目草稿'
                ? LegacyContentFormat.markdown
                : LegacyContentFormat.html,
        },
      );
      session = (await tester.runAsync(buildSession))!;
      await mount(tester);
      try {
        await tester.tap(find.text('周末随笔'));
        await tester.pump();
        await waitFor(tester, () => viewSources.any((s) => s.contains('周末随笔')));
        expect(find.byType(LocalHtmlBrowserPreview), findsOneWidget);
        expect(find.byType(BookstarkMarkdown), findsNothing);
        expect(unlockCalls, 0);
      } finally {
        await finish(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('password input waits for secure acquisition', (tester) async {
    secureGate = Completer<void>();
    await mount(tester);
    try {
      await protected(tester);
      final button = find.widgetWithText(FilledButton, '解锁查看');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(find.byType(TextField), findsNothing);
      secureGate!.complete();
      await waitFor(
        tester,
        () => tester.widget<FilledButton>(button).onPressed != null,
      );
      expect(unlockCalls, 0);
    } finally {
      if (!secureGate!.isCompleted) secureGate!.complete();
      await finish(tester);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets(
    'background cancels pending unlock and drops its eventual plaintext response',
    (tester) async {
      unlockGate = Completer<void>();
      await mount(tester);
      try {
        await protected(tester);
        await unlock(tester, vector['password'] as String);
        await waitFor(tester, () => unlockCalls == 1);
        pause(tester);
        await tester.pump();
        await waitFor(
          tester,
          () => find.byType(AlertDialog).evaluate().isEmpty,
        );
        unlockGate!.complete();
        await tester.pump();
        resume(tester);
        await tester.pumpAndSettle();
        expect(viewSources, isEmpty);
        expect(find.text('重新解锁'), findsOneWidget);
        expect(cancelCalls, greaterThan(0));
      } finally {
        await finish(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'source retirement closes owned reader and shows no stale verified result',
    (tester) async {
      await mount(tester);
      try {
        await protected(tester);
        await unlock(tester, vector['password'] as String);
        await waitFor(tester, () => viewSources.isNotEmpty);
        current = false;
        pause(tester);
        await tester.pump();
        resume(tester);
        await tester.pump();
        await waitFor(
          tester,
          () => find.byType(LocalLegacyCandidateReaderPage).evaluate().isEmpty,
        );
        expect(find.text('无法读取审阅副本'), findsOneWidget);
        expect(find.text('副本已校验'), findsNothing);
        expect(nativeCalls.where((c) => c.method == 'close'), isNotEmpty);
      } finally {
        await finish(tester);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    '320dp English200percent overview scrolls all actions without overflow',
    (tester) async {
      await mount(tester, english: true, width: 320, scale: 2);
      try {
        expect(tester.takeException(), isNull);
        final back = find.widgetWithText(
          OutlinedButton,
          'Return to migration checks',
        );
        await tester.scrollUntilVisible(
          back,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(back, findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await finish(tester);
      }
    },
  );
  testWidgets(
    'ancestor removal while entering a password safely clears its owned dialog',
    (tester) async {
      await mount(tester);
      try {
        await protected(tester);
        await tester.tap(find.text('解锁查看'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'temporary-input');
      } finally {
        await finish(tester);
      }
      expect(guards.every((g) => g.closed), isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
