import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/features/admin/admin_docker_models.dart';

Map<String, dynamic> inspect({
  String id = '',
  String status = 'running',
  bool running = true,
}) => {
  'id': id.isEmpty ? List.filled(64, 'a').join() : id,
  'name': 'owned43',
  'image': 'owned43:v1',
  'status': status,
  'running': running,
  'exit_code': 0,
  'created': '2026-11-08T00:00:00Z',
  'started_at': '2026-11-08T00:00:01Z',
  'finished_at': '',
  'hostname': 'owned43',
  'ip_address': '',
  'restart_policy': 'no',
  'command': ['/bin/sh'],
  'checked_at': 'read-one',
};
void main() {
  test(
    'list short ID is bound only after actual full inspect identity matches',
    () {
      final row = DockerRecord.parseList(DockerResource.containers, [
        {
          'id': 'aaaaaaaaaaaa',
          'name': 'owned43',
          'image': 'owned43:v1',
          'status': 'running',
        },
      ]).single;
      final detail = DockerInspect.parse(inspect());
      detail.match(row);
      expect(detail.id.length, 64);
      expect(
        () => DockerInspect.parse({...inspect(), 'name': 'another'}).match(row),
        throwsFormatException,
      );
      expect(
        () => DockerInspect.parse(
          inspect(id: List.filled(64, 'b').join()),
        ).match(row),
        throwsFormatException,
      );
      expect(
        () => DockerInspect.parse(inspect(id: 'aaaaaaaaaaaa')),
        throwsFormatException,
      );
    },
  );
  test(
    'read time is excluded but lifecycle and restart changes invalidate review',
    () {
      final first = DockerInspect.parse(inspect());
      expect(
        DockerInspect.parse({
          ...inspect(),
          'checked_at': 'read-two',
        }).fingerprint,
        first.fingerprint,
      );
      expect(
        DockerInspect.parse(
          inspect(status: 'exited', running: false),
        ).fingerprint,
        isNot(first.fingerprint),
      );
      expect(
        DockerInspect.parse({
          ...inspect(),
          'restart_policy': 'always',
        }).fingerprint,
        isNot(first.fingerprint),
      );
    },
  );
  test(
    'image tag selection remains precise even when two tags share short ID',
    () {
      final rows = DockerRecord.parseList(DockerResource.images, [
        {
          'id': 'aaaaaaaaaaaa',
          'repository': 'registry:5000/owned/image',
          'tag': 'one',
        },
        {
          'id': 'aaaaaaaaaaaa',
          'repository': 'registry:5000/owned/image',
          'tag': 'two',
        },
      ]);
      expect(rows.map((v) => v.target), [
        'registry:5000/owned/image:one',
        'registry:5000/owned/image:two',
      ]);
      expect(
        () => DockerRecord.parseList(DockerResource.images, [
          {'id': 'aaaaaaaaaaaa', 'repository': 'owned', 'tag': 'one'},
          {'id': 'bbbbbbbbbbbb', 'repository': 'owned', 'tag': 'one'},
        ]),
        throwsFormatException,
      );
    },
  );
  test(
    'relative ages do not invalidate stable identity while lifecycle still does',
    () {
      final first = DockerRecord.parseList(DockerResource.images, [
        {
          'id': 'aaaaaaaaaaaa',
          'repository': 'owned',
          'tag': 'v1',
          'created_since': '1 second ago',
        },
      ]).single;
      final later = DockerRecord.parseList(DockerResource.images, [
        {
          'id': 'aaaaaaaaaaaa',
          'repository': 'owned',
          'tag': 'v1',
          'created_since': '2 seconds ago',
        },
      ]).single;
      expect(first.fingerprint, later.fingerprint);
      final running = DockerRecord.parseList(DockerResource.containers, [
        {
          'id': 'aaaaaaaaaaaa',
          'name': 'owned',
          'image': 'owned:v1',
          'status': 'running',
          'status_text': 'Up 1 second',
        },
      ]).single;
      final stopped = DockerRecord.parseList(DockerResource.containers, [
        {
          'id': 'aaaaaaaaaaaa',
          'name': 'owned',
          'image': 'owned:v1',
          'status': 'stopped',
          'status_text': 'Exited',
        },
      ]).single;
      expect(running.fingerprint, isNot(stopped.fingerprint));
    },
  );
  test('malformed list cannot silently become empty or usable metadata', () {
    expect(
      () => DockerRecord.parseList(DockerResource.containers, {}),
      throwsFormatException,
    );
    expect(
      () => DockerRecord.parseList(DockerResource.containers, [
        {'id': '../evil'},
      ]),
      throwsFormatException,
    );
    expect(
      () => DockerRecord.parseList(DockerResource.volumes, [
        {'name': '-unsafe'},
      ]),
      throwsFormatException,
    );
    expect(
      () => DockerRecord.parseList(DockerResource.images, [
        {'id': 'aaaaaaaaaaaa', 'repository': 'bad\u0000', 'tag': 'v'},
      ]),
      throwsFormatException,
    );
  });
  test(
    'create explicitly controls start and preserves single command argument',
    () {
      final body = DockerCreateDraft(
        name: 'owned43',
        image: 'owned43:v1',
        command: 'printf hello world',
        env: [
          {'key': 'OWNED_VALUE', 'value': '中文😀=literal'},
        ],
      ).toRequest();
      expect(body['start_after_create'], false);
      expect(body['command'], 'printf hello world');
      expect((body['env'] as List).single, {
        'key': 'OWNED_VALUE',
        'value': '中文😀=literal',
      });
      expect(jsonEncode(body), isNot(contains('sh -c')));
    },
  );
  test('invalid resources or ambiguous environment cannot reach dispatch', () {
    for (final cpu in ['NaN', 'Infinity', '-1', '1000001']) {
      expect(
        () => DockerCreateDraft(
          name: 'owned43',
          image: 'owned:v1',
          cpus: cpu,
        ).toRequest(),
        throwsFormatException,
      );
    }
    expect(
      () => DockerCreateDraft(
        name: 'owned43',
        image: 'owned:v1',
        memory: '-1g',
      ).toRequest(),
      throwsFormatException,
    );
    expect(
      () => DockerCreateDraft(
        name: 'owned43',
        image: 'owned:v1',
        env: [
          {'key': 'SAME', 'value': 'a'},
          {'key': 'SAME', 'value': 'b'},
        ],
      ).toRequest(),
      throwsFormatException,
    );
    expect(
      () => DockerCreateDraft(
        name: 'owned43',
        image: 'owned:v1',
        ports: [
          {
            'host_ip': '0.0.0.0',
            'host_port': '',
            'container_port': '80',
            'protocol': 'tcp',
          },
        ],
      ).toRequest(),
      throwsFormatException,
    );
    expect(
      () => DockerCreateDraft(
        name: 'owned43',
        image: 'owned:v1',
        volumes: [
          {'host_path': '/source', 'container_path': 'relative', 'mode': 'rw'},
        ],
      ).toRequest(),
      throwsFormatException,
    );
  });
  test('published ports require explicit compatible address and host port', () {
    for (final address in ['', '::1', '999.0.0.1', '127.00.0.1']) {
      expect(
        () => DockerCreateDraft(
          name: 'owned43',
          image: 'owned:v1',
          ports: [
            {
              'host_ip': address,
              'host_port': '8080',
              'container_port': '80',
              'protocol': 'tcp',
            },
          ],
        ).toRequest(),
        throwsFormatException,
      );
    }
    expect(
      () => DockerCreateDraft(
        name: 'owned43',
        image: 'owned:v1',
        ports: [
          {
            'host_ip': '127.0.0.1',
            'host_port': '',
            'container_port': '80',
            'protocol': 'tcp',
          },
        ],
      ).toRequest(),
      throwsFormatException,
    );
    final body = DockerCreateDraft(
      name: 'owned43',
      image: 'owned:v1',
      ports: [
        {
          'host_ip': '127.0.0.1',
          'host_port': '8080',
          'container_port': '80',
          'protocol': 'tcp',
        },
      ],
    ).toRequest();
    expect((body['ports'] as List).single['host_port'], '8080');
  });
  test('diagnostic string never includes temporary values', () {
    final draft = DockerCreateDraft(
      name: 'owned43',
      image: 'owned:v1',
      env: [
        {'key': 'TOKEN', 'value': 'owned-test-secret'},
      ],
    );
    expect(draft.toString(), 'DockerCreateDraft');
    final info = DockerInspect.parse({
      ...inspect(),
      'command': ['owned-test-secret'],
    });
    expect(info.toString(), 'DockerInspect');
  });
}
