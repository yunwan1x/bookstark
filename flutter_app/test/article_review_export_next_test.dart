import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bookstark_flutter/core/complex_editor_document.dart';
import 'package:bookstark_flutter/core/complex_editor_transport.dart';
import 'package:bookstark_flutter/core/native_complex_source_io.dart';
import 'package:bookstark_flutter/core/owned_article_review_export.dart';
import 'support/markdown_creation_host.dart';

void main() {
  test(
    'ordinary readonly document has no export capability or identity RPC',
    () async {
      var identityCalls = 0;
      final host = MarkdownCreationHost();
      final transport = ComplexEditorTransport((name, args) async {
        if (name == 'reviewExportIdentity') {
          identityCalls++;
          throw StateError('No grant');
        }
        return host.call(name, args);
      });
      await transport.load(
        ComplexEditorDocument.parse(ComplexEditorKind.markdown, 'Original'),
      );
      await expectLater(transport.reviewExportIdentity(), throwsStateError);
      expect(identityCalls, 0);
      await transport.retire();
    },
  );
  test(
    'public/shared/editable sources cannot request owned readonly export',
    () async {
      var commands = 0;
      final transport = ComplexEditorTransport((_, _) async {
        commands++;
        return null;
      });
      final source = ComplexEditorDocument.parse(
        ComplexEditorKind.markdown,
        'Original',
      );
      await expectLater(
        transport.load(source, readOnly: false, ownedReviewExport: true),
        throwsArgumentError,
      );
      await expectLater(
        transport.load(
          source,
          ownedReviewExport: true,
          publicResourceRoot: Uri.parse('https://demo.example/'),
        ),
        throwsArgumentError,
      );
      await expectLater(
        transport.load(source, ownedReviewExport: true, sourceReadOnly: true),
        throwsArgumentError,
      );
      expect(commands, 0);
      await transport.retire();
    },
  );
  test(
    'exact private hash and byte length are required in Native identity receipt',
    () async {
      final host = MarkdownCreationHost();
      var corrupt = true, calls = 0;
      const rawHash =
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final transport = ComplexEditorTransport((name, args) async {
        if (name == 'reviewExportIdentity') {
          calls++;
          expect(args, [rawHash, 21 * 1024 * 1024]);
          return {
            'lease': 'owned-lease',
            'generation': host.generation,
            'sha256': corrupt ? 'b' * 64 : rawHash,
            'bytes': 21 * 1024 * 1024,
          };
        }
        return host.call(name, args);
      });
      await transport.load(
        ComplexEditorDocument.parse(
          ComplexEditorKind.markdown,
          'Explicit oversized-record notice',
        ),
        ownedReviewExport: true,
        ownedReviewExportDigest: rawHash,
        ownedReviewExportBytes: 21 * 1024 * 1024,
      );
      await expectLater(
        transport.reviewExportIdentity(),
        throwsFormatException,
      );
      corrupt = false;
      final grant = await transport.reviewExportIdentity();
      expect(grant['sha256'], rawHash);
      expect(grant['bytes'], 21 * 1024 * 1024);
      expect(calls, 2);
      await transport.retire();
      await expectLater(transport.reviewExportIdentity(), throwsStateError);
      expect(calls, 2);
    },
  );
  test(
    'fresh record verification after picker precedes every first exported byte',
    () async {
      var current = true, begins = 0, writes = 0, cancels = 0;
      final source = OwnedArticleReviewExport(
        source: '\ufeff{"body":"雪😀"}\r\n',
        mime: 'application/json',
        name: 'record.json',
      );
      Future<Map<Object?, Object?>?> invoke(
        String method,
        Map<String, Object?> args,
      ) async {
        switch (method) {
          case 'scopeState':
            return {'epoch': 0};
          case 'activateScope':
            return {'epoch': 1};
          case 'retireScope':
            return {'retired': true};
          case 'beginExport':
            begins++;
            expect(args['sha256'], source.digest);
            expect(args['bytes'], source.bytes.length);
            return {'id': args['id'], 'ready': true};
          case 'writeExport':
            writes++;
            throw StateError('Must not write');
          case 'cancel':
            cancels++;
            return {};
          default:
            throw StateError('Unexpected method');
        }
      }

      final owner = await ComplexSourceIoScope.activate(
        scope: 'a' * 64,
        isCurrent: () => current,
        invoke: invoke,
      );
      final native = NativeComplexSourceIo(
        owner: owner,
        lease: 'owned-lease',
        generation: 1,
        invoke: invoke,
      );
      final entered = Completer<void>(), release = Completer<void>();
      final operation = native.exportOwnedReview(
        source,
        beforeWrite: () async {
          entered.complete();
          await release.future;
          if (!current) throw StateError('Retained source retired');
        },
      );
      final assertion = expectLater(operation, throwsStateError);
      await entered.future;
      expect(begins, 1);
      expect(writes, 0);
      current = false;
      release.complete();
      await assertion;
      expect(writes, 0);
      expect(cancels, 1);
      native.retire();
      await owner.retire();
    },
  );
  test(
    'successful export transfers exact original BOM bytes and validates native digest',
    () async {
      final source = OwnedArticleReviewExport(
        source: '\ufeffOriginal雪😀\r\n',
        mime: 'application/json',
        name: 'record.json',
      );
      final received = <int>[];
      var fresh = 0;
      Future<Map<Object?, Object?>?> invoke(
        String method,
        Map<String, Object?> args,
      ) async {
        switch (method) {
          case 'scopeState':
            return {'epoch': 0};
          case 'activateScope':
            return {'epoch': 1};
          case 'retireScope':
            return {'retired': true};
          case 'beginExport':
            return {'id': args['id'], 'ready': true};
          case 'writeExport':
            received.addAll(base64Decode(args['data']! as String));
            return {
              'id': args['id'],
              'index': args['index'],
              'bytes': received.length,
            };
          case 'finishExport':
            return {
              'id': args['id'],
              'saved': true,
              'bytes': received.length,
              'sha256': sha256.convert(received).toString(),
            };
          case 'cancel':
            return {};
          default:
            throw StateError('Unexpected method');
        }
      }

      final owner = await ComplexSourceIoScope.activate(
        scope: 'b' * 64,
        isCurrent: () => true,
        invoke: invoke,
      );
      final native = NativeComplexSourceIo(
        owner: owner,
        lease: 'owned-lease',
        generation: 1,
        invoke: invoke,
      );
      expect(
        await native.exportOwnedReview(
          source,
          beforeWrite: () async {
            fresh++;
          },
        ),
        isTrue,
      );
      expect(fresh, 1);
      expect(received, source.bytes);
      native.retire();
      await owner.retire();
    },
  );
}
