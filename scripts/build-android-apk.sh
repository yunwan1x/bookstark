#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID_HOME="${ANDROID_HOME:-/root/Android/Sdk}"
BUILD_TOOLS="${BUILD_TOOLS:-$ANDROID_HOME/build-tools/36.0.0}"
PLATFORM="${PLATFORM:-$ANDROID_HOME/platforms/android-36/android.jar}"

AAPT="$BUILD_TOOLS/aapt"
D8="$BUILD_TOOLS/d8"
ZIPALIGN="$BUILD_TOOLS/zipalign"
APKSIGNER="$BUILD_TOOLS/apksigner"

APP_ID="com.bookstark.app"
BUILD_TYPE="${BUILD_TYPE:-release}"
ANDROID_UPX="${ANDROID_UPX:-0}"
ANDROID_DIR="$ROOT/android"
SRC_DIR="$ANDROID_DIR/app/src/main"
BUILD_DIR="$ROOT/dist/android/build"
OUT_DIR="$ROOT/dist/android"
ASSET_DIR="$SRC_DIR/assets"
RES_DIR="$SRC_DIR/res"
KEYSTORE="${BOOKSTARK_ANDROID_KEYSTORE:-$OUT_DIR/bookstark-${BUILD_TYPE}-local.keystore}"
KEY_ALIAS="${BOOKSTARK_ANDROID_KEY_ALIAS:-bookstark${BUILD_TYPE}}"
KEY_PASS="${BOOKSTARK_ANDROID_KEY_PASS:-bookstark}"
UNSIGNED_APK="$BUILD_DIR/bookstark-unsigned.apk"
ALIGNED_APK="$BUILD_DIR/bookstark-aligned.apk"
FINAL_APK="$OUT_DIR/bookstark-android-arm64-${BUILD_TYPE}.apk"

for tool in "$AAPT" "$D8" "$ZIPALIGN" "$APKSIGNER" javac keytool; do
  command -v "$tool" >/dev/null 2>&1 || { echo "missing tool: $tool" >&2; exit 1; }
done
test -f "$PLATFORM" || { echo "missing Android platform jar: $PLATFORM" >&2; exit 1; }

mkdir -p "$ASSET_DIR" "$RES_DIR/mipmap-hdpi" "$RES_DIR/mipmap-mdpi" "$BUILD_DIR/classes" "$OUT_DIR"

echo "[1/6] Building Go backend for android/arm64..."
GOOS=android GOARCH=arm64 CGO_ENABLED=0 go build \
  -trimpath \
  -tags timetzdata \
  -ldflags "-s -w -X main.gitCommit=android-local" \
  -o "$ASSET_DIR/bookstark-arm64" \
  "$ROOT"
if [ "$ANDROID_UPX" = "1" ] && command -v upx >/dev/null 2>&1; then
  upx -q -1 "$ASSET_DIR/bookstark-arm64" || true
fi

echo "[2/6] Preparing Android resources..."
cp "$ROOT/static/icon-192.png" "$RES_DIR/mipmap-mdpi/ic_launcher.png"
cp "$ROOT/static/icon-192.png" "$RES_DIR/mipmap-hdpi/ic_launcher.png"

echo "[3/6] Compiling Java..."
find "$BUILD_DIR" -mindepth 1 -delete
mkdir -p "$BUILD_DIR/classes" "$BUILD_DIR/dex"
javac -source 1.8 -target 1.8 \
  -bootclasspath "$PLATFORM" \
  -d "$BUILD_DIR/classes" \
  $(find "$SRC_DIR/java" -name '*.java' | sort)

echo "[4/6] Creating dex and unsigned APK..."
"$D8" --min-api 23 --lib "$PLATFORM" --output "$BUILD_DIR/dex" $(find "$BUILD_DIR/classes" -name '*.class' | sort)
"$AAPT" package -f \
  -M "$SRC_DIR/AndroidManifest.xml" \
  -S "$RES_DIR" \
  -A "$ASSET_DIR" \
  -I "$PLATFORM" \
  -F "$UNSIGNED_APK"
cd "$BUILD_DIR/dex"
"$AAPT" add "$UNSIGNED_APK" classes.dex >/dev/null
cd "$ROOT"

echo "[5/6] Signing $BUILD_TYPE APK..."
if [ ! -f "$KEYSTORE" ]; then
  keytool -genkeypair \
    -keystore "$KEYSTORE" \
    -storepass "$KEY_PASS" \
    -keypass "$KEY_PASS" \
    -alias "$KEY_ALIAS" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -dname "CN=BookStark Android ${BUILD_TYPE},O=BookStark,C=CN" >/dev/null
fi
"$ZIPALIGN" -f 4 "$UNSIGNED_APK" "$ALIGNED_APK"
"$APKSIGNER" sign \
  --ks "$KEYSTORE" \
  --ks-key-alias "$KEY_ALIAS" \
  --ks-pass "pass:$KEY_PASS" \
  --key-pass "pass:$KEY_PASS" \
  --out "$FINAL_APK" \
  "$ALIGNED_APK"
"$APKSIGNER" verify "$FINAL_APK"

echo "[6/6] Done: $FINAL_APK"
ls -lh "$FINAL_APK"
