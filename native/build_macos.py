#!/usr/bin/env python3
"""Cross-compile BookStark and package it as a macOS app ZIP."""
import argparse
import os
from pathlib import Path
import platform
import plistlib
import struct
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
APP = "BookStark"


def build_binary(arch, output):
    env = dict(os.environ, GOOS="darwin", GOARCH=arch, CGO_ENABLED="0")
    subprocess.run([
        "go", "build", "-trimpath", "-tags", "wails,production,purego",
        "-ldflags=-s -w", "-o", str(output), ".",
    ], cwd=ROOT, env=env, check=True)


def package_bundle(bundle, arch):
    contents = bundle / "Contents"
    executable = contents / "MacOS" / APP
    resources = contents / "Resources"
    executable.parent.mkdir(parents=True)
    resources.mkdir()
    build_binary(arch, executable)
    executable.chmod(0o755)

    # Modern ICNS supports a PNG payload for the 512x512 icon.
    icon = (ROOT / "static" / "icon-512.png").read_bytes()
    icns_image = struct.pack(">4sI", b"ic09", len(icon) + 8) + icon
    (resources / "BookStark.icns").write_bytes(
        struct.pack(">4sI", b"icns", len(icns_image) + 8) + icns_image
    )
    info = contents / "Info.plist"
    info.write_bytes(plistlib.dumps({
        "CFBundleDisplayName": APP,
        "CFBundleExecutable": APP,
        "CFBundleIconFile": "BookStark.icns",
        "CFBundleIdentifier": "com.bookstark.wails",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": APP,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "12.0",
        "NSHighResolutionCapable": True,
        "NSLocalNetworkUsageDescription": "连接局域网中的 BookStark 服务器。",
        "NSCameraUsageDescription": "在你允许后，为 BookStark 网页会议提供摄像头。 / Allow camera access for web meetings.",
        "NSMicrophoneUsageDescription": "在你允许后，为 BookStark 网页会议提供麦克风。 / Allow microphone access for web meetings.",
        "NSAppTransportSecurity": {"NSAllowsArbitraryLoadsInWebContent": True},
    }))
    info.chmod(0o644)
    (resources / "BookStark.icns").chmod(0o644)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--arch", choices=["arm64", "amd64"], default="arm64")
    parser.add_argument("--out", type=Path, help="Destination ZIP")
    args = parser.parse_args()
    out = (args.out or ROOT / "artifacts" / f"bookstark-wails-macos-{args.arch}.zip").resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".bookstark-macos-", dir=out.parent) as temp:
        scratch = Path(temp)
        bundle = scratch / f"{APP}.app"
        package_bundle(bundle, args.arch)
        if platform.system() == "Darwin":
            subprocess.run(["codesign", "--force", "--sign", "-", str(bundle)], check=True)
            subprocess.run(["codesign", "--verify", "--strict", str(bundle)], check=True)

        archive = scratch / out.name
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as zip_file:
            for path in sorted(bundle.rglob("*")):
                if path.is_file():
                    zip_file.write(path, path.relative_to(scratch))
        archive.chmod(0o644)
        archive.replace(out)
    print(f"{out} ({out.stat().st_size / 2**20:.1f} MiB)")


if __name__ == "__main__":
    main()
