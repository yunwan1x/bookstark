#!/usr/bin/env python3
"""Build the standalone SSH + SFTP + WebDAV tool from Rust WASM and BookStark assets."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RUST_DIR = HERE / "rust-wasm"
SHARED = {
    "static/webfonts/fa-solid-900.woff2": "fa-solid-900.woff2",
    "static/webfonts/font-awesome-license.txt": "LICENSE-font-awesome.txt",
    "static/js/utils.js": "utils.js",
    "static/js/bs-dialog.js": "bs-dialog.js",
    "static/css/components.css": "components.css",
    "static/js/xterm/xterm.js": "xterm.js",
    "static/js/xterm/addon-fit.js": "addon-fit.js",
    "static/css/xterm/xterm.css": "xterm.css",
    "static/js/xterm/LICENSE-xterm.txt": "LICENSE-xterm.txt",
    "static/js/xterm/LICENSE-addon-fit.txt": "LICENSE-addon-fit.txt",
}


def strip_wasm_custom_sections(wasm_path, drop_names):
    data = wasm_path.read_bytes()
    out = bytearray(data[:8])
    i = 8
    n = len(data)
    while i < n:
        sec_start = i
        sid = data[i]
        i += 1
        sz, shift = 0, 0
        while True:
            b = data[i]
            i += 1
            sz |= (b & 0x7F) << shift
            if not (b & 0x80):
                break
            shift += 7
        payload_start = i
        sec_end = payload_start + sz
        drop = False
        if sid == 0:
            j = payload_start
            nlen, shift = 0, 0
            while True:
                b = data[j]
                j += 1
                nlen |= (b & 0x7F) << shift
                if not (b & 0x80):
                    break
                shift += 7
            name = data[j : j + nlen]
            if name in drop_names:
                drop = True
        if not drop:
            out.extend(data[sec_start:sec_end])
        i = sec_end
    wasm_path.write_bytes(out)


def find_wasm_bindgen():
    for cand in [
        Path("/root/.local/wb130/bin/wasm-bindgen"),
        Path(shutil.which("wasm-bindgen") or ""),
    ]:
        if cand.is_file():
            out = subprocess.check_output([str(cand), "--version"], text=True).strip()
            if "0.2.130" in out:
                return str(cand)
    return shutil.which("wasm-bindgen") or "wasm-bindgen"


def build(output):
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HERE / "web/tool.json").read_text())
    archive = output / f"bookstark-ssh-terminal-{manifest['version']}.zip"

    # Build Rust WASM release binary (russh + russh-sftp + rustls WebDAV)
    rust_env = dict(os.environ, RUSTFLAGS='--cfg getrandom_backend="wasm_js"')
    subprocess.run(
        ["cargo", "build", "--target", "wasm32-unknown-unknown", "--release"],
        cwd=RUST_DIR,
        env=rust_env,
        check=True,
    )
    wasm_raw = RUST_DIR / "target/wasm32-unknown-unknown/release/bookstark_ssh_wasm.wasm"

    # Fresh staging prevents stale output or test credentials entering a ZIP.
    with tempfile.TemporaryDirectory(prefix="ssh-build-", dir=output) as stage:
        dist = Path(stage) / "package"
        shutil.copytree(HERE / "web", dist)
        for source, name in SHARED.items():
            shutil.copy2(ROOT / source, dist / name)
        css = (ROOT / "static/css/font-awesome.min.css").read_text()
        (dist / "font-awesome.css").write_text(css.replace("../webfonts/", "./"))
        base = (ROOT / "templates/base.html").read_text()
        dialog = base.split('{{define "dialog-styles"}}', 1)[1]
        dialog = dialog.split("<style>", 1)[1].split("</style>", 1)[0]
        (dist / "dialog.css").write_text(dialog)

        wb = find_wasm_bindgen()
        subprocess.run(
            [
                wb,
                "--target", "no-modules",
                "--no-typescript",
                "--out-dir", str(dist),
                "--out-name", "ssh_wasm",
                str(wasm_raw),
            ],
            check=True,
        )

        # Strip non-runtime custom sections (e.g. "name", "producers") to shrink WASM by ~750 KB.
        bg_wasm = dist / "ssh_wasm_bg.wasm"
        strip_wasm_custom_sections(bg_wasm, {b"name", b"producers"})

        # Optional wasm-opt size pass if installed
        wasm_opt = shutil.which("wasm-opt")
        if wasm_opt:
            subprocess.run([wasm_opt, "-Oz", "-o", str(bg_wasm), str(bg_wasm)], check=True)

        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as result:
            for file in sorted(dist.iterdir()):
                result.write(file, file.name)
        previous = output / "package"
        if previous.exists():
            shutil.rmtree(previous)
        shutil.move(str(dist), previous)
    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT.parent / "artifacts/ssh-terminal")
    print(build(parser.parse_args().output.resolve()))
