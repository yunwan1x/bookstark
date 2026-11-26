#!/usr/bin/env python3
"""Build the standalone Vault & 2FA BookStark tool package."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]

SHARED = {
    "static/webfonts/fa-solid-900.woff2": "fa-solid-900.woff2",
    "static/webfonts/font-awesome-license.txt": "LICENSE-font-awesome.txt",
    "static/css/components.css": "components.css",
}

VENDOR = {
    "vendor/jsQR.js": "jsQR.js",
    "vendor/LICENSE-jsQR.txt": "LICENSE-jsQR.txt",
    "vendor/qrcode.js": "qrcode.js",
    "vendor/LICENSE-qrcode.txt": "LICENSE-qrcode.txt",
}


def build(output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HERE / "web/tool.json").read_text(encoding="utf-8"))
    archive = output / f"bookstark-vault-2fa-{manifest['version']}.zip"

    with tempfile.TemporaryDirectory(prefix="vault-2fa-build-", dir=output) as stage:
        dist = Path(stage) / "package"
        shutil.copytree(HERE / "web", dist)

        for src, name in SHARED.items():
            shutil.copy2(ROOT / src, dist / name)

        for src, name in VENDOR.items():
            shutil.copy2(HERE / src, dist / name)

        css = (ROOT / "static/css/font-awesome.min.css").read_text(encoding="utf-8")
        (dist / "font-awesome.css").write_text(css.replace("../webfonts/", "./"), encoding="utf-8")

        base = (ROOT / "templates/base.html").read_text(encoding="utf-8")
        dialog = base.split('{{define "dialog-styles"}}', 1)[1]
        dialog = dialog.split("<style>", 1)[1].split("</style>", 1)[0]
        (dist / "dialog.css").write_text(dialog, encoding="utf-8")

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
    parser.add_argument("--output", type=Path, default=ROOT.parent / "artifacts/vault-2fa")
    print(build(parser.parse_args().output.resolve()))
