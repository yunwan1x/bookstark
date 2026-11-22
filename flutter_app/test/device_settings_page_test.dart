import 'package:flutter/rendering.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/owned_download_cache.dart';
import 'package:bookstark_flutter/features/settings/device_settings_page.dart';
import 'package:bookstark_flutter/features/settings/settings_connection_controller.dart';

class _Cache extends OwnedDownloadCache {
  _Cache() : super(Directory('/unused-settings45-ui-test'));
  int clears = 0;
  OwnedCacheResult value = const OwnedCacheResult(
    eligibleBytes: 1024,
    removedBytes: 0,
    eligibleEntries: 1,
    activeEntries: 1,
    skippedEntries: 2,
    failedEntries: 0,
  );
  @override
  Future<OwnedCacheResult> inspect() async => value;
  @override
  Future<OwnedCacheResult> clear() async {
    clears++;
    value = const OwnedCacheResult(
      eligibleBytes: 0,
      removedBytes: 0,
      eligibleEntries: 0,
      activeEntries: 1,
      skippedEntries: 2,
      failedEntries: 0,
    );
    return const OwnedCacheResult(
      eligibleBytes: 1024,
      removedBytes: 1024,
      eligibleEntries: 1,
      activeEntries: 1,
      skippedEntries: 2,
      failedEntries: 0,
    );
  }
}

Future<void> _tapLabel(WidgetTester tester, String label) async {
  final finder = find.text(label);
  await tester.scrollUntilVisible(
    finder,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  void viewport(WidgetTester tester, {bool large = false}) {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = large
        ? const Size(640, 1280)
        : const Size(780, 1688);
    tester.platformDispatcher.textScaleFactorTestValue = large ? 2 : 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> open(
    WidgetTester tester,
    SettingsConnectionController state,
    _Cache cache, {
    Future<bool> Function()? language,
    Future<void> Function()? prepare,
    void Function(String?)? result,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: bookstarkTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                final value = await Navigator.of(context).push<String>(
                  MaterialPageRoute(
                    builder: (_) => DeviceSettingsPage(
                      connection: state,
                      english: true,
                      canBackup: state.local,
                      cache: cache,
                      onLanguage: language ?? () async => false,
                      prepareSwitch: prepare ?? () async {},
                    ),
                  ),
                );
                result?.call(value);
              },
              child: const Text('Open settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'large-text network status stays inside its accessible tap area',
    (tester) async {
      viewport(tester, large: true);
      final state = SettingsConnectionController(
        local: true,
        server: null,
        isCurrent: () => true,
        checkConnection: (_) async {},
      );
      await open(tester, state, _Cache());
      final label = find.text('No network required');
      await tester.scrollUntilVisible(
        label,
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      final area = find
          .ancestor(of: label, matching: find.byType(InkWell))
          .first;
      final labelRect = tester.getRect(label);
      final paragraph = tester.renderObject<RenderParagraph>(label);
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMaxIntrinsicHeight(paragraph.size.width) - .01,
        ),
        reason:
            'The status paragraph must have enough height to paint every line',
      );
      final areaRect = tester.getRect(area);
      expect(labelRect.top, greaterThanOrEqualTo(areaRect.top));
      expect(
        labelRect.bottom,
        lessThanOrEqualTo(areaRect.bottom),
        reason: 'The complete status must remain within its interactive row',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('local settings shows actual offline status and backup route', (
    tester,
  ) async {
    viewport(tester);
    var checks = 0;
    String? destination;
    final state = SettingsConnectionController(
      local: true,
      server: null,
      isCurrent: () => true,
      checkConnection: (_) async {
        checks++;
      },
    );
    await open(tester, state, _Cache(), result: (value) => destination = value);
    expect(find.text('No network required'), findsOneWidget);
    expect(checks, 0);
    final semantics = tester.ensureSemantics();
    await tester.scrollUntilVisible(
      find.text('Language'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final languageNode = tester.getSemantics(find.text('Language'));
    expect(languageNode.label, contains('Language'));
    expect(
      languageNode.label,
      isNot(contains('Appearance')),
      reason: 'Adjacent informational row must not merge into language action',
    );
    semantics.dispose();
    await _tapLabel(tester, 'Local backup & recovery');
    await tester.pumpAndSettle();
    expect(destination, 'local-backup');
    expect(checks, 0);
  });

  testWidgets('language changes only after persistence callback confirms', (
    tester,
  ) async {
    viewport(tester);
    final saved = Completer<bool>();
    final state = SettingsConnectionController(
      local: true,
      server: null,
      isCurrent: () => true,
      checkConnection: (_) async {},
    );
    await open(tester, state, _Cache(), language: () => saved.future);
    await tester.ensureVisible(find.text('Language'));
    await tester.tap(find.text('Language'));
    await tester.pump();
    expect(find.text('Settings'), findsOneWidget);
    saved.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('简体中文'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'server check is explicit and stale status is never shown as verified',
    (tester) async {
      viewport(tester);
      final response = Completer<void>();
      var checks = 0;
      final state = SettingsConnectionController(
        local: false,
        server:
            'https://name:private@notes.example.com/base/?ak=private#private',
        isCurrent: () => true,
        checkConnection: (_) {
          checks++;
          return response.future;
        },
      );
      await open(tester, state, _Cache());
      expect(checks, 0);
      await tester.tap(find.text('Connections'));
      await tester.pumpAndSettle();
      expect(find.text('https://notes.example.com/base/'), findsOneWidget);
      expect(find.textContaining('private'), findsNothing);
      expect(find.text('Unverified'), findsOneWidget);
      expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
      expect(find.byIcon(Icons.computer_outlined), findsOneWidget);
      expect(
        tester
            .getSize(find.widgetWithText(OutlinedButton, 'Check connection'))
            .width,
        closeTo(200, .01),
      );
      final semantics = tester.ensureSemantics();
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Unverified')).label,
        contains('Unverified'),
        reason:
            'Selectable address must not replace connection status semantics',
      );
      expect(
        tester
            .getSemantics(find.text('Unverified'))
            .getSemanticsData()
            .flagsCollection
            .isTextField,
        isFalse,
        reason:
            'Android text fields expose their value instead of merged status labels',
      );
      semantics.dispose();
      await tester.tap(find.text('Check connection'));
      await tester.pump();
      expect(checks, 1);
      expect(find.text('Verified'), findsNothing);
      response.complete();
      await tester.pumpAndSettle();
      expect(find.text('Verified'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'connection switch waits for real preparation before returning destination',
    (tester) async {
      viewport(tester, large: true);
      final prepare = Completer<void>();
      String? destination;
      final state = SettingsConnectionController(
        local: false,
        server: 'https://notes.example.com/',
        isCurrent: () => true,
        checkConnection: (_) async {},
      );
      await open(
        tester,
        state,
        _Cache(),
        prepare: () => prepare.future,
        result: (value) => destination = value,
      );
      await _tapLabel(tester, 'Connections');
      await tester.pumpAndSettle();
      await _tapLabel(tester, 'Enter local space');
      await tester.pump();
      expect(destination, isNull);
      prepare.complete();
      await tester.pumpAndSettle();
      expect(destination, 'settings-local');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('cache follows prototype header and equal-width actions', (
    tester,
  ) async {
    viewport(tester);
    final state = SettingsConnectionController(
      local: true,
      server: null,
      isCurrent: () => true,
      checkConnection: (_) async {},
    );
    await open(tester, state, _Cache());
    await _tapLabel(tester, 'Cache management');
    final icon = tester.getRect(find.byIcon(Icons.cleaning_services_outlined));
    final title = tester.getRect(find.text('Clearable cache'));
    expect(icon.right, lessThan(title.left));
    expect(icon.bottom, greaterThan(title.top));
    await _tapLabel(tester, 'Clear cache');
    final cancel = tester.getRect(
      find.widgetWithText(OutlinedButton, 'Cancel'),
    );
    final clear = tester.getRect(find.widgetWithText(FilledButton, 'Clear'));
    expect(cancel.width, closeTo(clear.width, .01));
    expect(cancel.width, greaterThan(140));
    expect(cancel.top, closeTo(clear.top, .01));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'cache confirmation cancel keeps data; explicit clear refreshes actual bytes',
    (tester) async {
      viewport(tester, large: true);
      final state = SettingsConnectionController(
        local: true,
        server: null,
        isCurrent: () => true,
        checkConnection: (_) async {},
      );
      final cache = _Cache();
      await open(tester, state, cache);
      expect(tester.takeException(), isNull);
      await _tapLabel(tester, 'Cache management');
      await tester.pumpAndSettle();
      expect(find.text('1024 B'), findsOneWidget);
      await _tapLabel(tester, 'Clear cache');
      await tester.pumpAndSettle();
      await _tapLabel(tester, 'Cancel');
      await tester.pumpAndSettle();
      expect(cache.clears, 0);
      await _tapLabel(tester, 'Clear cache');
      await tester.pumpAndSettle();
      await _tapLabel(tester, 'Clear');
      await tester.pumpAndSettle();
      expect(cache.clears, 1);
      await tester.scrollUntilVisible(
        find.text('0 B'),
        -160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('0 B'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Nothing to clear'),
        160,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Nothing to clear'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
