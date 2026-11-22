# Content budget reconciliation — design before implementation

This is data/crypto validation work, with no new production page or layout.

Presentation editing already supports20MiB source. The shared legacy crypto primitive must support the same20MiB UTF8 plaintext, retaining salt16/nonce12/tag16 and original bcrypt/PBKDF2/AES-GCM formats. Set a conservative28MiB wire/envelope cap (the exact largest envelope is below28MiB), measured in bytes as well as characters. Android pure worker, Android MethodChannel, Dart wire decoder and envelope validator use matching bounds. Existing hashes/password rules and one-worker cancellation remain unchanged. Native Android actual maximum-size round-trip and independent Go decryption are mandatory before acceptance; host tests alone are insufficient.

Format-specific edit limits remain unchanged:5MiB nonpresentation complex formats,20MiB presentation, existing native Markdown editor limit and existing generation Markdown save boundary. A named generation may read20MiB Markdown through a read-only/chunked path; this does not enlarge the editor. Existing schema14 uncapped chunked Markdown read must remain intact. Protected input uses28MiB stored envelope, decrypted data20MiB; no truncation.

Keep legacy source JSON64MiB per file/aggregate as an explicit separate archive admission bound. Raise decoded string bound to28MiB so full20MiB source and its envelope can be inspected; encoded string scanning is bounded by the64MiB source admission cap. Canonical original-field payload cap becomes64MiB+64KiB, preserving any admitted original JSON record including escaped source plus controlled wrapper metadata. Archives above the declared JSON budget fail before publication and never partially import. This does not claim unbounded import.

The existing16MiB Go TSV scanner is a test transport bound. Maximum-size Android/Go proof must use bounded separate raw UTF8 body/plaintext files and streaming/hash verification, avoiding a doubly base64-encoded TSV. Keep existing small public vectors/proofs immutable.

Tests: exact20MiB and+1 plaintext with UTF8/Unicode/BOM; exact GCM tag/envelope and+1; presentation native decrypt/encrypt through real channel, wrong password, oversize reject, pending/cancel and no SQL before crypto. Real SQLite20MiB read and exact hashes, admitted escaped JSON/canonical bounds, explicit smaller configured parser limits unchanged. Actual app heap/allocation behavior must be observed on NAS redroid, not assumed. Retain original APK/data restore guard and independent Go reverse proof. No activation/UI/backup readiness claim.


Chunked SQLite reader default remains20MiB, documents remain20MiB (or the existing explicit uncapped Markdown path). An explicit note caller may request the28MiB stored envelope budget; invalid limits above28MiB still fail before SQL. No default editor or plain-document permission grows implicitly.
