#!/usr/bin/env python3
"""Own loopback-only assets/server for the immutable HTML source contract."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import os
import subprocess
import threading

app = Path(__file__).resolve().parents[1]


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def end_headers(self):
        self.send_header('Content-Security-Policy', "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-src 'self' blob:; worker-src 'self' blob:; base-uri 'none'; form-action 'none'; object-src 'none'")
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()


server = ThreadingHTTPServer(
    ('127.0.0.1', 0),
    partial(Handler, directory=str(app / 'assets/complex_editors')),
)
threading.Thread(target=server.serve_forever, daemon=True).start()
try:
    env = dict(os.environ, BOOKSTARK_COMPLEX_URL=f'http://127.0.0.1:{server.server_port}')
    subprocess.run(
        ['node', str(app / 'tool/complex_editor_source_readonly_browser_contract.cjs')],
        env=env, check=True, timeout=180,
    )
finally:
    server.shutdown()
    server.server_close()
