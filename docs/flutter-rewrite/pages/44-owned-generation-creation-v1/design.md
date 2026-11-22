# Owned15 creation and atomic receipt

Selected prototype: owned15-creation-v1.png, generated before implementation. Four existing visual patterns are reused: explicit editor Save, unknown readonly memory snapshot, fresh existing-ID review, known commit with local cleanup only. All article formats use the real WebView; only ordinary Markdown notes use the native editor. English320dp/200% text/180dp keyboard retains scrollable controls. Closing or background locking loses unsaved memory; no disk body/password is promised.

## Existing schema evidence

createLegacyCandidateSchema15 inherits createLocalSchema14. Its existing html_creation_receipts table has only creation_key32, positive note_id, collection note/article, input_hash64, positive created_at. The name is historical; physical constraints have no editor format restriction. LocalBackupContentVerifier currently checks those same typed fields, not html-only resources. Original HTML repository finds a receipt only by its exact creation key and validates its HTML resource. We must retain that behavior and reject collisions, never overwrite/reinterpret an old key.

The new typed15 domain can therefore INSERT one notes row and one receipt row in a single SQLite transaction, using only a sealed OwnedWritableGeneration15. No table or schema change is needed. No LocalStore16 writer or legacy_import_records/source provenance is fabricated. Full backup copies the original and new rows/IDs/seq exactly through its existing schema15 protocol.

## Protocol and immutable input

A new operation receives a cryptographically random 32-lowerhex creation key in memory. Preparation validates one of seven exact formats, collection, full title/source/labels, size and protection. Existing NativeLocalContentCrypto protects only the user-selected new protected body, before SQL; neither password nor plaintext body enters durable operation metadata. Exact UTF8 bytes, BOM/CRLF and the existing body algorithm are retained.

Receipt input_hash is domain-separated from old HTML: a typed15 canonical immutable STORED input tuple, including actual kind/collection, original title/labels, password-hash identity and stored body digest. It does not store a password or body. This permits fresh receipt/current-cipher verification without treating a title or user-entered ID as creation proof. Old HTML key conflicts fail closed.

Submission requires a durable unknown marker before the unique SQL attempt and a current sealed capability after every asynchronous preparation. The creator owns and joins crypto/SQL work through Root lifetime retirement. Within the same SQL transaction it checks the exact key is absent, INSERTs the note and receipt, and verifies the actual returned row. An already-present key never authorizes another INSERT. Pending/unknown state has no replay API.

## Four states

1. Editing: memory draft; explicit Save only. Cancel returns without SQL. The UI discloses memory loss on close/background.
2. Unknown: editor is actually replaced by readonly full warm snapshot. No second Save/Create. Cold start states that the prior text was not retained, then reads the exact operation receipt/current resource; it never pretends the fresh content is the lost draft.
3. Receipt review: matching receipt binds actual ID/collection/format and immutable stored-input digest. Current resource can be matching, changed, deleted, protected or unreadable. Read current content only through the correct existing native/WebView/password flow. Explicit finish repeats a fresh fingerprint/receipt check. Missing or corrupt evidence retains the marker; no title search or implicit recreation.
4. Known commit/local cleanup failed: retain actual positive ID. Retry is only durable marker acknowledgement/removal, no INSERT or UPDATE. Changed memory input cannot be sent under the old operation. Retire/background removes plaintext memory while keeping the body-free recovery record.

One generation-wide creation marker slot prevents changing collection/format to bypass unresolved creation. New independent owned15-creation prefix must participate in keys-only Native44 inventory and Root transition/backup barriers. Malformed/overbound records remain blocking across owners; metadata inventory does not read body or password.

## Required proofs before enabling Root

Real SQLite all7-kind note/article creation, protected crypto roundtrip, exact BOM/NULL/BLOB old-row preservation, transaction trigger failure rolls back note/receipt/seq, double-controller claim causes at most one INSERT, lost SQL receipt is recovered by actual atomic receipt only, known cleanup retry changes only secure metadata, changed/current/deleted fulltuple review, real NativeMD unknown replacement, article WebView routing, full backup15 receipt roundtrip and ARM64 redroid cold recovery. Existing Root owned15 creation block remains until the actual typed creator/entry is wired and tested.

This document and image are design artifacts, not runtime evidence.
