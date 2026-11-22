#!/usr/bin/env python3
"""NAS entry point for Flutter checks and builds. Does not start the Go service."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
import zipfile
import struct

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--contract', action='store_true', help='Run real API contracts against a disposable empty Docker fixture')
parser.add_argument('--audio-contract', action='store_true', help='Decode real MP3 through the framed HTTP pipeline before synthesis EOF, using FFmpeg in memory')
parser.add_argument('--visual-check', action='store_true', help='Run isolated browser regressions with a temporary loopback server')
parser.add_argument('--check', action='store_true')
parser.add_argument('--offline-dependencies', action='store_true', help='Use cached packages and enforce the existing pubspec.lock')
parser.add_argument('--test', action='append', help='Focus --check on one or more Flutter test paths')
parser.add_argument('--web', action='store_true')
parser.add_argument('--apk', action='store_true')
parser.add_argument('--owned-images-port', type=int, help='Owned20 fixture loopback port only')
parser.add_argument('--owned-images-run', help='Owned20 fixture unique64hex run only')
parser.add_argument('--owned-bookmarks-port', type=int, help='Owned15/16 fixture loopback port only')
parser.add_argument('--owned-bookmarks-run', help='Owned15/16 fixture unique64hex run only')
parser.add_argument('--owned-mp3-port', type=int, help='Owned speech14 fixture loopback port only')
parser.add_argument('--owned-speech-run', help='Owned speech14 fixture unique 64hex run only')
parser.add_argument('--fixture-entry', choices=['legacy-format', 'legacy-candidate', 'local-text-bytes', 'generation-content', 'generation-raster', 'generation-budget', 'candidate-review', 'speech14', 'bookmarks15-16', 'images20'], help='Isolated synthetic Android test entry; requires --apk and never promotes the fixed APK')
parser.add_argument('--emulator-apk', action='store_true', help='Removed: Android tests now use NAS redroid and ARM64 only')
parser.add_argument('--serve', action='store_true')
parser.add_argument('--visual', action='store_true', help='Build/serve the isolated UI fixture target; never an APK')
args = parser.parse_args()
if args.fixture_entry == 'speech14':
    import re
    if args.owned_mp3_port is None or not 1024 <= args.owned_mp3_port <= 65535 or not re.fullmatch('[0-9a-f]{64}', args.owned_speech_run or ''):
        parser.error('speech14 requires an owned port and unique 64hex run')
elif args.owned_mp3_port is not None or args.owned_speech_run is not None:
    parser.error('owned speech arguments require --fixture-entry speech14')

if args.fixture_entry == 'bookmarks15-16':
    import re
    if args.owned_bookmarks_port is None or not 1024 <= args.owned_bookmarks_port <= 65535 or not re.fullmatch('[0-9a-f]{64}', args.owned_bookmarks_run or ''):
        parser.error('bookmarks15-16 requires an owned port and unique64hex run')
elif args.owned_bookmarks_port is not None or args.owned_bookmarks_run is not None:
    parser.error('owned bookmarks arguments require --fixture-entry bookmarks15-16')

if args.fixture_entry == 'images20':
    import re
    if args.owned_images_port is None or not 1024 <= args.owned_images_port <= 65535 or not re.fullmatch('[0-9a-f]{64}', args.owned_images_run or ''):
        parser.error('images20 requires an owned port and unique64hex run')
elif args.owned_images_port is not None or args.owned_images_run is not None:
    parser.error('owned images arguments require --fixture-entry images20')

if args.emulator_apk:
    parser.error('Use --apk: Android tests run on NAS redroid with ARM64 APKs only; Win11/x64 testing is disabled')
if args.test and not args.check:
    parser.error('--test requires --check')
if args.fixture_entry and (not args.apk or args.web or args.visual or args.serve or args.contract or args.audio_contract or args.visual_check):
    parser.error('--fixture-entry requires --apk and cannot be combined with web/serve/contracts')

env = os.environ.copy()
sdk = Path(env.get('FLUTTER_ROOT', '/vol1/1000/wy/flutter-build-tools/flutter'))
flutter = str(sdk / 'bin/flutter')
env.setdefault('FLUTTER_STORAGE_BASE_URL', 'https://storage.flutter-io.cn')
env.setdefault('PUB_HOSTED_URL', 'https://pub.flutter-io.cn')
env.setdefault('BOOKSTARK_APK_TEST_ROOT', '/vol1/1000/wy/photos-apk-test/bookstark-flutter/unit-files')
# PDFium native-assets hooks fetch official GitHub releases through the build proxy.
env.setdefault('https_proxy', 'http://192.168.200.3:7890')
env.setdefault('no_proxy', '127.0.0.1,localhost,::1,192.168.200.2,192.168.200.3')
env.setdefault('PUB_CACHE', '/vol1/1000/wy/photos-apk-test/relocated/photos-android-tools/pub-cache')
env.setdefault('ANDROID_HOME', '/vol1/1000/wy/photos-apk-test/relocated/photos-android-tools/sdk')
env.setdefault('JAVA_HOME', '/opt/jdk-21.0.13+9')
env.setdefault('GRADLE_USER_HOME', '/vol1/1000/wy/photos-apk-test/relocated/photos-android-tools/gradle')
env.setdefault('GRADLE_OPTS', '-Dhttps.proxyHost=192.168.200.3 -Dhttps.proxyPort=7890 -Dhttp.proxyHost=192.168.200.3 -Dhttp.proxyPort=7890')
env['PATH'] = str(sdk / 'bin') + ':' + env['JAVA_HOME'] + '/bin:' + env['PATH']
def run(*command):
    if args.offline_dependencies and command[0] in {'analyze', 'test', 'build'}:
        command = (*command, '--no-pub')
    subprocess.run([flutter, *command], cwd=root, env=env, check=True)
if not args.serve and (not args.visual_check or args.check or args.web or args.apk or args.visual or args.contract):
    run('pub', 'get', *(['--offline', '--enforce-lockfile'] if args.offline_dependencies else []))
if args.check or not (args.web or args.apk or args.serve or args.visual or args.contract or args.audio_contract or args.visual_check):
    run('analyze')
    run('test', *(args.test or []))
if args.web or args.apk or args.visual:
    # Verification only: asset sync must happen explicitly before source freezing.
    subprocess.run([sys.executable, str(root / 'tool/sync_complex_editor_assets.py')], cwd=root, check=True)
if args.web:
    # This application targets JavaScript Web: secure-storage plugins still use
    # dart:html. Skip the optional Wasm dry run, not the actual JS build.
    run('build', 'web', '--no-wasm-dry-run')
if args.visual and not args.serve:
    run('build', 'web', '--no-wasm-dry-run', '--target', 'tool/notes_preview.dart', '--output', 'build/notes-preview')
if args.apk:
    from tool.build_spreadsheet_native import build_android
    build_android(env)
    fixture_target = {'legacy-format': 'tool/local_legacy_format_preview.dart', 'legacy-candidate': 'tool/legacy_candidate_probe.dart', 'local-text-bytes': 'tool/local_text_bytes_probe.dart', 'generation-content': 'tool/generation_content_probe.dart', 'generation-raster': 'tool/generation_raster_probe.dart', 'generation-budget': 'tool/generation_budget_probe.dart', 'candidate-review': 'tool/candidate_review_probe.dart', 'speech14': 'tool/speech14_native_fixture.dart', 'bookmarks15-16': 'tool/bookmarks15_navigation16_native_fixture.dart', 'images20': 'tool/images20_native_fixture.dart'}.get(args.fixture_entry)
    fixture_arguments = ['--target', fixture_target] if fixture_target else []
    if args.fixture_entry == 'speech14':
        fixture_arguments += ['--dart-define=OWNED_MP3_PORT=' + str(args.owned_mp3_port),
                              '--dart-define=OWNED_SPEECH_RUN=' + args.owned_speech_run]
    if args.fixture_entry == 'bookmarks15-16':
        fixture_arguments += ['--dart-define=OWNED_BOOKMARKS_PORT=' + str(args.owned_bookmarks_port),
                              '--dart-define=OWNED_BOOKMARKS_RUN=' + args.owned_bookmarks_run]
    if args.fixture_entry == 'images20':
        fixture_arguments += ['--dart-define=OWNED_IMAGES_PORT=' + str(args.owned_images_port),
                              '--dart-define=OWNED_IMAGES_RUN=' + args.owned_images_run]
    run('build', 'apk', '--debug', '--target-platform', 'android-arm64', *fixture_arguments)
    with zipfile.ZipFile(root / 'build/app/outputs/flutter-apk/app-debug.apk') as apk:
        abis = {name.split('/')[1] for name in apk.namelist()
                if name.startswith('lib/') and name.endswith('.so')}
        if abis != {'arm64-v8a'}:
            raise RuntimeError('APK must contain only arm64-v8a native libraries')
        with apk.open('lib/arm64-v8a/libflutter.so') as library:
            header = library.read(20)
        if header[:4] != b'\x7fELF' or struct.unpack('<H', header[18:20])[0] != 183:
            raise RuntimeError('Flutter engine must be an AArch64 ELF')
    subprocess.run([sys.executable, str(root / 'tool/check_complex_editor_apk_assets.py'),
                    '--flutter-root', str(root),
                    '--apk', str(root / 'build/app/outputs/flutter-apk/app-debug.apk'),
                    '--output', str(root / 'build/complex-editor-apk-assets-check.json')],
                   cwd=root, env=env, check=True)
    print('PASS verified ARM64-only APK and AArch64 Flutter engine', flush=True)


if args.serve:
    subprocess.run([sys.executable, '-m', 'http.server', '8099' if args.visual else '8098', '--bind', '127.0.0.1', '--directory', str(root / ('build/notes-preview' if args.visual else 'build/web'))], check=True)

if args.contract:
    from tool.backend_fixture import run_contract
    run_contract(root, env, sdk)

if args.audio_contract:
    run('test', '--reporter', 'expanded', 'tool/mp3_contract_test.dart')

if args.visual_check:
    from tool.visual_checks import run_visual_checks
    run_visual_checks(root, env)
