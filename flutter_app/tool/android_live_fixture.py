#!/usr/bin/env python3
"""Owned empty API fixture for the Windows Android emulator; never production data."""
import json
import os
from pathlib import Path
import secrets
import select
import shutil
import signal
import socket
import socketserver
import subprocess
import threading
import time
import urllib.request

root = Path(__file__).resolve().parent.parent
parent = Path('/vol1/1000/wy/photos-apk-test/bookstark-flutter/android-live-fixture')
parent.mkdir(mode=0o700, parents=True, exist_ok=True)
work = parent / 'current'
if work.exists():
    raise SystemExit('Existing Android fixture state must be inspected first')
work.mkdir(mode=0o700)
os.umask(0o077)
name = 'bookstark-flutter-android-api-' + secrets.token_hex(5)
stopping = threading.Event()
for signum in (signal.SIGINT, signal.SIGTERM):
    signal.signal(signum, lambda *_: stopping.set())

def docker(*args):
    result = subprocess.run(['docker', *args], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode:
        raise RuntimeError('Owned Android fixture container operation failed')
    return result.stdout.strip()

class Relay(socketserver.BaseRequestHandler):
    def handle(self):
        if self.client_address[0] not in {'192.168.200.1', '192.168.200.2', '127.0.0.1'}:
            self.request.sendall(b'HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n')
            return
        try:
            with socket.create_connection(('127.0.0.1', self.server.upstream_port), timeout=10) as upstream:
                upstream.settimeout(None)
                pair = [self.request, upstream]
                while not stopping.is_set():
                    ready, _, _ = select.select(pair, [], [], 1)
                    for source in ready:
                        data = source.recv(65536)
                        if not data:
                            return
                        (upstream if source is self.request else self.request).sendall(data)
        except (OSError, ValueError):
            pass

class Bridge(socketserver.ThreadingTCPServer):
    daemon_threads = True
    allow_reuse_address = False

bridge = None
try:
    image = docker('inspect', '-f', '{{.Image}}', 'bookstark-standby')
    revision = docker('inspect', '-f', '{{index .Config.Labels "org.opencontainers.image.revision"}}', image)
    expected = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root.parent, text=True).strip()
    if revision != expected:
        raise RuntimeError('Android API image must match checked-out Go revision')
    envfile = work / 'fixture.env'
    password = secrets.token_urlsafe(24)
    envfile.write_text('\n'.join(['PORT=8080','MODE=release','DB_PATH=/data/bookstark.db',
        'WEBDAV_DB_PATH=/data/webdav.db','ADMIN_ACCOUNT=flutter-android-fixture',
        'ADMIN_PASSWORD='+password,'JWT_SECRET='+secrets.token_urlsafe(40),
        'BOOKSTARK_ASSET_SECRET='+secrets.token_urlsafe(40),'NO_PROXY=*'])+'\n')
    envfile.chmod(0o600)
    data = work / 'data'; data.mkdir(mode=0o700)
    docker('run','-d','--name',name,'--label','bookstark.flutter-android-fixture=true',
        '--memory','512m','--cpus','1','-p','127.0.0.1::8080','--env-file',str(envfile),
        '-v',str(data)+':/data','-w','/data',image)
    binding = docker('port', name, '8080/tcp')
    if not binding.startswith('127.0.0.1:'):
        raise RuntimeError('Unexpected Android fixture binding')
    local = 'http://' + binding
    for _ in range(150):
        try:
            with urllib.request.urlopen(local+'/', timeout=1) as response:
                if response.status == 200:
                    break
        except OSError:
            time.sleep(.2)
    else:
        raise RuntimeError('Android fixture did not become ready')
    bridge = Bridge(('192.168.200.2', 0), Relay)
    bridge.upstream_port = int(binding.rsplit(':', 1)[1])
    threading.Thread(target=bridge.serve_forever, daemon=True).start()
    external = 'http://192.168.200.2:' + str(bridge.server_address[1])
    config = work / 'connection.json'
    config.write_text(json.dumps({'fixture':True,'local_base':local,'server':external,
        'account':'flutter-android-fixture','password':password,'share_password':secrets.token_urlsafe(12)}))
    config.chmod(0o600)
    env = dict(os.environ, BOOKSTARK_ANDROID_FIXTURE_CONFIG=str(config),
        PUB_CACHE='/vol1/1000/wy/photos-apk-test/relocated/photos-android-tools/pub-cache',
        PUB_HOSTED_URL='https://pub.flutter-io.cn',FLUTTER_STORAGE_BASE_URL='https://storage.flutter-io.cn')
    flutter = '/vol1/1000/wy/flutter-build-tools/flutter/bin/flutter'
    subprocess.run([flutter,'test','--reporter','expanded','tool/android_live_seed_test.dart'],
        cwd=root, env=env, check=True, timeout=120)
    (work / 'state.json').write_text(json.dumps({'pid':os.getpid(),'container':name,
        'server':external,'revision':revision,'seeded':True}))
    print('READY owned empty Android fixture at '+external, flush=True)
    deadline = time.monotonic() + 4*60*60
    while not stopping.wait(1):
        if (work/'stop').exists() or time.monotonic() > deadline:
            break
finally:
    stopping.set()
    if bridge:
        bridge.shutdown(); bridge.server_close()
    subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    shutil.rmtree(work)
    print('STOPPED owned Android fixture; private runtime files removed', flush=True)
