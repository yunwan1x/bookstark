#!/usr/bin/env python3
"""Build a BookStark APK using the pinned Wails Android host."""
import argparse
import os
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path, old, new):
    source = path.read_text(encoding="utf-8")
    if source.count(old) != 1:
        raise RuntimeError(f"Review the Wails Android template before updating {path.name}")
    path.write_text(source.replace(old, new), encoding="utf-8")


def configure_host(root, abi):
    app = root / "app"
    replace_once(app / "build.gradle", 'applicationId = "com.wails.app"',
                 'applicationId = "com.bookstark.wails"')
    replace_once(app / "build.gradle", "abiFilters 'arm64-v8a', 'x86_64'",
                 f"abiFilters '{abi}'")
    manifest = app / "src/main/AndroidManifest.xml"
    replace_once(manifest, 'android:allowBackup="true"',
                 'android:allowBackup="false" android:usesCleartextTraffic="true"')
    strings = app / "src/main/res/values/strings.xml"
    replace_once(strings, '>Wails App<', '>BookStark<')
    java = app / "src/main/java/com/wails/app/MainActivity.java"
    # The same WebView visits a user-supplied server. BookStark uses HTTP for
    # application calls, so neither origin needs access to Wails' JS bridge.
    replace_once(java,
                 '        webView.addJavascriptInterface(new WailsJSBridge(bridge, webView), "wails");',
                 '')
    start = ("                // Handle wails.localhost requests\n"
             "                if (request.getUrl().getHost() != null &&")
    replace_once(java, start, '''                if (WAILS_HOST.equals(request.getUrl().getHost()) &&
                        (!request.isForMainFrame() || !"/".equals(request.getUrl().getPath()))) {
                    return new WebResourceResponse("text/plain", "UTF-8", 403, "Forbidden",
                            java.util.Collections.emptyMap(), new java.io.ByteArrayInputStream(new byte[0]));
                }
                // Handle wails.localhost requests
                if (request.getUrl().getHost() != null &&''')
    replace_once(java, '        webView = findViewById(R.id.webview);',
                 '''        webView = findViewById(R.id.webview);
        findViewById(R.id.switch_workspace).setOnClickListener(view -> loadApplication());''')
    path_handler = app / "src/main/java/com/wails/app/WailsPathHandler.java"
    replace_once(path_handler, 'headers.put("Access-Control-Allow-Origin", "*");',
                 'headers.put("Content-Security-Policy", "frame-ancestors \'none\'");')
    layout = app / "src/main/res/layout/activity_main.xml"
    layout.write_text('''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/main_container"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:orientation="vertical">
    <Button android:id="@+id/switch_workspace"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="end"
        android:text="切换工作区" />
    <WebView android:id="@+id/webview"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1" />
</LinearLayout>
''', encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--abi", choices=["arm64-v8a", "x86_64"], default="arm64-v8a")
    parser.add_argument("--out", type=Path)
    parser.add_argument("--offline", action="store_true", help="Use the local Gradle dependency cache")
    args = parser.parse_args()
    sdk_value = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    ndk_value = os.environ.get("ANDROID_NDK_HOME")
    if not sdk_value or not ndk_value:
        parser.error("Set ANDROID_HOME and ANDROID_NDK_HOME to installed SDK and NDK directories")
    sdk, ndk = Path(sdk_value).resolve(), Path(ndk_value).resolve()
    host = {"Linux": "linux-x86_64", "Darwin": "darwin-x86_64"}.get(platform.system())
    if not host:
        parser.error("Run the Android build on Linux or macOS")
    if args.abi == "arm64-v8a":
        goarch, compiler = "arm64", "aarch64-linux-android21-clang"
    else:
        goarch, compiler = "amd64", "x86_64-linux-android21-clang"
    cc = ndk / "toolchains/llvm/prebuilt" / host / "bin" / compiler
    if not cc.is_file():
        parser.error(f"Android NDK compiler missing at {cc}")
    version_dir = Path(subprocess.check_output(
        ["go", "list", "-m", "-f", "{{.Dir}}", "github.com/wailsapp/wails/v3"],
        cwd=ROOT, text=True,
    ).strip())
    template = version_dir / "internal/commands/build_assets/android"
    out = (args.out or ROOT / "artifacts" / f"bookstark-wails-{goarch}.apk").resolve()
    with tempfile.TemporaryDirectory(prefix="bookstark-wails-android-") as scratch:
        project = Path(scratch) / "android"
        shutil.copytree(template, project)
        for p in project.rglob("*"):
            p.chmod(p.stat().st_mode | 0o200)
        configure_host(project, args.abi)
        library = project / "app/src/main/jniLibs" / args.abi / "libwails.so"
        library.parent.mkdir(parents=True)
        build_env = dict(os.environ, GOOS="android", GOARCH=goarch, CGO_ENABLED="1", CC=str(cc))
        subprocess.run(["go", "build", "-p", "2", "-trimpath", "-tags", "wails,production",
                        "-buildmode=c-shared", "-ldflags=-s -w", "-o", str(library), "."],
                       cwd=ROOT, env=build_env, check=True)
        gradle_env = dict(os.environ, ANDROID_HOME=str(sdk))
        mode = ["--offline"] if args.offline else []
        subprocess.run(["bash", "gradlew", "--no-daemon", "--max-workers=2", *mode, "assembleRelease"],
                       cwd=project, env=gradle_env, check=True)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(project / "app/build/outputs/apk/release/app-release.apk", out)
    print(f"{out} ({out.stat().st_size / 2**20:.1f} MiB)")


if __name__ == "__main__":
    main()
