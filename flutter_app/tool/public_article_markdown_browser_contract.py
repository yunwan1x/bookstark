#!/usr/bin/env python3
from pathlib import Path
from http.server import ThreadingHTTPServer,SimpleHTTPRequestHandler
from functools import partial
import os,subprocess,threading,sys
app=Path(__file__).resolve().parents[1]
class Handler(SimpleHTTPRequestHandler):
 def log_message(self,*args):pass
 def end_headers(self):
  self.send_header('Access-Control-Allow-Origin','*')
  self.send_header('Content-Security-Policy',"default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src http: data: blob:; font-src 'self' data:; connect-src 'self'; frame-src 'self' blob:; worker-src 'self' blob:; base-uri http:; form-action 'none'; object-src 'none'")
  self.send_header('Cache-Control','no-store')
  super().end_headers()
server=ThreadingHTTPServer(('127.0.0.1',0),partial(Handler,directory=str(app/'assets/complex_editors')))
threading.Thread(target=server.serve_forever,daemon=True).start()
try:
 env=dict(os.environ,BOOKSTARK_COMPLEX_URL='http://127.0.0.1:'+str(server.server_port),BOOKSTARK_MARKDOWN_PROOF=sys.argv[1])
 subprocess.run(['node',str(app/'tool/public_article_markdown_browser_contract.cjs')],env=env,check=True,timeout=240)
finally:server.shutdown();server.server_close()
