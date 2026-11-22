// Explicit disposable Go fixture only; excluded from normal test discovery.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/html_creation_vault.dart';
import 'package:bookstark_flutter/core/remote_html_creation_repository.dart';
import 'package:bookstark_flutter/core/remote_html_creation_controller.dart';

class ObservedCreationTransport extends http.BaseClient {
  final inner = http.Client();
  int posts = 0, receiptBytes = 0;
  int? appliedId;
  bool dropReceipt = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await inner.send(request);
    if (request.method != 'POST' || request.url.path != '/api/blogs') {
      return response;
    }
    posts++;
    final receipt = await http.Response.fromStream(response);
    receiptBytes = receipt.bodyBytes.length;
    final data = jsonDecode(utf8.decode(receipt.bodyBytes)) as Map;
    appliedId = (data['data'] as Map)['blog_id'] as int;
    if (dropReceipt) {
      throw http.ClientException(
        'Applied Go POST; intentionally dropped receipt',
      );
    }
    return http.StreamedResponse(
      Stream.value(receipt.bodyBytes),
      receipt.statusCode,
      headers: receipt.headers,
    );
  }

  @override
  void close() => inner.close();
}

void main() {
  test(
    'actual Go full Blog echo and applied POST loss recover with no replay',
    () async {
      final path = Platform.environment['BOOKSTARK_ANDROID_FIXTURE_CONFIG'];
      if (path == null ||
          !path.startsWith(
            '/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-live-fixture/',
          )) {
        throw StateError('Disposable fixture config required');
      }
      final config = jsonDecode(await File(path).readAsString()) as Map;
      final base = Uri.parse(config['local_base'] as String);
      if (config['fixture'] != true ||
          base.host != '127.0.0.1' ||
          base.scheme != 'http') {
        throw StateError('Only owned loopback fixture is permitted');
      }
      final transport = ObservedCreationTransport();
      final client = BookstarkClient(base.toString(), transport: transport);
      final values = <String, String>{};
      RemoteHtmlCreationController? controller;
      final created = <int>[];
      try {
        await client.login(
          config['account'] as String,
          config['password'] as String,
        );
        final member = (await client.profileSettingsJson())['member_id'] as int;
        final random = Random(4967);
        final noisy = base64Encode(
          List.generate(256 * 1024, (_) => random.nextInt(256)),
        );
        final edit = HtmlNoteEdit(
          title:
              'Go large HTML create ${DateTime.now().microsecondsSinceEpoch}',
          source: '<!doctype html>\r\n<p>中文</p>\n<!--$noisy-->\r\n',
          labels: ['html-create-fixture'],
        );
        final repo = RemoteHtmlCreationRepository(
          client,
          memberId: member,
          collection: 'note',
        );
        final empty = await repo.candidates(
          keyword: 'absent-${DateTime.now().microsecondsSinceEpoch}',
        );
        expect(empty.candidates, isEmpty);
        int? stored;
        final id = await repo.submit(
          edit,
          persistReceipt: (id) async {
            stored = id;
          },
        );
        created.add(id);
        final candidates = await repo.candidates(keyword: edit.title);
        expect(
          candidates.candidates.any((candidate) => candidate.id == id),
          isTrue,
        );
        expect(stored, id);
        expect(transport.posts, 1);
        expect(transport.receiptBytes, greaterThan(128 * 1024));
        final reader = RemoteHtmlNotesRepository(client, memberId: member);
        final saved = await reader.read(id);
        expect(edit.matches(saved), isTrue);
        reader.dispose();
        repo.dispose();

        final vault = HtmlCreationVault(
          server: client.baseUri,
          memberId: member,
          collection: 'note',
          readValue: (k) async => values[k],
          writeValue: (k, v) async {
            values[k] = v;
          },
          deleteValue: (k) async {
            values.remove(k);
          },
        );
        controller = RemoteHtmlCreationController(
          RemoteHtmlCreationRepository(
            client,
            memberId: member,
            collection: 'note',
          ),
          vault,
        );
        controller.edit(
          HtmlNoteEdit(
            title: '${edit.title} dropped',
            source: edit.source,
            labels: edit.labels,
          ),
        );
        transport.dropReceipt = true;
        await controller.save();
        final actualId = transport.appliedId!;
        created.add(actualId);
        expect(controller.phase, RemoteHtmlCreationPhase.unknown);
        expect(controller.receiptId, isNull);
        expect(transport.posts, 2);
        final recovery = await vault.readRecovery();
        controller.dispose();
        controller = RemoteHtmlCreationController(
          RemoteHtmlCreationRepository(
            client,
            memberId: member,
            collection: 'note',
          ),
          vault,
          record: recovery,
        );
        await controller.inspect(actualId);
        expect(controller.observed!.source, edit.source);
        controller.markReviewed(controller.observed!);
        await controller.adopt();
        expect(controller.phase, RemoteHtmlCreationPhase.finished);
        expect(controller.receiptKnown, isFalse);
        expect(transport.posts, 2);
        expect(values, isEmpty);
      } finally {
        controller?.dispose();
        for (final id in created) {
          await client.mutate('DELETE', '/api/blogs/$id', {});
        }
        client.close();
      }
    },
  );
}
