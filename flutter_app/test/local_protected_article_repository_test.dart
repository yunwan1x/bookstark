import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_protected_article_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';

// Real temporary SQLite; Android crypto channel ACKs alone are mocked.
// Real AES/GCM compatibility is separately covered by LegacyContentCryptoHostTest.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  if (Platform.isLinux) {
    open.overrideFor(
      OperatingSystem.linux,
      () => DynamicLibrary.open('libsqlite3.so.0'),
    );
  }
  const channel = MethodChannel('bookstark/local_content_crypto');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late LocalStore store;
  late String cipher, password, plain;
  late int id;
  var encryptCalls = 0;
  final opened = <LocalProtectedArticleRepository>[];
  final channelBodies = <String, String>{};
  late String changedCipher;
  setUp(() async {
    final vectors =
        jsonDecode(
              await File(
                'tool/legacy_crypto_test/go-vectors.json',
              ).readAsString(),
            )
            as List;
    final vector = vectors.first as Map;
    cipher = vector['body'] as String;
    password = vector['password'] as String;
    plain = vector['plain'] as String;
    changedCipher =
        'ENC:v1:' +
        base64Encode(List.filled(16, 1)) +
        ':' +
        base64Encode(List.filled(12, 2)) +
        ':' +
        base64Encode(List.filled(32, 3));
    channelBodies.clear();
    channelBodies[cipher] = plain;
    encryptCalls = 0;
    final base = Directory(
      Platform.environment['BOOKSTARK_APK_TEST_ROOT'] ??
          Directory.systemTemp.path + '/bookstark-unit',
    );
    await base.create(recursive: true);
    root = await base.createTemp('ordinary-protected-article-');
    store = LocalStore(
      path: root.path + '/content.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    id = await (await store.database).insert('notes', {
      'title': 'Existing protected article',
      'content': cipher,
      'updated_at': 10,
      'deleted': 0,
      'labels': '["existing"]',
      'collection': 'article',
      'editor_type': 'markdown',
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'drain') return {'format': 1, 'drained': true};
      if (call.method == 'cancel')
        return {
          'format': 1,
          'id': (call.arguments as Map)['id'],
          'cancelled': true,
        };
      final args = call.arguments as Map;
      expect(args.containsKey('hash'), isFalse);
      if (args['password'] != password)
        throw PlatformException(code: 'WRONG_PASSWORD');
      final wire = args['body'] as Uint8List;
      late String result;
      if (call.method == 'unlockEnvelope') {
        result = channelBodies[utf8.decode(wire)]!;
      } else {
        expect(call.method, 'encryptEnvelope');
        encryptCalls++;
        final bom =
            wire.length >= 3 &&
            wire[0] == 239 &&
            wire[1] == 187 &&
            wire[2] == 191;
        final submitted = utf8.decode(wire);
        result = changedCipher;
        channelBodies[result] = (bom ? '\ufeff' : '') + submitted;
      }
      return {
        'format': 1,
        'id': args['id'],
        'body': Uint8List.fromList(utf8.encode(result)),
      };
    });
  });
  tearDown(() async {
    for (final repo in opened) {
      repo.dispose();
    }
    opened.clear();
    messenger.setMockMethodCallHandler(channel, null);
    await store.close();
    await root.delete(recursive: true);
  });
  Future<LocalProtectedArticleRepository> unlock([String? value]) async {
    final repo = await LocalProtectedArticleRepository.open(
      store: store,
      id: id,
      password: value ?? password,
      isCurrentScope: () => true,
      crypto: NativeLocalContentCrypto(),
    );
    opened.add(repo);
    return repo;
  }

  Future<Map<String, Object?>> row() async =>
      (await (await store.database).query(
        'notes',
        where: 'id=?',
        whereArgs: [id],
      )).single;

  test('wrong password leaves original ID and ciphertext unchanged', () async {
    await expectLater(
      unlock('incorrect'),
      throwsA(isA<LocalContentCryptoFailure>()),
    );
    expect((await row())['content'], cipher);
    expect((await (await store.database).query('notes')).length, 1);
    expect(encryptCalls, 0);
  });
  test(
    'correct Markdown and HTML edit save and cold reopen preserve ID and encrypted SQL',
    () async {
      var expectedEncryptCalls = 0;
      for (final type in ['markdown', 'html']) {
        await (await store.database).update(
          'notes',
          {'content': cipher, 'editor_type': type, 'updated_at': 10},
          where: 'id=?',
          whereArgs: [id],
        );
        final repo = await unlock();
        final before = await repo.read(id);
        expect(before.document.source, plain);
        final changed = type == 'html'
            ? '\ufeff<p>edited exact</p>\r\n'
            : '\ufeff# edited exact\r\nsecond line\r\n';
        final edit = ComplexNoteEdit(
          title: before.title,
          labels: before.labels,
          document: ComplexEditorDocument.parse(
            ComplexEditorKind.parse(type),
            changed,
          ),
        );
        final saved = await repo.save(before, edit);
        expect(saved.id, id);
        expect(saved.document.source, changed);
        expect((await row())['content'], changedCipher);
        expect((await row())['content'], startsWith('ENC:v1:'));
        repo.dispose();
        await store.close();
        store = LocalStore(
          path: root.path + '/content.db',
          factory: databaseFactoryFfiNoIsolate,
        );
        final reopened = await unlock();
        expect((await reopened.read(id)).document.source, changed);
        expect((await (await store.database).query('notes')).length, 1);
        final disk = String.fromCharCodes(await File(store.path).readAsBytes());
        expect(disk.contains('edited exact'), isFalse);
        expect(encryptCalls, ++expectedEncryptCalls);
        reopened.dispose();
      }
    },
  );
  test(
    'no-op preserves exact ciphertext and timestamp without encryption',
    () async {
      final repo = await unlock();
      final baseline = await repo.read(id);
      await repo.save(
        baseline,
        ComplexNoteEdit(
          title: baseline.title,
          document: baseline.document,
          labels: baseline.labels,
        ),
      );
      expect((await row())['content'], cipher);
      expect((await row())['updated_at'], 10);
      expect(encryptCalls, 0);
    },
  );
  test(
    'full original tuple CAS conflict never overwrites current cipher or metadata',
    () async {
      final repo = await unlock();
      final baseline = await repo.read(id);
      await (await store.database).update(
        'notes',
        {'title': 'External current title'},
        where: 'id=?',
        whereArgs: [id],
      );
      await expectLater(
        repo.save(
          baseline,
          ComplexNoteEdit(
            title: baseline.title,
            document: ComplexEditorDocument.parse(
              ComplexEditorKind.markdown,
              'changed',
            ),
            labels: baseline.labels,
          ),
        ),
        throwsA(isA<ComplexNoteConflict>()),
      );
      expect((await row())['content'], cipher);
      expect((await row())['title'], 'External current title');
    },
  );
}
