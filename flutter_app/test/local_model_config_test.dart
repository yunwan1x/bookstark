import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

LocalModelConfig config({
  String endpoint = 'https://model.example.invalid/prefix/v1/',
  String key = 'fixture-secret',
}) => LocalModelConfig(
  endpoint: endpoint,
  model: 'fixture-model',
  apiKey: key,
  allowKnowledge: true,
);

void main() {
  test(
    'explicit endpoint and model validation rejects ambiguous or credential URLs',
    () {
      for (final value in [
        '',
        'file:///data/local',
        'ftp://host/v1',
        'https://u:p@host/v1',
        'https://host/v1?key=private',
        'https://host/v1#key',
        'https://host:70000/v1',
        'https:///',
      ]) {
        expect(() => config(endpoint: value), throwsFormatException);
      }
      expect(
        config().chatUri.toString(),
        'https://model.example.invalid/prefix/v1/chat/completions',
      );
      expect(config().chatUri.toString(), isNot(contains('fixture-secret')));
      expect(
        () => LocalModelConfig(endpoint: 'https://host', model: ''),
        throwsFormatException,
      );
      expect(() => config(key: 'line\nbreak'), throwsFormatException);
      expect(() => config(key: 'a' * 8193), throwsFormatException);
      expect(config(key: '').apiKey, '');
    },
  );
  test(
    'configuration roundtrip isolates actual DB identities without reading unrelated keys',
    () async {
      final values = <String, String>{'account-credential': 'keep'};
      final reads = <String>[];
      LocalModelConfigVault vault(String namespace) => LocalModelConfigVault(
        namespace: namespace,
        readValue: (k) async {
          reads.add(k);
          return values[k];
        },
        writeValue: (k, v) async {
          values[k] = v;
        },
      );
      final a = vault('/actual/a.db'), b = vault('/actual/b.db');
      await a.save(config());
      expect((await vault('/actual/a.db').read())!.same(config()), true);
      expect(await b.read(), isNull);
      expect(values['account-credential'], 'keep');
      expect(reads, everyElement(isNot('account-credential')));
      expect(a.key.startsWith('bookstark.local-'), false);
    },
  );
  test(
    'corrupt configuration is retained until explicit owned reset',
    () async {
      final values = <String, String>{};
      final vault = LocalModelConfigVault(
        namespace: 'a',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
      );
      values[vault.key] = '{broken';
      await expectLater(vault.read(), throwsA(isA<LocalModelConfigCorrupt>()));
      await expectLater(
        vault.save(config()),
        throwsA(isA<LocalModelConfigCorrupt>()),
      );
      expect(values[vault.key], '{broken');
      await vault.reset();
      expect(await vault.read(), isNull);
    },
  );
  test(
    'applied storage write with lost receipt is unknown and readback never repeats it',
    () async {
      String? value;
      var writes = 0;
      final vault = LocalModelConfigVault(
        namespace: 'a',
        readValue: (_) async => value,
        writeValue: (_, v) async {
          value = v;
          writes++;
          throw StateError('receipt dropped');
        },
      );
      await expectLater(
        vault.save(config()),
        throwsA(isA<LocalModelSaveUnknown>()),
      );
      expect(writes, 1);
      expect((await vault.read())!.same(config()), true);
      expect(writes, 1);
    },
  );
  test('scope retirement during read prevents any later write', () async {
    final read = Completer<String?>();
    var current = true, writes = 0;
    final vault = LocalModelConfigVault(
      namespace: 'a',
      isCurrent: () => current,
      readValue: (_) => read.future,
      writeValue: (_, _) async {
        writes++;
      },
    );
    final pending = vault.save(config());
    await Future<void>.delayed(Duration.zero);
    current = false;
    read.complete(null);
    await expectLater(pending, throwsA(isA<LocalModelScopeRetired>()));
    expect(writes, 0);
  });
  test(
    'compatible probe is one bounded prefixed request with no account authority',
    () async {
      var calls = 0;
      final probe = LocalModelProbe(
        createClient: () => MockClient((request) async {
          calls++;
          expect(
            request.url.toString(),
            'https://model.example.invalid/prefix/v1/chat/completions',
          );
          expect(request.followRedirects, false);
          expect(request.headers['authorization'], 'Bearer fixture-secret');
          expect(request.headers.containsKey('cookie'), false);
          expect(request.headers.containsKey('x-csrf-token'), false);
          final body = jsonDecode(request.body) as Map;
          expect(body['model'], 'fixture-model');
          expect(body['stream'], false);
          expect(body['max_tokens'], 16);
          expect(body['messages'], [
            {'role': 'user', 'content': 'ping'},
          ]);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'OK'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await probe.test(config());
      expect(calls, 1);
    },
  );
  test(
    'anonymous self-hosted service receives no invented authorization header',
    () async {
      final probe = LocalModelProbe(
        createClient: () => MockClient((request) async {
          expect(request.headers.containsKey('authorization'), false);
          return http.Response(
            '{"choices":[{"message":{"content":"OK"}}]}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await probe.test(config(endpoint: 'http://127.0.0.1:8080/v1', key: ''));
    },
  );
  test(
    'redirects and provider failures never expose response bodies or follow another host',
    () async {
      for (final row in [
        (302, LocalModelProbeIssue.redirect),
        (401, LocalModelProbeIssue.authentication),
        (403, LocalModelProbeIssue.authentication),
        (429, LocalModelProbeIssue.busy),
        (503, LocalModelProbeIssue.network),
      ]) {
        var calls = 0;
        final probe = LocalModelProbe(
          createClient: () => MockClient((_) async {
            calls++;
            return http.Response(
              'echo fixture-secret',
              row.$1,
              headers: {
                'location': 'https://other.invalid/steal',
                'content-type': 'text/plain',
              },
            );
          }),
        );
        try {
          await probe.test(config());
          fail('Failure required');
        } on LocalModelProbeFailure catch (e) {
          expect(e.issue, row.$2);
          expect(e.toString(), isNot(contains('fixture-secret')));
        }
        expect(calls, 1);
      }
    },
  );
  test(
    'wrong MIME, blank content, malformed and oversized JSON are not successful probes',
    () async {
      for (final row in [
        ('{"choices":[{"message":{"content":"OK"}}]}', 'text/html'),
        ('{"choices":[{"message":{"content":""}}]}', 'application/json'),
        ('{broken', 'application/json'),
        ('x' * 65537, 'application/json'),
      ]) {
        final probe = LocalModelProbe(
          createClient: () => MockClient(
            (_) async =>
                http.Response(row.$1, 200, headers: {'content-type': row.$2}),
          ),
        );
        await expectLater(
          probe.test(config()),
          throwsA(
            isA<LocalModelProbeFailure>().having(
              (e) => e.issue,
              'issue',
              LocalModelProbeIssue.protocol,
            ),
          ),
        );
      }
    },
  );
  test(
    'actual HTTP incomplete body is cancelled before deadline without waiting for EOF',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final began = Completer<void>();
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"choices":');
        await request.response.flush();
        if (!began.isCompleted) began.complete();
        try {
          await request.response.done;
        } catch (_) {}
      });
      final abort = Completer<void>();
      final probe = LocalModelProbe(deadline: const Duration(seconds: 5));
      final pending = probe.test(
        config(endpoint: 'http://127.0.0.1:${server.port}/prefix', key: ''),
        abortTrigger: abort.future,
      );
      final caught = expectLater(
        pending,
        throwsA(isA<LocalModelProbeFailure>()),
      );
      try {
        await began.future.timeout(const Duration(seconds: 3));
        abort.complete();
        await caught.timeout(const Duration(seconds: 2));
      } finally {
        await server.close(force: true);
      }
    },
  );
  test(
    'a retired writer cannot finish after a newer vault save for the same database',
    () async {
      String? value;
      var current = true, writes = 0;
      final started = Completer<void>(), release = Completer<void>();
      Future<void> write(String key, String record) async {
        writes++;
        if (writes == 1) {
          started.complete();
          await release.future;
        }
        value = record;
      }

      final old = LocalModelConfigVault(
        namespace: 'shared-db',
        isCurrent: () => current,
        readValue: (_) async => value,
        writeValue: write,
      );
      final fresh = LocalModelConfigVault(
        namespace: 'shared-db',
        readValue: (_) async => value,
        writeValue: write,
      );
      final pending = old.save(config());
      final failed = expectLater(
        pending,
        throwsA(isA<LocalModelScopeRetired>()),
      );
      await started.future;
      current = false;
      final newer = config(endpoint: 'https://new.example.invalid/v1');
      final saved = fresh.save(newer);
      await Future<void>.delayed(Duration.zero);
      expect(writes, 1);
      release.complete();
      await failed;
      await saved;
      expect(writes, 2);
      expect((await fresh.read())!.same(newer), true);
    },
  );
}
