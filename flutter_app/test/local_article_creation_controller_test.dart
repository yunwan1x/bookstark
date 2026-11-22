import 'dart:async';
import 'support/article_creation_storage.dart';
import 'dart:ffi';
import 'dart:io';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/local_article_creation_controller.dart';
import 'package:bookstark_flutter/core/local_article_creation_record.dart';
import 'package:bookstark_flutter/core/local_complex_notes_repository.dart';
import 'package:bookstark_flutter/core/local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });
  late Directory directory;
  late LocalStore store;
  late LocalComplexNotesRepository actual;
  late LostReplySQL sql;
  late OwnedBytes bytes;
  late LocalArticleCreationVault vault;
  final controllers = <LocalArticleCreationController>[];
  var current = true;
  ComplexNoteEdit input({String title = 'New article'}) => ComplexNoteEdit(
    title: title,
    document: ComplexEditorDocument.parse(
      ComplexEditorKind.markdown,
      '\ufeff\ufeff# 原稿\r\n- 保留字节\r\n',
    ),
    labels: const ['z', 'a,b'],
  );
  LocalArticleCreationController controller({
    LocalArticleCreationRecord? record,
  }) {
    final value = LocalArticleCreationController(
      repository: sql,
      vault: vault,
      record: record,
      isCurrentScope: () => current,
    );
    controllers.add(value);
    return value;
  }

  void close(LocalArticleCreationController value) {
    controllers.remove(value);
    value.dispose();
  }

  Future<int> noteCount() async =>
      (await (await store.database).query('notes')).length;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'article-create-controller-',
    );
    store = LocalStore(
      path: '${directory.path}/notes.db',
      factory: databaseFactoryFfiNoIsolate,
    );
    actual = LocalComplexNotesRepository(
      store,
      kind: ComplexEditorKind.markdown,
      collection: 'article',
    );
    sql = LostReplySQL(actual);
    bytes = OwnedBytes();
    vault = LocalArticleCreationVault(
      scope: actual.scope,
      store: bytes,
      maintenance: store.maintenance,
    );
    current = true;
  });
  tearDown(() async {
    for (final value in controllers) {
      value.dispose();
    }
    controllers.clear();
    actual.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test('invalid metadata never persists pending or calls SQL', () async {
    final value = controller();
    await value.save();
    expect(value.phase, LocalArticleCreationPhase.editing);
    expect(value.failure, isA<FormatException>());
    expect(sql.creates, 0);
    expect(bytes.values, isEmpty);
    expect(await noteCount(), 0);
  });
  test(
    'durable pending is observed before actual INSERT and one confirmed commit finishes',
    () async {
      var pendingObserved = false;
      bytes.beforeWrite = (record) async {
        if (record.pending && record.createdId == null) {
          expect(await noteCount(), 0);
          pendingObserved = true;
        }
      };
      final value = controller()..edit(input());
      await value.save();
      expect(pendingObserved, isTrue);
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(value.created!.document.source, input().document.source);
      expect(sql.creates, 1);
      expect(await noteCount(), 1);
      expect(bytes.values, isEmpty);
    },
  );
  test(
    'pending write refusal prevents SQL and explicit absence review permits retry',
    () async {
      bytes.failWrite = true;
      final value = controller()..edit(input());
      await value.save();
      expect(value.phase, LocalArticleCreationPhase.unknown);
      expect(sql.creates, 0);
      expect(await noteCount(), 0);
      bytes.failWrite = false;
      await value.inspect();
      expect(value.confirmedAbsent, isTrue);
      expect(() => value.retryCreate(), throwsStateError);
      value.setReviewed(true);
      await value.retryCreate();
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(sql.creates, 1);
      expect(await noteCount(), 1);
    },
  );
  test(
    'lost durable pending acknowledgment survives restart without an automatic INSERT',
    () async {
      bytes.loseWriteReply = true;
      final first = controller()..edit(input());
      await first.save();
      expect(sql.creates, 0);
      final saved = await vault.read();
      expect(saved!.pending, isTrue);
      close(first);
      bytes.loseWriteReply = false;
      final reopened = controller(record: saved);
      expect(reopened.phase, LocalArticleCreationPhase.unknown);
      expect(sql.creates, 0);
      await reopened.inspect();
      reopened.setReviewed(true);
      await reopened.retryCreate();
      expect(sql.creates, 1);
      expect(await noteCount(), 1);
    },
  );
  test(
    'actual committed SQL lost reply requires fresh read explicit review and adoption',
    () async {
      sql.dropAfterCommit = true;
      final first = controller()..edit(input());
      await first.save();
      expect(first.phase, LocalArticleCreationPhase.unknown);
      expect(await noteCount(), 1);
      expect(sql.creates, 1);
      expect(() => first.save(), throwsStateError);
      final pending = await vault.read();
      close(first);
      sql.dropAfterCommit = false;
      final reopened = controller(record: pending);
      expect(sql.creates, 1);
      await reopened.inspect();
      expect(reopened.observed, isNotNull);
      expect(reopened.reviewed, isFalse);
      expect(() => reopened.adopt(), throwsStateError);
      reopened.setReviewed(true);
      await reopened.adopt();
      expect(reopened.phase, LocalArticleCreationPhase.finished);
      expect(sql.lookups, 2);
      expect(sql.creates, 1);
      expect(await noteCount(), 1);
      expect(bytes.values, isEmpty);
    },
  );
  test(
    'changed article after review resets approval without overwriting it',
    () async {
      sql.dropAfterCommit = true;
      final value = controller()..edit(input());
      await value.save();
      sql.dropAfterCommit = false;
      await value.inspect();
      value.setReviewed(true);
      await (await store.database).update(
        'notes',
        {'content': 'changed later'},
        where: 'id = ?',
        whereArgs: [value.observed!.id],
      );
      await value.adopt();
      expect(value.phase, LocalArticleCreationPhase.review);
      expect(value.reviewed, isFalse);
      expect(value.observed!.document.source, 'changed later');
      expect(sql.creates, 1);
      expect(bytes.values, hasLength(1));
      value.setReviewed(true);
      await value.adopt();
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(
        (await actual.read(value.created!.id)).document.source,
        'changed later',
      );
    },
  );
  test(
    'absent review sees a concurrent receipt and reviews instead of creating twice',
    () async {
      bytes.failWrite = true;
      final value = controller()..edit(input());
      await value.save();
      bytes.failWrite = false;
      await value.inspect();
      value.setReviewed(true);
      await actual.createOnce(input(), creationKey: value.record.key);
      await value.retryCreate();
      expect(value.phase, LocalArticleCreationPhase.review);
      expect(value.reviewed, isFalse);
      expect(value.observed, isNotNull);
      expect(sql.creates, 0);
      expect(await noteCount(), 1);
    },
  );
  test(
    'known cleanup failure retries storage only including a cold controller',
    () async {
      bytes.failRemove = true;
      final value = controller()..edit(input());
      await value.save();
      expect(value.phase, LocalArticleCreationPhase.cleanup);
      final known = await vault.read();
      expect(known!.createdId, value.created!.id);
      expect(() => value.save(), throwsStateError);
      close(value);
      final reopened = controller(record: known);
      expect(reopened.phase, LocalArticleCreationPhase.cleanup);
      bytes.failRemove = false;
      await reopened.retryCleanup();
      expect(reopened.phase, LocalArticleCreationPhase.finished);
      expect(sql.creates, 1);
      expect(bytes.values, isEmpty);
    },
  );
  test(
    'failure persisting known ID leaves sealed intent that can recover through SQL',
    () async {
      bytes.failKnownId = true;
      final value = controller()..edit(input());
      await value.save();
      expect(value.phase, LocalArticleCreationPhase.cleanup);
      final pending = await vault.read();
      expect(pending!.createdId, isNull);
      close(value);
      bytes.failKnownId = false;
      final reopened = controller(record: pending);
      expect(reopened.phase, LocalArticleCreationPhase.unknown);
      await reopened.inspect();
      reopened.setReviewed(true);
      await reopened.adopt();
      expect(reopened.phase, LocalArticleCreationPhase.finished);
      expect(sql.creates, 1);
      expect(await noteCount(), 1);
    },
  );
  test(
    'deleted created target resolves by cleanup without resurrection',
    () async {
      sql.dropAfterCommit = true;
      final value = controller()..edit(input());
      await value.save();
      final receipt = await actual.findCreation(value.record.key);
      await (await store.database).delete(
        'notes',
        where: 'id = ?',
        whereArgs: [receipt!.noteId],
      );
      sql.dropAfterCommit = false;
      await value.inspect();
      expect(value.unavailable, isTrue);
      expect(() => value.adopt(), throwsStateError);
      expect(() => value.retryCreate(), throwsStateError);
      await value.finishUnavailable();
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(await noteCount(), 0);
      expect(sql.creates, 1);
      expect(
        await (await store.database).query('html_creation_receipts'),
        hasLength(1),
      );
      expect(bytes.values, isEmpty);
    },
  );
  test(
    'title conflict proves absent receipt before reopening editing',
    () async {
      await store.createNote('taken', 'existing', collection: 'article');
      final value = controller()..edit(input(title: 'taken'));
      await value.save();
      expect(value.phase, LocalArticleCreationPhase.editing);
      expect(value.failure, isA<DatabaseException>());
      expect((await vault.read())!.pending, isFalse);
      expect(await noteCount(), 1);
      value.edit(input(title: 'available'));
      await value.save();
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(await noteCount(), 2);
      expect(sql.creates, 2);
      expect(
        await (await store.database).query('html_creation_receipts'),
        hasLength(1),
      );
    },
  );
  test(
    'background flush waits for active creation and cannot recreate cleared recovery',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      bytes.beforeWrite = (record) async {
        if (record.createdId == null) {
          started.complete();
          await release.future;
        }
      };
      final value = controller()..edit(input());
      final creating = value.save();
      await started.future;
      expect(() => value.save(), throwsStateError);
      final flushing = value.flush();
      release.complete();
      await creating;
      expect(await flushing, isTrue);
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(bytes.values, isEmpty);
      expect(sql.creates, 1);
    },
  );
  test('retired scope while pending storage waits never starts SQL', () async {
    final started = Completer<void>(), release = Completer<void>();
    bytes.beforeWrite = (record) async {
      started.complete();
      await release.future;
    };
    final value = controller()..edit(input());
    final saving = value.save();
    await started.future;
    current = false;
    release.complete();
    await saving;
    expect(sql.creates, 0);
    expect(await noteCount(), 0);
    expect((await vault.read())!.pending, isTrue);
    expect(await value.flush(), isFalse);
  });
  test(
    'scope change after actual commit leaves pending for explicit future recovery',
    () async {
      sql.afterCommit = () async {
        current = false;
      };
      final value = controller()..edit(input());
      await value.save();
      expect(await noteCount(), 1);
      expect((await vault.read())!.createdId, isNull);
      current = true;
      final reopened = controller(record: await vault.read());
      await reopened.inspect();
      reopened.setReviewed(true);
      await reopened.adopt();
      expect(reopened.phase, LocalArticleCreationPhase.finished);
      expect(sql.creates, 1);
    },
  );
  test(
    'fresh absent review permits explicit return to editable draft only',
    () async {
      bytes.failWrite = true;
      final value = controller()..edit(input());
      await value.save();
      bytes.failWrite = false;
      await value.inspect();
      expect(() => value.resumeEditing(), throwsStateError);
      value.setReviewed(true);
      await value.resumeEditing();
      expect(value.canEdit, isTrue);
      value.edit(input(title: 'corrected'));
      await value.save();
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(sql.creates, 1);
    },
  );
  test(
    'failed deletion of unsubmitted draft remains editing and can retry',
    () async {
      final value = controller()..edit(input());
      expect(await value.flush(), isTrue);
      bytes.failRemove = true;
      await value.discardDraft();
      expect(value.phase, LocalArticleCreationPhase.editing);
      expect(value.recoveryFailure, isNotNull);
      expect(sql.creates, 0);
      bytes.failRemove = false;
      await value.discardDraft();
      expect(value.phase, LocalArticleCreationPhase.finished);
      expect(value.discarded, isTrue);
      expect(bytes.values, isEmpty);
    },
  );
  test(
    'synchronous busy listener flush waits for the active creation receipt',
    () async {
      final started = Completer<void>(), release = Completer<void>();
      bytes.beforeWrite = (record) async {
        if (record.pending && record.createdId == null) {
          started.complete();
          await release.future;
        }
      };
      final value = controller()..edit(input());
      Future<bool>? flushing;
      var flushCompleted = false;
      value.addListener(() {
        if (value.busy && flushing == null) {
          flushing = value.flush().then((ok) {
            flushCompleted = true;
            return ok;
          });
        }
      });
      final creating = value.save();
      await started.future;
      await Future<void>.delayed(Duration.zero);
      final premature = flushCompleted;
      release.complete();
      await creating;
      expect(await flushing, isTrue);
      expect(
        premature,
        isFalse,
        reason:
            'Lifecycle flush cannot acknowledge before the pending creation finishes',
      );
      expect(bytes.values, isEmpty);
      expect(sql.creates, 1);
    },
  );
}
