# Edge TTS adapter

Protocol implementation adapted from https://github.com/lib-x/edgetts at
`d7becd9b973f78ce962061b300983da1e124290e` (MIT; LICENSE included).
Only the protocol/validation packages used by text synthesis are retained.

Local changes: internal import paths, context-aware dialing, an 8-second handshake
limit, close the WebSocket on cancellation, read size limits, and cancel/drain the
producer on writer failure. The endpoint override is private and used only by
loopback regression tests. No caller can choose a synthesis endpoint or SSML.
The service protocol contains public upstream client identifiers, not user keys.

## GEC v2 compatibility

`gecv2/` is separately licensed **LGPL-3.0-only**, adapted from
https://github.com/lew2sss/edge-tts-go-gec-v2 at
9f7432372a95fedce29e4737a051326c892c1e85 (`edge_tts/drm_v2.go`, tests),
which aligns with rany2/edge-tts 7.3.1. Its LICENSE and GPL text are included.
Changes: package name, constants inlined, Cookie exported. All source and
build instructions are distributed in this repository so recipients can modify
this component and rebuild/relink Bookstark (`python3 build.py --build`).
The surrounding lib-x adapter remains MIT. Microsoft handshake updated to
v2, Chromium 143 and per-request random MUID. Fixed double XML escaping and
reject premature WebSocket disconnects after partial audio.
