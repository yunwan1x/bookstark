import 'package:bookstark_flutter/core/public_edit_controller.dart';
import 'support/shared_capability_http_fixture.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/public_edit_link.dart';
import 'package:bookstark_flutter/core/public_edit_snapshot.dart';
import 'package:bookstark_flutter/core/public_edit_repository.dart';
import 'package:bookstark_flutter/core/public_share_models.dart';

final server = Uri.parse('https://example.test/base');
final token = List.filled(64, 'b').join();
PublicEditLink link() => PublicEditLink.parse(
  server,
  'https://example.test/base/shares/实际%252F+?token=$token',
);
Map<String, Object?> publicRow({bool locked = false, int shareId = 8}) => {
  'share_type': 'blog',
  'share_id': shareId,
  'target_id': 3,
  'share_identify': '实际%2F+',
  'has_password': locked,
  'title': 'Actual title',
  'doc_type': 'markdown',
  'content': '# Public body',
};
Map<String, Object?> editRow({
  bool locked = false,
  String format = 'markdown',
}) => {
  'editable': true,
  'share_type': 'blog',
  'has_password': locked,
  'title': 'Actual editing title',
  'doc_type': format,
  'content': '\ufeff# Editable body\r\n',
  'modify_time': '2026-11-05 12:00:00',
};
http.Response json(Map<String, Object?> data) => http.Response.bytes(
  utf8.encode(jsonEncode({'code': 0, 'data': data})),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
void main() {
  test(
    'shared Markdown uses anonymous typed CAS, exact identity and empty source receipt',
    () async {
      final wire = SharedCapabilityHttpFixture(
        server: server,
        identify: '实际%2F+',
      );
      final account = BookstarkClient(
        server.toString(),
        transport: MockClient(
          (_) async => throw StateError('Owner endpoint forbidden'),
        ),
      );
      account.restoreSession({
        'token': 'root-token-never-copy',
        'csrf_token': 'root-csrf',
      });
      addTearDown(account.close);
      final repo = RemotePublicEditRepository(
        account,
        capabilityFactory: wire.capability,
        sourceFactory: wire.probe,
      );
      addTearDown(() => repo.retire(link()));
      final baseline = await repo.read(link());
      expect(baseline.content, '\ufeff# Editable body\r\n');
      expect(baseline.detail.targetId, 3);
      expect(baseline.detail.blogType, 'note');
      final receipt = await repo.save(link(), baseline, '');
      expect(wire.source, '');
      expect(wire.puts, 1);
      expect(receipt.modified, '2026-11-05 12:01:00');
      expect(wire.requests.where((r) => r.startsWith('PUT')), hasLength(1));
      expect(wire.requests.last, contains('/edit/cas'));
      expect(receipt.reference.canonicalUri.hasQuery, isFalse);
    },
  );
  test(
    'protected payload needs explicit password; spaces and identity survive new CSRF read/CAS',
    () async {
      final wire = SharedCapabilityHttpFixture(
        server: server,
        identify: '实际%2F+',
      )..protected = true;
      final account = BookstarkClient(
        server.toString(),
        transport: MockClient((_) async => throw StateError('Owner forbidden')),
      );
      addTearDown(account.close);
      final repo = RemotePublicEditRepository(
        account,
        capabilityFactory: wire.capability,
        sourceFactory: wire.probe,
      );
      addTearDown(() => repo.retire(link()));
      final locked = await repo.read(link());
      expect(locked.locked, isTrue);
      expect(locked.content, isEmpty);
      await expectLater(
        repo.save(link(), locked, 'overwrite'),
        throwsStateError,
      );
      expect(wire.puts, 0);
      final unlocked = await repo.read(link(), password: ' correct ');
      expect(unlocked.locked, isFalse);
      expect(unlocked.content, wire.source);
      await repo.save(
        link(),
        unlocked,
        '# Saved content',
        password: ' correct ',
      );
      expect(wire.source, '# Saved content');
      expect(wire.puts, 1);
      expect(wire.protected, isTrue);
    },
  );
  test(
    'applied lost typed CAS reply remains unknown and read-only review never replays',
    () async {
      final wire = SharedCapabilityHttpFixture(
        server: server,
        identify: '实际%2F+',
      )..loseReply = true;
      final account = BookstarkClient(server.toString());
      addTearDown(account.close);
      final repo = RemotePublicEditRepository(
        account,
        capabilityFactory: wire.capability,
        sourceFactory: wire.probe,
      );
      final controller = PublicEditController(repo, link());
      addTearDown(controller.close);
      await controller.initialize();
      await expectLater(controller.save('# Applied once'), throwsA(anything));
      expect(controller.phase, PublicEditPhase.unknown);
      expect(wire.puts, 1);
      expect(wire.source, '# Applied once');
      await controller.verify();
      expect(wire.puts, 1);
      expect(controller.phase, PublicEditPhase.acknowledged);
      expect(controller.confirmedByRead, isTrue);
    },
  );
  test(
    'same-body capability retarget rejected by mandatory transaction tuple',
    () async {
      final wire = SharedCapabilityHttpFixture(
        server: server,
        identify: '实际%2F+',
      );
      final account = BookstarkClient(server.toString());
      addTearDown(account.close);
      final repo = RemotePublicEditRepository(
        account,
        capabilityFactory: wire.capability,
        sourceFactory: wire.probe,
      );
      addTearDown(() => repo.retire(link()));
      final baseline = await repo.read(link());
      wire.retargetOnPut = true;
      await expectLater(
        repo.save(link(), baseline, '# Wrong target'),
        throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)),
      );
      expect(wire.source, baseline.content);
      expect(wire.puts, 1);
    },
  );
  test(
    'fresh actual collection change blocks controller before any typed PUT',
    () async {
      final wire = SharedCapabilityHttpFixture(
        server: server,
        identify: '实际%2F+',
      );
      final account = BookstarkClient(server.toString());
      addTearDown(account.close);
      final repo = RemotePublicEditRepository(
        account,
        capabilityFactory: wire.capability,
        sourceFactory: wire.probe,
      );
      final controller = PublicEditController(repo, link());
      addTearDown(controller.close);
      await controller.initialize();
      wire.collection = 'article';
      await expectLater(
        controller.save('# Forbidden collection'),
        throwsStateError,
      );
      expect(controller.phase, PublicEditPhase.blocked);
      expect(wire.puts, 0);
      expect(wire.source, '\ufeff# Editable body\r\n');
      expect(wire.title, 'Actual editing title');
    },
  );
  test(
    'format, protection and actual explicit-share membership cannot silently change into owner editing',
    () {
      final context = PublicShareDetail.fromJson(link().reference, publicRow());
      final html = PublicEditSnapshot.parse(context, editRow(format: 'html'));
      expect(html.format, 'html');
      expect(
        () => PublicEditSnapshot.parse(context, editRow(locked: true)),
        throwsStateError,
      );
      final implicit = PublicShareDetail.fromJson(
        link().reference,
        publicRow(shareId: -3),
      );
      expect(
        () => PublicEditSnapshot.parse(implicit, editRow()),
        throwsStateError,
      );
      final changed = PublicEditSnapshot.parse(context, {
        ...editRow(),
        'modify_time': '2026-11-05 12:00:01',
      });
      expect(
        changed.sameVersion(PublicEditSnapshot.parse(context, editRow())),
        isFalse,
      );
    },
  );
  test(
    'Markdown shared-save bound counts UTF8 bytes and rejects malformed surrogate text before any write',
    () {
      validateSharedMarkdown('');
      validateSharedMarkdown(List.filled(500 * 1024, 'a').join());
      expect(
        () => validateSharedMarkdown(List.filled(500 * 1024 + 1, 'a').join()),
        throwsFormatException,
      );
      expect(
        () => validateSharedMarkdown(List.filled(170667, '中').join()),
        throwsFormatException,
      );
      expect(
        () => validateSharedMarkdown(String.fromCharCode(0xd800)),
        throwsFormatException,
      );
    },
  );
}
