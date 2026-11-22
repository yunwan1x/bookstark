import 'dart:async';
import 'dart:convert';
import 'package:bookstark_flutter/core/local_model_config.dart';
import 'package:bookstark_flutter/features/assistant/local_model_settings_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Map<String, String> values;
  late LocalModelSettingsController state;
  var writes = 0, calls = 0, failWrite = false;
  Completer<http.Response>? response;
  setUp(() {
    values = {};
    writes = 0;
    calls = 0;
    failWrite = false;
    response = null;
    state = LocalModelSettingsController(
      vault: LocalModelConfigVault(
        namespace: 'db-a',
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
          writes++;
          if (failWrite) throw StateError('receipt lost');
        },
      ),
      probe: LocalModelProbe(
        createClient: () => MockClient((_) async {
          calls++;
          return response == null
              ? http.Response(
                  '{"choices":[{"message":{"content":"OK"}}]}',
                  200,
                  headers: {'content-type': 'application/json'},
                )
              : response!.future;
        }),
      ),
    );
  });
  tearDown(() => state.dispose());
  void edit() => state.edit(
    endpoint: 'https://model.example.invalid/v1',
    model: 'fixture-model',
    apiKey: 'fixture-secret',
  );
  test(
    'opening and editing never connect or save; save does not require a probe',
    () async {
      expect(await state.load(), true);
      expect(state.dirty, false);
      edit();
      expect(state.dirty, true);
      expect(calls, 0);
      expect(writes, 0);
      expect(await state.save(), true);
      expect(writes, 1);
      expect(calls, 0);
      expect(state.dirty, false);
      expect(state.probeOK, false);
    },
  );
  test(
    'unknown applied save blocks replay and matching readback resolves it',
    () async {
      await state.load();
      edit();
      failWrite = true;
      expect(await state.save(), false);
      expect(state.unknown, true);
      expect(writes, 1);
      expect(await state.save(), false);
      expect(writes, 1);
      expect(await state.testConnection(), false);
      expect(calls, 0);
      expect(await state.load(), true);
      expect(state.unknown, false);
      expect(state.dirty, false);
      expect(writes, 1);
    },
  );
  test(
    'different readback retains form instead of replacing the selected model',
    () async {
      await state.load();
      edit();
      failWrite = true;
      await state.save();
      final other = LocalModelConfig(
        endpoint: 'https://other.example.invalid/v1',
        model: 'other',
      );
      values[state.vault.key] = jsonEncode({
        'format': 1,
        'config': other.toRecord(),
      });
      expect(await state.load(), true);
      expect(state.model, 'fixture-model');
      expect(state.saved!.model, 'other');
      expect(state.dirty, true);
      expect(state.readbackDifferent, true);
    },
  );
  test('late test result cannot mark changed fields connected', () async {
    await state.load();
    edit();
    response = Completer<http.Response>();
    final pending = state.testConnection();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(state.probing, true);
    state.edit(model: 'different-model');
    response!.complete(
      http.Response(
        '{"choices":[{"message":{"content":"OK"}}]}',
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    expect(await pending, false);
    expect(state.probeOK, false);
    expect(state.probing, false);
  });
  test(
    'corrupt metadata requires explicit reset and touches no content keys',
    () async {
      values[state.vault.key] = '{broken';
      values['notes-content'] = 'unchanged';
      expect(await state.load(), false);
      expect(state.problem, isA<LocalModelConfigCorrupt>());
      expect(writes, 0);
      expect(await state.reset(), true);
      expect(await state.vault.read(), isNull);
      expect(values['notes-content'], 'unchanged');
      expect(state.dirty, false);
      expect(state.loaded, true);
    },
  );
  test(
    'disposing twice retires actual probe and rejects further operations',
    () async {
      await state.load();
      edit();
      response = Completer<http.Response>();
      final pending = state.testConnection();
      await Future<void>.delayed(Duration.zero);
      state.dispose();
      state.dispose();
      response!.complete(
        http.Response(
          '{"choices":[{"message":{"content":"OK"}}]}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect(await pending, false);
      expect(await state.save(), false);
      expect(await state.load(), false);
      expect(writes, 0);
      expect(state.retired, true);
    },
  );
}
