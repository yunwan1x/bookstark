# PPTist integration

This directory contains a production build of [PPTist](https://github.com/pipipi-pikachu/PPTist)
at commit `2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6`.

PPTist is licensed under AGPL-3.0. The upstream license is included as
`LICENSE`. BookStark applies the bridge in `tools/pptist-bookstark.patch` so
presentation data is supplied by the parent editor and returned through
same-origin `postMessage` events. The bridge also exposes a same-origin,
read-only snapshot method so manual and automatic saves can always pull the
latest slide state after a user interaction.

When embedded in BookStark, all local image entry points call the parent
`BookStarkPPTistUploadImage` bridge. The parent uploads through BookStark's
image API (including hash deduplication for authenticated editors) and PPTist
stores the returned URL instead of embedding a base64 data URL.

BookStark embeds `app.html`, a copy of the upstream build entry. Serving
`index.html` directly would trigger Go's static-file canonical redirect and
discard the embed URL.

The application JavaScript and CSS are served locally. Optional presentation
fonts are loaded on demand from the `admin` account's versioned, public
BookStark WebDAV directory:

`/dav-public/admin/pptist/2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6/fonts/`

This keeps roughly 43 MiB of font files out of the BookStark binary and avoids a
third-party runtime dependency. Browser and system font fallbacks remain
available if a font resource cannot be reached. Run the publisher in
`cmd/pptist-font-publisher` after exporting the upstream fonts:

```sh
PPTIST_FONT_EXPORT_DIR=/tmp/pptist-fonts tools/build-pptist.sh
go run ./cmd/pptist-font-publisher \
  -db /path/to/bookstark-webdav.db \
  -source /tmp/pptist-fonts \
  -member-id 1
```

Run `tools/build-pptist.sh` from the repository root to reproduce this bundle.
