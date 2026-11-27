#!/usr/bin/env python3
"""Build the standalone NavNotes (随手导航台) BookStark tool package."""
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
}


def build(output: Path) -> Path:
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HERE / "web/tool.json").read_text(encoding="utf-8"))
    archive = output / f"bookstark-nav-notes-{manifest['version']}.zip"

    with tempfile.TemporaryDirectory(prefix="nav-notes-build-", dir=output) as stage:
        dist = Path(stage) / "package"
        shutil.copytree(HERE / "web", dist)

        for src, name in SHARED.items():
            shutil.copy2(ROOT / src, dist / name)

        css = (ROOT / "static/css/font-awesome.min.css").read_text(encoding="utf-8")
        (dist / "font-awesome.css").write_text(css.replace("../webfonts/", "./"), encoding="utf-8")

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
    parser.add_argument("--output", type=Path, default=ROOT.parent / "artifacts/nav-notes")
    print(build(parser.parse_args().output.resolve()))
