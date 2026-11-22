# 08 Remote Markdown creation recovery v2

Selected prototype: remote-markdown-creation-v2.png. Generated with built-in imagegen; exact prompt is in prompt.json. This prototype precedes all implementation. Application source remains frozen.

## Scope and invariant
Ordinary remote Markdown note/article creation only. Every record is bound to normalized server, current authenticated member ID, collection, explicit markdown format, random local key and exact full edited snapshot (title, content, labels). The key is local bookkeeping, not a server idempotency token. No password or protected-body serialization. Existing HTML records and their namespaces stay unchanged.

Go POST /api/blogs has no creation-key/receipt lookup protocol. A returned owned ID is an acknowledgement, not a guarantee that an unacknowledged POST did not commit. Titles and empty list pages never establish identity or absence.

## Four states
1. Unknown result: retain a complete read-only local snapshot and disable another create request. View full draft opens every byte of title/body/labels; bounded initial preview never truncates the stored snapshot. Back retains the journal.
2. Check saved note: explicitly enter a positive ID. Verify fresh owner, collection, markdown format and unprotected status before reading body. A candidate list, if later added, is a manual discovery hint only. The first implementation needs no title search.
3. Review both versions: show full original snapshot and full freshly read server version, labels, ID and modified/version metadata. The user explicitly marks the complete snapshot reviewed. Adoption rereads the exact ID; changed fingerprint blocks adoption and requires another review. Matching content does not prove this request created the note. Adoption means explicitly using the selected existing resource; it never overwrites it. Format/protection changes require the existing typed opener and retain this journal.
4. Known ID finishing: a real acknowledged ID is durably persisted before any follow-up mutation. Labels may be finished only on that ID after fresh same-content comparison and explicit action. Device cleanup retries perform storage work only. The selected image groups two possible follow-up cards; implementation shows only actions valid for the actual current phase, not simultaneous executable controls.

## State machine
Editing -> durably pending -> single POST -> acknowledged ID -> strict fresh read -> finish / review / cleanup.
Any failure after transport submission, process death with pending, or uncertain persistence remains unknown. Only a positively proven pre-submit failure permits editing again. Unknown has no POST replay action, even after 404 or no matches. A known-ID label error never resets identity to null. A cleanup failure never returns to editing. Scope guards run before and after every await; active lease prevents a second editor for the same namespace. A corrupt record is blocking, not empty.

Persist with FlutterSecureStorage dedicated recovery preferences plus awaited NativeRecoveryStorage.flush and durable readback. Do not clear legacy editor drafts until the new journal is durable and the same full snapshot is verified. Storage errors preserve blocking state; applied-delete/lost-ack needs restoring the original record where possible and must never report a successful cleanup without readback.

## Rendering and accessibility
White rounded cards, navy text, blue primary buttons, amber uncertainty, green known-ID status. Use BookstarkMarkdown for inert Markdown previews; provide selectable raw source/full text access so source bytes remain inspectable. No authenticated WebView for ordinary Markdown. Full-width wrapping controls and scrollable layouts at EN320 / 200% font; ID input with keyboard must keep Return/Read reachable. Back and system back retain the pending record. Explicit disabled Create again explains uncertainty rather than looking like a broken button.

## Planned files and regression
Separate remote_markdown_creation_vault.dart and controller; no reuse of HtmlNoteEdit/HTML namespace. API adapter must bound request/reply and strictly validate actual owner/collection/format/ID. Tests: post applied/lost response; pending cold restore; known-ID persist failure; no POST on repeated Save/restore; hash and scope mismatch; metadata/full-body changes; wrong owner/format/protected refusal; label finish same-ID only; cleanup storage-only; full emoji/BOM/unknown text preservation; owner retirement across awaits; missing/damaged storage stays blocked.
This is a design artifact, not evidence of implemented UI or Native acceptance.

