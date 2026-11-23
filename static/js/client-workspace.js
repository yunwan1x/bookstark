/* Client preferences and credential autofill. All persistent secrets stay in the native vault. */
(function () {
  'use strict';
  const host = window.BookStarkHost;
  if (!host) return;
  const zh = () => document.documentElement.lang.startsWith('zh');
  const text = (cn, en) => zh() ? cn : en;
  let bridgeToken = '';
  const infoPromise = Promise.resolve(host.ready).then(async () => {
    if (!host.available) return null;
    const info = await host.request('client', {operation:'info',origin:location.origin},10000);
    bridgeToken = info.bridgeToken;
    return info;
  }).catch(() => null);
  const client = async (operation, args) => {
    if (!await infoPromise) throw new Error('Client settings unavailable');
    return host.request('client', {operation, origin:location.origin,bridgeToken,...args},10000);
  };
  window.BookStarkClient = {
    ready: infoPromise.then(Boolean),
    saveCredentials: (account, password) => client('credentials-save', {account, password}),
    clearCredentials: () => client('credentials-clear'),
    updateCredentials: async (account,password) => {const saved=await client('credentials-load');if(saved && saved.account===account)await client('credentials-save',{account,password});}
  };
  async function init() {
    const info = await infoPromise;
    if (!info) return;
    const account = document.getElementById('account'), password = document.getElementById('password');
    if (account && password) {
      document.getElementById('remember-client-credentials')?.removeAttribute('hidden');
      try {
        const saved = await client('credentials-load');
        if (saved && !account.value && !password.value) { account.value = saved.account; password.value = saved.password; }
      } catch (_) {
        const status = document.getElementById('client-login-status');
        if (status) status.textContent = text('无法读取已保存的账号密码，请重新输入。', 'Could not read saved credentials. Please enter them again.');
      }
    }
    const tablist = document.querySelector('.profile-tabs');
    if (!tablist || typeof window.switchProfileTab !== 'function') return;
    const button = document.createElement('button');
    button.id = 'tab-workspace'; button.type = 'button'; button.className = 'tab-btn flex-1';
    button.setAttribute('role', 'tab'); button.setAttribute('aria-selected', 'false'); button.setAttribute('aria-controls', 'panel-workspace');
    button.textContent = text('工作区', 'Workspace'); button.onclick = () => switchProfileTab('workspace');
    tablist.insertBefore(button, document.getElementById('tab-api'));
    const panel = document.createElement('div');
    panel.id = 'panel-workspace'; panel.className = 'profile-panel bg-white rounded-b-lg shadow-sm p-4 sm:p-7 hidden';
    panel.setAttribute('role', 'tabpanel'); panel.setAttribute('aria-labelledby', 'tab-workspace');
    panel.innerHTML = `<h2 class="text-base font-semibold mb-4">${text('启动方式', 'Startup behavior')}</h2>
      <p class="text-sm text-slate-500 mb-4">${text('下次打开 BookStark 时', 'When you next open BookStark')}</p>
      <label class="client-startup-option block border border-slate-300 rounded-lg p-4 mb-3"><input type="radio" name="client-startup" value="continue"> <strong>${text('继续上次工作区', 'Continue last workspace')}</strong><span class="text-xs text-blue-600"> · ${text('推荐', 'Recommended')}</span><p class="text-sm text-slate-500 mt-1">${text('自动打开上次成功使用的工作区，无需重复选择。', 'Open the last workspace used successfully, without choosing again.')}</p></label>
      <label class="client-startup-option block border border-slate-300 rounded-lg p-4 mb-4"><input type="radio" name="client-startup" value="ask"> <strong>${text('每次询问', 'Ask every time')}</strong><p class="text-sm text-slate-500 mt-1">${text('每次启动时选择本地工作区或远程服务器。', 'Choose a local workspace or remote server at every startup.')}</p></label>
      <h2 class="text-base font-semibold mb-3">${text('当前工作区', 'Current workspace')}</h2>
      <div class="border border-slate-300 rounded-lg p-4 mb-3"><strong id="client-workspace-name"></strong><p class="text-sm text-slate-500 mt-1" id="client-workspace-location"></p><button type="button" id="client-switch-workspace" class="mt-3 px-3 py-2 border border-slate-300 rounded-md text-sm">${text('切换工作区', 'Switch workspace')}</button></div>
      <p class="text-xs text-slate-500 mb-4">${text('仅影响此客户端。切换后保留各工作区的数据和已记住的账号密码。', 'Applies only to this client. Each workspace retains its data and saved credentials.')}</p>
      <button type="button" id="client-forget-credentials" class="text-sm text-red-600 mb-4">${text('清除此工作区记住的账号密码', 'Forget credentials for this workspace')}</button>
      <p id="client-workspace-status" role="status" aria-live="polite" class="text-sm mb-3"></p>
      <button type="button" id="client-save-workspace" class="px-4 py-2 bg-blue-600 text-white rounded-md text-sm">${text('保存设置', 'Save settings')}</button>`;
    tablist.parentElement.append(panel);
    panel.querySelector(`input[value="${info.ask ? 'ask' : 'continue'}"]`).checked = true;
    panel.querySelector('#client-workspace-name').textContent = info.local ? text('本地工作区', 'Local workspace') : text('远程服务器', 'Remote server');
    panel.querySelector('#client-workspace-location').textContent = info.local ? text('数据保存在这台设备上 · 运行中', 'Data stays on this device · Running') : info.remote;
    const status = panel.querySelector('#client-workspace-status');
    panel.querySelector('#client-switch-workspace').onclick = () => host.navigate(() => client('switch').catch(() => { status.textContent = text('切换失败，请重试。', 'Could not switch. Please retry.'); }));
    panel.querySelector('#client-save-workspace').onclick = async function () {
      this.disabled = true;
      try { await client('save', {ask: panel.querySelector('input[value="ask"]').checked}); status.textContent = text('设置已保存，下次启动生效。', 'Saved. Applies at next startup.'); }
      catch (_) { status.textContent = text('保存失败，请重试。', 'Could not save. Please retry.'); }
      finally { this.disabled = false; }
    };
    panel.querySelector('#client-forget-credentials').onclick = async function () {
      this.disabled = true;
      try { await client('credentials-clear'); status.textContent = text('已清除记住的账号密码，当前登录不受影响。', 'Saved credentials cleared. Your current session stays signed in.'); }
      catch (_) { status.textContent = text('清除失败，请重试。', 'Could not clear. Please retry.'); }
      finally { this.disabled = false; }
    };
    if (new URLSearchParams(location.search).get('tab') === 'workspace') { switchProfileTab('workspace', {updateUrl:false});button.scrollIntoView({block:'nearest',inline:'nearest'}); }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init, {once:true}); else init();
})();
