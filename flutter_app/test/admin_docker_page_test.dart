import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_secure_window.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_page.dart';
import 'admin_docker_test_fixture.dart';

class DockerTestWindow implements AdminAssetWindowGuard {
  int acquisitions = 0, closures = 0;
  bool fail = false;
  @override
  Future<void> acquire() async {
    acquisitions++;
    if (fail) throw StateError('owned failed guard');
  }

  @override
  Future<void> close() async {
    closures++;
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).last;
    final state = tester.state<ScrollableState>(scrollable);
    state.position.jumpTo(state.position.minScrollExtent);
    await tester.pumpAndSettle();
    for (
      var attempt = 0;
      attempt < 40 && finder.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(scrollable, const Offset(0, -180));
      await tester.pumpAndSettle();
    }
  }
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await reveal(tester, finder);
  await tester.tap(finder, warnIfMissed: true);
  await tester.pumpAndSettle();
}

Finder input(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> fill(WidgetTester tester, String label, String text) async {
  final finder = input(label);
  await reveal(tester, finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

void main() {
  late DockerHarness h;
  late DockerTestWindow window;
  setUp(() {
    WidgetController.hitTestWarningShouldBeFatal = true;
    h = DockerHarness();
    window = DockerTestWindow();
  });
  tearDown(() {
    h.dispose();
    WidgetController.hitTestWarningShouldBeFatal = false;
  });
  Future<void> launch(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: AdminDockerPage(
          scope: h.scope,
          host: AdminAssetHostMetadata.parse(h.host),
          english: true,
          secureWindowFactory: () => window,
          onReturn: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets(
    'resource tabs dispatch Android accessibility click actions to exact read-only lists',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await launch(tester);
        for (final (label, route) in [
          ('Images', 'docker-images'),
          ('Networks', 'docker-networks'),
          ('Volumes', 'docker-volumes'),
          ('Containers', 'docker-containers'),
        ]) {
          int reads() => h.requests
              .where((r) => r.method == 'GET' && r.url.path.endsWith(route))
              .length;
          final before = reads();
          tester.semantics.tap(find.semantics.byLabel(label));
          await tester.pumpAndSettle();
          expect(reads(), before + 1);
          expect(h.mutations, 0);
        }
        await finish(tester);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'resources use actual lists and cancelling exact delete sends nothing',
    (tester) async {
      await launch(tester);
      expect(find.text('owned43'), findsOneWidget);
      expect(window.acquisitions, 1);
      await tap(tester, find.byKey(const ValueKey('docker-resource-networks')));
      expect(find.text('owned-network'), findsOneWidget);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Delete'));
      expect(find.text('Exact target'), findsOneWidget);
      expect(find.text('owned-network'), findsOneWidget);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
      expect(h.mutations, 0);
      expect(window.closures, 0);
      await finish(tester);
      expect(window.closures, 1);
    },
  );
  testWidgets(
    'container action requires full target review and explicit confirmation',
    (tester) async {
      await launch(tester);
      await tap(tester, find.text('View'));
      await tap(tester, find.widgetWithText(OutlinedButton, 'Stop'));
      expect(find.text(List.filled(64, 'a').join()), findsOneWidget);
      expect(h.mutations, 0);
      await tap(tester, find.widgetWithText(FilledButton, 'Confirm operation'));
      expect(h.mutations, 1);
      await reveal(
        tester,
        find.text(
          'The server confirmed the operation. Read the details again.',
        ),
      );
      expect(
        find.text(
          'The server confirmed the operation. Read the details again.',
        ),
        findsOneWidget,
      );
      await tap(tester, find.byTooltip('Read details again'));
      expect(h.detail['running'], false);
      await finish(tester);
    },
  );
  testWidgets(
    'structured create keeps environment obscured and cancel never creates',
    (tester) async {
      await launch(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Create container'));
      await fill(tester, 'Container name', 'new-owned43');
      await fill(tester, 'Image', 'owned43:v1');
      await tap(tester, find.widgetWithText(FilledButton, 'Next'));
      await tap(tester, find.byKey(const ValueKey('docker-add-key')));
      await fill(tester, 'Key', 'OWNED_VALUE');
      await fill(tester, 'Value', 'owned-temporary-value');
      expect(tester.widget<TextField>(input('Value')).obscureText, true);
      await tap(
        tester,
        find.widgetWithText(FilledButton, 'Review configuration'),
      );
      expect(find.text('Show temporary values'), findsOneWidget);
      expect(find.text('OWNED_VALUE=owned-temporary-value'), findsNothing);
      await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
      expect(h.mutations, 0);
      await finish(tester);
    },
  );
  testWidgets(
    'background disposes create form and resume sends no automatic request',
    (tester) async {
      await launch(tester);
      await tap(tester, find.widgetWithText(FilledButton, 'Create container'));
      await fill(tester, 'Container name', 'owned-private-form');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('owned-private-form'), findsNothing);
      final count = h.requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.requests.length, count);
      expect(
        find.text(
          'Choose Read again. Returning to foreground never connects automatically.',
        ),
        findsOneWidget,
      );
      await finish(tester);
    },
  );
  testWidgets(
    'narrow and landscape200percent controls remain scrollable without overflow',
    (tester) async {
      await launch(tester, size: const Size(320, 740), scale: 2);
      await tap(tester, find.byKey(const ValueKey('docker-resource-volumes')));
      await tap(tester, find.byTooltip('Resource actions'));
      await tap(tester, find.text('Prune across host'));
      expect(
        find.textContaining('including resources outside the current filter'),
        findsOneWidget,
      );
      await tap(tester, find.widgetWithText(OutlinedButton, 'Cancel'));
      expect(h.mutations, 0);
      tester.view.physicalSize = const Size(780, 390);
      await tester.pumpAndSettle();
      await tap(tester, find.widgetWithText(OutlinedButton, 'Read again'));
      expect(tester.takeException(), isNull);
      await finish(tester);
    },
  );
  testWidgets(
    'background retires log tail dropdown and never resumes automatically',
    (tester) async {
      await launch(tester);
      await tap(tester, find.text('Logs'));
      expect(find.text('No log content'), findsOneWidget);
      final dropdown = find.byType(DropdownButtonFormField<int>);
      await tap(tester, dropdown);
      expect(find.text('Last 1000 lines'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text('Last 1000 lines'), findsNothing);
      expect(find.text('No log content'), findsNothing);
      final count = h.requests.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(h.requests.length, count);
      await finish(tester);
      expect(window.closures, 1);
    },
  );

  testWidgets(
    'failed secure window exposes no metadata and starts no request',
    (tester) async {
      window.fail = true;
      await launch(tester);
      expect(
        find.text('Secure window unavailable. Page remains closed.'),
        findsOneWidget,
      );
      expect(find.text('owned43'), findsNothing);
      expect(h.requests, isEmpty);
      await finish(tester);
    },
  );
}
