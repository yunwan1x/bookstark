const { test } = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const source = fs.readFileSync(__dirname + '/static/js/utils.js', 'utf8');
const helpers = source.slice(source.indexOf('var csrfRefreshPromise'), source.indexOf('/** CSRF-protected fetch'));
function setup(cookie, handler) {
    const env = { document: {cookie}, location: new URL('https://books.test/notes'), URL, Headers, Date };
    env.fetch = (url, opts) => handler(url, opts, env);
    vm.createContext(env);
    vm.runInContext(helpers, env);
    return env;
}
test('stale HTML header is replaced by the live cookie', async () => {
    const env = setup('csrf_token=current', (url, opts) => {
        assert.equal(opts.headers.get('X-CSRF-Token'), 'current');
        return Promise.resolve(new Response('{}'));
    });
    await env.fetchWithCurrentCSRF('/api/blogs', {method:'POST', headers:{'X-CSRF-Token':'stale'}});
});
test('expired cookie is refreshed once for concurrent submissions', async () => {
    let refreshes = 0, writes = 0;
    const env = setup('', async (url, opts, e) => {
        if (url.startsWith('/api/csrf-token')) {
            refreshes++;
            assert.equal(opts.cache, 'no-store');
            await new Promise(r => setImmediate(r));
            e.document.cookie = 'csrf_token=renewed';
        } else {
            writes++;
            assert.equal(opts.headers.get('X-CSRF-Token'), 'renewed');
        }
        return new Response('{}');
    });
    await Promise.all([env.fetchWithCurrentCSRF('/api/blogs', {method:'POST'}), env.fetchWithCurrentCSRF('/api/blogs', {method:'POST'})]);
    assert.equal(refreshes, 1);
    assert.equal(writes, 2);
});
test('middleware rejection retries once, preserving body', async () => {
    let writes = 0;
    const env = setup('csrf_token=first', async (url, opts, e) => {
        if (url.startsWith('/api/csrf-token')) {e.document.cookie='csrf_token=second'; return new Response('{}');}
        writes++;
        assert.equal(opts.body, 'original body');
        if (writes === 1) return new Response('{"csrf_error":true}', {status:403});
        assert.equal(opts.headers.get('X-CSRF-Token'), 'second');
        return new Response('{"csrf_error":true}', {status:403});
    });
    assert.equal((await env.fetchWithCurrentCSRF('/api/blogs', {method:'POST',body:'original body'})).status, 403);
    assert.equal(writes, 2);
});
test('general permission failures and network errors are never replayed', async () => {
    for (const networkError of [false,true]) {
        let writes=0;
        const env=setup('csrf_token=current', async()=>{writes++;if(networkError)throw Error('network');return new Response('{"code":403}',{status:403});});
        if(networkError) await assert.rejects(env.fetchWithCurrentCSRF('/api/blogs',{method:'POST'}));
        else assert.equal((await env.fetchWithCurrentCSRF('/api/blogs',{method:'POST'})).status,403);
        assert.equal(writes,1);
    }
});
test('external requests never receive the CSRF cookie', async()=>{
    const env=setup('csrf_token=private',async(url,opts)=>{assert.equal(new Headers(opts.headers).has('X-CSRF-Token'),false);return new Response('{}');});
    await env.fetchWithCurrentCSRF('https://external.test/upload',{method:'POST'});
});

test('notes HTML uses live network ahead of a cached page, with offline fallback',async()=>{
    for(const offline of [false,true]){
        let handler, response;
        const pending=[];
        const env={URL,Response,AbortController,location:new URL('https://books.test'),
            self:{addEventListener:(type,fn)=>{if(type==='fetch')handler=fn;}},
            caches:{match:async()=>new Response('stale'),open:async()=>({put:async()=>{}})},
            fetch:async(req,opts)=>{assert.equal(opts.cache,'no-store');if(offline)throw Error('offline');return new Response('fresh');}
        };
        vm.createContext(env);vm.runInContext(fs.readFileSync(__dirname+'/static/sw.js','utf8'),env);
        handler({request:new Request('https://books.test/notes',{headers:{accept:'text/html'}}),respondWith:p=>{response=p;},waitUntil:p=>pending.push(p)});
        assert.equal(await (await response).text(),offline?'stale':'fresh');await Promise.all(pending);
    }
});

test('service worker never serves a cached CSRF refresh',()=>{
    let handler,intercepted=false;
    const env={URL,location:new URL('https://books.test'),self:{addEventListener:(type,fn)=>{if(type==='fetch')handler=fn;}}};
    vm.createContext(env);vm.runInContext(fs.readFileSync(__dirname+'/static/sw.js','utf8'),env);
    handler({request:new Request('https://books.test/api/csrf-token'),respondWith:()=>{intercepted=true;}});
    assert.equal(intercepted,false);
});
