import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/speech/local_speech_provider_page.dart';

class _Client extends BookstarkClient {
  _Client() : super('https://voice.example.test');
  Completer<Map<String, Object?>>? loginGate;
  int logins = 0, uploads = 0, closes = 0;
  @override
  Future<Map<String, Object?>> login(String account, String password) async {
    logins++;
    return loginGate?.future ?? {'code': 0};
  }

  @override
  Future<Map<String, Object?>> profileSettingsJson({
    bool update = false,
    Map<String, Object?>? body,
    Future<void>? abortTrigger,
  }) => Future.value({'member_id': 42});
  @override
  Future<Map<String, Object?>> speechVoicesJson({
    required Future<void> abortTrigger,
  }) => Future.value({
    'voices': [
      {'id': 'zh-CN-YunxiNeural', 'name': 'Voice', 'locale': 'zh-CN'},
    ],
  });
  @override
  Stream<List<int>> postStream(
    String path,
    Map<String, Object?> body, {
    required String accept,
    Future<void>? abortTrigger,
    void Function()? beforeSubmit,
  }) {
    beforeSubmit?.call();
    uploads++;
    return const Stream.empty();
  }

  @override
  void close() {
    closes++;
    super.close();
  }
}

void main() {
  Future<void> inputs(WidgetTester tester) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'https://voice.example.test');
    await tester.enterText(fields.at(1), 'reader');
    await tester.enterText(fields.at(2), 'ephemeral fixture');
  }

  testWidgets(
    'provider login never sends local text and requires unchecked per-reading consent',
    (tester) async {
      final client = _Client();
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSpeechProviderPage(
            text: 'Private local text',
            title: 'Local fixture',
            isCurrentScope: () => true,
            english: true,
            clientFactory: (_) => client,
          ),
        ),
      );
      await inputs(tester);
      await tester.tap(find.text('Sign in and verify speech'));
      await tester.pumpAndSettle();
      expect(client.logins, 1);
      expect(client.uploads, 0);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      final begin = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm and start'),
      );
      expect(begin.onPressed, isNull);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Confirm and start'),
            )
            .onPressed,
        isNotNull,
      );
      expect(client.uploads, 0);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'missing full readable text is disabled and real capture remains separate',
    (tester) async {
      final capture = LocalSpeechSelection.captured(
        text: 'Actual chosen text',
        bindingId: 'book4/doc9/kind-html/fullfp/sourceSHA/lease1/gen2',
        selectionKind: 'text',
        isCurrentBinding: () => true,
        verifyFreshBinding: () async => true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSpeechProviderPage(
            text: '',
            selection: capture,
            title: 'HTML capture',
            isCurrentScope: () => true,
            english: true,
          ),
        ),
      );
      final full = find.widgetWithText(
        ListTile,
        'Complete text (sent in passages)',
      );
      final selected = find.widgetWithText(ListTile, 'Current selection');
      expect(tester.widget<ListTile>(full).enabled, isFalse);
      expect(tester.widget<ListTile>(selected).selected, isTrue);
      expect(find.textContaining('18 characters'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'retired local scope rejects late login and clears password without text upload',
    (tester) async {
      final client = _Client()..loginGate = Completer();
      var current = true;
      await tester.pumpWidget(
        MaterialApp(
          home: LocalSpeechProviderPage(
            text: 'Private local text',
            title: 'Local fixture',
            isCurrentScope: () => current,
            english: true,
            clientFactory: (_) => client,
          ),
        ),
      );
      await inputs(tester);
      await tester.tap(find.text('Sign in and verify speech'));
      await tester.pump();
      current = false;
      client.loginGate!.complete({'code': 0});
      await tester.pumpAndSettle();
      expect(client.uploads, 0);
      expect(client.closes, greaterThanOrEqualTo(1));
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
