import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/settings/settings_connection_controller.dart';

void main() {
  testWidgets(
    'connection deadline aborts the read without replay or late verification',
    (tester) async {
      final response = Completer<void>();
      var aborted = false, calls = 0;
      final state = SettingsConnectionController(
        local: false,
        server: 'https://notes.example.com/',
        timeout: const Duration(seconds: 2),
        isCurrent: () => true,
        checkConnection: (abort) {
          calls++;
          abort.then((_) => aborted = true);
          return response.future;
        },
      );
      final pending = state.check();
      await tester.pump(const Duration(seconds: 3));
      await pending;
      expect(aborted, true);
      expect(state.state, ConnectionCheckState.unavailable);
      expect(calls, 1);
      response.complete();
      await tester.pump();
      expect(state.state, ConnectionCheckState.unavailable);
      expect(calls, 1);
      state.dispose();
    },
  );

  test('local mode performs no server check', () async {
    var calls = 0;
    final state = SettingsConnectionController(
      local: true,
      server: null,
      isCurrent: () => true,
      checkConnection: (_) async {
        calls++;
      },
    );
    await state.check();
    expect(state.state, ConnectionCheckState.local);
    expect(calls, 0);
    state.dispose();
  });

  test('server status is unverified until an explicit real check', () async {
    var calls = 0;
    final state = SettingsConnectionController(
      local: false,
      server: 'https://notes.example.com/base/',
      isCurrent: () => true,
      checkConnection: (_) async {
        calls++;
      },
    );
    expect(calls, 0);
    expect(state.state, ConnectionCheckState.unverified);
    await state.check();
    expect(calls, 1);
    expect(state.state, ConnectionCheckState.verified);
    expect(state.checkedAt, isNotNull);
    state.dispose();
  });

  test('visible server address strips credentials, query and fragment', () {
    final state = SettingsConnectionController(
      local: false,
      server:
          'https://account:secret@notes.example.com:9443/base/?ak=secret#secret',
      isCurrent: () => true,
      checkConnection: (_) async {},
    );
    expect(state.displayAddress, 'https://notes.example.com:9443/base/');
    state.dispose();
  });

  for (final status in [401, 403, 500]) {
    test(
      'HTTP $status becomes a bounded state without exposing response text',
      () async {
        var calls = 0;
        final state = SettingsConnectionController(
          local: false,
          server: 'https://notes.example.com/',
          isCurrent: () => true,
          checkConnection: (_) async {
            calls++;
            throw ApiFailure(status, 'private response');
          },
        );
        await state.check();
        expect(
          state.state,
          status == 401
              ? ConnectionCheckState.loginExpired
              : status == 403
              ? ConnectionCheckState.accessDenied
              : ConnectionCheckState.unavailable,
        );
        expect(state.checkedAt, isNull);
        expect(calls, 1);
        await Future<void>.delayed(Duration.zero);
        expect(calls, 1);
        state.dispose();
      },
    );
  }

  test('old response cannot verify a different workspace', () async {
    final response = Completer<void>();
    var current = true;
    final state = SettingsConnectionController(
      local: false,
      server: 'https://notes.example.com/',
      isCurrent: () => current,
      checkConnection: (_) => response.future,
    );
    final pending = state.check();
    current = false;
    response.complete();
    await pending;
    expect(state.state, isNot(ConnectionCheckState.verified));
    expect(state.checkedAt, isNull);
    state.dispose();
  });

  test(
    'switch cancels checking and waits for the draft/retirement barrier',
    () async {
      final response = Completer<void>(), prepared = Completer<void>();
      final events = <String>[];
      final state = SettingsConnectionController(
        local: false,
        server: 'https://notes.example.com/',
        isCurrent: () => true,
        checkConnection: (abort) {
          abort.then((_) => events.add('cancel'));
          return response.future;
        },
      );
      final pending = state.check();
      final switched = state.switchSpace(
        prepare: () async {
          events.add('prepare');
          await prepared.future;
          events.add('retired');
        },
        enter: () async {
          events.add('enter');
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, contains('cancel'));
      expect(events, isNot(contains('enter')));
      response.complete();
      await pending;
      expect(state.state, ConnectionCheckState.unverified);
      prepared.complete();
      await switched;
      expect(events.indexOf('retired'), lessThan(events.indexOf('enter')));
      state.dispose();
    },
  );

  test(
    'failed draft barrier prevents entering and allows another attempt',
    () async {
      var entered = 0;
      final state = SettingsConnectionController(
        local: false,
        server: 'https://notes.example.com/',
        isCurrent: () => true,
        checkConnection: (_) async {},
      );
      await expectLater(
        state.switchSpace(
          prepare: () async {
            throw StateError('Storage failed');
          },
          enter: () async {
            entered++;
          },
        ),
        throwsStateError,
      );
      expect(entered, 0);
      expect(state.switching, false);
      await state.switchSpace(
        prepare: () async {},
        enter: () async {
          entered++;
        },
      );
      expect(entered, 1);
      state.dispose();
    },
  );

  test(
    'dispose aborts pending read and suppresses late notifications',
    () async {
      final response = Completer<void>(), aborted = Completer<void>();
      var notifications = 0;
      final state = SettingsConnectionController(
        local: false,
        server: 'https://notes.example.com/',
        isCurrent: () => true,
        checkConnection: (abort) {
          abort.then((_) => aborted.complete());
          return response.future;
        },
      );
      state.addListener(() {
        notifications++;
      });
      final pending = state.check();
      expect(notifications, 1);
      state.dispose();
      await aborted.future;
      response.complete();
      await pending;
      expect(notifications, 1);
    },
  );
}
