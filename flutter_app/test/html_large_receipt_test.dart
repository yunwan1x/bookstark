import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'html_notes_save_test.dart' show Server;

class OversizedUpdateReceiptServer extends Server {
  @override
  http.Response receipt([int status = 200]) => status != 200
      ? super.receipt(status)
      : http.Response(
          jsonEncode({
            'code': 0,
            'message': List.filled(128 * 1024 + 1, 'x').join(),
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
}

void main() {
  test(
    'applied update with oversized 200 receipt stays unknown and verifies without replay',
    () async {
      final server = OversizedUpdateReceiptServer();
      final baseline = await server.baseline();
      final controller = HtmlEditorController(server.repo, baseline);
      controller.edit(server.edit(labels: baseline.labels));
      await controller.save();
      expect(server.contentWrites, 1);
      expect(server.source, server.edit().source);
      expect(server.labelWrites, 0);
      expect(controller.phase, HtmlEditorPhase.contentUnknown);
      expect(controller.canSave, false);
      await controller.verify();
      expect(controller.phase, HtmlEditorPhase.observed);
      expect(server.contentWrites, 1);
      expect(server.labelWrites, 0);
      controller.dispose();
      server.client.close();
    },
  );
}
