/* Optional update checks run after page startup, never block workspace loading. */
(function(){'use strict';let running=false;
 async function request(path,method='GET',data){const response=await fetchWithCurrentCSRF(path,{method,cache:'no-store',headers:data===undefined?{}:{'Content-Type':'application/json'},body:data===undefined?undefined:JSON.stringify(data),offlinePolicy:'reject'});if(!response.ok)throw Error('market unavailable');return response.json();}
 async function check(){
  if(running||!document.getElementById('user-menu-trigger')||typeof fetchWithCurrentCSRF!=='function')return;
  running=true;
  try{
   const config=await request('/api/tool-market/client');
   if(window.BookStarkClient&&await BookStarkClient.ready){const local=await BookStarkClient.marketSettings();if(local.url)Object.assign(config,local);}
   if(!config.check_updates)return;
   const key='bookstark-tool-update-check:'+config.url;
   const last=Number(sessionStorage.getItem(key)||0);if(Date.now()-last<15*60*1000)return;
   sessionStorage.setItem(key,String(Date.now()));
   const installed=(await request('/api/tool-installs')).tools;if(!installed.length)return;
   const own=new URL(config.url).origin===location.origin;
   const catalog=(own?await request('/api/tool-market'):await request('/api/tool-sources','POST',{server:config.url})).tools;
   const updates=installed.filter(old=>catalog.some(next=>next.id===old.id&&next.revision!==old.revision));
   window.dispatchEvent(new CustomEvent('tool-market-updates',{detail:{count:updates.length}}));
   if(!config.auto_update){if(updates.length&&window.BSDialog){const zh=document.documentElement.lang.startsWith('zh');BSDialog.toast(zh?'发现 '+updates.length+' 个工具更新，可在「我的工具」查看。':updates.length+' tool update(s) available. Review them in My tools.','info',6000);}return;}
   for(const old of updates){
    const pkg=await request(old.id<0?'/api/tool-sources/'+old.id+'?metadata=1':'/api/tool-market/'+old.id+'?metadata=1');
    // New permissions require an explicit review, even with automatic updates on.
    if(['read_files','save_files','network'].some(k=>pkg.permissions?.[k]&&!old.permissions?.[k]))continue;
    await request('/api/tool-installs/'+old.id,'PUT',{revision:pkg.revision,hash:pkg.hash||'',expected:old.revision,instance:old.instance});
    window.dispatchEvent(new Event('tool-market-changed'));
   }
  }catch(_){/* Installed tools remain usable while a market is unreachable. */}
  finally{running=false;}
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>setTimeout(check,0),{once:true});else setTimeout(check,0);
 window.addEventListener('tool-market-source-changed',()=>{try{for(let i=sessionStorage.length-1;i>=0;i--){const key=sessionStorage.key(i);if(key.startsWith('bookstark-tool-update-check:'))sessionStorage.removeItem(key);}}catch(_){};check();});
})();
