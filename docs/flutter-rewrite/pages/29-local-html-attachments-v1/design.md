# Local HTML images and attachments v1 — design and protocol

Selected structural prototype: local-html-attachments-v1.png, generated using
builtin image_gen. This is design only, never an acceptance screenshot.
Style: primary #6530AD, lavender #F1E8FC, background #F7F4FC, white radius16
cards, 16dp gutters, scrollable native control sheets around the real HTML
CodeMirror/interactive-preview WebViews. Keep sheets/actions usable at320dp,
text scale2 and IME. Chinese/English copy is equivalent.

## Proven existing paths and genuine gaps

- LocalHtmlResourcesRepository._owned requires positive active note ID, exact
  collection note/article, editor_type html and the captured LocalStore.
- Existing html_preview_resources binds note ID + canonical relative path +
  actual local_drive_nodes node ID + approved SHA256. replace uses baseline CAS,
  preserves body, and does not delete original drive files. A changed hash must
  be explicitly approved again.
- Existing LocalHtmlPreviewDocument accepts32 resources,5MiB each,20MiB total;
  HTML/CSS/JS/JSON/text/raster/SVG/fonts/audio/video. PDF and arbitrary files are
  NOT render resources. Do not insert a producer row that load cannot consume.
- Existing LocalAttachments owns bookstark-attachment:///32hex/encodedName in
  the current LocalDataPaths.attachments directory. read is bounded; add refuses
  protected data. It is separate from the drive library and account uploads.
- Existing full preview is LocalHtmlPreviewHost -> LocalHtmlPreviewPanel ->
  LocalHtmlBrowserPreview -> Native LocalHtmlPreviewView: owned in-memory
  allowlist, blocked network/file/content access, explicit script-resource
  approvals. Existing resource import/approval does not insert an HTML tag.
- Existing source is real private HTML CodeMirror via ComplexEditorBrowser.
  Native insertImageSnapshot is account-owned-mode-only: do NOT borrow that
  account factory to enable local insertion.
- Existing local preview externalLink accepts HTTP(S), not the custom attachment
  scheme. Existing bookstark-attachment image refs and ordinary file links need
  an explicit local adapter and verified handoff.

## Three prototype states

1. Add local image or file: source remains complete and unchanged; device picker
   or existing local file library. Copy/import is a user asset operation, not a
   body save. Say 文件留在当前本地空间，不上传服务器 / Files remain in this local
   space; nothing is uploaded. Existing drive-library imports may create a
   library row/file immediately; never claim zero SQL for that operation.
2. Imported/selected: show actual bounded filename/MIME/size and raster dimensions
   after validation. Only one actual item is selected. Inserting a raster yields
   插入图片 / Insert image; a non-render file yields 插入附件链接 / Insert
   attachment link. Native SAF retires the old runtime; on return acquire a new
   current runtime and require a new explicit insertion at its actual selection.
   Never reuse a pre-picker range. Merely selecting/importing does not mutate
   body. Insert checkpoints the exact resulting draft; explicit Save alone
   updates the HTML note/article body/labels using its existing CAS.
3. Full local interactive preview: render only approved local image/resource
   bytes. File links do not expose PDF/arbitrary bytes to scripts. A real user
   gesture selects a single source-referenced attachment, shows its actual
   filename/size, awaits preview retirement ACK, then opens/shares that file.
   Fast return needs explicit reload; no old runtime revives.

## Ownership and resource protocol

Capture an immutable local identity:
canonical database path + data-layout/maintenance identity + note ID +
collection + html kind + baseline full fingerprint + runtime lease/generation
+ actual current draft source SHA256. Bind operation currentness to Root scope
owner epoch and the captured controller/repository, never dynamic widget.repo.

All operations must check currentness before and after every await. Repository
work (actual file/DB/read/decode/share work) is tracked and retireAndDrain waits
for it; it does not wait for the human picker/sheet/Navigator lifetime. Owner
transition retires Native grants before enabling another owner.

For existing drive-relative resources retain their exact approved node/hash
bindings. Raster import/insertion may reuse that actual local-resource lane.
For existing bookstark-attachment image refs, read only exact statically present
img/src refs from the captured current source in the current local attachments
directory, validate real raster MIME/dimensions/pixel/byte bounds and freeze
immutable bytes/hash per preview. No HTTP fallback through LocalAttachments
readPublic is allowed in this local broker.

If an alias is required for Native in-memory URLs, transform only the preview
projection's matching attributes, never the persisted original HTML. Reserved
alias collisions fail closed. Merge limits with existing drive resources:
32 combined resources,5MiB raster per item,20MiB combined bytes. Arbitrary CSS,
script strings or guessed file IDs do not authorize attachment reads.

Generic attachment links use a distinct exact URI allowlist and typed native
user-gesture event, not render-resource bytes. Validate current source ref,
canonical attachment ID/name, actual immutable bytes/hash, current lease and
owner before external handoff. Public/account factories are never involved.
Do not widen HTML resource MIME to PDF merely to make link opening work.

Local protected HTML cannot silently store plaintext attachments. Preserve the
existing encrypted-storage-required refusal and show an honest unavailable
state. Schema15 original-generation assets belong to C's separate exact-reader
adapter; no active16 LocalStore or attachments path impersonation.

## Required regression and real Native work

- Current schema16 and reconstructed schema14 preserve source BOM/CRLF/Unicode,
  original IDs/timestamps/resource bindings and all original tables through
  ordinary upgrade/open.
- Existing relative drive image and existing attachment URI display from actual
  local files; unsupported or changed/cross-space data fails without rewriting
  source. No HTTP/auth/account transport call exists.
- Real source snapshot insertion at current range -> durable recovery draft ->
  explicit Save exactly once; cancellation/no-selection/source drift/retirement
  never changes body. Unknown/pending save stays readonly.
- PDF/arbitrary file is a link only; JS/fetch cannot read its bytes, a forged or
  non-user-gesture link cannot open it. Actual share awaits old close ACK and
  returning requires fresh runtime.
- Retire during picker/read/decode/file copy/share, account replacement and
  reused State reject stale IDs/callbacks and drain actual work.
- Combined byte/item/decode bounds and alias collisions fail safely.
- EN320/font2/IME genuine widget controls, then future ARM64 redroid actual local
  image render/JS isolation/attachment open/fast return/exact restore. No mocks
  are Native evidence. No acceptance snapshots are accumulated.

## Implementation refinement: local raster URLs

The current external draft uses a separate localAttachmentRaster callback and
an explicitly enabled bookstark-attachment image scheme in the owned local
preview, instead of rewriting saved HTML or broadening the older dynamicRaster
lane. The older generation-candidate raster lane remains scripts-disabled and
/upload-files-only. Native rejects the new capability on public previews and
accepts only GET subresources with the exact local attachment URI grammar.
Dart additionally requires a statically present img/src in the frozen source;
comments, script strings and ordinary file links grant nothing.

Actual LocalHtmlPreviewHost now has an external-draft successor that captures
the store/collection/ID before awaits, binds the real HtmlEditorController
baseline fingerprint and current scope from openLocalHtmlNote, and loads the
ordinary-space attachment directory. The local preview wrapper registers its
actual IO drain in HtmlBrowserSession retirement, so opening another account's
browser cannot pass the close barrier while old reads remain active.

This is not Native evidence. WebView interception/CSP handling of the custom
image scheme must be verified on the future ARM64 candidate. Failure must stay
unavailable; it must not fall back to file/content/network or account factory.
Insertion and ordinary attachment link handoff remain unfinished at this stage.
