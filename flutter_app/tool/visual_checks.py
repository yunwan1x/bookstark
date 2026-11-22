"""Run app and deterministic fixture pages on short-lived private HTTP servers."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import threading


def run_visual_checks(root, env):
    test_env = dict(env)
    names = test_env.get('BOOKSTARK_VISUAL_SCRIPTS', 'auth,notes,attachments,articles,assistant,tasks,books,speech,bookmarks,navigation,topics,labels,search,images,drive,public_feed,public_shares,share_edit,sharing,public_notes,profile,account_security,reminders,background,credentials,trash').split(',')
    if not names or any(name not in {'auth', 'notes', 'attachments', 'articles', 'assistant', 'tasks', 'books', 'speech', 'bookmarks', 'navigation', 'topics', 'labels', 'search', 'images', 'drive', 'public_feed', 'public_shares', 'share_edit', 'sharing', 'public_notes', 'profile', 'account_security', 'reminders', 'background', 'credentials', 'trash'} for name in names):
        raise ValueError('Unknown visual regression script')
    module = test_env.setdefault('PLAYWRIGHT_MODULE', '/vol1/1000/wy/photos-apk-test/bookstark-flutter/browser-tools/node_modules/playwright-core')
    browser = test_env.setdefault('CHROMIUM_PATH', '/root/.cache/ms-playwright/chromium-1243/chrome-linux64/chrome')
    if Path(module).is_absolute() and not Path(module).is_dir():
        raise RuntimeError('Install the isolated Playwright dependency described in docs/flutter-rewrite/validation/browser-tests.md')
    if not Path(browser).is_file():
        raise RuntimeError('Set CHROMIUM_PATH to an installed Chromium executable')
    class QuietHandler(SimpleHTTPRequestHandler):
        def log_message(self, *_):
            pass
    servers = []
    origins = {}
    try:
        targets = {'app' if name == 'auth' else 'fixture' for name in names}
        for target in targets:
            output = root / ('build/web' if target == 'app' else 'build/notes-preview')
            if not (output / 'index.html').is_file():
                raise RuntimeError('Build both targets with ./build.py --web --visual')
            server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(output)))
            servers.append(server)
            threading.Thread(target=server.serve_forever, daemon=True).start()
            origins[target] = f'http://127.0.0.1:{server.server_port}'
        for name in names:
            test_env['BOOKSTARK_VISUAL_URL'] = origins['app' if name == 'auth' else 'fixture']
            filename = 'visual_smoke.cjs' if name == 'auth' else f'{name}_visual_smoke.cjs'
            subprocess.run(['node', f'tool/{filename}'], cwd=root, env=test_env, check=True, timeout=180)
        print(f'PASS {len(names)} browser regression scripts; temporary servers close automatically', flush=True)
    finally:
        for server in servers:
            server.shutdown()
            server.server_close()
