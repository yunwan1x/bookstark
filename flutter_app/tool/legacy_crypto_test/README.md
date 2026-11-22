# Legacy protected content interoperability
Synthetic values only. The generator is standalone and imports no production BookStark code.
Pinned golang.org/x/crypto v0.50.0 and go.sum match the actual legacy server.
Generate in an isolated writable NAS test directory with Go 1.25+:
go run -mod=readonly .
Java tests compile the actual application Java sources plus these host tests.
Verify Java outputs in Go: go run -mod=readonly . verify-java java-vectors.tsv

The Go 8 vectors exercise exact UTF8/BOM/CRLF/NUL, empty bodies, Unicode/combining
characters, modern 2a/2b/2y prefixes, 72-byte and historical longer passwords.
The longer-password fixture uses a hash of the first 72 bytes (same Go compare
semantics) while AES/PBKDF2 uses the complete password. New passwords longer than
72 bytes are explicitly rejected, matching current Go generation.

JVM tests are not Android execution evidence. LegacyBase64 compares against the
JDK codec because java.util.Base64 requires Android API26 while the app supports24.
AES-GCM, HMAC and bcrypt work must run on a bounded worker away from Android UI.
No password, decrypted body or key is written by the production crypto helper.
Only owned temporary byte arrays are cleared; immutable Strings/JCE internal
copies cannot be claimed to be zeroized.

Primary references:
https://www.mindrot.org/projects/jBCrypt/
https://pkg.go.dev/golang.org/x/crypto/bcrypt
The unmodified jBCrypt 0.4 source and ISC notice have their own provenance file.


Maximum-size source revision (2026-11-09, pending Android acceptance): shared
crypto plaintext20MiB and wire28MiB. This primitive does not enlarge individual
editor limits. Host tests include a20MiB Unicode/BOM/CRLF round-trip and+1 reject.
The original TSV verification bound remains16MiB. For large owned synthetic
inputs use verify-files <password-file> <hash-file> <ciphertext-file> <plain-file>;
each path must be a regular bounded raw file. It reports only size and SHA,
never the supplied values. Actual Android channel/SQLite and cold-process proof
must be recorded separately before acceptance.
