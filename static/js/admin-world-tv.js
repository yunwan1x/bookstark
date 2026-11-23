(() => {
    'use strict';
    const el = id => document.getElementById('wtv-'+id);
    let channels=[], selected='', loaded=false, loading=false, busy=false, saving=false, state, saved, frame, timer;
    let active = new URL(location.href).searchParams.get('tvtab')==='world'?'world':'domestic';
    const names = typeof Intl.DisplayNames==='function'?new Intl.DisplayNames(['zh-CN'],{type:'region'}):null;
    function country(c){try{return /^[A-Z]{2}$/.test(c.country)?(names?.of(c.country)||c.country):(c.country||c.group||'未标注')}catch{return c.country||'未标注'}}
    function time(s){if(!s||s.startsWith('0001'))return '—';return new Date(s).toLocaleString('zh-CN',{timeZone:'Asia/Shanghai',hour12:false})}
    function message(s){el('error').hidden=!s;el('error').textContent=s||''}
    function toast(s,type='success'){window.BSDialog?.toast(s,type)}
    function config(){return {source:el('source').value.trim(),enabled:el('auto').checked,intervalHours:Number(el('period').value)}}
    const dirty = () => saved && JSON.stringify(config())!==JSON.stringify(saved);
    function controls(){
        const unavailable=!loaded||busy||saving||state?.running;
        el('source').disabled=el('auto').disabled=unavailable;
        el('period').disabled=unavailable||!el('auto').checked;
        el('save').disabled=unavailable||!dirty();
        el('pull').disabled=unavailable||dirty();
        el('pull').textContent=busy||state?.running?'拉取中…':'立即拉取';
        el('saved').textContent=dirty()?'有未保存的修改，请先保存再拉取':loaded?'配置已保存':'正在读取…';
    }
    function status(s){
        state=s;el('pull-status').dataset.error=String(!!s.error);
        el('pull-status').textContent=s.running?'正在拉取…':s.error?'最近拉取失败：'+s.error:(s.lastSuccess&&!s.lastSuccess.startsWith('0001')?'● 最近拉取成功':'尚未拉取');
        el('last').textContent='上次执行：'+time(s.lastAttempt);
        el('next').textContent=s.config.enabled?'下次：'+time(s.nextRun)+'（北京时间）':'自动拉取已关闭';
        el('duration').textContent='最近成功：'+time(s.lastSuccess)+' · '+s.count+' 个频道'+(s.durationMs?' · 耗时 '+(s.durationMs/1000).toFixed(1)+' 秒':'');controls();
    }
    async function api(path,opts){
        const response=opts?await csrfFetch('/api/admin/tv/world'+path,{...opts,offlinePolicy:'reject'}):await fetch('/api/admin/tv/world',{cache:'no-store'});
        const data=await response.json();if(!response.ok||data.code!==0)throw Error(data.message||'请求失败');return data.data;
    }
    function fill(c){el('source').value=c.source;el('auto').checked=c.enabled;el('period').value=String(c.intervalHours);saved={source:c.source,enabled:c.enabled,intervalHours:c.intervalHours}}
    function setCatalog(c){
        channels=c.channels||[];const previous=el('country').value;
        el('country').replaceChildren(new Option('全部国家 / 地区',''));
        [...new Set(channels.map(country))].sort((a,b)=>a.localeCompare(b,'zh-CN')).forEach(n=>el('country').add(new Option(n,n)));
        el('country').value=previous;if(el('country').selectedIndex<0)el('country').value='';
        render();
    }
    async function load(){
        if(loading)return;loading=true;
        try{const data=await api('');if(!loaded||!dirty())fill(data.state.config);loaded=true;status(data.state);setCatalog(data.catalog);message(data.catalogError||'')}
        catch(e){message('读取失败：'+e.message+'。切换到世界电视页可重试。')}
        finally{loading=false;controls()}
    }
    function stop(){frame=null;el('preview-world').replaceChildren()}
    function node(tag,text,cls){const n=document.createElement(tag);n.textContent=text;if(cls)n.className=cls;return n}
    function safeURL(raw){try{const u=new URL(raw);return ['https:','http:'].includes(u.protocol)&&!u.username&&!u.password?u.href:''}catch{return ''}}
    function details(c){
        stop();el('channel-name').textContent=c?.name||'请选择频道';
        el('channel-country').textContent=c?'国家 / 地区：'+country(c):'';
        el('channel-group').textContent=c?'分组：'+(c.group||'未标注'):'';
        el('channel-language').textContent=c?'语言：'+(c.language||'未标注'):'';
        const url=c?safeURL(c.url):'';
        el('protocol').textContent=c?(c.external?'来源网页':url.startsWith('https:')?'HTTPS':'HTTP'):'';
        el('channel-url').textContent=c?.url||'';
        el('open').hidden=!url;if(url)el('open').href=url;else el('open').removeAttribute('href');
        el('try').disabled=!c||c.external||!url.startsWith('https:');
        const reason=!c?(channels.length?'没有匹配的频道':'尚无频道，请配置订阅并立即拉取'):c.external?'此频道通过来源网页观看':!url.startsWith('https:')?'HTTP 来源不能在 HTTPS 页面内试播，请打开来源':c.geo?'此频道可能受地区限制，可尝试试播':'选择频道后可试播';
        el('preview-world').append(node('b',reason),node('span','视频由浏览器直连来源，可能受跨域、地区或格式限制。'));
    }
    function render(){
        const query=el('world-search').value.trim().toLowerCase(),filter=el('country').value;
        const visible=channels.filter(c=>(!query||c.name.toLowerCase().includes(query))&&(!filter||country(c)===filter));
        if(!visible.some(c=>c.id===selected))selected=visible[0]?.id||'';
        el('count').textContent='共 '+channels.length+' 个频道 · 当前显示 '+visible.length+' 个';
        el('world-list').replaceChildren();
        for(const c of visible){
            const b=document.createElement('button');b.type='button';b.className=c.id===selected?'active':'';b.setAttribute('aria-current',String(c.id===selected));
            const text=document.createElement('span');text.append(node('strong',c.name),node('small',country(c)+' · '+(c.group||'其他')));
            b.append(node('span',c.name.slice(0,3).toUpperCase(),'channel-mark'),text);
            b.onclick=()=>{selected=c.id;render()};el('world-list').append(b);
        }
        if(!visible.length)el('world-list').append(node('p',channels.length?'没有匹配的频道，请调整搜索或筛选。':'尚无频道，请先拉取订阅。','empty'));
        details(visible.find(c=>c.id===selected));
    }
    function switchTab(name,updateURL=true){
        active=name;stop();
        for(const key of ['domestic','world']){
            const selected=key===name,b=document.getElementById('tv-'+key+'-tab');
            document.getElementById('tv-'+key).hidden=!selected;b.classList.toggle('chosen',selected);b.setAttribute('aria-selected',String(selected));b.tabIndex=selected?0:-1;
        }
        if(updateURL){const u=new URL(location.href);u.searchParams.set('tvtab',name);history.replaceState(null,'',u)}
        window.dispatchEvent(new CustomEvent('tv-subtab',{detail:name}));
        if(name==='world')load();
    }
    for(const key of ['domestic','world']){
        const b=document.getElementById('tv-'+key+'-tab');b.onclick=()=>switchTab(key);
        b.onkeydown=e=>{if(['ArrowLeft','ArrowRight','Home','End'].includes(e.key)){e.preventDefault();const next=e.key==='Home'?'domestic':e.key==='End'?'world':key==='world'?'domestic':'world';switchTab(next);document.getElementById('tv-'+next+'-tab').focus()}};
    }
    el('period').replaceChildren(...[6,12,24].map(n=>new Option('每 '+n+' 小时',String(n))));
    el('world-search').oninput=render;el('country').onchange=render;
    el('world-form').oninput=controls;
    el('world-form').onsubmit=async e=>{
        e.preventDefault();if(!loaded||busy||saving)return;const cfg=config();saving=true;controls();
        try{const s=await api('',{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify(cfg)});fill(s.config);status(s);message('');toast('拉取配置已保存')}
        catch(err){message(err.message)}finally{saving=false;controls()}
    };
    el('pull').onclick=async()=>{
        if(busy||dirty())return;busy=true;controls();message('');
        try{const data=await api('/pull',{method:'POST'});status(data.state);setCatalog(data.catalog);toast('拉取完成：'+data.catalog.channels.length+' 个频道')}
        catch(err){await load();message('拉取失败：'+err.message)}finally{busy=false;controls()}
    };
    el('try').onclick=()=>{
        const c=channels.find(c=>c.id===selected);if(!c||c.external||!safeURL(c.url).startsWith('https:'))return;stop();
        frame=document.createElement('iframe');const f=frame;f.title=c.name+' 试播';f.allow='autoplay';f.src='/static/tv-preview/player.html';
        f.onload=()=>{if(frame===f)f.contentWindow.postMessage({type:'tv-preview',source:{protocol:'https',url:c.url,original:c.url},resolved:{url:c.url}},location.origin)};
        const close=node('button','关闭试播','w-btn');close.type='button';close.onclick=()=>details(c);
        el('preview-world').append(f,node('span','正在连接，请稍候…'),close);
    };
    window.addEventListener('message',e=>{if(!frame||e.source!==frame.contentWindow||e.origin!==location.origin||e.data?.type!=='tv-preview-result')return;el('preview-world').querySelector('span').textContent=e.data.ok?'已出画面，请核对台标':e.data.message||'试播失败'});
    window.addEventListener('admin-tab',e=>{if(e.detail!=='tv'){stop();clearInterval(timer)}else{if(active==='world')load();poll()}});
    function poll(){clearInterval(timer);timer=setInterval(()=>{if(active==='world'&&!document.hidden&&!busy&&!loading&&!dirty()&&!frame)load()},15000)}
    window.addEventListener('pagehide',()=>{stop();clearInterval(timer)});
    if (window.BookStarkNativeGuards) BookStarkNativeGuards.add(() => !dirty());
    window.addEventListener('beforeunload',e=>{if(!window.BookStarkHost?.isLeaving&&dirty()){e.preventDefault();e.returnValue=''}});
    switchTab(active,false);if(!document.getElementById('panel-tv').classList.contains('hidden'))poll();
})();
