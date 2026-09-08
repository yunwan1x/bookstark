#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMIT="2bfd88fef0d721b24b3a97bd5e3c8a36cabff0c6"
FONT_PUBLIC_BASE="${PPTIST_FONT_PUBLIC_BASE:-/dav-public/admin/pptist/${COMMIT}/fonts}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/bookstark-pptist.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

git clone --filter=blob:none https://github.com/pipipi-pikachu/PPTist.git "$WORK/src"
git -C "$WORK/src" checkout "$COMMIT"
git -C "$WORK/src" apply "$ROOT/tools/pptist-bookstark.patch"
python3 "$ROOT/tools/generate-pptist-academic-templates.py" "$WORK/src"

BUN_BIN="${BUN_BIN:-$(command -v bun || true)}"
if [[ -z "$BUN_BIN" ]]; then
  echo "bun is required to build PPTist" >&2
  exit 1
fi

(
  cd "$WORK/src"
  "$BUN_BIN" install
  "$BUN_BIN" ./node_modules/vite/bin/vite.js build
)

mkdir -p "$ROOT/static/pptist"
find "$ROOT/static/pptist" -mindepth 1 -maxdepth 1 ! -name BOOKSTARK-INTEGRATION.md -exec rm -rf {} +
cp -a "$WORK/src/dist/." "$ROOT/static/pptist/"
cp "$ROOT/static/pptist/index.html" "$ROOT/static/pptist/app.html"
cp "$WORK/src/LICENSE" "$ROOT/static/pptist/LICENSE"

# Keep the editor self-hosted while loading optional slide fonts on demand from
# BookStark's versioned, public WebDAV directory. This removes about 43 MiB from
# the embedded static assets without changing PPTist's font names or fallbacks.
while IFS= read -r source_font; do
  source_name="$(basename "$source_font")"
  source_stem="${source_name%.woff2}"
  for built_font in "$ROOT/static/pptist/assets/${source_stem}-"*.woff2; do
    [[ -f "$built_font" ]] || continue
    built_name="$(basename "$built_font")"
    find "$ROOT/static/pptist/assets" -maxdepth 1 -type f -name '*.css' \
      -exec sed -i "s#\\./${built_name}#${FONT_PUBLIC_BASE}/${source_name}#g" {} +
    rm -f "$built_font"
  done
done < <(find "$WORK/src/src/assets/fonts" -maxdepth 1 -type f -name '*.woff2' | sort)

if [[ -n "${PPTIST_FONT_EXPORT_DIR:-}" ]]; then
  mkdir -p "$PPTIST_FONT_EXPORT_DIR"
  find "$PPTIST_FONT_EXPORT_DIR" -mindepth 1 -maxdepth 1 -type f -name '*.woff2' -delete
  cp "$WORK/src/src/assets/fonts/"*.woff2 "$PPTIST_FONT_EXPORT_DIR/"
fi
