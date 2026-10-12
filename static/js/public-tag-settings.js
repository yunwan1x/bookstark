(function(){
 'use strict';
 document.querySelectorAll('.public-tag-editor').forEach(function(root){
  const value=root.querySelector('.public-tags-value'),mode=root.querySelector('.public-tags-mode'),search=root.querySelector('.public-tags-search'),list=root.querySelector('.public-tags-selected');
  let labels=JSON.parse(value.value).labels||[];
  const options=Array.from(root.querySelectorAll('[data-tag]'));
  function action(text,key,fn){const b=document.createElement('button');b.type='button';b.className='row-action';b.textContent=text;b.title=window.__(key);b.setAttribute('aria-label',window.__(key));b.onclick=fn;return b;}
  function render(){
   value.value=JSON.stringify({mode:mode.value,labels});
   root.querySelector('.public-tags-auto').hidden=mode.value!=='auto';
   root.querySelector('.public-tags-manual').hidden=mode.value!=='manual';
   list.replaceChildren();
   labels.forEach((name,i)=>{const li=document.createElement('li'),span=document.createElement('span');span.textContent=name;li.append(span);
    const up=action('↑','footer.manage.up',()=>{[labels[i-1],labels[i]]=[labels[i],labels[i-1]];render();});up.disabled=i===0;
    const down=action('↓','footer.manage.down',()=>{[labels[i+1],labels[i]]=[labels[i],labels[i+1]];render();});down.disabled=i===labels.length-1;
    li.append(up,down,action('×','public.tags.remove',()=>{labels.splice(i,1);render();}));list.append(li);
   });
   options.forEach(b=>{b.hidden=labels.includes(b.dataset.tag)||!b.dataset.tag.toLocaleLowerCase().includes(search.value.trim().toLocaleLowerCase());b.disabled=labels.length>=100;});
  }
  options.forEach(b=>b.onclick=()=>{if(!labels.includes(b.dataset.tag)&&labels.length<100){labels.push(b.dataset.tag);render();}});
  mode.onchange=render;search.oninput=render;render();
 });
})();
