# Legacy upload migration — file plan and copy contract

This data-only step follows the accepted candidate15 SQL and schema14 exact-text components. It introduces no production page or activation action. Existing migration V3/V4 visual designs remain the reference.

Build an immutable upload plan from the same inspected Go export, accepted format recipe and ZIP stage, with identical source SHA256. All unresolved issues remain blocking. Every declared original and thumbnail maps to the exact staged entry and verified size/SHA; omitted, extra, changed or missing files are never silently accepted. Retain all original metadata in existing canonical records.

Allocate storage basenames by a domain-separated SHA256 of source identity and logical archive identity. Use a 32-hex attachment ID compatible with existing local attachments; detect collisions explicitly. Never use archive filenames or storage paths as destination filesystem paths. Equal logical original/thumbnail entries share one copied blob but retain every source binding. Different logical names remain distinct even with equal bytes.

Plan root-relative /upload-files/ aliases using URI-encoded individual path segments. Preserve original bodies byte-for-byte; do not rewrite Markdown, HTML or complex JSON. Percent, question and fragment characters in legacy storage paths require explicit conflict handling and block this initial plan because raw Go URL concatenation makes their interpretation ambiguous. Absolute remote URLs and original server prefixes are not implicitly trusted or fetched.

File copying, in a subsequent implementation, must allocate a new owned private child; preflight disk reserve; stream and hash bounded chunks; honor cancellation; flush/close; reopen and independently verify every destination; and clean only its allocated child on failure. Source stage symlinks/type/length changes must fail. Copy receipts bind source SHA, plan identity, file keys, sizes and exact byte hashes, with no activation or success UI receipt.

A later reviewed candidate15 schema extension will connect source upload metadata, aliases and copied blobs. Alias resolution requires the correct generation and rendering lease, path canonicalization exactly once, no filesystem path from URL, no external network fallback and no automatic executable resource permission. Existing HTML approval/sandbox and protected-content unlock rules remain in force. Copying a file does not authorize WebView execution.

No declaration of complete migration until blob copying, SQL receipts, source URL handling, engine validation, protected readers, backups and actual Android activation/restart/rollback are all verified. Current data schema14 stays active.


## Candidate15 upload observation extension

Add two candidate-only tables. legacy_import_upload_blobs maps each generated 32-hex attachment ID to source SHA, original logical ZIP name, encoded root alias, exact size and SHA. Source/logical-name and source/alias pairs are unique. legacy_import_upload_bindings preserves every source upload ID plus original/thumbnail role; composite foreign keys bind the same source to its canonical upload metadata record and blob. Original and thumbnail may share one blob, and several thumbnails may share one file.

The SQL writer must run in the same fresh-candidate transaction after canonical source metadata. Require schema15/foreign keys/UTF8, the exact source and recipe, exact upload metadata IDs, and empty upload tables. Reverify the typed private copy receipt and every file byte immediately before writing. Use UTF8 BLOB-to-TEXT binding; read back all cells and counts. Any error or cancellation must escape and roll back the whole transaction. Do not populate the normal image library with unknown MIME or category, and do not create drive records by guessing semantics.

These tables store verified observations, not a durable activation receipt. Files can still change after verification; later activation must revalidate them and perform required directory durability barriers. Current LocalStore14 and independent backup14 stay unchanged. Old accepted candidate15 APKs with the earlier draft remain immutable, distinct source snapshots.


## Runtime alias path policy, before implementation

The next data-only policy accepts URLs from the existing random HTTPS WebView origins (32-hex bookstark-local.invalid or bookstark-editor.invalid hosts). Relative requests must be root-relative. Absolute requests must match that exact isolated origin; network-path, foreign origin, credentials and other schemes are rejected. This is canonical path selection only and supplies no filesystem/network/rendering permission.

Decode each path segment exactly once with strict UTF8 while retaining every leading BOM. Reject encoded separators, backslashes, controls, dot segments, malformed encodings and second-stage percent escapes. Source paths containing percent/query/fragment already block import; decoded forms must not reintroduce them. Canonicalize by the same per-segment URI construction as the source upload plan. Query and fragment do not select different file bytes, matching HTTP file serving. No path normalization may turn a rejected traversal into an allowed alias.

Later lookup must additionally bind the active generation, source SHA, rendering lease and allowed resource MIME/approval. A canonical alias by itself never grants access, unlocks protected content, authorizes execution or falls back to network. No new production page is introduced.


## Generation-bound alias metadata lookup, before implementation

A read-only index receives trusted LocalDataPaths for a named generation, its exact already-open database path, expected source SHA, isolated-origin policy and a live rendering-lease callback. Reject legacy/unmatched paths at construction. Lookup must reject invalid URLs before SQL, require schema15, join blob/source/binding/canonical-upload metadata in one same-source query, validate SQL types and fixed hex IDs/hashes, and impose an explicit bounded resource byte limit.

Check lease liveness before and after asynchronous SQL and before returning. Closing the index retires returned references; references retain generation/source identity and expose current status, not a File, private path or network client. SQL failures fail closed without reporting driver arguments. A reference is metadata only; subsequent trusted file/MIME/approval checks and lifecycle rechecks are still required. No public-share scope is supplied such an index, and lookup never unlocks a note or grants JavaScript/file permissions.


## Passive raster byte access, before implementation

The first renderer-facing byte reader is restricted to PNG/JPEG/GIF/WebP selected by actual header bytes, never extension or imported MIME alone. SVG, CSS, JavaScript, HTML and arbitrary binary remain outside this first passive path. No network fallback or executable permission is introduced.

Require both a current source/generation-bound alias reference and an actual open GenerationContentHandle for the same generation. The private handle cannot be forged or reconstructed from list previews, and protected content requires native unlock before it exists. Resolve only the trusted generation attachments directory plus validated32-hex ID. Verify canonical generation containment, directory/file types without symlinks, bounded byte count, current lease/handle throughout async reads, final file length and SHA before returning immutable bytes. Retire during any await or file mismatch returns no bytes.

This reader does not declare complete attachment rendering or interactive-resource approval. Existing native sandbox/network/lease controls remain mandatory. Actual WebView rendering, SVG and approved script/style resources require later engine-specific wiring and regression; no new page is introduced here.


## Existing local WebView raster callback extension, before implementation

Reuse LocalHtmlBrowserPreview without changing its layout. Add an optional scoped raster loader with an explicit immutable scope key and current-content callback. It is valid only with scripts disabled and no preloaded resource list. Existing local interactive and public previews retain their defaults. A provider/scope/document change retires the old native lease; pending callback results are discarded if widget, lease, generation, provider or content is no longer current.

The native local preview accepts dynamic raster GETs only for its own random origin and /upload-files/ paths. It forwards root-relative encoded paths to the Dart raster loader, never arbitrary file paths or foreign origins. Reuse bounded native request/cache/timeout/retirement barriers, but accept only PNG/JPEG/GIF/WebP. Public resources keep their separate public URL policy; local raster mode cannot be enabled on the public view.

This is renderer wiring on the existing preview, not a new page or interactive/script permission. Native tests must prove actual image display, no inline script execution in this mode, denied foreign requests, retirement and exact original-data restoration before acceptance. Protected production routes still require their secure-window and pending-recovery adapters.

