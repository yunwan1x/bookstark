import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_html_creation_controller_test.dart' show CreationServer;

void main() {
  late CreationServer server;
  late RemoteHtmlCreationController c;
  setUp(() {
    server = CreationServer()..ignoreLabels = true;
    final values = <String, String>{};
    final vault = HtmlCreationVault(
      server: Uri.parse('https://books.example'),
      memberId: 3,
      collection: 'note',
      readValue: (k) async => values[k],
      writeValue: (k, v) async {
        values[k] = v;
      },
      deleteValue: (k) async {
        values.remove(k);
      },
    );
    c = RemoteHtmlCreationController(
      RemoteHtmlCreationRepository(
        server.client,
        memberId: 3,
        collection: 'note',
      ),
      vault,
    );
    c.edit(
      HtmlNoteEdit(
        title: 'New HTML',
        source: '<p>exact</p>',
        labels: ['desired'],
      ),
    );
  });
  tearDown(() {
    c.dispose();
    server.client.close();
    server.repo.dispose();
  });
  test(
    'reviewed acknowledged POST can finish labels with no content or creation replay',
    () async {
      await c.save();
      expect(c.canFinishLabels, isFalse);
      c.markReviewed(c.observed!);
      expect(c.canFinishLabels, isTrue);
      await c.finishLabels();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 1);
      expect(server.labels, ['desired']);
    },
  );
  test(
    'lost labels receipt is observed without another label PUT or POST',
    () async {
      await c.save();
      c.markReviewed(c.observed!);
      server.loseLabels = true;
      await c.finishLabels();
      expect(c.phase, RemoteHtmlCreationPhase.unknown);
      await c.inspect(7);
      c.markReviewed(c.observed!);
      await c.adopt();
      expect(c.phase, RemoteHtmlCreationPhase.finished);
      expect(server.posts, 1);
      expect(server.contentWrites, 0);
      expect(server.labelWrites, 1);
    },
  );
  test(
    'external edit after review prevents label mutation and body overwrite',
    () async {
      await c.save();
      c.markReviewed(c.observed!);
      server.source = '<p>external</p>';
      server.row['version'] = 32;
      await c.finishLabels();
      expect(c.phase, RemoteHtmlCreationPhase.unknown);
      expect(server.labelWrites, 0);
      expect(server.posts, 1);
      expect(server.contentWrites, 0);
      expect(server.source, '<p>external</p>');
    },
  );
}
