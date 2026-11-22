#!/usr/bin/env python3
from pathlib import Path
from functools import partial
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
import os,subprocess,threading
app=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def do_GET(self):
  if self.path.split('?',1)[0]=='/static/pptist/app.html':
   data=(app/'assets/complex_editors/static/pptist/app.html').read_bytes()
   assert b'<head>' in data
   data=data.replace(b'<head>',b'<head><script src="/memory-storage.js"></script><script type="module" src="/memory-indexeddb.js"></script>',1)
   self.send_response(200);self.send_header('Content-Type','text/html; charset=utf-8');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
  else:super().do_GET()
 def end_headers(self):
  self.send_header('Access-Control-Allow-Origin','*')
  self.send_header('Content-Security-Policy',"default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-src 'self' blob:; worker-src 'self' blob:; base-uri 'none'; form-action 'none'; object-src 'none'")
  self.send_header('Cache-Control','no-store');super().end_headers()
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(app/'assets/complex_editors')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 env=dict(os.environ,BOOKSTARK_COMPLEX_URL=f'http://127.0.0.1:{server.server_port}')
 subprocess.run(['node',str(app/'tool/complex_editor_browser_contract.cjs')],env=env,check=True,timeout=300)
finally:server.shutdown();server.server_close()
