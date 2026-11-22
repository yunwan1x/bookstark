Design before implementation. Reuse selected08 unlock docs/flutter-rewrite/pages/08-unlock.png +08-drafts-unlock.md and current LocalComplexNotePage/ComplexEditorBrowser read-only review chrome. No new cipher architecture or public/share route. Only owned note spreadsheet/drawing/mindmap/richdoc/presentation. Password dialog stays memory-only and never sends password to DOM. Editor shows a fixed memory-only notice; full source/title/labels drafts never enter NativeComplexRecoveryStore or secure preferences. Before sole Save transport send, durable metadata journal stores opaque scope/id/kind hashes, baseline fingerprint, edit digest and attempt/state only. Unknown cold gate says previous edited body was NOT retained; shows only fresh password-unlocked server source in real read-only engine, no replay. Explicit reviewed fresh fingerprint may end this attempt and start a NEW editor; content match is not historical receipt proof. Known receipt cleanup is metadata-only; failure Retry cleanup never repeats PUT. Cancel/unlock failure/scope retirement preserve opaque marker and expose no old source. Existing article/HTML/Markdown/public flows unchanged. Parent approved memory+durable no-body policy.\n

## All-kind recovery completion (external draft, not executed)
Reuse the selected 08 unlock dialog and current read-only complex review chrome.
The slot is opaque owner + blog ID, independent of present editor kind,
collection and protection flag. Baseline/submitted digests bind the original
complete tuple; a changed routing format must not hide the slot. Before any
authenticated note/article route Root checks it. A five-kind note marker opens
its dedicated recovery flow. A Markdown, HTML or article retarget opens only
seven-kind current-source recovery; ordinary editing is blocked.

Authenticated CSRF-protected readonly POST
/api/owned-complex/notes/:id/protected-review accepts only a bounded password
body (empty only works for an actually unprotected record). Its one transaction
verifies actual owner, blog type, kind, bcrypt protection, all current metadata,
labels, original cipher and fully decoded source. Markdown remains exact
UTF8/BOM/CRLF within 5MiB; HTML/richdoc use existing bounded gzip. Presentation
is 20MiB, others 5MiB. Password/hash never enter DTO. Read expansion grants no
Markdown/HTML write endpoint.

Cold UI states that the previous edited body was not retained on disk, and
shows only current server source. Return retains marker. Explicit end requires
a second same-fingerprint read; changed versions require review again.
Retargeted content equality never proves the earlier mutation committed.
Ending tracking never automatically enters an editor. Password/body remain
route-owned memory. Closing drops references and zeros owned byte buffers;
Dart immutable strings are GC-managed, not claimed securely wiped.

Native metadata includes keys only for both owned/shared marker prefixes.
44 inventory retains every owner's opaque references; corrupt/wrong-storage
keys remain unknown blocking records. This does not inspect marker phase,
content or SQL receipts, nor expand assistant helper ledger coverage.
Root revokes active protected owners before transition, awaiting exact owned
route/native closure. Switching account retains markers while permitting
return to the original owner; migration preflight blocks on all unresolved
markers, including other accounts.

### Verification status
Dart/Go tests remain unrun drafts. No actual repository/device/data/provider
state changed. Final API/main/opener patches require Root next frozen source.
Controller is exact after A shared-core; page hooks exact after A engine9.
