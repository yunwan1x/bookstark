# 09/22 Unified article creation: real WebView body

Selected candidate article-create-webview-v1.png uses existing article palette: primary #6530ad, lavender #f1e8fc, background #f7f4fc, 16dp cards. No browser URL toolbar; title/labels stay existing Flutter metadata controls while all article body editing AND retained/observed review use one real Markdown WebView. Controls and Chinese wording follow the prototype; equivalent English wraps at 320dp/font2/IME. Content scrolls, action rows remain reachable. One live WebView/lease at a time.

## Production evidence
- features/public_feed/resource_create_coordinator.dart currently constructs NoteEditorPage for both note/article; main._resourceCreator has no typed delegates. This serves actual Home and public-feed create.
- features/notes/notes_page.dart new remote article Markdown bypasses onCreateMarkdown (guard !article) and falls through openNativeNoteEditor(null) → NoteEditorPage.
- features/notes/remote_markdown_creation_factory.dart rejects article deliberately, correctly protecting the note-only native wrapper. Keep this existing method note-only.
- LocalArticleCreatePage + defaultArticleCreationSurface already use real ComplexEditorBrowser Markdown. Reuse this local path, not another native editor.
- RemoteMarkdownCreationController/Vault/Transport already support collection=article, retained unknown, provenance, prepared onSubmit durability, metadata/labels brackets and no repeat POST. Existing factory migrates pre-journal null-ID drafts to pending read-only unknown. Reuse; do not invent a fresh unsubmitted state for old drafts.

## States and truthful actions
Editing: storage-only open, complete recovered input wins; one WebView Markdown generation, real snapshot/checkpoint to existing creation vault, title/labels dialog. Timer writes only draft. Explicit Save locks/captures, drains old editor writes, invokes controller once; pending marker and prepared HTTP remain authoritative.
Unknown/review: complete local draft read-only in WebView; no Save/POST/retry-create. Exact positive ID inspect only, actual owner/collection/kind/source/labels/profile checks. Switch one WebView between full device/server versions; reviewed flags bind exact fingerprint and ready runtime, reset on drift. Adoption calls existing markReviewed/adopt, never overwrites body/labels; manualExisting provenance cannot become created=true.
Known cleanup: show known ID; retryCleanup is storage-only. Known-ID open uses Root actual existing-article WebView, never NoteEditorPage. Keep retained record until CAS/flush/readback succeeds. Retirement blocks late Save/inspect/adopt.
Finished: created result requires postReceipt provenance and verified ID. ManualExisting/unknownLegacy means adopted/opened existing, not this request created it. onSaved is only an ID-refresh event.
Local: existing creation receipt+inputDigest/ID is authority. Transferred positive-ID legacy branches reopen same ID WebView; successful route boolean alone proves no creation.
Discard only canEdit/unsubmitted after editor writer retire/drain; unknown is never discarded to open a new POST lane. Preserve old vault namespaces and full drafts.

## Minimal implementation boundaries
1. Extract shared real remote creation-binding setup from existing note factory into a narrow common binding (controller + current predicate + verified legacy cleanup). Preserve existing createRemoteMarkdownCreationEditor return type and note-only guard. New article factory consumes common binding; Root duplicates no low-level HTTP.
2. New RemoteMarkdownArticleCreationPage + source coordinator use real ComplexEditorTransport with separate editor lease, then existing controller.edit/save/inspect/adopt/retryCleanup. Reuse ArticleMetadataDialog and Markdown Browser. Do not borrow LocalArticleCreationController or send JSON to Markdown.
3. ResourceCreateCoordinator typed note/article delegates return actual ResourceCreationResult; Root supplies current account/local closures. Article fallback goes through existing LocalArticleCreation or new remote WebView, never native or disabled creation. Existing note fallback stays compatible only for old callers; real production gets 08 typed note entry.
4. NotesPage article Markdown invokes actual new article callback; error/unknown never falls through to NoteEditor save. Existing IDs remain NativeResourceOpener server/local article WebViews.
5. Recovery uses same page by typed collection=article and pending marker, including old null-ID compatibility. No new prefix bypass.
6. Root main exact successor only after current full gate and synchronized final input SHA.

## Required regressions / future Native
Real widgets: Home/feed article dispatch to actual Browser; article never builds NoteEditorPage in editing/unknown/known; note still 08; cancel zero POST/SQL; timer cold exact; legacy draft unknown/zero POST; explicit Save once despite double click; CSRF retirement zero send; cleanup retry zero POST; manual adoption created=false; member/namespace/collection switch rejects late writes; real 320dp/font2/IME controls reachable.
Actual Native later: fresh pinned APK/source gates, genuine CM6 source hash + one POST/known ID + existing server WebView handoff, unknown force-stop cold no replay, original 18-table/app exact restoration. Offline mocks never count as Native.


## Owned review export and source bounds

The complete retained local draft remains authoritative until an explicit user
choice. Recovery does not make the draft editable and never repeats POST.
An explicit export action may write the full retained source through SAF.
Its capability is separate from editor import/write: private owned scope and
epoch, current native lease/generation and complete source SHA-256 are mandatory.
Public and shared readonly views never receive this capability. Picker cancel,
provider failure and native retirement preserve every old storage key.

Editable new remote Markdown articles use the existing 4 MiB wire contract.
The actual CodeMirror transaction filter rejects the entire change, including
paste or undo, when exact UTF-8 bytes exceed that limit or Unicode is malformed.
It never truncates or normalizes a BOM. A visible WebView notice states that the
change was not applied. The limit is installed while input is locked and only
decreases within the current generation.

An already oversized retained draft is never fed through the 4 MiB input DTO
or rewritten as a blank document. Up to the real engine's 20 MiB bound, its full
source can be shown readonly. A larger or malformed recovery record retains its original opaque bytes and
key. The owned export capability binds the exact retained bytes/hash separately
from a clearly labelled display notice; it does not pretend that the notice is
the original body. Exact export is bounded to 32 MiB and checks the old record
again after the picker before its first write. An even larger abnormal record
remains blocked and untouched; it is never truncated or unlocked for POST.
All implementation and tests are pending Root gates and real Native acceptance.

The retained status is shown only after actual vault CAS, native flush and
readback have succeeded. Local pending bytes or a failed checkpoint instead
show retention pending/failure. Source-lock state updates do not reschedule a
new autosave unless the actual document revision changed.
