import 'dart:async';
import 'dart:ffi' show DynamicLibrary;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:bookstark_flutter/core/native_local_backup_picker.dart';
import 'package:bookstark_flutter/core/local_legacy_format_selection.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_migration_page.dart';
import 'package:bookstark_flutter/features/local_backup/local_legacy_candidate_review_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, inbox;
  late NativeLocalBackupPicker picker;
  var current = true, releases = 0, cancelCalls = 0, spaceCalls = 0;
  bool corruptReceipt = false, noSpace = false;
  Completer<void>? pickGate, spaceGate;
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
    current = true;
    releases = 0;
    cancelCalls = 0;
    spaceCalls = 0;
    spaceGate = null;
    corruptReceipt = false;
    noSpace = false;
    pickGate = null;
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files',
    );
    await base.create(recursive: true);
    root = await base.createTemp('legacy-entry-unit-');
    inbox = await Directory('${root.path}/local-backup-inbox-v1').create();
    picker = NativeLocalBackupPicker(
      invoke: (method, args) async {
        final id = args['id'] as String;
        if (method == 'pick') {
          await pickGate?.future;
          final file = await File(
            'test/fixtures/legacy_zip/identity-candidate-review.zip',
          ).copy('${inbox.path}/$id.bsbackup');
          return {
            'format': 1,
            'cancelled': false,
            'id': id,
            'bytes': await file.length(),
            'sha256': corruptReceipt
                ? '0' * 64
                : (await sha256.bind(file.openRead()).first).toString(),
          };
        }
        if (method == 'release') {
          releases++;
          final file = File('${inbox.path}/$id.bsbackup');
          if (await file.exists()) await file.delete();
          return {'format': 1, 'released': id};
        }
        if (method == 'cancel') {
          cancelCalls++;
          return {'format': 1, 'cancelled': true};
        }
        throw StateError('unexpected picker call');
      },
    );
  });
  tearDown(() async {
    if (pickGate != null && !pickGate!.isCompleted) pickGate!.complete();
    await picker.dispose();
    await root.delete(recursive: true);
  });
  Future<void> waitFor(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 150 && !ready(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(ready(), isTrue);
  }

  Future<void> tap(WidgetTester tester, Finder target) async {
    if (target.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        target,
        250,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(target);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.runAsync(() => tester.tap(target));
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> mount(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(390, 844);
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
        home: LocalLegacyMigrationPage(
          privateCache: root,
          picker: picker,
          factory: databaseFactoryFfiNoIsolate,
          isCurrentScope: () => current,
          availableBytes: () async {
            spaceCalls++;
            await spaceGate?.future;
            return noSpace ? 0 : 4 * 1024 * 1024 * 1024;
          },
        ),
      ),
    );
  }

  Future<void> disposePage(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await waitFor(
      tester,
      () => !Directory(
        root.path,
      ).listSync().any((e) => e.path.contains('legacy-review-flow-')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> inspect(WidgetTester tester) async {
    await tap(tester, find.text('选择 ZIP 文件'));
    await waitFor(tester, () => find.text('已完成检查').evaluate().isNotEmpty);
  }

  testWidgets(
    'actual Go ZIP inspection binds counts and releases only inbox copy',
    (tester) async {
      await mount(tester);
      try {
        await inspect(tester);
        expect(releases, 1);
        expect(inbox.listSync(), isEmpty);
        expect(find.text('等待确认'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '只读审阅副本'))
              .onPressed,
          isNull,
        );
        expect(find.text('2'), findsOneWidget);
        expect(find.text('1'), findsNWidgets(3));
        expect(find.text('切换当前数据'), findsNothing);
      } finally {
        await disposePage(tester);
      }
    },
  );
  testWidgets(
    'format confirmation opens real read-only candidate then cleans on removal',
    (tester) async {
      await mount(tester);
      try {
        await inspect(tester);
        await tap(tester, find.text('确认内容格式'));
        await tester.pump(const Duration(milliseconds: 350));
        await tap(tester, find.text('批量选择格式'));
        await tester.pump(const Duration(milliseconds: 350));
        await tap(
          tester,
          find.byType(DropdownButtonFormField<LegacyContentFormat>),
        );
        await tap(tester, find.text('HTML 网页').last);
        await tap(tester, find.text('应用选择'));
        await tester.pump(const Duration(milliseconds: 350));
        await tap(tester, find.text('保存选择并继续'));
        await waitFor(tester, () => find.text('已确认').evaluate().isNotEmpty);
        await tap(tester, find.text('只读审阅副本'));
        await waitFor(
          tester,
          () =>
              find.byType(LocalLegacyCandidateReviewPage).evaluate().isNotEmpty,
        );
        await waitFor(tester, () => find.text('副本已校验').evaluate().isNotEmpty);
        expect(find.text('旅行计划'), findsOneWidget);
        expect(find.text('保存'), findsNothing);
        expect(releases, 1);
      } finally {
        await disposePage(tester);
      }
    },
  );
  testWidgets('changed source receipt rejects and cleans staged files', (
    tester,
  ) async {
    corruptReceipt = true;
    await mount(tester);
    try {
      await tap(tester, find.text('选择 ZIP 文件'));
      await waitFor(tester, () => find.text('无法读取审阅副本').evaluate().isNotEmpty);
      expect(find.text('已完成检查'), findsNothing);
      expect(releases, 1);
    } finally {
      await disposePage(tester);
    }
  });
  testWidgets('large text initial state scrolls without overflow', (
    tester,
  ) async {
    await mount(tester, scale: 2);
    try {
      await tap(tester, find.text('选择 ZIP 文件'));
      await waitFor(tester, () => find.text('已完成检查').evaluate().isNotEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await disposePage(tester);
    }
  });
  testWidgets(
    'space failure cleans its partial private stage and keeps original ZIP',
    (tester) async {
      noSpace = true;
      await mount(tester);
      try {
        await tap(tester, find.text('选择 ZIP 文件'));
        await waitFor(
          tester,
          () => find.text('无法读取审阅副本').evaluate().isNotEmpty,
        );
        expect(find.text('已完成检查'), findsNothing);
        expect(releases, 1);
        expect(
          await tester.runAsync(
            () => File(
              'test/fixtures/legacy_zip/identity-candidate-review.zip',
            ).exists(),
          ),
          isTrue,
        );
      } finally {
        await disposePage(tester);
      }
    },
  );
  testWidgets(
    'cancelled pending selection drops and releases its late bound copy',
    (tester) async {
      pickGate = Completer<void>();
      await mount(tester);
      try {
        await tap(tester, find.text('选择 ZIP 文件'));
        await waitFor(tester, () => find.text('取消检查').evaluate().isNotEmpty);
        await tap(tester, find.text('取消检查'));
        pickGate!.complete();
        await waitFor(
          tester,
          () => find.text('选择 ZIP 文件').evaluate().isNotEmpty,
        );
        expect(find.text('已完成检查'), findsNothing);
        expect(releases, 1);
        expect(inbox.listSync(), isEmpty);
      } finally {
        if (!pickGate!.isCompleted) pickGate!.complete();
        await disposePage(tester);
      }
    },
  );
  testWidgets(
    'system document activity pause preserves its pending selection',
    (tester) async {
      pickGate = Completer<void>();
      await mount(tester);
      try {
        await tap(tester, find.text('选择 ZIP 文件'));
        await waitFor(tester, () => find.text('取消检查').evaluate().isNotEmpty);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expect(cancelCalls, 0);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        pickGate!.complete();
        await waitFor(tester, () => find.text('已完成检查').evaluate().isNotEmpty);
        expect(cancelCalls, 0);
        expect(releases, 1);
      } finally {
        if (!pickGate!.isCompleted) pickGate!.complete();
        await disposePage(tester);
      }
    },
  );
  testWidgets(
    'background after picker receipt cancels ZIP staging and releases inbox',
    (tester) async {
      spaceGate = Completer<void>();
      await mount(tester);
      try {
        await tap(tester, find.text('选择 ZIP 文件'));
        await waitFor(tester, () => spaceCalls > 0);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        spaceGate!.complete();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await waitFor(
          tester,
          () => find.text('选择 ZIP 文件').evaluate().isNotEmpty,
        );
        expect(find.text('已完成检查'), findsNothing);
        expect(releases, 1);
        expect(inbox.listSync(), isEmpty);
      } finally {
        if (!spaceGate!.isCompleted) spaceGate!.complete();
        await disposePage(tester);
      }
    },
  );
}
