import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';

import 'package:bookstark_flutter/core/remote_markdown_creation_transport.dart';
import 'package:bookstark_flutter/core/remote_markdown_creation_vault.dart';

void main() {
  final scope = MarkdownCreationScope(
    server: Uri.parse('https://demo.example/prefix'),
    memberId: 7,
    collection: 'note',
  );
  final input = MarkdownCreationInput(
    title: 'Trip',
    content: '\ufeff# 完整😀\r\n',
    labels: ['travel', 'work'],
  );
  Map<String, Object?> row({
    String format = 'markdown',
    bool protected = false,
    int owner = 7,
    int version = 1,
    int visibility = 0,
  }) => {
    'blog_id': 318,
    'member_id': owner,
    'blog_type': 'note',
    'editor_type': format,
    'visibility': visibility,
    'has_password': protected,
    'blog_title': input.title,
    'blog_content': input.content,
    'version': version,
    'modify_at': 100 + version,
  };
  BookstarkClient client(
    Map<String, Object?> Function() meta, {
    int owner = 7,
  }) {
    final c = BookstarkClient(
      scope.server.toString(),
      transport: MockClient((request) async {
        final data = request.url.path.endsWith('/318')
            ? meta()
            : {'member_id': owner};
        return http.Response(
          jsonEncode({'code': 0, 'data': data}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    c.restoreSession({'token': 'fixture-token', 'csrf_token': 'fixture-csrf'});
    return c;
  }

  test(
    'same token and same cookies restore blocks the pre-send hook',
    () async {
      final c = client(() => row());
      var sends = 0;
      final transport = BookstarkMarkdownCreationTransport(
        client: c,
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async {
          c.restoreSession(c.exportSession());
          onSubmit(); // must throw before an actual sender may send bytes
          sends++;
          return {'code': 0, 'data': row()};
        },
        readFullJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': row(),
        },
        readLabelsJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': input.labels,
        },
      );
      await expectLater(
        transport.submit(input, onSubmit: () {}),
        throwsStateError,
      );
      expect(sends, 0);
    },
  );
  test(
    'same token same cookies restore rejects late full-source inspection',
    () async {
      final c = client(() => row());
      final ready = Completer<void>(),
          pending = Completer<Map<String, Object?>>();
      final transport = BookstarkMarkdownCreationTransport(
        client: c,
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async {
          onSubmit();
          return {'code': 0, 'data': row()};
        },
        readFullJson: (id, {required abortTrigger}) {
          ready.complete();
          return pending.future;
        },
        readLabelsJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': input.labels,
        },
      );
      final result = transport.inspect(318);
      final checked = expectLater(result, throwsStateError);
      await ready.future;
      c.restoreSession(c.exportSession());
      pending.complete({'code': 0, 'data': row()});
      await checked;
    },
  );
  test('retire aborts an actual in-flight read callback', () async {
    final ready = Completer<void>(),
        pending = Completer<Map<String, Object?>>();
    var aborted = false;
    final transport = BookstarkMarkdownCreationTransport(
      client: client(() => row()),
      scope: scope,
      isCurrent: () => true,
      createJson: (body, {required onSubmit, required abortTrigger}) async {
        onSubmit();
        return {'code': 0, 'data': row()};
      },
      readFullJson: (id, {required abortTrigger}) {
        ready.complete();
        abortTrigger.then((_) {
          aborted = true;
          if (!pending.isCompleted) {
            pending.completeError(StateError('Aborted'));
          }
        });
        return pending.future;
      },
      readLabelsJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': input.labels,
      },
    );
    final result = transport.inspect(318);
    final assertion = expectLater(result, throwsStateError);
    await ready.future;
    transport.retire();
    await assertion;
    expect(aborted, true);
  });
  test(
    'Go nil label slice means empty labels, missing data still fails',
    () async {
      final transport = BookstarkMarkdownCreationTransport(
        client: client(() => row()),
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async {
          onSubmit();
          return {'code': 0, 'data': row()};
        },
        readFullJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': row(),
        },
        readLabelsJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': null,
        },
      );
      expect((await transport.inspect(318)).input.labels, isEmpty);
      final missing = BookstarkMarkdownCreationTransport(
        client: client(() => row()),
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async {
          onSubmit();
          return {'code': 0, 'data': row()};
        },
        readFullJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': row(),
        },
        readLabelsJson: (id, {required abortTrigger}) async => {'code': 0},
      );
      await expectLater(missing.inspect(318), throwsFormatException);
    },
  );
  test(
    'required callback receives exact private Markdown body and precise submit hook',
    () async {
      var hooks = 0, creates = 0;
      final c = client(() => row());
      final transport = BookstarkMarkdownCreationTransport(
        client: c,
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async {
          creates++;
          expect(body['editor_type'], 'markdown');
          expect(body['visibility'], 0);
          expect(body['blog_content'], input.content);
          expect(body.containsKey('new_password'), false);
          onSubmit();
          return {'code': 0, 'data': row()};
        },
        readFullJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': row(),
        },
        readLabelsJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': input.labels,
        },
      );
      expect(
        await transport.submit(
          input,
          onSubmit: () {
            hooks++;
          },
        ),
        318,
      );
      expect(creates, 1);
      expect(hooks, 1);
    },
  );
  test(
    'missing callback invocation is invalid, not a fake acknowledged request',
    () async {
      final transport = BookstarkMarkdownCreationTransport(
        client: client(() => row()),
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async =>
            row(),
        readFullJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': row(),
        },
        readLabelsJson: (id, {required abortTrigger}) async => {
          'code': 0,
          'data': input.labels,
        },
      );
      await expectLater(
        transport.submit(input, onSubmit: () {}),
        throwsFormatException,
      );
    },
  );
  test(
    'receipt rejects wrong owner/format/public and preserves exact BOM content',
    () async {
      for (final bad in [
        row(owner: 8),
        row(format: 'html'),
        row(visibility: 1),
        {...row(), 'blog_content': 'normalized content'},
      ]) {
        final transport = BookstarkMarkdownCreationTransport(
          client: client(() => row()),
          scope: scope,
          isCurrent: () => true,
          createJson: (body, {required onSubmit, required abortTrigger}) async {
            onSubmit();
            return {'code': 0, 'data': bad};
          },
          readFullJson: (id, {required abortTrigger}) async => {
            'code': 0,
            'data': row(),
          },
          readLabelsJson: (id, {required abortTrigger}) async => {
            'code': 0,
            'data': input.labels,
          },
        );
        await expectLater(
          transport.submit(input, onSubmit: () {}),
          throwsFormatException,
        );
        transport.retire();
      }
    },
  );
  test(
    'metadata full source labels metadata labels bracket preserves full snapshot',
    () async {
      var fullReads = 0, labelReads = 0;
      final transport = BookstarkMarkdownCreationTransport(
        client: client(() => row()),
        scope: scope,
        isCurrent: () => true,
        createJson: (body, {required onSubmit, required abortTrigger}) async {
          onSubmit();
          return {'code': 0, 'data': row()};
        },
        readFullJson: (id, {required abortTrigger}) async {
          fullReads++;
          return {'code': 0, 'data': row()};
        },
        readLabelsJson: (id, {required abortTrigger}) async {
          labelReads++;
          return {'code': 0, 'data': input.labels};
        },
      );
      final actual = await transport.inspect(318);
      expect(actual.input.fingerprint, input.fingerprint);
      expect(fullReads, 1);
      expect(labelReads, 2);
    },
  );
  test(
    'foreign protected complex and public metadata rejected BEFORE raw callback',
    () async {
      for (final bad in [
        row(owner: 8),
        row(protected: true),
        row(format: 'html'),
        row(visibility: 1),
        Map<String, Object?>.from(row())..remove('visibility'),
      ]) {
        var raw = 0;
        final transport = BookstarkMarkdownCreationTransport(
          client: client(() => bad),
          scope: scope,
          isCurrent: () => true,
          createJson: (body, {required onSubmit, required abortTrigger}) async {
            onSubmit();
            return {'code': 0, 'data': row()};
          },
          readFullJson: (id, {required abortTrigger}) async {
            raw++;
            return {'code': 0, 'data': row()};
          },
          readLabelsJson: (id, {required abortTrigger}) async => {
            'code': 0,
            'data': input.labels,
          },
        );
        await expectLater(transport.inspect(318), throwsFormatException);
        expect(raw, 0);
      }
    },
  );
  test('version or label changes across bracket refuse snapshot', () async {
    var reads = 0;
    final transport = BookstarkMarkdownCreationTransport(
      client: client(() => row(version: ++reads == 1 ? 1 : 2)),
      scope: scope,
      isCurrent: () => true,
      createJson: (body, {required onSubmit, required abortTrigger}) async {
        onSubmit();
        return {'code': 0, 'data': row()};
      },
      readFullJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': row(),
      },
      readLabelsJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': input.labels,
      },
    );
    await expectLater(transport.inspect(318), throwsStateError);
    var labels = 0;
    final other = BookstarkMarkdownCreationTransport(
      client: client(() => row()),
      scope: scope,
      isCurrent: () => true,
      createJson: (body, {required onSubmit, required abortTrigger}) async {
        onSubmit();
        return {'code': 0, 'data': row()};
      },
      readFullJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': row(),
      },
      readLabelsJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': ++labels == 1 ? input.labels : ['changed'],
      },
    );
    await expectLater(other.inspect(318), throwsStateError);
  });
  test('wrong active owner and retired transport do not submit', () async {
    var creates = 0;
    final transport = BookstarkMarkdownCreationTransport(
      client: client(() => row(), owner: 8),
      scope: scope,
      isCurrent: () => true,
      createJson: (body, {required onSubmit, required abortTrigger}) async {
        creates++;
        onSubmit();
        return {'code': 0, 'data': row()};
      },
      readFullJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': row(),
      },
      readLabelsJson: (id, {required abortTrigger}) async => {
        'code': 0,
        'data': input.labels,
      },
    );
    await expectLater(
      transport.submit(input, onSubmit: () {}),
      throwsStateError,
    );
    expect(creates, 0);
    transport.retire();
    await expectLater(transport.inspect(318), throwsStateError);
  });
}
