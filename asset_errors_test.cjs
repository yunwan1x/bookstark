const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('static/js/assets.js', 'utf8');
const helper = source.slice(source.indexOf('  function apiJSON('), source.indexOf('  function loadData('));
const ctx = vm.createContext({ t: key => key, console: {warn() {}} });
vm.runInContext(helper, ctx);
async function check(response, message) {
  ctx.csrfFetch = async () => response;
  await assert.rejects(ctx.apiJSON('/test'), error => error.message === message);
}
(async () => {
  for (const body of ['', '<html>Bad gateway</html>', '{', 'null', '[]', '{}']) {
    await check(new Response(body, {status: 502}), 'asset.error.response');
  }
  for (const [status, key] of [[401, 'session'], [403, 'forbidden'], [504, 'timeout']]) {
    await check(new Response('', {status}), 'asset.error.' + key);
  }
  for (const [message, key] of [['认证失败', 'ssh_auth'], ['私钥解析失败', 'ssh_key'], ['私钥需要密码', 'ssh_key_password'], ['连接超时', 'timeout'], ['SSH 连接失败', 'ssh_connect']]) {
    await check(new Response(JSON.stringify({code:502, message}), {status:502}), 'asset.error.' + key);
  }
  await check(new Response(JSON.stringify({code:400, message:'Docker unavailable'}), {status:400}), 'Docker unavailable');
  ctx.csrfFetch = async () => { throw new TypeError('Failed to fetch'); };
  await assert.rejects(ctx.apiJSON('/test'), /asset.error.network/);
  ctx.csrfFetch = async () => { throw new DOMException('aborted', 'AbortError'); };
  await assert.rejects(ctx.apiJSON('/test'), error => error.name === 'AbortError');
  ctx.csrfFetch = async () => new Response(JSON.stringify({code:0, data:[{id:'test'}]}));
  assert.equal((await ctx.apiJSON('/test'))[0].id, 'test');
  console.log('PASS: invalid/empty JSON, HTTP errors, SSH errors, network, cancellation and successful response');
})().catch(error => {console.error(error); process.exitCode = 1;});
