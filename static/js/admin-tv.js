(() => {
    'use strict';
    const el = id => document.getElementById('tv-'+id);
    const clone = value => JSON.parse(JSON.stringify(value));
    const equal = (a,b) => JSON.stringify(a) === JSON.stringify(b);
    const entries = new Map();
    let selected, filter='全部', opened=0, loading=false, saving=false, run=0, controller, frame;
    const current=()=>entries.get(selected);
    function element(type,text,cls) {
        const n=document.createElement(type);
        if(text!==undefined)n.textContent=text;
        if(cls)n.className=cls;
        return n;
    }
    function button(text,fn,cls) {
        const b=element('button',text,cls);b.type='button';b.onclick=fn;return b;
    }
    function sorted(channel) {
        return channel.sources.slice().sort((a,b)=>Number(b.id===channel.preferredSourceId)-Number(a.id===channel.preferredSourceId));
    }
    function linesOf(channel) {
        if(channel.externalOnly) return [{id:'official',protocol:'web',label:'央视频官网入口',url:channel.officialUrl}];
        return sorted(channel).map(s=>({id:s.id,protocol:s.protocol,label:s.label,url:s.url||s.original}));
    }
    function group(channel){return channel.groupIds.includes('satellite')?'卫视':'央视'}
    function changed(item){return !equal(item.saved,item.draft)}
    function message(text){el('status').textContent=text}
    function stop(){
        run++;controller?.abort();controller=null;frame=null;el('preview').replaceChildren();
    }
    function list(){
        const query=el('search').value.trim().toLowerCase();
        const show=[...entries.values()].filter(({channel})=>(filter==='全部'||group(channel)===filter)&&(channel.name+channel.pinyin).toLowerCase().includes(query));
        el('count').textContent=show.length+' 个';
        const host=el('list');host.replaceChildren();
        for(const category of ['央视','卫视']){
            const subset=show.filter(i=>group(i.channel)===category);
            if(subset.length)host.append(element('small',category));
            for(const i of subset){
                const b=button(i.channel.name,()=>select(i.channel.id),selected===i.channel.id?'active':'');
                b.dataset.channel=i.channel.id;b.setAttribute('aria-current',String(selected===i.channel.id));
                if(changed(i))b.append(element('span','草稿'));host.append(b);
            }
        }
        if(!show.length)host.append(element('small','没有找到这个频道'));
    }
    function select(id){
        stop();selected=id;opened=0;render();message('选择一条线路，点「验证」即可试播。');
    }
    function resetPreview(){stop();message('草稿已修改，可验证当前线路。');footer();list()}
    function footer(){
        const dirty=changed(current());
        el('save').disabled=!dirty || saving;
        el('dirty').textContent=dirty?'有未保存的修改 · 仅此频道':'正在使用已保存的配置';
    }
    function field(host,label,value,onChange,numeric=false){
        const l=element('label',label,'tv-field'),input=document.createElement('input');
        input.type='text';input.value=value||'';if(numeric){input.inputMode='numeric';input.maxLength=19}
        input.oninput=()=>{onChange(input.value.trim());resetPreview()};l.append(input);host.append(l);
    }
    function https(value){try{const u=new URL(value);return u.protocol==='https:'&&!u.username&&!u.password}catch{return false}}
    function isWeb(line){return line.protocol==='web'}
    function valid(line,ids){
        if(line.protocol==='cctv-live')return ids&&[ids.pid,ids.streamId].every(x=>/^[1-9][0-9]{0,18}$/.test(x));
        if(isWeb(line)){if(!https(line.url))return false;const u=new URL(line.url);return u.host==='www.yangshipin.cn'&&u.pathname==='/tv/home'&&/^[1-9][0-9]{0,18}$/.test(u.searchParams.get('pid')||'')}
        return line.protocol!=='https'||https(line.url);
    }
    function handleChange(i){
        opened=i;resetPreview();render();
    }
    function render(){
        const item=current(),draft=item.draft,lines=draft.lines;
        list();el('group').textContent=group(item.channel)+' / 频道设置';el('name').textContent=item.channel.name;
        el('kind').textContent=isWeb(lines[0])?'前往官网观看':'网页内播放';
        el('lines').replaceChildren();el('guide').hidden=lines[opened]?.protocol!=='cctv-live';
        lines.forEach((line,i)=>{
            const card=element('div',undefined,'tv-line'+(i===opened?' open':''));
            const h=element('div',undefined,'tv-line-head');card.append(h);
            h.append(element('span',i?'备用 '+i:'首选','tv-badge'+(!i?' first':'')),element('strong',line.label),
                button(i===opened?'收起':'编辑',()=>{opened=i===opened?-1:i;render()}),
                button(isWeb(line)?'打开核对':'验证',()=>verify(i)));
            if(i===opened){
                const e=element('div',undefined,'tv-details');card.append(e);
                if(line.protocol==='cctv-live'){
                    const pair=element('div',undefined,'tv-pair');e.append(pair);
                    field(pair,'央视频频道编号（PID）',draft.ids.pid,v=>draft.ids.pid=v,true);
                    field(pair,'流编号（streamId）',draft.ids.streamId,v=>draft.ids.streamId=v,true);
                }else if(line.protocol==='https'||isWeb(line)){
                    field(e,isWeb(line)?'央视频官网频道页（HTTPS）':'播放地址（HTTPS）',line.url,v=>line.url=v);
                }else e.append(element('small','内置取址线路。播放时自动获取地址，可以调整顺序或添加备用直链。'));
                const tools=element('div',undefined,'tv-tools');
                if(i>0)tools.append(button('设为首选',()=>{lines.unshift(lines.splice(i,1)[0]);handleChange(0)}));
                if(i<lines.length-1)tools.append(button('下移',()=>{[lines[i],lines[i+1]]=[lines[i+1],lines[i]];handleChange(i+1)}));
                if(lines.length>1)tools.append(button('移除线路',()=>{lines.splice(i,1);handleChange(Math.min(i,lines.length-1))}));
                e.append(tools);
            }
            el('lines').append(card);
        });
        const omitted=item.defaults.lines.filter(l=>!isWeb(l)&&!lines.some(s=>s.id===l.id));
        if(omitted.length){
            const more=element('div',undefined,'tv-tools');
            omitted.forEach(l=>more.append(button('加回：'+l.label,()=>{if(lines.length>=16)return message('每个频道最多 16 条线路');lines.push(clone(l));handleChange(lines.length-1)})));
            el('lines').append(more);
        }
        footer();
    }
    async function verify(i){
        stop();const seq=run,item=current(),line=clone(item.draft.lines[i]),ids=item.draft.ids;
        if(!valid(line,ids))return message('请先填写有效的播放地址或编号。');
        if(isWeb(line)){window.open(line.url,'_blank','noopener,noreferrer');return message('已打开官网，请在新窗口核对频道。')}
        controller=new AbortController();
        message('正在验证「'+line.label+'」…');
        try{
            let resolved;
            if(line.protocol==='cctv-live'){
                const r=await csrfFetch('/api/admin/tv/channels/'+selected+'/preview',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(ids),signal:controller.signal});
                const d=await r.json();if(!r.ok||!d.data?.url)throw Error(d.message||'央视频取址失败');
                resolved=d.data;
            }
            if(seq!==run)return;
            const f=document.createElement('iframe');frame=f;f.title='当前线路试播';f.allow='autoplay';
            f.onload=()=>{if(seq===run)f.contentWindow.postMessage({type:'tv-preview',source:{protocol:line.protocol,url:line.protocol==='https'?line.url:undefined,original:line.url},resolved},location.origin)};
            f.src='/static/tv-preview/player.html';
            el('preview').append(f,button('关闭试播',()=>{stop();message('试播已关闭。')}));
        }catch(e){if(seq===run)message(e.message||'试播失败')}
    }
    window.addEventListener('message',e=>{
        if(!frame||e.source!==frame.contentWindow||e.origin!==location.origin||e.data?.type!=='tv-preview-result')return;
        message((e.data.ok?'验证通过：':'验证失败：')+e.data.message);
    });
    function serialize(item){
        return item.draft.lines.map(line=>{
            if(isWeb(line))return 'official:'+line.url;
            const builtin=item.defaults.lines.find(s=>s.id===line.id);
            return line.protocol==='https'&&(!builtin||builtin.url!==line.url)?line.url:line.id;
        });
    }
    async function save(){
        const item=current(),draft=clone(item.draft);
        if(saving || !changed(item))return;
        if(!draft.lines.every(line=>valid(line,draft.ids)))return message('有线路地址或编号无效，请修改后再保存。');
        const lines=serialize(item);
        if(new Set(lines).size!==lines.length)return message('有重复的线路，请检查后再保存。');
        saving=true;footer();const seq=run;
        try{
            const r=await csrfFetch('/api/admin/tv/channels/'+item.channel.id,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({lines,ids:draft.ids,reset:equal(draft,item.defaults)})});
            const data=await r.json();if(!r.ok||data.code!==0)throw Error(data.message||'保存失败');
            item.saved=draft;if(item===current()&&seq===run)message('已保存 '+item.channel.name+'。刷新直播页后使用新配置。');
        }catch(e){if(item===current())message(e.message||'保存失败')}
        finally{saving=false;footer();list()}
    }
    async function load(){
        if(loading||entries.size)return;
        loading=true;
        try{
            const r=await fetch('/api/admin/tv/channels',{cache:'no-store'}),reply=await r.json();
            if(!r.ok||reply.code!==0)throw Error(reply.message||'读取失败');
            const {defaults,current:catalog,official,mappings}=reply.data;
            const byID=new Map(defaults.channels.map(c=>[c.id,c])),ys=new Map(official.map(c=>[c.ID,c]));
            for(const channel of catalog.channels){
                const source=ys.get(channel.id),def={lines:linesOf(byID.get(channel.id)),ids:source?.Default||null};
                const saved={lines:linesOf(channel),ids:source?(mappings?.[source.Key]||source.Default):null};
                entries.set(channel.id,{channel,defaults:def,saved,draft:clone(saved)});
            }
            const first=entries.has('10023')?'10023':catalog.defaultChannelId;
            select(first);opened=current().draft.lines.findIndex(l=>l.protocol==='cctv-live');if(opened<0)opened=0;render();
            const l=el('list'),active=l.querySelector('.active');if(active)l.scrollTop+=active.getBoundingClientRect().top-l.getBoundingClientRect().top-32;
        }catch(e){message('读取频道失败：'+e.message);el('status').append(button('重试',load))}
        finally{loading=false}
    }
    for(const name of ['全部','央视','卫视']){
        const b=button(name,()=>{filter=name;for(const n of el('filters').children)n.classList.toggle('active',n===b);list()},name==='全部'?'active':'');el('filters').append(b);
    }
    el('search').oninput=list;
    el('save').onclick=save;
    el('reset').onclick=()=>{if(!current())return;current().draft=clone(current().defaults);handleChange(0);message('已把内置配置放入草稿，保存后生效。')};
    el('add').onclick=()=>{if(!current())return;const lines=current().draft.lines;if(lines.length>=16)return message('每个频道最多 16 条线路');if(lines.some(isWeb))lines.length=0;lines.push({id:'',protocol:'https',label:'自定义直链',url:''});handleChange(lines.length-1)};
    window.addEventListener('admin-tab',e=>{if(e.detail==='tv')load();else if(frame||controller){stop();message('试播已关闭。')}});
    window.addEventListener('pagehide',stop);
    if(!document.getElementById('panel-tv').classList.contains('hidden'))load();
})();
