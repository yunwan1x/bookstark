import 'dart:async';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/attachments.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';

class Notes implements NotesRepository {
  @override
  Future<int> save(Note note) async => 7;
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<Note> read(int id) async => throw UnimplementedError();
  @override
  Future<void> remove(int id) async {}
}

class Media extends AttachmentRepository {
  Media()
    : super(publicTransport: MockClient((_) async => http.Response('', 404)));
  int adds = 0;
  bool? wasProtected;
  bool fail = false;
  Completer<Attachment>? pending;
  final uri = Uri.parse(
    'bookstark-attachment:///0123456789abcdef0123456789abcdef/report.pdf',
  );
  @override
  bool owns(Uri uri) => uri.scheme == 'bookstark-attachment';
  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async {
    adds++;
    wasProtected = protected;
    if (fail) throw StateError('upload failed');
    final waiting = pending;
    if (waiting != null) {
      cancellation?.signal.then((_) {
        if (!waiting.isCompleted) {
          waiting.completeError(const AttachmentCancelled());
        }
      });
      return waiting.future;
    }
    return Attachment(uri: uri, name: '报告[1].pdf', image: false, size: 3);
  }

  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) async =>
      Uint8List.fromList([1, 2, 3]);
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    Media media, {
    bool protected = false,
    Future<XFile?> Function(bool)? picker,
    Future<void> Function(Attachment, Uint8List)? share,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorPage(
          repository: Notes(),
          attachments: media,
          note: Note(
            id: 7,
            title: '原题',
            content: '# 保留正文',
            isProtected: protected,
            unlockPassword: protected ? 'ephemeral' : null,
          ),
          pickFile:
              picker ??
              (_) async => XFile.fromData(
                Uint8List.fromList([1, 2, 3]),
                path: 'report.pdf',
              ),
          shareFile: share,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cancelled picker leaves note unchanged and makes no upload', (
    tester,
  ) async {
    final media = Media();
    addTearDown(media.close);
    await mount(tester, media, picker: (_) async => null);
    await tester.tap(find.byTooltip('添加附件'));
    await tester.pumpAndSettle();
    expect(media.adds, 0);
    expect(find.text('# 保留正文'), findsOneWidget);
    expect(find.text('未保存'), findsNothing);
  });
  testWidgets(
    'attachment inserts escaped link, shares actual bytes and removes only reference',
    (tester) async {
      final media = Media();
      addTearDown(media.close);
      var shared = 0;
      await mount(
        tester,
        media,
        share: (attachment, bytes) async {
          expect(bytes, [1, 2, 3]);
          shared++;
        },
      );
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      expect(media.adds, 1);
      expect(find.text('报告[1].pdf'), findsOneWidget);
      final content = tester
          .widget<TextField>(find.byType(TextField).last)
          .controller!
          .text;
      expect(content, contains(r'报告\[1\].pdf'));
      expect(content, contains('# 保留正文'));
      await tester.ensureVisible(find.byTooltip('分享附件'));
      await tester.tap(find.byTooltip('分享附件'));
      await tester.pumpAndSettle();
      expect(shared, 1);
      await tester.tap(find.byTooltip('移除引用'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byType(TextField).last)
            .controller!
            .text
            .trim(),
        '# 保留正文',
      );
      expect(find.text('报告[1].pdf'), findsNothing);
    },
  );
  testWidgets(
    'failed upload retains source and inserts no phantom attachment',
    (tester) async {
      final media = Media()..fail = true;
      addTearDown(media.close);
      await mount(tester, media);
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pumpAndSettle();
      expect(find.textContaining('upload failed'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '# 保留正文',
      );
    },
  );
  testWidgets(
    'protected note passes protected flag; cancelled pending upload adds no URL',
    (tester) async {
      final media = Media()..pending = Completer<Attachment>();
      addTearDown(media.close);
      await mount(tester, media, protected: true);
      await tester.tap(find.byTooltip('添加附件'));
      await tester.pump();
      expect(media.wasProtected, isTrue);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('取消附件操作'));
      await tester.tap(find.text('取消附件操作'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '# 保留正文',
      );
      expect(find.text('正在处理附件…'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
