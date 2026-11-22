import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/html_editor_controller.dart';
import 'package:bookstark_flutter/core/html_notes_repository.dart';
import 'package:bookstark_flutter/core/owned_html_note_images.dart';
import 'package:bookstark_flutter/core/owned_complex_image_upload_journal.dart';
import 'package:bookstark_flutter/core/owned_complex_resource_lease.dart';
import 'package:bookstark_flutter/core/secure_record_store.dart';

const opaque =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
HtmlNote note({
  String collection = 'note',
  String source = '<p>Actual</p>',
  bool protected = false,
}) => HtmlNote(
  metadata: HtmlNoteMetadata(
    id: 41,
    memberId: 7,
    collection: collection,
    title: 'Actual HTML',
    version: 2,
    modifiedAt: 100,
    protected: protected,
  ),
  source: source,
  labels: const ['real'],
  unlockPassword: protected ? 'memory-only-fixture' : null,
);

class Repository implements HtmlNotesRepository {
  Repository(this.actual);
  HtmlNote actual;
  String? readPassword;
  int reads = 0, saves = 0;
  @override
  bool get labelsUseCsv => true;
  @override
  Future<HtmlNote> read(int id, {String? password}) async {
    expect(id, 41);
    reads++;
    readPassword = password;
    return actual;
  }

  @override
  Future<HtmlSaveOutcome> save(HtmlNote baseline, HtmlNoteEdit edit) async {
    saves++;
    throw StateError('No resource write allowed in image tests');
  }

  @override
  Future<HtmlSaveOutcome> finishLabels(HtmlSaveAttempt attempt) async {
    throw StateError('No label write allowed in image tests');
  }

  @override
  void dispose() {}
}

void main() {
  BookstarkClient client() => BookstarkClient(
    'https://owned.test/prefix',
    transport: MockClient(
      (_) async => throw StateError('No account HTTP expected'),
    ),
  )..restoreSession({'token': 'account-only', 'csrf_token': 'csrf-only'});
  test(
    'dedicated HTML uses actual protected baseline and password only in memory',
    () async {
      final c = client(), repository = Repository(note(protected: true));
      final editor = HtmlEditorController(repository, repository.actual);
      final values = <String, String>{};
      final store = SecureRecordStore(
        prefix: OwnedComplexImageUploadJournal.prefix,
        namespace: opaque,
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final images = OwnedHtmlNoteImages(
        client: c,
        memberId: 7,
        resourceId: 41,
        namespace: 'remote-html-v1',
        isCurrent: () => true,
        editor: editor,
        journalStore: store,
        flush: () async {},
      );
      try {
        await images.open();
        expect(await images.verifyFreshSource(), true);
        expect(repository.readPassword, 'memory-only-fixture');
        expect(editor.canPersistDraft, false);
        await images.journal.write(
          OwnedImageUploadRecord(
            bindingId: images.lease.identity,
            inputSHA256: opaque,
            phase: OwnedImageUploadPhase.unknown,
          ),
        );
        expect(values.values.join(), isNot(contains('memory-only-fixture')));
        expect(values.values.join(), isNot(contains('<p>Actual</p>')));
        expect(repository.saves, 0);
        repository.actual = note(source: '<p>Changed</p>', protected: true);
        expect(await images.verifyFreshSource(), false);
        expect(repository.saves, 0);
      } finally {
        await images.retireAndDrain();
        editor.dispose();
        c.close();
      }
    },
  );
  test(
    'real collection change hits the same unknown slot and refuses new upload',
    () async {
      final c = client(), values = <String, String>{};
      final store = SecureRecordStore(
        prefix: OwnedComplexImageUploadJournal.prefix,
        namespace: opaque,
        readValue: (k) async => values[k],
        writeValue: (k, v) async {
          values[k] = v;
        },
        deleteValue: (k) async {
          values.remove(k);
        },
      );
      final nr = Repository(note()), nc = HtmlEditorController(nr, nr.actual);
      final first = OwnedHtmlNoteImages(
        client: c,
        memberId: 7,
        resourceId: 41,
        namespace: 'remote-html-v1',
        isCurrent: () => true,
        editor: nc,
        journalStore: store,
        flush: () async {},
      );
      await first.open();
      await first.journal.write(
        OwnedImageUploadRecord(
          bindingId: first.lease.identity,
          inputSHA256: opaque,
          phase: OwnedImageUploadPhase.unknown,
        ),
      );
      final old = Map<String, String>.of(values);
      final key = first.journal.identity;
      await first.retireAndDrain();
      nc.dispose();
      final ar = Repository(note(collection: 'article')),
          ac = HtmlEditorController(ar, ar.actual);
      final second = OwnedHtmlNoteImages(
        client: c,
        memberId: 7,
        resourceId: 41,
        namespace: 'remote-html-v1',
        isCurrent: () => true,
        editor: ac,
        journalStore: store,
        flush: () async {},
      );
      try {
        expect(second.journal.identity, key);
        expect(second.lease.identity, isNot(first.lease.identity));
        await second.open();
        expect(second.initializationFailed, true);
        expect(second.upload.canUpload, false);
        expect(values, old);
        expect(ar.saves, 0);
        expect(ar.reads, 0);
      } finally {
        await second.retireAndDrain();
        ac.dispose();
        c.close();
      }
    },
  );
  test(
    'metadata-only version or collection drift rejects a fresh image insertion',
    () async {
      final c = client(),
          repository = Repository(note()),
          editor = HtmlEditorController(repository, repository.actual);
      final images = OwnedHtmlNoteImages(
        client: c,
        memberId: 7,
        resourceId: 41,
        namespace: 'remote-html-v1',
        isCurrent: () => true,
        editor: editor,
        journalStore: SecureRecordStore(
          prefix: OwnedComplexImageUploadJournal.prefix,
          namespace: opaque,
          readValue: (_) async => null,
          writeValue: (_, _) async {},
          deleteValue: (_) async {},
        ),
        flush: () async {},
      );
      try {
        await images.open();
        final original = repository.actual;
        repository.actual = HtmlNote(
          metadata: HtmlNoteMetadata(
            id: 41,
            memberId: 7,
            collection: 'note',
            title: original.metadata.title,
            version: original.metadata.version + 1,
            modifiedAt: original.metadata.modifiedAt,
            protected: false,
          ),
          source: original.source,
          labels: original.labels,
        );
        expect(await images.verifyFreshSource(), false);
        repository.actual = note(collection: 'article');
        expect(await images.verifyFreshSource(), false);
        expect(repository.saves, 0);
      } finally {
        await images.retireAndDrain();
        editor.dispose();
        c.close();
      }
    },
  );
  test(
    'same-token same-cookie restore retires actual HTML image binding before read',
    () async {
      final c = client(),
          repository = Repository(note()),
          editor = HtmlEditorController(repository, repository.actual);
      final images = OwnedHtmlNoteImages(
        client: c,
        memberId: 7,
        resourceId: 41,
        namespace: 'remote-html-v1',
        isCurrent: () => true,
        editor: editor,
        journalStore: SecureRecordStore(
          prefix: OwnedComplexImageUploadJournal.prefix,
          namespace: opaque,
          readValue: (_) async => null,
          writeValue: (_, _) async {},
          deleteValue: (_) async {},
        ),
        flush: () async {},
      );
      try {
        await images.open();
        c.restoreSession({'token': 'account-only', 'csrf_token': 'csrf-only'});
        await expectLater(
          images.verifyFreshSource(),
          throwsA(isA<OwnedComplexResourceRetired>()),
        );
        expect(repository.reads, 0);
        expect(repository.saves, 0);
      } finally {
        await images.retireAndDrain();
        editor.dispose();
        c.close();
      }
    },
  );
}
