#!/usr/bin/env python3
"""Build the data-only spreadsheet engine on NAS; package Android ARM64 only."""
from pathlib import Path
import os
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
CRATE = ROOT / 'native/spreadsheet_calc'

def build_android(env=None):
    env = dict(os.environ if env is None else env)
    rust = Path(env.get('BOOKSTARK_RUST_ROOT', '/vol1/1000/wy/flutter-build-tools/rust'))
    env.setdefault('CARGO_HOME', str(rust / 'cargo'))
    env.setdefault('RUSTUP_HOME', str(rust / 'rustup'))
    env.setdefault('RUSTUP_TOOLCHAIN', 'stable')
    env.setdefault('CARGO_TARGET_DIR', '/vol1/1000/wy/photos-apk-test/bookstark-flutter/spreadsheet-engine-research/target')
    cargo, rustc = rust / 'cargo/bin/cargo', rust / 'cargo/bin/rustc'
    version = subprocess.check_output([str(rustc), '--version'], env=env, text=True).strip()
    if not version.startswith('rustc 1.99.1 '):
        raise RuntimeError('Spreadsheet engine toolchain must be reviewed Rust 1.99.1')
    ndk = Path(env.get('ANDROID_NDK_HOME', '/vol1/1000/wy/photos-apk-test/relocated/photos-android-tools/sdk/ndk/28.2.13676358'))
    linker = ndk / 'toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang'
    if not linker.is_file():
        raise RuntimeError('Missing reviewed ARM64 Android NDK linker')
    env['CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER'] = str(linker)
    env['RUSTFLAGS'] = '-C link-arg=-Wl,-z,max-page-size=16384'
    subprocess.run([str(cargo), 'build', '--release', '--locked', '--target', 'aarch64-linux-android'], cwd=CRATE, env=env, check=True)
    library = Path(env['CARGO_TARGET_DIR']) / 'aarch64-linux-android/release/libbookstark_spreadsheet_calc.so'
    header = library.read_bytes()[:20]
    if header[:4] != b'\x7fELF' or struct.unpack('<H', header[18:20])[0] != 183:
        raise RuntimeError('Spreadsheet engine must be an AArch64 ELF')
    destination = ROOT / 'android/app/src/main/jniLibs/arm64-v8a/libbookstark_spreadsheet_calc.so'
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix('.so.tmp')
    shutil.copyfile(library, temporary)
    temporary.replace(destination)
    print('PASS native spreadsheet engine ARM64 ELF', flush=True)
    return destination

if __name__ == '__main__':
    build_android()
