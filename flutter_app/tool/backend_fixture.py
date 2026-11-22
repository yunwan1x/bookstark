"""Disposable real Go API fixture. Never reads production database or credentials."""
import http.server
import json
import os
from pathlib import Path
import secrets
import socketserver
import shutil
import subprocess
import tempfile
import threading
import time
import urllib.request


def run_contract(root, env, sdk):
    parent = Path('/vol1/1000/wy/photos-apk-test/bookstark-flutter/api-fixture')
    parent.mkdir(parents=True, exist_ok=True)
    name = 'bookstark-flutter-api-' + secrets.token_hex(5)
    def docker(*args, capture=False):
        return subprocess.run(['docker', *args], check=True, text=True,
                              stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
                              stderr=subprocess.PIPE)
    image = docker('inspect', '-f', '{{.Image}}', 'bookstark-standby', capture=True).stdout.strip()
    network = json.loads(docker('network', 'inspect', 'bridge', capture=True).stdout)[0]
    gateway = network['IPAM']['Config'][0]['Gateway']
    revision = docker('inspect', '-f', '{{index .Config.Labels "org.opencontainers.image.revision"}}', image, capture=True).stdout.strip()
    source_revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root.parent, check=True, text=True, stdout=subprocess.PIPE).stdout.strip()
    if revision != source_revision:
        raise RuntimeError('Fixture image revision differs from checked-out Go source; build a matching image first')
    workspace = Path(tempfile.mkdtemp(prefix='run-', dir=parent))
    workspace.chmod(0o700)

    # This sink has no forwarding implementation. Bind only the Docker bridge,
    # accept reserved .invalid recipients, retain only a message count.
    mail_count = {'count': 0}
    mail_lock = threading.Lock()
    class MailSink(socketserver.StreamRequestHandler):
        def handle(self):
            self.request.settimeout(5)
            self.wfile.write(b'220 fixture.invalid ESMTP\r\n')
            recipient_ok = False
            for _ in range(40):
                line = self.rfile.readline(4097)
                if not line or len(line) > 4096:
                    return
                command = line.decode('ascii', errors='replace').strip()
                upper = command.upper()
                if upper.startswith(('EHLO ', 'HELO ')):
                    self.wfile.write(b'250 fixture.invalid\r\n')
                elif upper.startswith('MAIL FROM:'):
                    recipient_ok = False
                    self.wfile.write(b'250 sender accepted\r\n')
                elif upper.startswith('RCPT TO:'):
                    recipient_ok = upper.endswith('.INVALID>')
                    self.wfile.write(b'250 recipient accepted\r\n' if recipient_ok else b'550 reserved test recipients only\r\n')
                elif upper == 'DATA' and recipient_ok:
                    self.wfile.write(b'354 end with dot\r\n')
                    size = 0
                    while True:
                        body = self.rfile.readline(65537)
                        size += len(body)
                        if not body or size > 1024*1024:
                            return
                        if body == b'.\r\n':
                            break
                    with mail_lock:
                        mail_count['count'] += 1
                    self.wfile.write(b'250 fixture accepted\r\n')
                elif upper == 'QUIT':
                    self.wfile.write(b'221 bye\r\n')
                    return
                else:
                    self.wfile.write(b'250 ok\r\n')
    smtp = socketserver.ThreadingTCPServer((gateway, 0), MailSink)
    smtp.daemon_threads = True
    threading.Thread(target=smtp.serve_forever, daemon=True).start()

    active_completions = {'count': 0}
    completion_lock = threading.Lock()
    class Provider(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_GET(self):
            if self.path == '/reminder-mail-count':
                with mail_lock:
                    result = json.dumps(mail_count).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Content-Length', str(len(result)))
                self.end_headers()
                self.wfile.write(result)
                return
            if self.path != '/active-completions':
                self.send_error(404)
                return
            with completion_lock:
                result = json.dumps(active_completions).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(result)))
            self.end_headers()
            self.wfile.write(result)
        def do_POST(self):
            stopped_completion = False
            try:
                request = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
                assert request['stream'] is True
                last = request['messages'][-1]
                self.send_response(200)
                self.send_header('Content-Type', 'text/event-stream')
                self.end_headers()
                def chunk(delta, finish=None):
                    payload = {'choices': [{'index': 0, 'delta': delta, 'finish_reason': finish}]}
                    self.wfile.write(('data: '+json.dumps(payload, ensure_ascii=False)+'\n\n').encode())
                    self.wfile.flush()
                if 'COMPLETE_STOP_FIXTURE' in last.get('content', ''):
                    with completion_lock:
                        active_completions['count'] += 1
                    stopped_completion = True
                    for _ in range(120):
                        chunk({'content': '小结流式片段 '})
                        time.sleep(.1)
                elif 'COMPLETE_FIXTURE' in last.get('content', ''):
                    chunk({'content': '## 主题小结\n\n'})
                    time.sleep(.05)
                    chunk({'content': '真实接口生成的可审核草稿。'})
                    chunk({}, 'stop')
                elif last.get('content') == 'STOP_FIXTURE':
                    for _ in range(120):
                        chunk({'content': '流式测试 '})
                        time.sleep(.1)
                elif last['role'] != 'tool':
                    chunk({'tool_calls': [{'index': 0, 'id': 'fixture-call', 'type': 'function',
                         'function': {'name': 'draft_note', 'arguments': json.dumps(
                             {'title': '接口回归草稿', 'content': '# 原生 Markdown\n\n真实后端测试正文。'}, ensure_ascii=False)}}]})
                    chunk({}, 'tool_calls')
                else:
                    chunk({'content': '## 已整理\n\n请核对草稿后确认创建。'})
                    chunk({}, 'stop')
                self.wfile.write(b'data: [DONE]\n\n')
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            finally:
                if stopped_completion:
                    with completion_lock:
                        active_completions['count'] -= 1
    provider = http.server.ThreadingHTTPServer((gateway, 0), Provider)
    provider.daemon_threads = True
    threading.Thread(target=provider.serve_forever, daemon=True).start()
    password = secrets.token_urlsafe(24)
    envfile = workspace / 'fixture.env'
    envfile.write_text('\n'.join([
        'PORT=8080', 'MODE=release', 'DB_PATH=/data/bookstark.db',
        'WEBDAV_DB_PATH=/data/webdav.db', 'ADMIN_ACCOUNT=flutter-fixture',
        'ADMIN_PASSWORD='+password, 'JWT_SECRET='+secrets.token_urlsafe(40),
        'BOOKSTARK_ASSET_SECRET='+secrets.token_urlsafe(40), 'NO_PROXY='+gateway,
    ])+'\n')
    envfile.chmod(0o600)
    data = workspace / 'data'
    data.mkdir()
    try:
        docker('run', '-d', '--name', name, '--label', 'bookstark.flutter-fixture=true',
               '--memory', '512m', '--cpus', '1', '-p', '127.0.0.1::8080',
               '--env-file', str(envfile), '-v', str(data)+':/data', '-w', '/data', image)
        binding = docker('port', name, '8080/tcp', capture=True).stdout.strip()
        base = 'http://'+binding
        for _ in range(100):
            try:
                with urllib.request.urlopen(base+'/', timeout=1) as response:
                    if response.status == 200:
                        break
            except OSError:
                time.sleep(.2)
        else:
            raise RuntimeError('Isolated API fixture did not become healthy')
        manifest = workspace / 'client.json'
        manifest.write_text(json.dumps({'base': base, 'account': 'flutter-fixture',
            'smtp_host': gateway, 'smtp_port': smtp.server_address[1],
            'password': password, 'provider': f'http://{gateway}:{provider.server_port}/v1'}))
        manifest.chmod(0o600)
        test_env = dict(env, BOOKSTARK_FIXTURE_CONFIG=str(manifest))
        subprocess.run([str(sdk/'bin/flutter'), 'test', '--reporter', 'expanded', 'tool/backend_contract_test.dart'],
                       cwd=root, env=test_env, check=True, timeout=150)
        print('PASS disposable backend fixture; revision '+revision+'; fresh data only', flush=True)
    finally:
        subprocess.run(['docker', 'rm', '-f', name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        smtp.shutdown()
        smtp.server_close()
        provider.shutdown()
        provider.server_close()
        shutil.rmtree(workspace)
