# BookStark Flutter

The Flutter client for BookStark. Configure the BookStark server URL in the app. This client and the backend API additions are maintained together.

## Development

Use a Flutter SDK matching the Dart constraint in pubspec.yaml. From this directory run:

```sh
flutter pub get
flutter analyze
flutter test
```

The Android build entry point is `python3 build.py --apk`. It builds an ARM64 APK and validates the bundled native libraries. Run `python3 build.py --help` for other supported targets. Generated APKs, build outputs, and device-local config remain outside version control.

Markdown editors run natively. The complex editors reuse BookStark's browser engines in an embedded WebView. Their packaged runtime assets and associated licenses are in `assets/complex_editors` and `assets/licenses`. The local re_editor package includes its license and patch description. The spreadsheet helper's Rust sources and notices are checked in. Cargo targets and generated native binaries are produced during builds.

See [Flutter rewrite designs](../docs/flutter-rewrite/README.md) and the [original rewrite plan](../docs/prototypes/flutter-rewrite-2026-11-04/rewrite-plan.md).
