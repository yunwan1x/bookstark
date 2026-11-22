import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_asset_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_logs_page.dart';
import 'admin_docker_test_fixture.dart';

void main() {
  for (final english in [false, true]) {
    testWidgets(
      '320dp200% logs retain visible panel and readable footer english=$english',
      (tester) async {
        final h = DockerHarness();
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          h.dispose();
        });
        final info = await h.repo.inspect(h.row(DockerResource.containers));
        final before = h.requests.length;
        await tester.pumpWidget(
          MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: AdminDockerLogsPage(
              scope: h.scope,
              host: AdminAssetHostMetadata.parse(h.host),
              container: info,
              english: english,
              onReturn: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final panel = tester.getRect(
          find.byKey(const ValueKey('docker-log-panel')),
        );
        expect(panel.height, greaterThanOrEqualTo(120));
        expect(panel.bottom, lessThan(740));
        final title = tester.getRect(
          find.text(english ? 'Auto scroll' : '自动滚动'),
        );
        expect(title.width, greaterThanOrEqualTo(100));
        // Material's 32px large-text title can legitimately occupy two 48px lines.
        // Character-column wrapping (as in V2) is many lines tall.
        expect(title.height, lessThanOrEqualTo(100));
        final clear = find.text(english ? 'Clear display' : '清空显示');
        expect(tester.getRect(clear).bottom, lessThanOrEqualTo(740));
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(
          h.requests.length,
          before,
          reason: 'Local clear/initial rendering never starts remote logs.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
