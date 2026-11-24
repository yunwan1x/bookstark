"""Isolated WebKitGTK smoke test for native Linux loopback tool origins."""
import gi,json,os,sys

gi.require_version('Gtk','3.0')
gi.require_version('WebKit2','4.0')
from gi.repository import Gtk,WebKit2,GLib

origin=os.environ['BOOKSTARK_TEST_ORIGIN']
manager=WebKit2.UserContentManager()
manager.register_script_message_handler('toolTestProbe')
view=WebKit2.WebView(web_context=WebKit2.WebContext.new_ephemeral(),user_content_manager=manager)
window=Gtk.Window();window.set_default_size(900,650);window.add(view)
status=1

def received(_manager,result):
    global status
    data=json.loads(result.get_js_value().to_string())
    print(json.dumps(data,ensure_ascii=False),flush=True)
    if data.get('secure') and '.localhost:' in data.get('origin','') and data.get('isolated') and data.get('content')=='WebKit file bridge':
        status=0
    Gtk.main_quit()
manager.connect('script-message-received::toolTestProbe',received)
started=False

def loaded(_view,event):
    global started
    if event==WebKit2.LoadEvent.FINISHED and not started:
        started=True
        credentials=json.dumps({'account':'admin','password':os.environ['BOOKSTARK_TEST_PASSWORD']})
        view.run_javascript("fetch('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:"+json.dumps(credentials)+"}).then(r=>{if(!r.ok)throw Error('login failed');location.href='/tools/run/9200'})",None,None,None)
view.connect('load-changed',loaded)

def timeout():
    print('WebKit tool did not become ready: '+str(view.get_uri()),file=sys.stderr,flush=True)
    Gtk.main_quit();return False
GLib.timeout_add_seconds(25,timeout)
window.show_all();view.load_uri(origin+'/login');Gtk.main();window.destroy();sys.exit(status)
