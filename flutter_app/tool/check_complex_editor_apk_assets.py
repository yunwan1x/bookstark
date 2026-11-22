#!/usr/bin/env python3
"""Read-only actual APK/source closure check; no build, device or module imports."""
from pathlib import Path, PurePosixPath
from html.parser import HTMLParser
import argparse, collections, hashlib, json, re, stat, zipfile

PREFIX = 'assets/flutter_assets/assets/complex_editors/'
def digest_stream(stream):
    value = hashlib.sha256()
    while True:
        chunk = stream.read(65536)
        if not chunk:
            return value.hexdigest()
        value.update(chunk)

class HostReferences(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.paths = []
    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        raw = data.get('src') if tag == 'script' else (
            data.get('href') if tag == 'link' else None)
        if raw is not None:
            self.paths.append(raw)

def check(flutter_root, apk):
    flutter_root, apk = Path(flutter_root), Path(apk)
    root = flutter_root / 'assets/complex_editors'
    if root.is_symlink() or apk.is_symlink():
        raise ValueError('Symlink source/APK rejected')
    if not root.is_dir() or not apk.is_file():
        raise ValueError('Actual source assets and APK required')
    original_apk = apk.stat()
    paths = sorted(root.rglob('*'))
    if any(path.is_symlink() for path in paths):
        raise ValueError('Symlink asset rejected')
    files = {path.relative_to(root).as_posix(): path
             for path in paths if path.is_file()}
    if not files:
        raise ValueError('Empty source asset set')
    signatures = {name: (path.stat().st_dev, path.stat().st_ino,
                         path.stat().st_size, path.stat().st_mtime_ns)
                  for name, path in files.items()}
    source_hashes = {}
    for name, path in files.items():
        with path.open('rb') as stream:
            source_hashes[name] = digest_stream(stream)
    host = HostReferences()
    host.feed((root / 'host.html').read_text(encoding='utf-8'))
    references = set(host.paths)
    # Literal dynamically-loaded assets from all first-party root JS. Full
    # source comparison below covers vendor imports/chunks/fonts as well.
    for name, path in files.items():
        if '/' not in name and name.endswith('.js'):
            text = path.read_text(encoding='utf-8')
            references.update(re.findall(
                r'''\bscript\(\s*['"](/[^'"]+\.(?:js|css))['"]''', text))
    invalid_refs, referenced = [], set()
    for raw in references:
        relative = raw[1:] if raw.startswith('/') else ''
        parsed = PurePosixPath(relative)
        if (not relative or raw.startswith('//') or '?' in raw or '#' in raw
                or '\\' in raw or '..' in parsed.parts
                or parsed.is_absolute() or relative not in files):
            invalid_refs.append(raw)
        else:
            referenced.add(relative)
    native = flutter_root / 'android/app/src/main/kotlin/com/bookstark/bookstark_flutter/ComplexEditorView.kt'
    native_missing = []
    if native.is_file():
        match = re.search(r'private val hostFiles\s*=\s*setOf\((.*?)\)',
                          native.read_text(), re.S)
        if match is None:
            raise ValueError('Native host asset allowlist missing')
        allowed = set(re.findall(r'"([^"]+)"', match.group(1)))
        native_missing = sorted(name for name in referenced
                                if '/' not in name and name.endswith('.js')
                                and name not in allowed
                                and not name.startswith('messages-'))
    missing, changed, extra = [], [], []
    with zipfile.ZipFile(apk) as archive:
        names = archive.namelist()
        duplicates = [name for name, count in collections.Counter(names).items()
                      if count > 1]
        if duplicates:
            raise ValueError('Duplicate APK ZIP entries')
        packaged = {info.filename[len(PREFIX):]: info
                    for info in archive.infolist()
                    if info.filename.startswith(PREFIX) and not info.is_dir()}
        missing = sorted(set(files) - set(packaged))
        extra = sorted(set(packaged) - set(files))
        for name in sorted(set(files) & set(packaged)):
            info = packaged[name]
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError('Symlink APK asset rejected')
            with archive.open(info) as stream:
                actual = digest_stream(stream)
            if actual != source_hashes[name]:
                changed.append(name)
    current_files = {path.relative_to(root).as_posix()
                     for path in root.rglob('*') if path.is_file()}
    if current_files != set(files):
        raise ValueError('Source asset set changed during verification')
    for name, path in files.items():
        current = path.stat()
        if signatures[name] != (current.st_dev, current.st_ino,
                                 current.st_size, current.st_mtime_ns):
            raise ValueError('Source asset changed during verification')
    current_apk = apk.stat()
    if (original_apk.st_dev, original_apk.st_ino, original_apk.st_size,
        original_apk.st_mtime_ns) != (
            current_apk.st_dev, current_apk.st_ino, current_apk.st_size,
            current_apk.st_mtime_ns):
        raise ValueError('APK changed during verification')
    with apk.open('rb') as stream:
        apk_hash = digest_stream(stream)
    aggregate = hashlib.sha256(json.dumps(source_hashes, sort_keys=True,
        separators=(',', ':')).encode()).hexdigest()
    return {
        'passed': not (missing or changed or extra or invalid_refs or native_missing),
        'actualAPK': str(apk.resolve()), 'apkSHA256': apk_hash,
        'sourceAssetCount': len(files), 'packagedAssetCount': len(packaged),
        'sourceAssetAggregateSHA256': aggregate,
        'staticHostReferenceCount': len(host.paths),
        'staticAndLiteralDynamicReferenceCount': len(referenced),
        'missingAssets': missing, 'changedAssets': changed,
        'unexpectedAssets': extra, 'invalidHostReferences': sorted(invalid_refs),
        'missingNativeHostAllowlist': native_missing,
        'allSourceAssetsCheckedByteForByte': True,
        'deviceExecuted': False,
    }

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-root', type=Path, required=True)
    parser.add_argument('--apk', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    result = check(args.flutter_root, args.apk)
    text = json.dumps(result, indent=2) + '\n'
    if args.output:
        # A single current proof; caller owns the exact output path.
        args.output.write_text(text)
    print(text, end='')
    return 0 if result['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
