import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/main.dart';
import 'package:bookstark_flutter/features/trash/trash_page.dart';
import 'profile_root_test.dart' as root;
import 'trash_repository_test.dart' as fixture;
import 'api_tokens_page_test.dart' show click;

void main() {
  testWidgets(
    'actual root My entry opens owned trash, cancellation does not write and confirmed restore verifies actual list',
    (tester) async {
      final server = root.Server();
      var restored = false, writes = 0;
      final queries = <Map<String, String>>[];
      server.extra = (r) async {
        if (r.url.path == '/api/trash') {
          queries.add(r.url.queryParameters);
          return fixture.page(
            restored ? [] : [fixture.item(1)],
            total: restored ? 0 : 1,
          );
        }
        if (r.url.path == '/api/trash/1/restore' && r.method == 'POST') {
          writes++;
          restored = true;
          return http.Response(
            '{"code":0,"message":"restored"}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return null;
      };
      root.seed();
      await tester.pumpWidget(BookstarkApp(clientFactory: server.client));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.account_circle_outlined));
      await tester.pumpAndSettle();
      await click(tester, find.text('回收站'));
      expect(find.byType(TrashPage), findsOneWidget);
      await click(tester, find.text('还原'));
      await click(tester, find.text('取消'));
      expect(writes, 0);
      await click(tester, find.text('还原'));
      await click(tester, find.text('确认还原'));
      expect(writes, 1);
      expect(
        queries.every((q) => !q.containsKey('all') && q['page_size'] == '20'),
        true,
      );
      expect(find.textContaining('还原回执已收到，回收站记录已移出。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
