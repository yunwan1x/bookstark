import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/admin/admin_settings_repository.dart';
import 'package:bookstark_flutter/features/admin/admin_signaling_controller.dart';
import 'package:bookstark_flutter/features/admin/admin_signaling_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const owner = AdminPrincipal(memberId: 1, account: 'fixture', role: 0);
AdminSettingsSnapshot snapshot() => AdminSettingsSnapshot.parse([
  for (final entry in {
    'webrtc_signaling_enabled': '1',
    'webrtc_signaling_default_url': 'wss://example.invalid/ws',
    'webrtc_signaling_max_peers': '8',
    'webrtc_signaling_max_message_kb': '64',
    'webrtc_signaling_allow_local_file': '0',
    'webrtc_signaling_allowed_origins': '',
    'webrtc_signaling_stun_urls': '',
    'webrtc_signaling_turn_url': '',
    'webrtc_signaling_turn_username': 'fixture',
    'webrtc_signaling_turn_credential': 'fixture-key',
  }.entries)
    {
      'key': entry.key,
      'value': entry.value,
      'description': '',
      'update_time': '',
    },
]);

class SignalingRepository extends AdminSettingsRepository {
  SignalingRepository() : super(BookstarkClient('https://example.invalid'));
  Map<String, String>? patch;
  int puts = 0;
  @override
  Future<AdminSettingsSnapshot> read(
    AdminPrincipal owner, {
    Future<void>? abortTrigger,
  }) async => snapshot();
  @override
  Future<void> saveSignaling(
    AdminPrincipal owner,
    AdminSettingsSnapshot base,
    AdminSignalingChanges changes, {
    Future<void>? abortTrigger,
  }) async {
    puts++;
    patch = changes.patch(base);
  }
}

void main() {
  test(
    'signaling validates Go bounds schemes prefixes and credential bytes',
    () {
      final empty = AdminSettingsSnapshot.parse(<Object?>[]);
      for (final entry in {
        AdminSignalingField.enabled: '2',
        AdminSignalingField.localFile: '',
        AdminSignalingField.peers: '65',
        AdminSignalingField.messageSize: '7',
        AdminSignalingField.url: 'https://example.invalid',
        AdminSignalingField.origins: 'file:///fixture',
        AdminSignalingField.stun: 'turn:example.invalid',
        AdminSignalingField.turn: 'https://example.invalid',
        AdminSignalingField.turnUsername: List.filled(86, '中').join(),
        AdminSignalingField.turnCredential: List.filled(257, 'a').join(),
      }.entries) {
        expect(
          () => AdminSignalingChanges({entry.key: entry.value}).patch(empty),
          throwsFormatException,
        );
      }
      expect(
        AdminSignalingChanges({
          AdminSignalingField.peers: '2',
          AdminSignalingField.messageSize: '512',
          AdminSignalingField.url: ' wss://example.invalid/ws ',
          AdminSignalingField.turn: ' turns:example.invalid ',
        }).patch(empty),
        hasLength(4),
      );
    },
  );
  test(
    'signaling preserves raw list separators and only submits changed field',
    () async {
      final repo = SignalingRepository();
      final c = AdminSignalingController(repo, owner);
      await c.load();
      c.edit(
        'webrtc_signaling_stun_urls',
        ' stun:first.invalid,\r\nstun:second.invalid\n',
      );
      await c.save();
      expect(repo.patch, {
        'webrtc_signaling_stun_urls':
            ' stun:first.invalid,\r\nstun:second.invalid\n',
      });
      c.dispose();
    },
  );
  test(
    'TURN clear requires exact revision confirmation and submits empty value',
    () async {
      final repo = SignalingRepository();
      final c = AdminSignalingController(repo, owner);
      await c.load();
      c.edit('webrtc_signaling_turn_credential', '');
      final revision = c.revision;
      c.edit('webrtc_signaling_max_peers', '10');
      await c.save(confirmedClearRevision: revision);
      expect(repo.puts, 0);
      await c.save(confirmedClearRevision: c.revision);
      expect(repo.patch!['webrtc_signaling_turn_credential'], '');
      c.dispose();
    },
  );
  testWidgets('signaling 320dp200% expands TURN with credential masked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = AdminSignalingController(SignalingRepository(), owner);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AdminSignalingPage(controller: c, onReturn: () {}),
      ),
    );
    await tester.pumpAndSettle();
    final turn = find.text('TURN 服务');
    await tester.scrollUntilVisible(
      turn.hitTestable(),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(turn.hitTestable());
    await tester.pumpAndSettle();
    final credential = find.byKey(
      const ValueKey('webrtc_signaling_turn_credential'),
    );
    await tester.scrollUntilVisible(
      credential,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<TextField>(credential).obscureText, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
