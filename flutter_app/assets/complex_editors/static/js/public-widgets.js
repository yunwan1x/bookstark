/* Small, opt-in player and local-time widgets for the public workspace. */
(function () {
 'use strict';
 const t = key => window.__('public.' + key);
 const locale = document.documentElement.lang === 'zh' ? 'zh-CN' : 'en-US';
 document.querySelectorAll('[data-visit-number]').forEach(el => { el.textContent = new Intl.NumberFormat(locale).format(Number(el.textContent)); });
 const clocks = [...document.querySelectorAll('[data-clock-zone]')].map(el => ({el,
  time: new Intl.DateTimeFormat(locale, {timeZone:el.dataset.clockZone,hour:'2-digit',minute:'2-digit',hourCycle:'h23'}),
  parts: new Intl.DateTimeFormat('en-US', {timeZone:el.dataset.clockZone,hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}),
  date: new Intl.DateTimeFormat(locale, {timeZone:el.dataset.clockZone,month:'short',day:'numeric'}),
  digital:el.querySelector('time'), dateLabel:el.querySelector('[data-clock-date]'), period:el.querySelector('[data-clock-period]'), icon:el.querySelector('i'),
  hourHand:el.querySelector('.public-clock-hour'), minuteHand:el.querySelector('.public-clock-minute'), secondHand:el.querySelector('.public-clock-second')
 }));
 function tick() {
  const now = new Date();
  clocks.forEach(({el,time,parts,date,digital,dateLabel,period,icon,hourHand,minuteHand,secondHand}) => {
   const values=Object.fromEntries(parts.formatToParts(now).map(p=>[p.type,p.value]));
   const hour=Number(values.hour), minute=Number(values.minute), second=Number(values.second);
   // Day/night is a local-time indicator (06:00–18:00), not a sunrise forecast.
   const day=hour>=6&&hour<18;
   digital.textContent=time.format(now); digital.dateTime=now.toISOString();
   dateLabel.textContent=date.format(now); period.textContent=t(day?'clock_day':'clock_night');
   icon.className='fa-regular '+(day?'fa-sun':'fa-moon'); el.classList.toggle('is-night',!day);
   hourHand.setAttribute('transform','rotate('+((hour%12)*30+minute*.5+second/120)+' 50 50)');
   minuteHand.setAttribute('transform','rotate('+(minute*6+second*.1)+' 50 50)');
   secondHand.setAttribute('transform','rotate('+(second*6)+' 50 50)');
  });
 }
 let clockTimer;
 function stopClock(){clearInterval(clockTimer);clockTimer=undefined;}
 function startClock(){stopClock();tick();if(!document.hidden)clockTimer=setInterval(tick,1000);}
 startClock();
 document.addEventListener('visibilitychange',()=>document.hidden?stopClock():startClock());
 window.addEventListener('pagehide',stopClock);
 window.addEventListener('pageshow',e=>{if(e.persisted)startClock();});
 const audio=document.getElementById('publicRadioAudio'); if(!audio)return;
 const play=document.getElementById('publicRadioPlay'), select=document.getElementById('publicRadioStation'), volume=document.getElementById('publicRadioVolume'), status=document.getElementById('publicRadioStatus');
 const stations=new Map([...select.options].map(option=>[option.value,{
  id:option.value,name:option.textContent,url:'https://stream.srg-ssr.ch/srgssr/'+option.value+'/mp3/128',
  builtin:true
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
  return {id:'catalog:'+url,name,url,country:String(raw.countrycode||'').slice(0,2),tags:String(raw.tags||'').slice(0,100)};
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
 function save(){try{localStorage.setItem('bookstark:public-radio',JSON.stringify({station:select.value,selected:stations.get(select.value)?.builtin?null:stations.get(select.value),volume:audio.volume}));}catch(_){}}
 play.addEventListener('click',()=>active?stop():start());
 select.addEventListener('change',()=>{const resume=active;stop();save();if(resume)start();});
 volume.addEventListener('input',()=>{audio.volume=Number(volume.value);save();});
 audio.addEventListener('playing',()=>{if(active){clearTimeout(timeout);render('playing');}});
 audio.addEventListener('waiting',()=>{if(active)waitForStream();});
 audio.addEventListener('error',failed);
 audio.addEventListener('ended',()=>stop());

 // Use the same directory mirrors as the full Radio page; fetch only on intent.
 const form=document.getElementById('publicRadioSearch'),query=document.getElementById('publicRadioQuery'),genre=document.getElementById('publicRadioGenre'),results=document.getElementById('publicRadioResults'),searchStatus=document.getElementById('publicRadioSearchStatus'),more=document.getElementById('publicRadioMore');
 const mirrors=['https://de1.api.radio-browser.info','https://de2.api.radio-browser.info'];
 let searchVersion=0,searchAbort,offset=0,preferred=0,lastQuery,lastGenre,lastCountry,countryCode='';

 let countryPicker,countryPromise;
 const countryNames=new Intl.DisplayNames([locale],{type:'region'}),englishNames=new Intl.DisplayNames(['en'],{type:'region'}),chineseNames=new Intl.DisplayNames(['zh'],{type:'region'});
 async function loadCountries() {
  for(const mirror of mirrors){
   const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),7000);
   try {
    const response=await fetch(mirror+'/json/countrycodes?hidebroken=true',{signal:controller.signal,credentials:'omit'});
    if(!response.ok)throw Error();
    const rows=await response.json();if(!Array.isArray(rows))throw Error();
    return [...new Set(rows.map(row=>String(row.name||'').toUpperCase()).filter(code=>/^[A-Z]{2}$/.test(code)))].map(code=>({value:code,label:countryNames.of(code),meta:code,keywords:[code,englishNames.of(code),chineseNames.of(code)].join(' ').toLowerCase()})).sort((a,b)=>a.label.localeCompare(b.label,locale));
   }catch(_){}finally{clearTimeout(timer);}
  }
  throw Error(t('radio_countries_error'));
 }
 const countryHost=document.getElementById('publicRadioCountry');
 document.getElementById('publicRadioDiscovery').addEventListener('toggle',event=>{
  if(!event.target.open){countryPicker?.close();return;}
  if(countryPicker)return;
  countryPicker=window.BookStarkSearchSelect.create(countryHost,{
   icon:'fa-globe',optionIcon:'fa-globe',placeholder:t('radio_all_countries'),searchPlaceholder:t('radio_country_search'),clearLabel:t('radio_clear_search'),loadingText:t('radio_searching'),emptyText:t('radio_country_empty'),errorText:t('radio_countries_error'),
   load:async text=>{
    if(!countryPromise)countryPromise=loadCountries().catch(error=>{countryPromise=null;throw error;});
    const countries=await countryPromise,needle=text.trim().toLowerCase();
    return [{value:'',label:t('radio_all_countries')},...countries].filter(item=>!needle||(item.label+' '+(item.keywords||'')).toLowerCase().includes(needle));
   },
   onChange:(_,value)=>{countryCode=value;search();}
  });
  countryPicker.trigger.setAttribute('aria-label',t('radio_country_filter'));
  // Do not select the previous highlighted country while search is debouncing.
  countryPicker.search.addEventListener('input',()=>{countryPicker.activeIndex=-1;});
 });
 // Enter within the dropdown chooses a country, never submits the outer search.
 countryHost.addEventListener('keydown',event=>{if(event.key==='Enter')event.preventDefault();});
 const seen=new Set();
 async function search(append=false) {
  const version=++searchVersion;searchAbort?.abort();
  if(!append){offset=0;seen.clear();results.replaceChildren();lastQuery=query.value.trim();lastGenre=genre.value;lastCountry=countryCode;}
  const params=new URLSearchParams({name:lastQuery,tag:lastGenre,countrycode:lastCountry,hidebroken:'true',order:'votes',reverse:'true',limit:'40',offset:String(offset)});
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
   button.addEventListener('click',()=>{stop();addStation(station);save();start();});results.append(button);
  });
  searchStatus.textContent=seen.size?seen.size+' '+t('radio_results'):t('radio_no_results');more.hidden=rows.length<40;
 }
 form.addEventListener('submit',e=>{e.preventDefault();search();});
 genre.addEventListener('change',()=>search());
 more.addEventListener('click',()=>search(true));
 window.addEventListener('pagehide',()=>{searchVersion++;searchAbort?.abort();stop();});
 window.addEventListener('pageshow',e=>{if(e.persisted){if(results.getAttribute('aria-busy')==='true'){results.setAttribute('aria-busy','false');searchStatus.textContent=t('radio_search_hint');}}});
})();
