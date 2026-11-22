import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'package:bookstark_flutter/core/public_share_attachments.dart';
import 'package:bookstark_flutter/features/html/html_browser_session.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_page.dart';
import 'package:bookstark_flutter/features/public_shares/share_edit_link_page.dart';
import 'package:bookstark_flutter/features/public_shares/shared_article_edit_page.dart';

import 'share_edit_pages_test.dart' as fixture;
import 'support/markdown_creation_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late fixture.Repository repo;
  late PublicShareAttachments attachments;
  late MarkdownCreationHost host;
  final channels = <MethodChannel>[];
  final nativeCommands = <String>[];
  final leases = <String>[];
  final viewTypes = <String>[];
  String? viewChannel, lease;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    repo = fixture.Repository()..blogType = 'article';
    attachments = PublicShareAttachments(fixture.server);
    host = MarkdownCreationHost();
    nativeCommands.clear();
    channels.clear();
    leases.clear();
    viewTypes.clear();
    viewChannel = null;
    lease = null;
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, (
      call,
    ) async {
      if (call.method == 'openPublic') {
        lease = (call.arguments as Map)['lease'] as String;
        leases.add(lease!);
      }
      return null;
    });
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      final args = call.arguments as Map?;
      if (call.method == 'create') {
        viewTypes.add(args!['viewType'] as String);
        final params =
            const StandardMessageCodec().decodeMessage(
                  ByteData.sublistView(args['params'] as Uint8List),
                )
                as Map;
        expect(params.keys.toSet(), {'lease', 'server'});
        viewChannel = 'bookstark/shared_markdown_view/${args['id']}';
        final channel = MethodChannel(viewChannel!);
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'retire') return null;
          final command = call.arguments as Map;
          final name = command['name'] as String;
          nativeCommands.add('${channel.name}:$name');
          final arguments = (command['arguments'] as List).cast<Object?>();
          if (name == 'acknowledgeSnapshot') {
            await host.call('endSnapshot', arguments);
            return host.state();
          }
          if (name == 'insertMarkdownSnapshot') {
            host.source += arguments[1] as String;
            host.revision++;
            await host.call('endSnapshot', [arguments[0]]);
            return host.state();
          }
          return host.call(name, arguments);
        });
        return 99;
      }
      if (call.method == 'resize') {
        return {'width': args!['width'], 'height': args['height']};
      }
      return null;
    });
  });
  tearDown(() {
    attachments.close();
    messenger.setMockMethodCallHandler(HtmlBrowserSession.channel, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
  Future<void> pump(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> event(WidgetTester tester, String method) async {
    final completed = Completer<void>();
    final previousGeneration = host.generation;
    messenger.handlePlatformMessage(
      viewChannel!,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall(method, {'lease': lease}),
      ),
      (_) => completed.complete(),
    );
    await pump(tester);
    expect(completed.isCompleted, isTrue);
    if (method == 'hostReady') {
      expect(
        host.generation,
        previousGeneration + 1,
        reason:
            'hostReady must reach current handler; calls=${nativeCommands.join(",")}; UI=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).join("|")}',
      );
    }
  }

  Future<PublicEditController> mount(
    WidgetTester tester, {
    bool large = false,
  }) async {
    final controller = PublicEditController(repo, fixture.link);
    await controller.initialize();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await pump(tester);
      var closed = false;
      HtmlBrowserSession.closeActive().then((_) => closed = true);
      await pump(tester);
      expect(closed, isTrue);
    });
    await tester.pumpWidget(
      MaterialApp(
        builder: large
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              )
            : null,
        home: ShareEditPage(controller: controller, attachments: attachments),
      ),
    );
    await pump(tester);
    if (repo.blogType != 'note') await event(tester, 'hostReady');
    return controller;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await pump(tester);
    var closed = false;
    HtmlBrowserSession.closeActive().then((_) => closed = true);
    await pump(tester);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'link-owned controller survives outgoing route rebuild then clears on disposal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ShareEditLinkPage(
            server: fixture.server,
            repository: repo,
            shares: fixture.UnusedShares(),
            attachments: attachments,
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField), fixture.url);
      await tester.ensureVisible(find.text('验证并打开'));
      await tester.tap(find.text('验证并打开'));
      await pump(tester);
      await event(tester, 'hostReady');
      final page = find.byType(SharedArticleEditPage);
      expect(page, findsOneWidget);
      final controller = tester.widget<SharedArticleEditPage>(page).controller;
      expect(controller.snapshot, isNotNull);
      Navigator.of(tester.element(page)).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      // Reverse transition is still mounted. Force the precise Native failure
      // boundary rather than waiting until the widget has silently disappeared.
      expect(page, findsOneWidget);
      expect(controller.snapshot, isNotNull);
      tester.element(page).markNeedsBuild();
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      await pump(tester);
      expect(page, findsNothing);
      expect(
        controller.snapshot,
        isNull,
        reason:
            'controller must close after route disposal; no retained source',
      );
      expect(repo.writes, 0);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  for (final type in <String?>['article', null]) {
    testWidgets(
      'article and legacy shared editing use anonymous WebView: $type',
      (tester) async {
        repo.blogType = type;
        await mount(tester);
        expect(find.byType(SharedArticleEditPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('shared-markdown-input')),
          findsNothing,
        );
        expect(viewTypes, ['bookstark/shared_markdown_view']);
        expect(host.readOnly, isFalse);
        expect(host.locked, isFalse);
        expect(repo.writes, 0);
        await unmount(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
  testWidgets(
    'actual page disposal releases RAM owner before the next HTML lease',
    (tester) async {
      await mount(tester);
      host.source = 'unsaved RAM-only body';
      final commandsBefore = nativeCommands.length;
      await unmount(tester);
      expect(
        nativeCommands
            .skip(commandsBefore)
            .where((c) => c.endsWith(':beginSnapshot')),
        isEmpty,
      );
      expect(repo.writes, 0);
      var opened = false;
      final pending = HtmlBrowserSession.openLocal(retire: () async {}).then((
        v,
      ) {
        opened = true;
        return v;
      });
      await pump(tester);
      expect(opened, isTrue);
      final next = await pending;
      final closing = next.close();
      await pump(tester);
      await closing;
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets('explicit ordinary note retains the native editing route', (
    tester,
  ) async {
    repo.blogType = 'note';
    await mount(tester);
    expect(find.byType(SharedArticleEditPage), findsNothing);
    expect(find.byKey(const ValueKey('shared-markdown-input')), findsOneWidget);
    expect(viewTypes, isEmpty);
    await unmount(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  testWidgets(
    'save captures live source and unknown response disables repeat submission',
    (tester) async {
      final controller = await mount(tester);
      host.source = '\ufeff# Live\r\n';
      repo.unknown = true;
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await pump(tester);
      expect(repo.writes, 1);
      expect(controller.phase, PublicEditPhase.unknown);
      expect(host.locked, isTrue);
      expect(
        find.widgetWithText(TextButton, '保存').evaluate().single.widget,
        isA<TextButton>().having(
          (button) => button.onPressed,
          'disabled',
          isNull,
        ),
      );
      expect(
        viewTypes.length,
        1,
        reason: 'Status changes must not remount the editor',
      );
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'background captures then requires an explicit fresh capability read',
    (tester) async {
      await mount(tester);
      host.source = '# Paused';
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await pump(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pump(tester);
      expect(viewTypes.length, 1);
      expect(find.text('编辑已暂停'), findsWidgets);
      final reads = repo.reads;
      final resume = find.widgetWithText(FilledButton, '重新核对并继续');
      await tester.scrollUntilVisible(
        resume,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(resume);
      await pump(tester);
      expect(repo.reads, reads + 1);
      expect(viewTypes.length, 2);
      await event(tester, 'hostReady');
      expect(host.source, '# Paused');
      expect(repo.writes, 0);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'adopting a reviewed conflict retires the old runtime before replacing its source',
    (tester) async {
      final controller = await mount(tester);
      host.source = '# Local';
      repo.content = '# Remote';
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await pump(tester);
      await tester.pumpAndSettle();
      expect(controller.phase, PublicEditPhase.conflict);
      expect(repo.writes, 0);
      expect(host.locked, isTrue);
      await tester.tap(find.widgetWithText(TextButton, '采用远端'));
      // A new native view awaits its hostReady handshake. pumpAndSettle would
      // fast-forward its spinner to the 60-second load deadline.
      await pump(tester);
      expect(viewTypes.length, 2);
      await event(tester, 'hostReady');
      expect(host.source, '# Remote');
      expect(host.locked, isFalse);
      expect(repo.writes, 0);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'native public link insertion changes the frozen body without an upload or save',
    (tester) async {
      await mount(tester);
      await tester.tap(find.byTooltip('插入附件'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shared-attachment-name')),
        'existing',
      );
      await tester.enterText(
        find.byKey(const ValueKey('shared-attachment-url')),
        'https://example.test/upload-files/existing.txt',
      );
      await tester.tap(find.widgetWithText(FilledButton, '插入'));
      await tester.pumpAndSettle();
      await pump(tester);
      expect(
        host.source,
        '# Seed[existing](<https://example.test/upload-files/existing.txt>)',
      );
      expect(host.locked, isFalse);
      expect(host.transfers, isEmpty);
      expect(repo.writes, 0);
      expect(viewTypes.length, 1);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'keyboard inset reveals the live editor without remounting or losing pending source',
    (tester) async {
      await mount(tester);
      host.source = '# Pending while keyboard opens';
      host.revision = 1;
      final generation = host.generation;
      final height =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(
        bottom: 280 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.resetViewInsets);
      await pump(tester);
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(PlatformViewLink)).bottom,
        lessThanOrEqualTo(height - 280 + 1),
        reason: 'The editable viewport must end above the software keyboard',
      );
      expect(viewTypes.length, 1);
      expect(host.generation, generation);
      expect(host.source, '# Pending while keyboard opens');
      await tester.tap(find.widgetWithText(TextButton, '保存'));
      await pump(tester);
      expect(repo.content, host.source);
      expect(repo.writes, 1);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'native attachment dialog cancellation preserves body at 320dp and 200 percent text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, large: true);
      await tester.tap(find.byTooltip('插入附件'));
      await pump(tester);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('shared-attachment-url')),
        findsOneWidget,
      );
      expect(host.locked, isTrue);
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(host.source, '# Seed');
      expect(host.locked, isFalse);
      expect(host.transfers, isEmpty);
      expect(repo.writes, 0);
      await unmount(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
