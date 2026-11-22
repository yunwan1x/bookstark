# Candidate15 protected content repository contract

This data-only repository precedes any new production protected-content page or adapter. Active LocalStore and backup14 remain unchanged. Named candidate15 generation paths must exactly match the supplied already-open owned database; the current generation/rendering lease and shared LocalDataMaintenance gate govern every operation. No source Go database is opened as a current store.

Metadata/list reads never select protected bodies or hashes for UI. Body search is restricted to unprotected records; protected previews are empty, including legacy hash-protected plaintext. Editor type is explicit. Read complete bodies in bounded raw UTF8 chunks, preserving all BOMs and CRLF. Password-free open of protected content returns locked metadata only. Unlock uses the existing native bcrypt/GCM worker and cancellation API, then rereads the stored baseline before publishing plaintext.

Return an ephemeral handle tied to repository/generation and exact revision, title, labels JSON, editor type, hash and stored-body digest. The handle is not serializable and does not expose its password/hash/ciphertext. Closing/background/generation retirement clears held plaintext/password and cancels pending native work; late results cannot publish a new handle. UI must secure its window before requesting/exposing passwords and retire every plaintext reference before restoring screenshots.

Saving will require an active handle, exact baseline comparison inside the transaction and a positive independent revision counter. Preserve source legacy_version and unrelated source metadata. Protected body changes are encrypted with the existing password hash before SQL; new content/title uses exact UTF8 binding. Reject revision overflow, format/label/title errors and deleted/type/collection changes. Never reuse server legacy_version or timestamp as the CAS counter. An uncertain post-write result requires read-only reconciliation, never automatic replay.

No UI may call saving until encrypted pending recovery is durable; passwords must not enter drafts, logs or result JSON. Canonical historical source metadata remains the exact private original under the existing migration contract, so this component does not claim whole-database encryption. Existing source plaintext compatibility and canonical backups need explicit protection/export review before final activation.

Current native crypto/plaintext limits are5MiB/8MiB; presentations allow20MiB in their editor. This source-contract mismatch remains a release blocker and must be reconciled with actual Android tests before full migration is declared. No unsupported source is silently truncated or activated.

