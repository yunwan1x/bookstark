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
 const stations=new Set(['rsc_de','rsj','rsp']);
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
  audio.src='https://stream.srg-ssr.ch/srgssr/'+select.value+'/mp3/128';
  waitForStream();
  try { await audio.play(); } catch (_) { if(request===generation&&active)failed(); }
 }
 audio.volume=0.5;
 try {
  const saved=JSON.parse(localStorage.getItem('bookstark:public-radio')||'null');
  if(saved&&stations.has(saved.station))select.value=saved.station;
  if(saved&&typeof saved.volume==='number'&&saved.volume>=0&&saved.volume<=1)audio.volume=volume.value=saved.volume;
 }catch(_){}
 function updateSource(){document.getElementById('publicRadioSource').href='https://www.radioswiss'+({rsc_de:'classic',rsj:'jazz',rsp:'pop'}[select.value])+'.ch/en/reception/internet';}
 updateSource();
 function save(){try{localStorage.setItem('bookstark:public-radio',JSON.stringify({station:select.value,volume:audio.volume}));}catch(_){}}
 play.addEventListener('click',()=>active?stop():start());
 select.addEventListener('change',()=>{const resume=active;stop();updateSource();save();if(resume)start();});
 volume.addEventListener('input',()=>{audio.volume=Number(volume.value);save();});
 audio.addEventListener('playing',()=>{if(active){clearTimeout(timeout);render('playing');}});
 audio.addEventListener('waiting',()=>{if(active)waitForStream();});
 audio.addEventListener('error',failed);
 audio.addEventListener('ended',()=>stop());
 window.addEventListener('pagehide',()=>{clearInterval(clockTimer);stop();});
 window.addEventListener('pageshow',e=>{if(e.persisted){tick();clockTimer=setInterval(tick,15000);}});
})();
