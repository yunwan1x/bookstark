import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/book_draft_vault.dart';
import 'package:bookstark_flutter/core/books_repository.dart';
import 'package:bookstark_flutter/core/labels_repository.dart';
import 'package:bookstark_flutter/features/books/book_editor_page.dart';
import '../core/book_creation_attempt.dart';
import '../core/book_creation_attempt_store.dart';
import '../core/book_creation_controller.dart';
import '../core/book_creation_http_adapter.dart';
import 'book_creation_recovery_page.dart';

final _bookEntryOwners = <String>{};

/// Page owns its newly opened controller/adapter. No HTTP during factory open.
Future<Widget> createRemoteBookEntry({
  required BookstarkClient client,
  required BookCreationScope scope,
  required BooksRepository repository,
  required LabelsRepository labelsRepository,
  required BookDraftVault ordinaryDrafts,
  required Future<String?> Function(String) readValue,
  required Future<void> Function(String, String) writeValue,
  required Future<void> Function(String) deleteValue,
  required Future<void> Function() flush,
  required bool Function() isCurrent,
  bool english = false,
}) async {
  if (!_bookEntryOwners.add(scope.identity)) {
    throw StateError('Book creation entry already open');
  }
  try {
    final revision = client.sessionRevision,
        token = client.exportSession()['token'];
    bool current() =>
        isCurrent() &&
        client.sessionRevision == revision &&
        token != null &&
        token.isNotEmpty &&
        client.exportSession()['token'] == token;
    void guard() {
      if (!current()) throw StateError('Book scope retired');
    }

    final pointer =
        'bookstark.book-create-slot.v1.${base64Url.encode(utf8.encode(scope.identity))}';
    guard();
    await flush();
    guard();
    var key = await readValue(pointer);
    guard();
    final retiring = key?.startsWith('retiring:') ?? false;
    if (retiring) key = key!.substring('retiring:'.length);
    final fresh = key == null;
    if (fresh) {
      key = List.generate(
        16,
        (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      await writeValue(pointer, key);
      guard();
      await flush();
      guard();
      if (await readValue(pointer) != key) {
        throw StateError('Book slot unconfirmed');
      }
      guard();
    }
    final attemptKey = key;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(attemptKey)) {
      throw const FormatException('Book slot corrupt');
    }
    final store = BookCreationAttemptStore(
      scope: scope,
      attemptKey: attemptKey,
      readValue: readValue,
      writeValue: writeValue,
      deleteValue: deleteValue,
      flush: flush,
      isCurrent: current,
    );
    final adapter = BookCreationHttpAdapter(
      client: client,
      scope: scope,
      isCurrent: current,
    );
    final c = BookCreationController(
      store: store,
      transport: adapter.transport,
    );
    final draft = _EntryDrafts(
      namespace: jsonEncode([scope.identity, attemptKey, 'editor']),
      readValue: readValue,
      writeValue: writeValue,
      deleteValue: deleteValue,
      flush: flush,
      isCurrent: current,
    );
    BookItem? legacy;
    try {
      final stored = await store.read();
      guard();
      if (retiring && stored == null) {
        // Prior explicit Finish reached durable absence. Retire its key before a
        // fresh random operation; never re-use a cleared attempt after cold restart.
        if (await readValue(pointer) != 'retiring:$attemptKey') {
          throw StateError('Book slot changed');
        }
        await deleteValue(pointer);
        guard();
        await flush();
        guard();
        if (await readValue(pointer) != null) {
          throw StateError('Book slot cleanup unconfirmed');
        }
        c.dispose();
        adapter.retire();
        draft.retired = true;
        _bookEntryOwners.remove(scope.identity);
        return await createRemoteBookEntry(
          client: client,
          scope: scope,
          repository: repository,
          labelsRepository: labelsRepository,
          ordinaryDrafts: ordinaryDrafts,
          readValue: readValue,
          writeValue: writeValue,
          deleteValue: deleteValue,
          flush: flush,
          isCurrent: isCurrent,
          english: english,
        );
      }
      if (retiring && stored?.state != BookAttemptState.knownID) {
        throw StateError('Book retiring slot corrupt');
      }
      legacy = await ordinaryDrafts.read(null);
      guard();
      if (stored == null) {
        if (legacy != null) {
          // Legacy null IDs have no transmission proof: never promote to unsent.
          final input = BookCreationInput(
            name: legacy.name,
            description: legacy.description,
            labels: legacy.labels,
          );
          await store.put(
            BookCreationAttempt(
              key: attemptKey,
              scope: scope,
              input: input,
              state: BookAttemptState.submittedUnknown,
            ),
          );
        }
      }
      if (stored != null &&
          legacy != null &&
          BookCreationInput(
                name: legacy.name,
                description: legacy.description,
                labels: legacy.labels,
              ).digest !=
              stored.input.digest) {
        throw StateError('Unrelated legacy book draft requires review');
      }
      await c.load();
      guard();
      if (!c.store.isCurrent() || c.phase == BookCreationPhase.failed) {
        throw StateError('Book record unreadable');
      }
      var retired = false;
      void retireOwned() {
        if (retired) return;
        retired = true;
        draft.retired = true;
        c.dispose();
        adapter.retire();
        _bookEntryOwners.remove(scope.identity);
      }

      return _BookEntry(
        controller: c,
        adapter: adapter,
        draft: draft,
        ordinary: repository,
        ordinaryDrafts: ordinaryDrafts,
        labels: labelsRepository,
        current: current,
        english: english,
        legacy: legacy,
        release: retireOwned,
        prepareFinish: () async {
          guard();
          final raw = await readValue(pointer);
          guard();
          if (raw != attemptKey && raw != 'retiring:$attemptKey') {
            throw StateError('Book slot changed');
          }
          await writeValue(pointer, 'retiring:$attemptKey');
          guard();
          await flush();
          guard();
          if (await readValue(pointer) != 'retiring:$attemptKey') {
            throw StateError('Book slot retirement unconfirmed');
          }
        },
        finishPointer: () async {
          guard();
          if (await readValue(pointer) != 'retiring:$attemptKey') {
            throw StateError('Book slot changed');
          }
          await deleteValue(pointer);
          guard();
          await flush();
          guard();
          if (await readValue(pointer) != null) {
            throw StateError('Book slot cleanup unconfirmed');
          }
        },
      );
    } catch (_) {
      draft.retired = true;
      c.dispose();
      adapter.retire();
      rethrow;
    }
  } catch (_) {
    _bookEntryOwners.remove(scope.identity);
    rethrow;
  }
}

class _EntryDrafts extends BookDraftVault {
  _EntryDrafts({
    required super.namespace,
    required super.readValue,
    required super.writeValue,
    required super.deleteValue,
    required this.flush,
    required this.isCurrent,
  });
  final Future<void> Function() flush;
  final bool Function() isCurrent;
  bool retired = false;
  void guard() {
    if (retired || !isCurrent()) throw StateError('Book draft retired');
  }

  @override
  Future<BookItem?> read(int? id) async {
    guard();
    final v = await super.read(id);
    guard();
    return v;
  }

  @override
  Future<void> write(BookItem value) async {
    if (retired || !isCurrent()) return;
    if (value.id != null) throw StateError('New draft only');
    await super.write(value);
    guard();
    await flush();
    guard();
    final observed = await super.read(null);
    guard();
    if (observed == null ||
        jsonEncode([observed.name, observed.description, observed.labels]) !=
            jsonEncode([value.name, value.description, value.labels])) {
      throw StateError('Book draft readback failed');
    }
  }

  @override
  Future<void> remove(int? id) async {
    if (retired || !isCurrent()) return;
    if (id != null) throw StateError('New draft only');
    await super.remove(id);
    guard();
    await flush();
    guard();
    if (await super.read(id) != null) {
      throw StateError('Book draft removal unconfirmed');
    }
    guard();
  }

  Future<void> clearOwned() async {
    // Used only after known durable record and editor retirement.
    if (!isCurrent()) throw StateError('Book scope retired');
    await super.remove(null);
    await flush();
    if (!isCurrent() || await super.read(null) != null) {
      throw StateError('Book draft removal unconfirmed');
    }
  }
}

class _CreationBooks implements BooksRepository {
  _CreationBooks(this.owner);
  final _BookEntryState owner;
  @override
  Future<int> save(BookItem book) => owner.create(book);
  @override
  Future<BooksPageResult> list({String keyword = '', int page = 1}) =>
      owner.widget.ordinary.list(keyword: keyword, page: page);
  @override
  Future<BookItem> read(int id) => owner.widget.ordinary.read(id);
  @override
  Future<void> remove(int id) =>
      Future.error(StateError('Creation cannot delete'));
}

class _BookEntry extends StatefulWidget {
  const _BookEntry({
    required this.controller,
    required this.adapter,
    required this.draft,
    required this.ordinary,
    required this.ordinaryDrafts,
    required this.labels,
    required this.current,
    required this.prepareFinish,
    required this.finishPointer,
    required this.release,
    required this.english,
    this.legacy,
  });
  final BookCreationController controller;
  final BookCreationHttpAdapter adapter;
  final _EntryDrafts draft;
  final BooksRepository ordinary;
  final BookDraftVault ordinaryDrafts;
  final LabelsRepository labels;
  final bool Function() current;
  final Future<void> Function() finishPointer, prepareFinish;
  final bool english;
  final BookItem? legacy;
  final VoidCallback release;
  @override
  State<_BookEntry> createState() => _BookEntryState();
}

class _BookEntryState extends State<_BookEntry> {
  bool review = false, busy = false;
  String? error;
  late final _creationBooks = _CreationBooks(this);
  void changed() {
    if (mounted && widget.current()) setState(() {});
  }

  BookCreationController get c => widget.controller;
  String t(String zh, String en) => widget.english ? en : zh;
  @override
  void initState() {
    super.initState();
    review = c.attempt != null;
    c.addListener(changed);
  }

  Future<int> create(BookItem book) async {
    if (busy || review || !widget.current() || book.id != null) {
      throw StateError('Book review required');
    }
    busy = true;
    try {
      // Preserve actual complete fields BEFORE the controller's transmission marker.
      await widget.draft.write(book);
      if (!widget.current()) throw StateError('Book scope retired');
      await c.start(
        BookCreationInput(
          name: book.name,
          description: book.description,
          labels: book.labels,
        ),
      );
      if (c.canSubmit) await c.submit();
    } finally {
      widget.draft.retired = true;
      busy = false;
      if (mounted && widget.current()) setState(() => review = true);
    }
    // Never return an uncertain ID to old BookEditor cleanup/pop logic.
    throw StateError('Creation record retained; review the result');
  }

  Future<void> existing(int id) async {
    if (!widget.current() || c.attempt?.knownID != id || !c.knownDurable) {
      return;
    }
    final actual = await widget.adapter.readExisting(id);
    if (!mounted || !widget.current()) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (ctx) => Scaffold(
          appBar: AppBar(title: Text(t('核对已有书籍', 'Review existing book'))),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(actual.name),
              Text(actual.description),
              Wrap(
                children: actual.labels
                    .map((v) => Chip(label: Text(v)))
                    .toList(),
              ),
              FilledButton(
                onPressed: () async {
                  final fresh = await widget.adapter.readExisting(id);
                  if (!ctx.mounted || !widget.current()) return;
                  await Navigator.push<bool>(
                    ctx,
                    MaterialPageRoute(
                      builder: (_) => BookEditorPage(
                        repository: widget.ordinary,
                        book: fresh,
                        labelsRepository: widget.labels,
                        vault: widget.ordinaryDrafts,
                        english: widget.english,
                        ownerScope: c.store.scope.identity,
                        isCurrentScope: widget.current,
                      ),
                    ),
                  );
                },
                child: Text(t('编辑已有书籍设置', 'Edit existing book settings')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> finish() async {
    if (busy || !c.knownDurable || c.attempt?.knownID == null) return;
    setState(() => busy = true);
    try {
      await widget.adapter.readExisting(c.attempt!.knownID!);
      if (!widget.current()) throw StateError('Book scope retired');
      widget.draft.retired = true;
      await widget.draft.clearOwned();
      final legacy = widget.legacy;
      if (legacy != null) {
        if (!widget.current()) throw StateError('Book scope retired');
        final now = await widget.ordinaryDrafts.read(null);
        if (!widget.current()) throw StateError('Book scope retired');
        if (now != null &&
            jsonEncode([now.name, now.description, now.labels]) !=
                jsonEncode([legacy.name, legacy.description, legacy.labels])) {
          throw StateError('Legacy draft changed');
        }
        if (now != null) {
          await widget.ordinaryDrafts.remove(null);
          await widget.draft.flush();
        }
        if (await widget.ordinaryDrafts.read(null) != null) {
          throw StateError('Legacy cleanup unconfirmed');
        }
      }
      if (!widget.current()) throw StateError('Book scope retired');
      await widget.prepareFinish();
      await c.clearKnownRecord();
      if (c.cleanupPending) throw StateError('Book cleanup pending');
      await widget.finishPointer();
      if (mounted && widget.current()) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error = t(
            '记录仍需核对，未发送新建请求。',
            'Record needs review. No creation was sent.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    c.removeListener(changed);
    widget.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.current()) {
      return Scaffold(body: Center(child: Text(t('空间已切换', 'Space changed'))));
    }
    if (!review) {
      return BookEditorPage(
        repository: _creationBooks,
        book: const BookItem(name: ''),
        labelsRepository: widget.labels,
        vault: widget.draft,
        english: widget.english,
        ownerScope: c.store.scope.identity,
        isCurrentScope: widget.current,
      );
    }
    return Column(
      children: [
        Expanded(
          child: BookCreationRecoveryPage(
            controller: c,
            english: widget.english,
            onOpenReadOnly: existing,
          ),
        ),
        SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (error != null) Text(error!),
              if (c.canSubmit)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await c.submit();
                          if (mounted) setState(() {});
                        },
                  child: Text(t('明确重交同一草稿', 'Submit this same draft')),
                ),
              if (c.knownDurable)
                TextButton(
                  onPressed: busy ? null : finish,
                  child: Text(t('结束已知结果记录', 'Finish known-result tracking')),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Retire a prepared page if its route was abandoned before mounting.
void retireRemoteBookEntry(Widget page) {
  if (page is _BookEntry) page.release();
}
