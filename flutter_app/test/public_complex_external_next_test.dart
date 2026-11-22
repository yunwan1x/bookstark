import 'dart:async';
// Draft only; no Flutter/toolchain run during Root Native ownership.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/public_shares/public_complex_readonly_body.dart';

void main() {
  test('cancel never retires; confirmed launch awaits retirement', () async {
    var retired = false, launched = false;
    await openConfirmedPublicComplexExternal(
      confirm: () async => false,
      isCurrent: () => true,
      isRetired: () => retired,
      retire: () async {
        retired = true;
      },
      launch: () async {
        launched = true;
      },
    );
    expect(retired, false);
    expect(launched, false);
    final barrier = Completer<void>();
    final result = openConfirmedPublicComplexExternal(
      confirm: () async => true,
      isCurrent: () => true,
      isRetired: () => retired,
      retire: () async {
        retired = true;
        await barrier.future;
      },
      launch: () async {
        launched = true;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(retired, true);
    expect(launched, false);
    barrier.complete();
    await result;
    expect(launched, true);
  });
  test(
    'late scope/background or retired dialog confirmation never launches',
    () async {
      for (final duringRetire in [false, true]) {
        var current = true, retired = false, launched = false;
        final decision = Completer<bool>(), barrier = Completer<void>();
        final result = openConfirmedPublicComplexExternal(
          confirm: () => decision.future,
          isCurrent: () => current,
          isRetired: () => retired,
          retire: () async {
            retired = true;
            await barrier.future;
          },
          launch: () async {
            launched = true;
          },
        );
        if (!duringRetire) current = false;
        decision.complete(true);
        await Future<void>.delayed(Duration.zero);
        if (duringRetire) {
          expect(retired, true);
          current = false;
          barrier.complete();
        }
        await result;
        expect(launched, false);
      }
      var launched = false;
      await openConfirmedPublicComplexExternal(
        confirm: () async => true,
        isCurrent: () => true,
        isRetired: () => true,
        retire: () async {},
        launch: () async {
          launched = true;
        },
      );
      expect(launched, false);
    },
  );

  for (final english in [false, true]) {
    testWidgets(
      'external dialog explicit cancellation preserves caller state $english',
      (tester) async {
        bool? answer;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    answer = await confirmPublicComplexExternalLink(
                      context,
                      Uri.parse('https://example.invalid/path'),
                      english: english,
                    );
                  },
                  child: const Text('begin'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('begin'));
        await tester.pumpAndSettle();
        expect(answer, isNull);
        await tester.tap(find.text(english ? 'Cancel' : '取消'));
        await tester.pumpAndSettle();
        expect(answer, false);
      },
    );
  }
  testWidgets('EN320 200 percent long URL scrolls and explicit confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                answer = await confirmPublicComplexExternalLink(
                  context,
                  Uri.parse('https://example.invalid/${'long-path/' * 80}'),
                  english: true,
                );
              },
              child: const Text('begin'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('begin'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Open link'));
    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();
    expect(answer, true);
    expect(tester.takeException(), isNull);
  });
  // Actual platform lifecycle delivery remains a Native integration check.
}
