# AI assistant speech

Completed assistant answers have an opt-in read button, pause/resume, stop,
voice and playback-speed controls. Default: Yunxi, 1×. Preferences are local
browser settings; answers and audio are not stored in localStorage/IndexedDB.
Only one answer plays per tab. Starting a new answer stops the previous one.

Integrated surfaces: homepage assistant, topic reading assistant, Markdown
preview assistant, AIComposeDialog (notes and other consumers), editor writing
panel, book chapter outline, note inline generation and topic summary/comment
inline generation. Code-only/JSON drawing output is intentionally not spoken.
Code fences, raw URLs, images and HTML executable content are stripped. No
autoplay; incomplete generation does not expose reading controls.

## Go backend

- `GET /api/ai/tts/voices`: curated Yunxi, Xiaoxiao, Aria and Guy voices.
- `POST /api/ai/tts/stream`: JSON `{text, voice}`, authenticated + AI enabled.
- At most 800 Unicode characters / 16 KiB input per call, 1 MiB audio,
  25-second deadline, 2 simultaneous calls per member and 8 globally.
- Optional `BOOKSTARK_TTS_PROXY=http://host:port` (HTTP/HTTPS proxy).
  Otherwise standard Go HTTP proxy environment settings apply.
- Edge online speech requires network access to Microsoft. The selected text
  is sent to Microsoft; this is not an offline synthesizer. No Azure key,
  Python process or extra Docker service is required.
- Microsoft can change the consumer endpoint. The vendored adapter includes
  the October 2026 GEC v2 handshake and has a live opt-in smoke test.

The wire format is newline-delimited JSON: base64 `audio` frames followed by
`done` with the exact byte count, or `error`. The browser rejects incomplete
segments. Each segment (up to 200 characters, at most 20,000 per answer) is
assembled in memory before playback; one next segment is prefetched. This is
segmented streaming, not playback from the very first audio byte. MP3 object
URLs are revoked and requests cancelled when stopped/hidden/removed or when
the page is left. No application audio files/cache are created. Service worker
never caches or replays TTS calls. No answer text or raw provider errors are
logged by the TTS handlers.

## Verification

```sh
go test -p=1 ./internal/edgetts/... ./controllers ./routers
# Playwright must be installed; CHROMIUM_PATH is optional.
node ai_speech_browser_test.cjs
node home_assistant_browser_test.cjs
# Explicitly opt in to Microsoft network test; optional proxy as above.
BOOKSTARK_TTS_LIVE=1 go test ./internal/edgetts -run TestEdgeLive -v
python3 build.py --build
```

Loopback tests cover stalled WebSocket cancellation, writer failure, partial
upstream disconnect and successful completion. Controller tests cover auth,
AI disabled, bounds, concurrency, deadline and error framing. Chromium tests
cover desktop/mobile, Chinese/English, no autoplay, pause/resume, replacement,
stop/page leave/removal, truncated audio and completed-only assistant controls.
Optional `BOOKSTARK_TTS_FIXTURE` writes a synthetic test MP3 for decoder checks;
this is a test-only switch, never used by the application. `TTS_MP3` supplies
that test fixture to the browser test. Physical speaker output has not been
verified automatically.

Third-party source and notices: `internal/edgetts/UPSTREAM.md` and
`/static/licenses/ai-speech.txt` (embedded in production builds).
