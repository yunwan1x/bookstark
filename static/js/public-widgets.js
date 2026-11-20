/* Small, opt-in player and local-time widgets for the public workspace. */
(function () {
 'use strict';
 const t = key => window.__('public.' + key);
 const locale = document.documentElement.lang === 'zh' ? 'zh-CN' : 'en-US';
 document.querySelectorAll('[data-visit-number]').forEach(el => { el.textContent = new Intl.NumberFormat(locale).format(Number(el.textContent)); });
 const clocks = [...document.querySelectorAll('[data-clock-zone]')].map(el => ({el,
  time: new Intl.DateTimeFormat(locale, {timeZone:el.dataset.clockZone,hour:'2-digit',minute:'2-digit',hourCycle:'h23'}),
  date: new Intl.DateTimeFormat(locale, {timeZone:el.dataset.clockZone,month:'short',day:'numeric'})
 }));
 function tick() {
  const now = new Date();
  clocks.forEach(({el,time,date}) => {
   const parts=time.formatToParts(now), hour=Number(parts.find(p=>p.type==='hour').value);
   el.querySelector('time').textContent=time.format(now);
   el.querySelector('time').dateTime=now.toISOString();
   el.querySelector('small').textContent=date.format(now);
   el.querySelector('i').className='fa-regular '+(hour>=6&&hour<18?'fa-sun':'fa-moon');
  });
 }
 tick(); let clockTimer=setInterval(tick,15000);
 document.addEventListener('visibilitychange',()=>{if(!document.hidden)tick();});
 const audio=document.getElementById('publicRadioAudio'); if(!audio)return;
 const play=document.getElementById('publicRadioPlay'), select=document.getElementById('publicRadioStation'), volume=document.getElementById('publicRadioVolume'), status=document.getElementById('publicRadioStatus');
 const stations=new Map([...select.options].map(option=>[option.value,{
  id:option.value,name:option.textContent,url:'https://stream.srg-ssr.ch/srgssr/'+option.value+'/mp3/128',
  homepage:'https://www.radioswiss'+({rsc_de:'classic',rsj:'jazz',rsp:'pop'}[option.value])+'.ch/en/reception/internet',builtin:true
 }]));
 function httpsURL(raw) {
  try { const u=new URL(raw); return u.protocol==='https:'&&!u.username&&!u.password ? u.href : ''; } catch(_){return '';}
 }
 function normalizeStation(raw) {
  if(!raw||typeof raw!=='object'||typeof raw.name!=='string')return null;
  const url=httpsURL(raw.url_resolved||raw.url), name=raw.name.trim().slice(0,120);
  if(!url||!name||(raw.hls&&!audio.canPlayType('application/vnd.apple.mpegurl')))return null;
  const codec=String(raw.codec||'').toUpperCase(),types={MP3:'audio/mpeg',AAC:'audio/aac','AAC+':'audio/aac',OGG:'audio/ogg',OPUS:'audio/ogg; codecs="opus"',FLAC:'audio/flac'};
  if(types[codec]&&!audio.canPlayType(types[codec]))return null;
  return {id:'catalog:'+url,name,url,homepage:httpsURL(raw.homepage)||'https://www.radio-browser.info/',country:String(raw.countrycode||'').slice(0,2),tags:String(raw.tags||'').slice(0,100)};
 }
 function addStation(station) {
  // Keep the dropdown compact: presets plus the selected search result.
  [...stations].forEach(([id,s])=>{if(!s.builtin){stations.delete(id);[...select.options].find(o=>o.value===id)?.remove();}});
  stations.set(station.id,station);select.add(new Option(station.name,station.id));select.value=station.id;
 }
 let active=false, generation=0, timeout;
 function render(state) {
  status.textContent=t('radio_'+state);
  play.setAttribute('aria-label',t(active?'radio_pause':'radio_play'));
  play.setAttribute('aria-pressed',String(active));
  play.querySelector('i').className='fa-solid '+(active?'fa-pause':'fa-play');
 }
 function stop(state='idle') {
  active=false; generation++;clearTimeout(timeout);
  audio.pause();audio.removeAttribute('src');audio.load();render(state);
 }
 function failed() { if(active)stop('error'); }
 function waitForStream() { clearTimeout(timeout);timeout=setTimeout(failed,15000);render('loading'); }
 async function start() {
  if(!stations.has(select.value))return;
  active=true;const request=++generation;
  audio.src=stations.get(select.value).url;
  waitForStream();
  try { await audio.play(); } catch (_) { if(request===generation&&active)failed(); }
 }
 audio.volume=0.5;
 try {
  const saved=JSON.parse(localStorage.getItem('bookstark:public-radio')||'null');
  if(saved&&stations.has(saved.station))select.value=saved.station;
  else if(saved?.selected){const station=normalizeStation(saved.selected);if(station)addStation(station);}
  if(saved&&typeof saved.volume==='number'&&saved.volume>=0&&saved.volume<=1)audio.volume=volume.value=saved.volume;
 }catch(_){}
 function updateSource(){const station=stations.get(select.value),link=document.getElementById('publicRadioSource');link.href=station.homepage;link.textContent=(station.builtin?'Radio Swiss':station.name)+' ↗';}
 updateSource();
 function save(){try{localStorage.setItem('bookstark:public-radio',JSON.stringify({station:select.value,selected:stations.get(select.value)?.builtin?null:stations.get(select.value),volume:audio.volume}));}catch(_){}}
 play.addEventListener('click',()=>active?stop():start());
 select.addEventListener('change',()=>{const resume=active;stop();updateSource();save();if(resume)start();});
 volume.addEventListener('input',()=>{audio.volume=Number(volume.value);save();});
 audio.addEventListener('playing',()=>{if(active){clearTimeout(timeout);render('playing');}});
 audio.addEventListener('waiting',()=>{if(active)waitForStream();});
 audio.addEventListener('error',failed);
 audio.addEventListener('ended',()=>stop());

 // Use the same directory mirrors as the full Radio page; fetch only on intent.
 const form=document.getElementById('publicRadioSearch'),query=document.getElementById('publicRadioQuery'),genre=document.getElementById('publicRadioGenre'),results=document.getElementById('publicRadioResults'),searchStatus=document.getElementById('publicRadioSearchStatus'),more=document.getElementById('publicRadioMore');
 const mirrors=['https://de1.api.radio-browser.info','https://de2.api.radio-browser.info'];
 let searchVersion=0,searchAbort,offset=0,preferred=0,lastQuery,lastGenre;
 const seen=new Set();
 async function search(append=false) {
  const version=++searchVersion;searchAbort?.abort();
  if(!append){offset=0;seen.clear();results.replaceChildren();lastQuery=query.value.trim();lastGenre=genre.value;}
  const params=new URLSearchParams({name:lastQuery,tag:lastGenre,hidebroken:'true',order:'votes',reverse:'true',limit:'40',offset:String(offset)});
  results.setAttribute('aria-busy','true');searchStatus.textContent=t('radio_searching');more.hidden=true;
  let rows;
  for(let i=0;i<mirrors.length;i++){
   const controller=new AbortController();searchAbort=controller;
   const timer=setTimeout(()=>controller.abort(),7000);
   try {
    const response=await fetch(mirrors[(preferred+i)%mirrors.length]+'/json/stations/search?'+params,{signal:controller.signal,credentials:'omit'});
    if(!response.ok)throw Error('directory');
    rows=await response.json();if(!Array.isArray(rows))throw Error('directory');
    preferred=(preferred+i)%mirrors.length;break;
   }catch(_){if(version!==searchVersion)return;}finally{clearTimeout(timer);}
  }
  if(version!==searchVersion)return;
  results.setAttribute('aria-busy','false');
  if(!Array.isArray(rows)){searchStatus.textContent=t('radio_search_error');more.hidden=!append;return;}
  offset+=rows.length;
  rows.forEach(raw=>{
   const station=normalizeStation(raw);if(!station||seen.has(station.url))return;seen.add(station.url);
   const button=document.createElement('button');button.type='button';button.className='public-radio-result';
   const title=document.createElement('strong');title.textContent=station.name;
   const meta=document.createElement('small');meta.textContent=[station.country,station.tags].filter(Boolean).join(' · ');
   const icon=document.createElement('i');icon.className='fa-solid fa-play';icon.setAttribute('aria-hidden','true');
   button.append(title,meta,icon);button.setAttribute('aria-label',t('radio_play')+' '+station.name);
   button.addEventListener('click',()=>{stop();addStation(station);updateSource();save();start();});results.append(button);
  });
  searchStatus.textContent=seen.size?seen.size+' '+t('radio_results'):t('radio_no_results');more.hidden=rows.length<40;
 }
 form.addEventListener('submit',e=>{e.preventDefault();search();});
 genre.addEventListener('change',()=>search());
 more.addEventListener('click',()=>search(true));
 window.addEventListener('pagehide',()=>{clearInterval(clockTimer);searchVersion++;searchAbort?.abort();stop();});
 window.addEventListener('pageshow',e=>{if(e.persisted){tick();clockTimer=setInterval(tick,15000);if(results.getAttribute('aria-busy')==='true'){results.setAttribute('aria-busy','false');searchStatus.textContent=t('radio_search_hint');}}});
})();
