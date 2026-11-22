import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:bookstark_flutter/core/local_generation_state.dart';
import 'package:bookstark_flutter/main.dart';

class _NeverOpen extends Fake implements sql.DatabaseFactory {
  _NeverOpen(this.root);
  final String root;
  int opened = 0;
  @override
  Future<String> getDatabasesPath() async => root;
  @override
  Future<sql.Database> openDatabase(
    String path, {
    sql.OpenDatabaseOptions? options,
  }) async {
    opened++;
    throw StateError('SQL must not open before recovery review');
  }
}

void main() {
  for (final available in [false, true]) {
    testWidgets(
      available
          ? 'cold prepared root blocks SQL and never replays restore'
          : 'unavailable native recovery state has no legacy SQL fallback',
      (tester) async {
        final directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('bookstark-cold-review-'),
        ))!;
        final factory = _NeverOpen(directory.path);
        FlutterSecureStorage.setMockInitialValues({});
        final mutations = <String>[];
        var reads = 0;
        const paths = MethodChannel('plugins.flutter.io/path_provider');
        const control = MethodChannel('bookstark/local_data_control');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
        messenger.setMockMethodCallHandler(control, (call) async {
          if (call.method != 'readState') {
            mutations.add(call.method);
            throw StateError('No automatic restore mutation allowed');
          }
          reads++;
          if (!available) throw PlatformException(code: 'unavailable');
          final intent = LocalRestoreIntent(
            operationId: 'a' * 32,
            sourcePointerRaw: null,
            retainedId: 'b' * 32,
            retainedManifestSHA256: 'c' * 64,
            targetPointerRaw: LocalGenerationPointer(
              generation: 'd' * 32,
              epoch: 1,
              activationId: 'a' * 32,
              sourceSHA256: 'e' * 64,
            ).encode(),
          );
          final retention = LocalRetention(
            id: intent.retainedId,
            sourcePointerSHA256: intent.sourcePointerSHA256,
            sourceGeneration: 'legacy',
            manifestSHA256: intent.retainedManifestSHA256,
          ).encode();
          return {
            'format': 1,
            'pointerRaw': null,
            'intentRaw': intent.encode(),
            'currentRetentionRaw': retention,
            'sourceRetentionRaw': retention,
            'metadataOnly': true,
          };
        });
        addTearDown(() async {
          messenger.setMockMethodCallHandler(paths, null);
          messenger.setMockMethodCallHandler(control, null);
          await directory.delete(recursive: true);
        });
        await tester.pumpWidget(BookstarkApp(localDatabaseFactory: factory));
        await tester.pumpAndSettle();
        await tester.tap(find.text('本地空间'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('进入本地空间'));
        await tester.pump();
        final expected = available ? '尚未切换数据' : '恢复记录不一致';
        for (
          var attempt = 0;
          attempt < 60 && find.text(expected).evaluate().isEmpty;
          attempt++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(reads, greaterThanOrEqualTo(2));
        if (available) {
          expect(find.text('尚未切换数据'), findsOneWidget);
          expect(find.text('结束本次恢复'), findsOneWidget);
        } else {
          expect(find.text('恢复记录不一致'), findsOneWidget);
        }
        expect(factory.opened, 0);
        expect(mutations, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      },
    );
  }
}
