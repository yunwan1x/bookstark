import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/local_backup_exporter.dart';
import 'package:bookstark_flutter/core/local_backup_importer.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/core/local_legacy_go_export.dart';
import 'package:bookstark_flutter/core/local_legacy_zip_stage.dart';
import 'package:bookstark_flutter/core/owned_generation15_staging.dart';
import 'package:bookstark_flutter/features/local_backup/owned_generation15_activation_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalBackupCandidate candidate;
  int discarded = 0, activated = 0, reviewed = 0, cancelled = 0;
  bool current = true;
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  setUp(() async {
    final parent = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/current-run/test-tmp',
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('owned15-activation-ui-');
    discarded = 0;
    activated = 0;
    reviewed = 0;
    cancelled = 0;
    current = true;
    final input = File(
      'test/fixtures/legacy_zip/identity-upload-shared-thumb.zip',
    );
    final zip = await LegacyZipStage.inspect(
      input,
      privateParent: root,
      expectedSha256: (await sha256.bind(input.openRead()).first).toString(),
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
    );
    final source = await LegacyGoExport.inspect(zip);
    final formats = LegacyFormatSource.fromInspection(
      source,
      scopeKey: 'b' * 32,
    );
    final selection = LegacyFormatSelection(
      formats,
      choices: {
        for (final item in formats.items)
          item.id: item.collection == 'article'
              ? LegacyContentFormat.html
              : LegacyContentFormat.markdown,
      },
    );
    final stage = await OwnedGeneration15Staging.build(
      stage: zip,
      selection: selection,
      privateParent: root,
      availableBytes: () async => 4 * 1024 * 1024 * 1024,
      isCurrentScope: () => true,
      factory: databaseFactoryFfiNoIsolate,
    );
    final archive = await StagedGeneration15BackupExporter(
      stage: stage,
      factory: databaseFactoryFfiNoIsolate,
      workspace: Directory('${root.path}/exports'),
      checkPendingRecovery: () async {},
    ).create();
    try {
      final support = await Directory('${root.path}/support').create();
      final cache = await Directory('${root.path}/cache').create();
      final inbox = await Directory(
        '${cache.path}/local-backup-inbox-v1',
      ).create();
      await archive.file.copy('${inbox.path}/${'f' * 32}.bsbackup');
      candidate = await LocalBackupCandidateImporter(
        privateSupport: support,
        privateCache: cache,
        factory: databaseFactoryFfiNoIsolate,
        availableBytes: () async => 4 * 1024 * 1024 * 1024,
        identity: () => 'a' * 32,
        discardCandidate: (id) async {
          expect(id, 'a' * 32);
          discarded++;
        },
      ).inspectPicked('f' * 32);
    } finally {
      await archive.dispose();
      await stage.retire();
    }
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Widget page({bool english = false, bool fail = false, bool large = false}) =>
      MaterialApp(
        builder: large
            ? (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 180),
                ),
                child: child!,
              )
            : null,
        home: OwnedGeneration15ActivationPage(
          english: english,
          summary: const Owned15ActivationSummary(
            notes: 2,
            articles: 1,
            protectedItems: 1,
            attachments: 3,
          ),
          prepareCandidate: (_) async => candidate,
          isCurrentScope: () => current,
          activate: (value) async {
            expect(identical(value, candidate), isTrue);
            activated++;
            value.preserveForActivation();
            if (fail) throw StateError('Native receipt unconfirmed');
          },
          onReview: () async {
            reviewed++;
          },
          onCancel: () async {
            cancelled++;
          },
        ),
      );
  Future<void> visible(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(finder);
    await tester.pump();
    expect(finder.hitTestable(), findsOneWidget);
  }

  testWidgets(
    'explicit retention confirmation is required and uncertain result never replays',
    (tester) async {
      await tester.pumpWidget(page(fail: true));
      await tester.pumpAndSettle();
      expect(activated, 0);
      final button = find.widgetWithText(FilledButton, '启用独立空间');
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await visible(tester, find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await visible(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(activated, 1);
      expect(candidate.preservedForActivation, isTrue);
      expect(find.text('启用独立空间'), findsNothing);
      final review = find.widgetWithText(FilledButton, '核对激活结果');
      await visible(tester, review);
      await tester.tap(review);
      await tester.pumpAndSettle();
      expect(reviewed, 1);
      expect(activated, 1);
      expect(discarded, 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(discarded, 0);
      expect(cancelled, 0);
    },
  );
  testWidgets(
    'English320 200percent keyboard keeps exact explicit controls reachable',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      try {
        await tester.pumpWidget(page(english: true, large: true));
        await tester.pumpAndSettle();
        await visible(tester, find.byType(Checkbox));
        await tester.tap(find.byType(Checkbox));
        await tester.pump();
        final activate = find.widgetWithText(
          FilledButton,
          'Activate independent space',
        );
        await visible(tester, activate);
        await tester.tap(activate);
        await tester.pumpAndSettle();
        expect(activated, 1);
        final review = find.widgetWithText(
          FilledButton,
          'Review activation result',
        );
        await visible(tester, review);
        await tester.tap(review);
        await tester.pumpAndSettle();
        expect(reviewed, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    },
  );
  testWidgets('owner changed before click cannot activate old prepared copy', (
    tester,
  ) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await visible(tester, find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    final activate = find.widgetWithText(FilledButton, '启用独立空间');
    await visible(tester, activate);
    current = false;
    await tester.tap(activate);
    await tester.pumpAndSettle();
    expect(activated, 0);
    expect(reviewed, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(discarded, 1);
    expect(cancelled, 1);
  });
}
