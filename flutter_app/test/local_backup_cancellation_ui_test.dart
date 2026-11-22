import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/local_storage_session.dart';
import 'package:bookstark_flutter/core/native_local_backup_picker.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/features/local_backup/local_backup_feature.dart';
import 'support/local_backup_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LocalBackupFixture fixture;
  late LocalStorageSession session;
  late NativeLocalBackupPicker picker;
  late Completer<Object?> selected;
  Completer<int>? capacity;
  var mode = 'cancelled', spaceReads = 0;
  var copyReady = false;
  String? pickedId;
  final calls = <String>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  String inputPath() =>
      '${fixture.root.path}/local-backup-inbox-v1/$pickedId.bsbackup';
  Map<String, Object?> receipt() => {
    'format': 1,
    'cancelled': false,
    'id': pickedId,
    'bytes': fixture.candidate.sourceBytes,
    'sha256': fixture.candidate.sourceSHA256,
  };
  setUp(() async {
    fixture = await LocalBackupFixture.create();
    picker = NativeLocalBackupPicker();
    selected = Completer<Object?>();
    capacity = null;
    mode = 'cancelled';
    spaceReads = 0;
    copyReady = false;
    pickedId = null;
    calls.clear();
    final control = NativeLocalDataControl(
      invoke: (method, arguments) async {
        if (method == 'space') {
          spaceReads++;
          final bytes = capacity == null ? 1 << 40 : await capacity!.future;
          return {'format': 1, 'availableBytes': bytes};
        }
        expect(method, 'readState');
        return {
          'format': 1,
          'pointerRaw': null,
          'intentRaw': null,
          'currentRetentionRaw': null,
          'sourceRetentionRaw': null,
          'metadataOnly': true,
        };
      },
    );
    session = LocalStorageSession(
      control: control,
      privateSupport: fixture.root,
      legacyDatabasePath: fixture.store.path,
      factory: fixture.store.factory,
    );
    messenger.setMockMethodCallHandler(NativeLocalBackupPicker.channel, (
      call,
    ) async {
      calls.add(call.method);
      final args = call.arguments as Map;
      if (call.method == 'pick') {
        pickedId = args['id'] as String;
        final input = File(inputPath());
        await input.parent.create(recursive: true);
        await File(
          '${fixture.root.path}/local-data-v1/retained/${fixture.retention.id}/content.bsbackup',
        ).copy(input.path);
        copyReady = true;
        if (mode == 'complete') return receipt();
        return await selected.future;
      }
      expect(args['id'], pickedId);
      if (call.method == 'cancel') {
        if (mode == 'cancelled' && !selected.isCompleted) {
          await File(inputPath()).delete();
          selected.complete({'format': 1, 'cancelled': true});
        }
        return {'format': 1, 'cancelled': true};
      }
      if (call.method == 'release') {
        if (await File(inputPath()).exists()) await File(inputPath()).delete();
        return {'format': 1, 'released': pickedId};
      }
      throw StateError('Unexpected picker operation');
    });
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(NativeLocalBackupPicker.channel, null);
    await fixture.dispose();
  });
  Widget app() => MaterialApp(
    home: LocalBackupFeature(
      session: session,
      picker: picker,
      privateCache: fixture.root,
      store: fixture.store,
      isCurrentScope: () => true,
      onEntered: (_) async => throw StateError('No restore confirmed'),
      onConnection: () async {},
      openDraft: (_, _) async => throw StateError('No editor requested'),
    ),
  );
  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var attempt = 0; attempt < 100 && !done(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(done(), isTrue);
  }

  Future<void> begin(WidgetTester tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('选择备份文件'), 200);
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '选择备份文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择备份文件'));
    await tester.pump();
    await settle(
      tester,
      () =>
          pickedId != null &&
          copyReady &&
          find.text('取消检查').evaluate().isNotEmpty,
    );
  }

  Future<List<String>> generations() async => (await Directory(
    '${fixture.root.path}/local-data-v1/generations',
  ).list().toList()).map((entry) => entry.path).toList()..sort();

  testWidgets(
    'copy cancellation reaches native once and preserves current SQL/attachments',
    (tester) async {
      final before = await tester.runAsync(generations);
      await begin(tester);
      await tester.tap(find.text('取消检查'));
      await tester.pump();
      await settle(
        tester,
        () => find.textContaining('检查已取消').evaluate().isNotEmpty,
      );
      expect(calls, ['pick', 'cancel']);
      expect(spaceReads, 0);
      expect(await tester.runAsync(generations), before);
      expect(await tester.runAsync(() => File(inputPath()).exists()), isFalse);
      expect(
        await tester.runAsync(
          () => File(
            '${fixture.root.path}/attachments/${'a' * 32}',
          ).readAsBytes(),
        ),
        [1, 255, 0],
      );
      expect(fixture.store.maintenance.retired, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'cancel while candidate capacity is pending stops verification and releases only private inbox',
    (tester) async {
      mode = 'complete';
      capacity = Completer<int>();
      final before = await tester.runAsync(generations);
      await begin(tester);
      await settle(tester, () => spaceReads == 1);
      await tester.tap(find.text('取消检查'));
      await tester.pump();
      capacity!.complete(1 << 40);
      await settle(
        tester,
        () => find.textContaining('检查已取消').evaluate().isNotEmpty,
      );
      expect(calls, ['pick', 'release']);
      expect(await tester.runAsync(generations), before);
      expect(await tester.runAsync(() => File(inputPath()).exists()), isFalse);
      expect(find.text('确认恢复'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'late successful native copy receipt after cancel never becomes a checked candidate',
    (tester) async {
      mode = 'late';
      final before = await tester.runAsync(generations);
      await begin(tester);
      await tester.tap(find.text('取消检查'));
      await tester.pump();
      await settle(tester, () => calls.contains('cancel'));
      expect(find.textContaining('检查已取消'), findsNothing);
      selected.complete(receipt());
      await settle(
        tester,
        () => find.textContaining('检查已取消').evaluate().isNotEmpty,
      );
      expect(calls, ['pick', 'cancel', 'release']);
      expect(spaceReads, 0);
      expect(await tester.runAsync(generations), before);
      expect(find.text('文件完整性检查通过'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'disposing the owning feature cancels its request once without leaving live UI work',
    (tester) async {
      await begin(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      var cleanupDone = false;
      unawaited(picker.dispose().whenComplete(() => cleanupDone = true));
      await settle(tester, () => selected.isCompleted && cleanupDone);
      await tester.pumpAndSettle();
      expect(calls.where((call) => call == 'cancel').length, 1);
      expect(spaceReads, 0);
      expect(fixture.store.maintenance.retired, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
