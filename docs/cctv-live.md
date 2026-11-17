# Official live metadata

BookStark serves `GET /api/cctv-live/resolve?channel=<key>` directly from Go. The fixed allowlist contains the two existing CCTV UHD channels and 33 provincial satellite channels. The endpoint returns `{url, transform}` and never fetches playlists, video segments, or caller-supplied URLs. Browser video traffic goes directly to the official CDN. No Node process, NAS tunnel, extra listener, or Caddy route is needed.

The anonymous official web-client auth → token → live metadata flow uses Go's standard library. It accepts no account cookies or paid credentials. Only fixed channel IDs and official metadata hosts are used. Redirects and outbound proxy environment variables are disabled; the deployment server uses its own network exit.

Satellite keys: zjws, hnws, jsws, dfws, bjws, hbws, gdws, gxws, hljws, hnws2, cqws, szws, scws, henanws, fjdnhz, gzhws, jxws, lnws, ahws, hbws2, sdws, tjws, jlws, shanxiws, nxws, nmgws, ynws, shanxiws2, qhws, gsws, btws, xzws, xjws. Existing keys: cctv8k, cctv164k.

IDs were checked against the official current navigation on 2026-11-17: `https://capi.yangshipin.cn/api/oms/pc/navigation/home_top_nav` points to `https://capi.yangshipin.cn/api/oms/pc/page/PG00000004`. The protobuf TvChannelListData contains pid and streamId. Xinjiang now uses streamId 2050898603 with pid 600152138; the old streamId 2019927403 is rejected. No route accepts arbitrary IDs.

Requests for the same channel share an upstream call. Successes are cached for 30 seconds and failures for 5 seconds, with at most two upstream operations. The 15-second operation is cancelled when its last consumer disconnects. JSON responses are capped at 1 MiB. Responses use Cache-Control: no-store; errors omit tokens, playback URLs and raw upstream messages. Region/copyright denial remains HTTP 403 with REGION_OR_COPYRIGHT_RESTRICTED.

Signed addresses are short-lived. The frontend resolves them on connection instead of embedding addresses in article HTML, and reacquires metadata after eligible playback failures. The two CCTV UHD entries retain their existing official-site link behavior; extending this API does not automatically change them.

Validation: `go test ./services/cctvlive ./routers` and `go vet ./services/cctvlive`. Protocol golden vectors, official flow fixtures, validation, deduplication, timeout and cancellation tests are retained. Live metadata was checked from the actual www server exit; browser playback evidence and release receipts are stored with the frontend release on NAS. Metadata success alone is not proof of playback or regional availability.
