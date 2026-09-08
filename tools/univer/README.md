# Univer browser bundle

BookStark uses the open-source Univer sheet presets at one pinned version. Build
the browser assets with:

```sh
cd tools/univer
bun install --frozen-lockfile
bun run build
```

The generated `static/js/univer/univer.js` and `univer.css` files are committed
so production does not need Node.js or Bun.

The bundled drawing preset overrides Univer's default Base64 image service.
Images are uploaded through BookStark's `/api/uploads` endpoint and workbook
snapshots persist the returned `/upload-files/...` URL. A data URL is retained
only as the in-memory insertion preview and is not written to the snapshot.

Univer is licensed under Apache-2.0. Source: https://github.com/dream-num/univer
