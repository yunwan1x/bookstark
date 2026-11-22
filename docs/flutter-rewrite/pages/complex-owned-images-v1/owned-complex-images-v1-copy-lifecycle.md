# Owned complex images v1: copy and picker lifecycle

Retain the selected owned-complex-images-v1.png three-state layout and palette. Change wording and the real system-picker handoff only.

Normal confirmation: 图片上传到服务器后可通过地址访问。上传不会保存文档；插入后仍需明确保存。
English: Uploaded images can be accessed through their server address. Uploading does not save the document; Save is still required after insertion.

Protected confirmation: 图片上传到服务器后可通过地址访问，不受笔记密码保护。上传不会保存文档；插入后仍需明确保存。
English: Uploaded images can be accessed through their server address and are not protected by the note password. Uploading does not save the document; Save is still required after insertion.

Both use the existing initially unchecked explicit checkbox and Cancel/confirm. No extra approval flow, and no account-only/private/encrypted-image guarantee.

Existing-image selector: 服务器已有图片 / Server images. Current authenticated Go list is global to authorized users and returns no per-row member identity. Never label Only my uploads. Selection adopts a visible server URL, not evidence an unknown POST succeeded.

## System picker

Capture complete actual engine source and await existing controller checkpoint before SAF. Protected routes retain source only under their explicit memory-only contract. End the old WebView runtime before the system activity; keep account/document owner alive but never reuse retired runtime snapshot/selection.

After selection, validate exact bytes/hash/raster bounds and obtain upload consent. Durable unknown precedes the single POST. Retain a confirmed URL and reload the retained source. Button copy is 上传图片 / Upload image, followed by 插入已确认图片 / Insert confirmed image. The second explicit action captures the new runtime's actual selection/source. No guessed cursor restoration or automatic Save.

Cancel returns to retained source and sends zero POST. Unknown stays unknown after cold reopen. Choosing an existing image keeps that unknown record unchanged. Known URL storage/insertion retry sends zero POST.

## Existing-image selection

Fixed GET /api/uploads, page_size=20, 128KiB response bound. Explicit ID selection; refresh its original page and require equal ID/URL/dimensions/size before insertion. Also verify document full fingerprint, runtime generation/lease, owner and session revision. Opening the list does not grant URLs. Only explicit verified choice extends allowlist.

Use existing scrollable Material list/sheet vocabulary; generate a separate prototype before any new gallery layout. Never enable a fake selection button.

## Verified insertion boundary

HTML uses actual CM6 EditorView.findFromDOM/dispatch; richdoc uses executeImage and retained range. Other four engine insertion APIs remain pending and disabled, never generic JSON rewriting. All six may independently read bounded exact source references.
