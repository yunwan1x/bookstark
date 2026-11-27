#!/usr/bin/env python3
"""Build the BookStark Remote Desktop (RDP IronRDP WASM + VNC noVNC) tool package."""
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

SHARED = {
    "static/webfonts/fa-solid-900.woff2": "fa-solid-900.woff2",
    "static/webfonts/font-awesome-license.txt": "LICENSE-font-awesome.txt",
}


def build_rdp_wasm(dist: Path) -> None:
    crate_dir = HERE / "rdp-wasm"
    env = dict(os.environ)
    env["RUSTFLAGS"] = '--cfg getrandom_backend="wasm_js"'
    subprocess.run(
        [
            "cargo",
            "build",
            "--release",
            "--target",
            "wasm32-unknown-unknown",
        ],
        cwd=crate_dir,
        env=env,
        check=True,
    )
    wasm_path = (
        crate_dir
        / "target/wasm32-unknown-unknown/release/bookstark_rdp_wasm.wasm"
    )
    subprocess.run(
        [
            "wasm-bindgen",
            "--target",
            "no-modules",
            "--out-name",
            "rdp_wasm",
            "--out-dir",
            str(dist),
            str(wasm_path),
        ],
        cwd=crate_dir,
        check=True,
    )
    # Remove unused TypeScript definitions from the runtime bundle
    for extra in ("rdp_wasm.d.ts", "rdp_wasm_bg.wasm.d.ts"):
        p = dist / extra
        if p.exists():
            p.unlink()


def build(output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HERE / "web/tool.json").read_text(encoding="utf-8"))
    archive = output / f"bookstark-remote-desktop-{manifest['version']}.zip"

    with tempfile.TemporaryDirectory(prefix="rdp-build-", dir=output) as stage:
        dist = Path(stage) / "package"
        shutil.copytree(HERE / "web", dist)

        for src, name in SHARED.items():
            shutil.copy2(ROOT / src, dist / name)

        css = (ROOT / "static/css/font-awesome.min.css").read_text(encoding="utf-8")
        (dist / "font-awesome.css").write_text(
            css.replace("../webfonts/", "./"), encoding="utf-8"
        )

        build_rdp_wasm(dist)

        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for item in sorted(dist.iterdir()):
                if item.is_file():
                    zf.write(item, item.name)

        previous = output / "package"
        if previous.exists():
            shutil.rmtree(previous)
        shutil.move(str(dist), previous)

    return archive


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=ROOT.parent / "artifacts/remote-desktop",
    )
    print(build(parser.parse_args().output.resolve()))
