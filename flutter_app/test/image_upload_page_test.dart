import 'dart:convert';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/features/images/image_upload_page.dart';
import '../tool/fixtures/images.dart';
import 'images_page_test.dart' show drain, tapVisible;

XFile source(String color) => XFile.fromData(
  Uint8List.fromList(
    utf8.encode(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="$color"/></svg>',
    ),
  ),
  path: 'same.svg',
  name: 'same.svg',
);
void main() {
  testWidgets(
    'picker cancellation produces no upload and leaves no queue entries',
    (tester) async {
      final repo = ImagesFixture();
      var picks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ImageUploadPage(
            repository: repo,
            english: true,
            pickFiles: () async {
              picks++;
              return [];
            },
          ),
        ),
      );
      await drain(tester);
      await tapVisible(tester, find.text('Choose images (multiple)'));
      expect(picks, 1);
      expect(repo.uploadCalls, 0);
      expect(find.text('0 pending · 0 confirmed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'same-name files remain separate, invalid content cannot block a valid later file',
    (tester) async {
      final repo = ImagesFixture();
      await tester.pumpWidget(
        MaterialApp(
          home: ImageUploadPage(
            repository: repo,
            english: true,
            initialFiles: [
              XFile.fromData(Uint8List.fromList([0, 1, 2]), path: 'same.svg'),
              source('blue'),
            ],
          ),
        ),
      );
      await drain(tester);
      expect(find.text('same.svg'), findsNWidgets(2));
      expect(repo.uploadCalls, 0);
      await tester.scrollUntilVisible(
        find.text('Process 2 items'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Process 2 items'));
      expect(repo.uploadCalls, 1);
      expect(repo.records.length, 1);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await drain(tester);
      expect(find.text('0 pending · 1 confirmed'), findsOneWidget);
      expect(find.textContaining('Failed'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'unknown save result is verified by hash without another upload',
    (tester) async {
      final repo = ImagesFixture();
      repo.uploadOverride = (payload, cancel, onSent) async {
        repo.recordPayload(payload);
        throw const ApiFailure(502, 'Acknowledgement lost');
      };
      await tester.pumpWidget(
        MaterialApp(
          home: ImageUploadPage(
            repository: repo,
            english: true,
            initialFiles: [source('blue')],
          ),
        ),
      );
      await drain(tester);
      await tester.scrollUntilVisible(
        find.text('Process 1 items'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tapVisible(tester, find.text('Process 1 items'));
      await tapVisible(tester, find.text('Verify result'));
      expect(repo.uploadCalls, 1);
      expect(repo.hashCalls, 2);
      expect(find.textContaining('Confirmed file:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
