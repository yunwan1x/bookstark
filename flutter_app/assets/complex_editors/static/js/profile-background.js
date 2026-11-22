(function(){
    'use strict';
    const root=document.getElementById('profile-background');
    if(!root || !window.BookStarkAppearance)return;
    const mode=document.getElementById('background-mode'),animated=document.getElementById('background-animated'),fade=document.getElementById('background-fade'),file=document.getElementById('background-file'),status=document.getElementById('background-status');
    let saved={...window.BookStarkAppearance},url='',remove=false,busy=false;
    const t=k=>window.__(k);
    function revoke(){if(url)URL.revokeObjectURL(url);url='';}
    function value(){return {mode:mode.value,animated:animated.checked,fade:Number(fade.value),image_hash:remove?'':saved.image_hash};}
    function preview(){
        document.getElementById('background-motion').hidden=mode.value!=='dynamic';
        document.getElementById('background-image-options').hidden=mode.value!=='image';
        document.getElementById('background-fade-value').textContent=fade.value+'%';
        window.BookStarkApplyAppearance(value(),url);
    }
    function fill(p){mode.value=p.mode;animated.checked=p.animated;fade.value=p.fade;preview();}
    mode.onchange=animated.onchange=fade.oninput=()=>{status.textContent=t('background.unsaved');preview();};
    file.onchange=()=>{
        revoke();const f=file.files[0];
        if(f && (!['image/png','image/jpeg','image/webp'].includes(f.type)||f.size>5*1024*1024)){file.value='';status.textContent=t('background.invalid');preview();return;}
        if(f){url=URL.createObjectURL(f);remove=false;}
        status.textContent=t('background.unsaved');preview();
    };
    document.getElementById('background-reset').onclick=()=>{revoke();file.value='';remove=true;fill({mode:'dynamic',animated:true,fade:65});status.textContent=t('background.unsaved');};
    document.getElementById('background-save').onclick=async()=>{
        if(busy)return;
        const p=value();if(p.mode==='image'&&!url&&!p.image_hash){status.textContent=t('background.required');return;}
        busy=true;root.querySelectorAll('button,input,select').forEach(el=>el.disabled=true);status.textContent=t('background.saving');
        try{
            const body=new FormData();body.append('mode',p.mode);body.append('animated',p.animated);body.append('fade',p.fade);body.append('remove',remove);
            if(file.files[0])body.append('file',file.files[0]);
            const res=await csrfFetch('/api/profile/background',{method:'PUT',body,offlinePolicy:'reject'}),data=await res.json();
            if(!res.ok||data.code!==0)throw new Error(data.message||t('background.error'));
            saved=data.data;remove=false;revoke();file.value='';fill(saved);status.textContent=t('background.saved');
        }catch(err){status.textContent=t('background.error')+' '+(err.message||'');}
        finally{busy=false;root.querySelectorAll('button,input,select').forEach(el=>el.disabled=false);}
    };
    window.addEventListener('pagehide',revoke);
    fill(saved);
})();
