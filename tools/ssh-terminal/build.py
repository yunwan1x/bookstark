#!/usr/bin/env python3
"""Build the standalone tool from pinned Go dependencies and BookStark assets."""
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
    "static/js/utils.js": "utils.js",
    "static/js/bs-dialog.js": "bs-dialog.js",
    "static/css/components.css": "components.css",
    "static/js/xterm/xterm.js": "xterm.js",
    "static/js/xterm/addon-fit.js": "addon-fit.js",
    "static/css/xterm/xterm.css": "xterm.css",
    "static/js/xterm/LICENSE-xterm.txt": "LICENSE-xterm.txt",
    "static/js/xterm/LICENSE-addon-fit.txt": "LICENSE-addon-fit.txt",
}


def build(output):
    subprocess.run(["go", "mod", "download"], cwd=HERE, check=True)
    output.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((HERE / "web/tool.json").read_text())
    archive = output / f"bookstark-ssh-terminal-{manifest['version']}.zip"
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
        goroot = Path(subprocess.check_output(["go", "env", "GOROOT"], text=True).strip())
        shutil.copy2(goroot / "lib/wasm/wasm_exec.js", dist / "wasm_exec.js")
        shutil.copy2(goroot / "LICENSE", dist / "LICENSE-Go.txt")
        crypto = json.loads(subprocess.check_output(
            ["go", "list", "-m", "-json", "golang.org/x/crypto"], cwd=HERE, text=True))
        shutil.copy2(Path(crypto["Dir"]) / "LICENSE", dist / "LICENSE-x-crypto.txt")
        sftp_mod = json.loads(subprocess.check_output(
            ["go", "list", "-m", "-json", "github.com/pkg/sftp"], cwd=HERE, text=True))
        shutil.copy2(Path(sftp_mod["Dir"]) / "LICENSE", dist / "LICENSE-pkg-sftp.txt")
        env = dict(os.environ, GOOS="js", GOARCH="wasm", CGO_ENABLED="0",
                   GOMAXPROCS="2", GOMEMLIMIT="350MiB")
        subprocess.run(["go", "build", "-trimpath", "-ldflags=-s -w", "-o",
                        str(dist / "ssh.wasm"), "./wasm"], cwd=HERE, env=env, check=True)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as result:
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
