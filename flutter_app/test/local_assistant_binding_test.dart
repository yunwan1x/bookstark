import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/local_assistant_binding.dart';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LocalModelConfig config({
    String key = 'private-key',
    bool knowledge = false,
  }) => LocalModelConfig(
    endpoint: 'https://model.invalid/v1',
    model: 'test',
    apiKey: key,
    allowKnowledge: knowledge,
  );
  test(
    'database configuration credential and permission changes isolate context',
    () async {
      final values = <String, String>{};
      LocalAssistantBinding vault(String database) => LocalAssistantBinding(
        namespace: database,
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      final a = await vault('database-a').open(config());
      expect(await vault('database-a').open(config()), a);
      final b = await vault('database-a').open(config(key: 'rotated'));
      final c = await vault(
        'database-a',
      ).open(config(key: 'rotated', knowledge: true));
      final d = await vault('database-b').open(config());
      expect({a, b, c, d}.length, 4);
      expect(values.keys.join(), isNot(contains('private-key')));
      expect(values.keys.join(), isNot(contains('rotated')));
      expect(values.keys.join(), isNot(contains('model.invalid')));
    },
  );
  test(
    'corrupt metadata is retained and never silently resets conversation',
    () async {
      var writes = 0;
      final vault = LocalAssistantBinding(
        namespace: 'corrupt',
        readValue: (_) async => '{"version":2}',
        writeValue: (_, _) async {
          writes++;
        },
      );
      await expectLater(vault.open(config()), throwsFormatException);
      expect(writes, 0);
    },
  );
  test(
    'unknown write uses readback on next open without generating another session',
    () async {
      String? value;
      var writes = 0;
      final vault = LocalAssistantBinding(
        namespace: 'unknown',
        readValue: (_) async => value,
        writeValue: (_, data) async {
          value = data;
          writes++;
          throw StateError('lost ack');
        },
      );
      await expectLater(vault.open(config()), throwsStateError);
      final recovered = await vault.open(config());
      expect(recovered, (jsonDecode(value!) as Map)['generation']);
      expect(writes, 1);
    },
  );
  test(
    'retired slow writer cannot overwrite subsequent owner configuration',
    () async {
      String? value;
      var current = true;
      final started = Completer<void>(), release = Completer<void>();
      final old = LocalAssistantBinding(
        namespace: 'ordered',
        isCurrent: () => current,
        readValue: (_) async => value,
        writeValue: (_, data) async {
          started.complete();
          await release.future;
          value = data;
        },
      );
      final pending = old.open(config());
      final failed = expectLater(
        pending,
        throwsA(isA<LocalModelScopeRetired>()),
      );
      await started.future;
      current = false;
      final next = LocalAssistantBinding(
        namespace: 'ordered',
        readValue: (_) async => value,
        writeValue: (_, data) async {
          value = data;
        },
      );
      final fresh = next.open(config(key: 'new'));
      release.complete();
      await failed;
      final id = await fresh;
      expect((jsonDecode(value!) as Map)['generation'], id);
      expect(
        LocalModelConfig.fromRecord(
          (jsonDecode(value!) as Map)['config'],
        ).apiKey,
        'new',
      );
    },
  );
  test(
    'explicit corrupt-link reset replaces only the binding after confirmation',
    () async {
      final values = <String, String>{'unrelated': 'retained'};
      final vault = LocalAssistantBinding(
        namespace: 'reset',
        readValue: (key) async => values[key],
        writeValue: (key, value) async {
          values[key] = value;
        },
      );
      values[vault.key] = 'corrupt';
      await expectLater(
        vault.open(config()),
        throwsA(isA<LocalAssistantBindingCorrupt>()),
      );
      expect(values[vault.key], 'corrupt');
      final id = await vault.reset(config());
      expect(await vault.open(config()), id);
      expect(values['unrelated'], 'retained');
    },
  );
  test('retired owner cannot reset even an unreadable binding', () async {
    var writes = 0;
    final vault = LocalAssistantBinding(
      namespace: 'retired-reset',
      isCurrent: () => false,
      readValue: (_) async => 'corrupt',
      writeValue: (_, _) async {
        writes++;
      },
    );
    await expectLater(
      vault.reset(config()),
      throwsA(isA<LocalModelScopeRetired>()),
    );
    expect(writes, 0);
  });
}
