import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/notes_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/attachments.dart';

void main() {
  const url = '/api/webdav/files/download?path=%2Freport.pdf';
  final uri = Uri.parse(url);
  final attachment = Attachment(
    uri: uri,
    name: 'different metadata label',
    image: false,
  );
  String remove(String source) => removeAttachmentReference(source, attachment);
  for (final image in [false, true]) {
    final prefix = image ? '!' : '';
    for (final destination in [
      '($url "A title")',
      '(<$url> \'A title\')',
      '($url (A title))',
    ]) {
      test('inline title syntax image=$image $destination', () {
        final syntax = '$prefix[Display *label*]$destination';
        expect(remove('Before $syntax after'), 'Before  after');
      });
    }
    for (final usage in ['$prefix[Report][r]', '$prefix[r][]', '$prefix[r]']) {
      test('reference usage image=$image $usage preserves definitions', () {
        final definitions = '\n\n[r]: <$url> "Shared title"\n[unused]: $url\n';
        expect(
          remove('Before $usage after$definitions'),
          'Before  after$definitions',
        );
      });
    }
  }
  test(
    'shared reference removes all uses but keeps definition and other URI',
    () {
      final definition = '\n\n[r]: $url\n[other]: /other.pdf\n';
      expect(
        remove('[One][r] and ![Two][r] plus [Keep][other]$definition'),
        ' and  plus [Keep][other]$definition',
      );
    },
  );
  test('code and bare URLs retain byte-identical duplicated syntax', () {
    const syntax = '[Report][r]';
    final ticks = String.fromCharCode(96);
    final literal =
        '$ticks$syntax$ticks\n\n'
        '$ticks$ticks$ticks markdown\n$syntax\n$ticks$ticks$ticks\n\n'
        '    $syntax\n\nBare: $url\n\n';
    final definition = '[r]: $url\n';
    expect(
      remove('$literal Real $syntax end\n\n$definition'),
      '$literal Real  end\n\n$definition',
    );
  });
  test(
    'unused definitions and escaped syntax do not count as live references',
    () {
      final source =
          '\\[r]\n\n[r]: $url\n\n'
          '[unused]: $url "Not used"\n';
      expect(remove(source), source);
    },
  );
  test(
    'URI identity distinguishes query path and keeps unrelated source bytes',
    () {
      final source =
          '\uFEFFBefore\r\n\r\n[Other]($url-other)\r\n\r\n'
          '[Remove](<$url> "title")\r\n\r\nTail 😀\r\n';
      expect(
        remove(source),
        '\uFEFFBefore\r\n\r\n[Other]($url-other)\r\n\r\n'
        '\r\n\r\nTail 😀\r\n',
      );
    },
  );
  test('multiline use preserves CRLF outside the exact link range', () {
    final source = 'Before [Long\r\nlabel](<$url> "Title") after\r\n';
    expect(remove(source), 'Before  after\r\n');
  });
  test('heading list and quote references keep other original Markdown', () {
    final source =
        '# Keep\n\n- one [Report]($url) end\n\n> Quote ![Image]($url)\n';
    expect(remove(source), '# Keep\n\n- one  end\n\n> Quote \n');
  });
  test('plain non-link punctuation remains untouched', () {
    final source = '[missing]\n\n[url]: $url\n\n$uri\n';
    expect(remove(source), source);
  });
  test(
    'target wrapper unwraps without deleting a different attachment image',
    () {
      final source =
          'Before [![Keep image](/other.png)]($url "Download") after';
      expect(remove(source), 'Before ![Keep image](/other.png) after');
    },
  );
  test(
    'nested image and wrapper for the same target remove as one outer use',
    () {
      final source = 'Before [![Remove]($url)]($url) after';
      expect(remove(source), 'Before  after');
    },
  );
  test(
    'many ordinary references use the same exact bounded edit semantics',
    () {
      final source = List.generate(
        300,
        (i) => 'Line $i [r]($url) end',
      ).join('\n');
      final expected = List.generate(300, (i) => 'Line $i  end').join('\n');
      expect(remove(source), expected);
    },
  );
  testWidgets(
    'actual editor removes reference-style usage and retains source definition and code',
    (tester) async {
      final media = _OwnedAttachments();
      addTearDown(media.close);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final ticks = String.fromCharCode(96);
      final content =
          'Before [Report][r] after\n\n'
          '$ticks[Report][r]$ticks\n\n[r]: $url "Title"\n';
      await tester.pumpWidget(
        MaterialApp(
          home: NoteEditorPage(
            repository: _Notes(),
            attachments: media,
            note: Note(id: 7, title: 'Original', content: content),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('移除引用'));
      await tester.tap(find.byTooltip('移除引用'));
      await tester.pumpAndSettle();
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      expect(
        fields.last.controller!.text,
        content.replaceFirst('[Report][r]', ''),
      );
      expect(find.byTooltip('移除引用'), findsNothing);
      expect(media.reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _Notes implements NotesRepository {
  @override
  Future<List<Note>> list({String keyword = '', int page = 1}) async => [];
  @override
  Future<Note> read(int id) async => throw UnimplementedError();
  @override
  Future<int> save(Note note) async => 7;
  @override
  Future<void> remove(int id) async => throw UnimplementedError();
}

class _OwnedAttachments extends AttachmentRepository {
  int reads = 0;
  @override
  bool owns(Uri uri) => uri.path == '/api/webdav/files/download';
  @override
  Future<Attachment> add(
    XFile file, {
    bool protected = false,
    AttachmentCancellation? cancellation,
  }) async => throw UnimplementedError();
  @override
  Future<Uint8List> read(Uri uri, {int maxBytes = 64 * 1024 * 1024}) async {
    reads++;
    return Uint8List(0);
  }
}
