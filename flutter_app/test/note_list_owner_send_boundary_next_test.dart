import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bookstark_flutter/core/api_client.dart';
import 'package:bookstark_flutter/core/note_pin_actions.dart';
import 'package:bookstark_flutter/core/notes_repository.dart';
import 'package:bookstark_flutter/features/notes/owned_note_list_scope.dart';

void main() {
  for (final operation in ['pin', 'batch', 'remove']) {
    for (final retirement in ['barrier', 'same-token-restore', 'dispose']) {
      test(
        '$operation CSRF pending then $retirement sends zero mutation HTTP',
        () async {
          final csrfEntered = Completer<void>(),
              csrfRelease = Completer<void>();
          var mutations = 0, reads = 0, current = true;
          final client = BookstarkClient(
            'https://owned.invalid/prefix',
            transport: MockClient((request) async {
              if (request.url.path == '/prefix/api/csrf-token') {
                csrfEntered.complete();
                await csrfRelease.future;
                return http.Response(
                  jsonEncode({'code': 0, 'data': <String, Object?>{}}),
                  200,
                  headers: {
                    'content-type': 'application/json',
                    'set-cookie': 'csrf_token=fixture-csrf; Path=/',
                  },
                );
              }
              if (request.method != 'GET') {
                mutations++;
                throw StateError('Retired write reached HTTP');
              }
              reads++;
              return http.Response(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'blog_id': 19,
                    'member_id': 7,
                    'blog_type': 'note',
                    'editor_type': 'markdown',
                    'is_pinned': 0,
                    'visibility': 0,
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }),
          );
          client.restoreSession({'token': 'fixture-only'});
          addTearDown(client.close);
          final binding = OwnedNoteListBinding.remote(
            client: client,
            memberId: 7,
            collection: NoteCollection.note,
            scope: 'case-$operation-$retirement',
            isCurrent: () => current,
          );
          addTearDown(binding.retire);
          final Future<Object?> pending = operation == 'pin'
              ? binding.actions!.setPinned(19, true)
              : operation == 'batch'
              ? binding.actions!.pinSelected([19])
              : binding.repository.remove(19).then<Object?>((_) => null);
          // Attach assertion immediately so an abort rejection is never unhandled.
          final rejected = expectLater(
            pending,
            throwsA(
              operation == 'remove'
                  ? isA<StateError>()
                  : isA<NoteActionScopeRetired>(),
            ),
          );
          await csrfEntered.future;
          if (retirement == 'barrier') {
            current = false;
          } else if (retirement == 'same-token-restore') {
            client.restoreSession({'token': 'fixture-only'});
          } else {
            binding.retire();
          }
          csrfRelease.complete();
          await rejected;
          expect(mutations, 0);
          expect(reads, operation == 'remove' ? 0 : 1);
        },
      );
    }
  }
}
