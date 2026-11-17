# CCTV live metadata

BookStark serves `GET /api/cctv-live/resolve?channel=cctv8k|cctv164k` directly from Go. The endpoint returns `{url, transform}` and never fetches playlists, video segments, or arbitrary caller-supplied URLs. No Node.js process, SSH tunnel, extra listener, or Caddy special route is required.

The implementation reproduces the previously tested anonymous official web-client auth → token → live metadata flow using Go's standard library. It does not accept account cookies or paid channel credentials. Only the two fixed channels and fixed official metadata hosts are used. Redirects and outbound proxy environment variables are disabled for this flow, so deployment uses its own network exit.

Requests for the same channel share an upstream call; responses are cached for 30 seconds (failures for 5 seconds), with at most two upstream operations. The shared operation times out after 15 seconds and is cancelled when its last consumer disconnects. JSON responses are capped at 1 MiB. Responses use `Cache-Control: no-store`; errors omit tokens, playback URLs and raw upstream messages. Region/copyright denial returns HTTP 403 with `REGION_OR_COPYRIGHT_RESTRICTED`.

The existing CCTV article v3.1.2 deliberately keeps these two channels as official-site links. Deploying this backend does not edit article content or enable them automatically. A later NAS migration can reconnect the same-origin browser resolver to this endpoint without a tunnel. NAS success depends on the actual network exit and upstream permissions; moving the application is no guarantee of unrestricted access.

Tests: `go test ./services/cctvlive`. Protocol golden vectors are from the previous runtime-tested JS implementation. Tests also cover the three official metadata stages, region errors, input validation, cache/deduplication, cancellation and timeout.
