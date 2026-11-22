// Synthetic-only maximum-size native channel and named-generation acceptance.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/bounded_note_text_reader.dart';
import 'package:bookstark_flutter/core/local_content_crypto_limits.dart';
import 'package:bookstark_flutter/core/local_content_protection_format.dart';
import 'package:bookstark_flutter/core/local_data_paths.dart';
import 'package:bookstark_flutter/core/local_generation_content_repository.dart';
import 'package:bookstark_flutter/core/local_legacy_candidate_schema.dart';
import 'package:bookstark_flutter/core/native_local_content_crypto.dart';
import 'generation_content_fixture_seed.dart';

class _ObservedChannel extends MethodChannel {
  _ObservedChannel() : super('bookstark/local_content_crypto');
  int calls = 0;
  Completer<void>? started;
  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) {
    final result = super.invokeMethod<T>(method, arguments);
    if (method != 'cancel') {
      calls++;
      final s = started;
      if (s != null && !s.isCompleted) s.complete();
    }
    return result;
  }
}

void _require(bool value) {
  if (!value) throw StateError('Synthetic budget mismatch');
}

String _body(bool edited) {
  const prefix =
          '{"width":960,"height":540,"slides":[{"id":"one","elements":[]}],"padding":"中🙂\\r\\n',
      suffix = '"}';
  final n = localCryptoMaxPlaintextBytes - utf8.encode(prefix + suffix).length;
  return prefix + 'x' * (n - 1) + (edited ? 'y' : 'x') + suffix;
}

String _sha(String value) => sha256.convert(utf8.encode(value)).toString();
Future<void> _emit(
  Directory root,
  String name,
  Map<String, Object?> value,
) async {
  final file = File('${root.path}/$name.tmp');
  await file.writeAsString(jsonEncode(value), flush: true);
  await file.rename('${root.path}/$name');
}

Future<void> _failure(
  Future<Object?> Function() action,
  LocalContentCryptoReason reason,
) async {
  try {
    await action();
    throw StateError('Expected rejection');
  } on LocalContentCryptoFailure catch (error) {
    _require(error.reason == reason);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Directory? root;
  Database? db;
  LocalGenerationContentRepository? repo;
  var phase = 'startup', operation = 'marker';
  try {
    final support = await getApplicationSupportDirectory();
    root = Directory('${support.path}/generation-budget-probe');
    _require(
      await FileSystemEntity.type(root.path, followLinks: false) ==
          FileSystemEntityType.directory,
    );
    _require(
      (await root.resolveSymbolicLinks()).startsWith(
        '${await support.resolveSymbolicLinks()}/',
      ),
    );
    final file = File('${root.path}/owned.json');
    _require(await file.length() < 32768);
    final marker = jsonDecode(await file.readAsString()) as Map,
        nonce = marker['nonce'];
    _require(
      marker.length == 4 &&
          marker['format'] == 1 &&
          marker['synthetic_only'] == true &&
          nonce is String &&
          RegExp(r'^[a-f0-9]{32}$').hasMatch(nonce) &&
          {'build', 'verify'}.contains(marker['phase']),
    );
    phase = marker['phase'] as String;
    final generation = LocalDataPaths.generation(
      id: nonce as String,
      privateSupport: root,
    );
    final vector = generationContentProbeCases['protected-native']!,
        password = vector['password']!,
        hash = vector['hash']!;
    final observed = _ObservedChannel(),
        crypto = NativeLocalContentCrypto(
          channel: observed,
          deadline: const Duration(minutes: 4),
        );
    final plain = _body(false), edited = _body(true);
    _require(
      utf8.encode(plain).length == localCryptoMaxPlaintextBytes &&
          plain != edited,
    );
    if (phase == 'build') {
      operation = 'reject-before-dispatch';
      final before = observed.calls;
      await _failure(
        () => crypto.encryptExisting(
          password: password,
          passwordHash: hash,
          plaintext: '${plain}x',
        ),
        LocalContentCryptoReason.unsupported,
      );
      final cancelled = AttachmentCancellation()..cancel();
      await _failure(
        () => crypto.encryptExisting(
          password: password,
          passwordHash: hash,
          plaintext: plain,
          cancellation: cancelled,
        ),
        LocalContentCryptoReason.cancelled,
      );
      _require(observed.calls == before);
      operation = 'native-encrypt20MiB';
      final sealed = await crypto.encryptExisting(
        password: password,
        passwordHash: hash,
        plaintext: plain,
      );
      _require(
        localProtectedEnvelope(sealed) &&
            utf8.encode(sealed).length > 20 * 1024 * 1024,
      );
      operation = 'native-wrong-password';
      await _failure(
        () => crypto.unlock(
          password: 'wrong-synthetic',
          passwordHash: hash,
          body: sealed,
        ),
        LocalContentCryptoReason.wrongPassword,
      );
      operation = 'native-unlock20MiB';
      _require(
        _sha(
              await crypto.unlock(
                password: password,
                passwordHash: hash,
                body: sealed,
              ),
            ) ==
            _sha(plain),
      );
      operation = 'candidate-sql';
      await File(generation.databasePath).parent.create(recursive: true);
      db = await openDatabase(
        generation.databasePath,
        version: 15,
        singleInstance: false,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys=ON'),
        onCreate: (db, v) => createLegacyCandidateSchema15(db),
      );
      await db.rawInsert(
        'INSERT INTO notes(id,title,content,labels,updated_at,editor_type,password_hash) VALUES(1,?,CAST(? AS TEXT),?,0,?,?)',
        [
          'budget',
          Uint8List.fromList(utf8.encode(sealed)),
          '[]',
          'presentation',
          hash,
        ],
      );
      repo = LocalGenerationContentRepository(
        database: db,
        generation: generation,
        isCurrent: () => true,
        crypto: crypto,
      );
      operation = 'repository-unlock20MiB';
      final opened = await repo.open(1, password: password);
      _require(_sha(opened.source) == _sha(plain));
      operation = 'protected-save20MiB';
      final saved = await repo.save(
        opened,
        title: 'budget saved',
        source: edited,
        labels: const [],
      );
      _require(
        saved.metadata.revision == 2 && _sha(saved.source) == _sha(edited),
      );
      operation = 'stored-wire-chunks';
      final stored = await db.transaction(
        (tx) => BoundedNoteTextReader.readNoteContent(
          tx,
          id: 1,
          collection: 'note',
          editorType: 'presentation',
          maxRecordBytes: localCryptoMaxWireBytes,
        ),
        exclusive: false,
      );
      _require(localProtectedEnvelope(stored) && stored != sealed);
      await File(
        '${root.path}/saved-cipher.txt',
      ).writeAsBytes(utf8.encode(stored), flush: true);
      operation = 'pending-real-unlock-cancel';
      final cancellation = AttachmentCancellation();
      observed.started = Completer<void>();
      final pending = crypto.unlock(
        password: password,
        passwordHash: hash,
        body: stored,
        cancellation: cancellation,
      );
      final checked = _failure(
        () => pending,
        LocalContentCryptoReason.cancelled,
      );
      await observed.started!.future;
      cancellation.cancel();
      await checked;
      saved.close();
      repo.dispose();
      repo = null;
      await db.close();
      db = null;
      await _emit(root, 'build-proof.json', {
        'passed': true,
        'nonce': nonce,
        'phase': phase,
        'schema': 15,
        'plaintextBytes': localCryptoMaxPlaintextBytes,
        'storedWireBytes': utf8.encode(stored).length,
        'initialPlainSHA256': _sha(plain),
        'editedPlainSHA256': _sha(edited),
        'cipherSHA256': _sha(stored),
        'actualNative20MiBEncryptUnlockSave': true,
        'actualWrongPassword': true,
        'oversizeRejectedBeforeDispatch': true,
        'preCancelledBeforeDispatch': true,
        'pendingRealNativeUnlockCancelled': true,
        'revision': 2,
        'noProductionRoute': true,
        'all45Complete': false,
      });
    } else {
      operation = 'cold-read-only-open';
      db = await openDatabase(
        generation.databasePath,
        readOnly: true,
        singleInstance: false,
      );
      repo = LocalGenerationContentRepository(
        database: db,
        generation: generation,
        isCurrent: () => true,
        crypto: crypto,
      );
      final opened = await repo.open(1, password: password);
      _require(
        opened.metadata.revision == 2 && _sha(opened.source) == _sha(edited),
      );
      opened.close();
      repo.dispose();
      repo = null;
      await db.close();
      db = null;
      await _emit(root, 'verify-proof.json', {
        'passed': true,
        'nonce': nonce,
        'phase': phase,
        'schema': 15,
        'plaintextBytes': localCryptoMaxPlaintextBytes,
        'editedPlainSHA256': _sha(edited),
        'coldReadOnlyActualNativeUnlock': true,
        'revision': 2,
        'all45Complete': false,
      });
    }
  } catch (error) {
    if (root != null) {
      await _emit(root, 'failure-$phase.json', {
        'passed': false,
        'phase': phase,
        'operation': operation,
        'failureType': error.runtimeType.toString(),
      });
    }
  } finally {
    repo?.dispose();
    await db?.close();
  }
  runApp(const SizedBox.shrink());
}
