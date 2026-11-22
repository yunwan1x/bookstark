import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/app_theme.dart';
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/core/native_local_data_control.dart';
import 'package:bookstark_flutter/features/local_backup/local_recovery_page.dart';

void main() {
  final target = LocalGenerationPointer(
    generation: 'a' * 32,
    epoch: 1,
    activationId: 'b' * 32,
    sourceSHA256: 'c' * 64,
  );
  final intent = LocalRestoreIntent(
    operationId: 'b' * 32,
    sourcePointerRaw: null,
    retainedId: 'd' * 32,
    retainedManifestSHA256: 'e' * 64,
    targetPointerRaw: target.encode(),
  );
  final retention = LocalRetention(
    id: 'd' * 32,
    sourcePointerSHA256: localPointerSHA256(null),
    sourceGeneration: 'legacy',
    manifestSHA256: 'e' * 64,
  );
  var phase = LocalGenerationPhase.prepared;
  var failLoad = false, failFinish = false;
  var reads = 0, finishes = 0, entered = 0, reviewed = 0;
  Future<LocalDataControlState> load() => NativeLocalDataControl(
    invoke: (_, _) async {
      reads++;
      if (failLoad) throw StateError('Read unavailable');
      final switched = phase == LocalGenerationPhase.switched;
      return {
        'format': 1,
        'pointerRaw': switched ? target.encode() : null,
        'intentRaw': phase == LocalGenerationPhase.prepared || switched
            ? intent.encode()
            : null,
        'currentRetentionRaw': switched || phase == LocalGenerationPhase.ready
            ? null
            : retention.encode(),
        'sourceRetentionRaw': phase == LocalGenerationPhase.prepared || switched
            ? retention.encode()
            : null,
        'metadataOnly': true,
      };
    },
  ).readState();
  Widget page({double scale = 1}) => MaterialApp(
    theme: bookstarkTheme(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: LocalRecoveryPage(
      load: load,
      reviewApplied: (_) async {
        reviewed++;
        throw StateError('Not verified yet');
      },
      finishUnapplied: (_) async {
        finishes++;
        if (failFinish) {
          throw const LocalControlUnconfirmed('finished-unapplied');
        }
        phase = LocalGenerationPhase.retained;
        return load();
      },
      acknowledge: (_) async =>
          throw StateError('Unverified result cannot be accepted'),
      reenter: (_) async {
        entered++;
      },
      openRetained: () async {},
      returnToConnection: () async {},
    ),
  );
  setUp(() {
    phase = LocalGenerationPhase.prepared;
    failLoad = false;
    failFinish = false;
    reads = 0;
    finishes = 0;
    entered = 0;
    reviewed = 0;
  });
  testWidgets(
    'prepared is observation only; finishing still requires explicit reentry',
    (tester) async {
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(finishes, 0);
      expect(entered, 0);
      await tester.scrollUntilVisible(find.text('结束本次恢复'), 200);
      await tester.tap(find.text('结束本次恢复'));
      await tester.pumpAndSettle();
      expect(finishes, 1);
      expect(entered, 0);
      expect(find.text('重新进入原数据'), findsOneWidget);
      await tester.tap(find.text('重新进入原数据'));
      await tester.pumpAndSettle();
      expect(entered, 1);
    },
  );
  testWidgets(
    'uncertain finish removes actionable old state and never retries automatically',
    (tester) async {
      failFinish = true;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('结束本次恢复'), 200);
      await tester.tap(find.text('结束本次恢复'));
      await tester.pumpAndSettle();
      expect(finishes, 1);
      expect(reads, 1);
      expect(find.text('结束本次恢复'), findsNothing);
      expect(find.text('恢复记录不一致'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('重新只读检查'), 200);
      await tester.tap(find.text('重新只读检查'));
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(finishes, 1);
    },
  );
  testWidgets(
    'switched result cannot enter before actual complete verification',
    (tester) async {
      phase = LocalGenerationPhase.switched;
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('已切换，等待核对'), findsOneWidget);
      expect(find.text('确认并进入本地空间'), findsNothing);
      expect(entered, 0);
      await tester.tap(find.text('只读查看范围'));
      await tester.pumpAndSettle();
      expect(reviewed, 1);
      expect(entered, 0);
      expect(find.text('恢复记录不一致'), findsOneWidget);
    },
  );
  testWidgets(
    'failed cold read remains usable at narrow width and double text',
    (tester) async {
      failLoad = true;
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(page(scale: 2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('返回连接页'), 220);
      expect(tester.takeException(), isNull);
      expect(entered, 0);
      expect(finishes, 0);
    },
  );
}
