# 33 ordinary-local rich document images: design before implementation

Reuse the actual rich-document WebView and its original canvas-editor toolbar.
Layout contract: BookStark docs/flutter-rewrite/pages/complex-editors-webview.md
(section 29–34; original complex-webview-v1 prototype), together with the selected
local-html-attachments-next-patch/design/local-html-attachments-v1.png three-state
attachment layout. No new page composition or synthetic Flutter rich-text body.
Purple #6530AD, pale #F1E8FC/#F7F4FC, 16dp cards/spacing remain the selected design.

Rich-document differences:
- Existing local note/article positive ID only; kind must be richdoc. Book
  document extension waits its independent body-only writer/source fingerprint.
- Add local image chooser uses real local drive library/device SAF and exact file
  bytes; it never invokes account upload or generation15 original asset readers.
- Only validated raster images (PNG/JPEG/GIF/WebP) can be inserted. PDF/generic
  attachment insertion is not advertised until the real canvas-editor hyperlink/
  attachment command is separately verified.
- The picture uses the actual current canvas-editor getRange tuple, including
  main/header/footer and any table/cell range. After system picker closes the old
  runtime, the user explicitly Reloads and selects a new current range. Never
  restore a stale range. Library choice does not itself insert.
- Explicit Insert calls actual instance.command('executeImage', value/width/
  height), confirms exported source changed, and durably checkpoints the editor.
  Original Save remains the only same-ID SQL mutation. No raw JSON insertion.
- Read only and unknown/conflict/cleanup modes cannot import or insert.
- Local images are source-reference allowlisted and source/kind/owner/epoch/lease
  bound, 32 references, 5MiB/image, 20MiB total, 16384 dimensions/32MiPixels.
  Native receives no file paths or account cookies. Files referenced elsewhere,
  HTTP/network URLs and cross-owner late callbacks must be rejected.
- Account/local-space switch awaits native revoke/close ACK plus actual local IO
  drain; late picker completion is inert. Human picker time is not joined IO.
- Ordinary local paths only: sealed generation15/protected memory/public/shared
  and remote-owned resource capabilities stay distinct and must not gain this
  mode. Their independent readers and permissions remain unchanged.

Audited production evidence (current):
open_local_complex_note.dart 291–300 passes LocalAttachments only for Markdown
articles. LocalComplexNotePage 1913–1915 has the same gate. Browser 440–463 opens
LocalMarkdownResources only when that value is supplied. Native asset() 540–551
has the matching localMarkdownImages /__bookstark_local_image route; default
WebView allowFileAccess/contentAccess=false and blockNetworkLoads=true.
Thus ordinary-local richdoc source images have no actual loader currently.

Real engine evidence:
host.js imageSelection richdoc uses instance.command('getRange') and validates
zone/table tuple; insertImageSnapshot invokes executeImage with bounded size.
Packaged canvas-editor executeImage binds adapter.image(), which synchronously
inserts an IMAGE element via insertElementList and returns an element ID.
No new alternative editor or speculative vendor API is required.

Implementation must not be called complete until actual fresh ARM64 WebView
range/image/export/explicit Save/cold reopen and owner-switch tests execute.
Current phase: design and API audit only, no runtime source changed.

Implementation refinement: existing images are the exact captured body's image
elements plus actual background.image and type=image watermark.data fields;
separately selected images require fresh local SHA/source verification before
approval. A same-resource Save ACK does not widen that body's original grants;
a new runtime receives a new full-fingerprint/source identity. Resource discovery
overflow fails closed for images but keeps the valid original body editable and
warns, rather than rejecting or replacing the document. Before executeImage the
host counts the actual getRangeParagraph inherited table/list/title/area metadata
and full merged getSource bytes, then reserves 2048 bytes for the generated element envelope, rejecting a
near-limit transaction whole; no old source truncation or direct JSON insertion.
