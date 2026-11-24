(function(){
 'use strict';
 const U=ToolMarketUI,{text:t,esc:e,api}=U,params=new URLSearchParams(location.search);
 const root=document.getElementById('toolPublishSelection');if(!root)return;
 const query=document.getElementById('publishSourceQuery'),state=document.getElementById('publishSourceState'),sort=document.getElementById('publishSourceSort'),next=document.getElementById('publishSourceNext'),rows=document.getElementById('publishSourceRows'),status=document.getElementById('publishSourceStatus');
 let page=Math.max(1,Number(params.get('page'))||1),selectedID=Math.max(0,Number(params.get('selected'))||0),selected=null,articles=[],loadVersion=0,timer=0;
 const skeletons=rows.innerHTML,list=document.getElementById('publishSourceList'),empty=document.getElementById('publishSourceEmpty'),pagination=document.getElementById('publishSourcePagination');
 const returnTo=U.marketReturn(params.get('return'));
 const take=['10','20','50'].includes(params.get('take'))?params.get('take'):'10';
 root.querySelectorAll('[data-return-market]').forEach(link=>link.href=returnTo);
 query.value=params.get('q')||'';
 state.value=['all','published','unpublished'].includes(params.get('status'))?params.get('status'):'all';
 sort.value=params.get('sort')==='name'?'name':'updated';
 function updateURL(){
  const url=new URL('/market/publish',location.origin);url.searchParams.set('return',returnTo);
  for(const [key,value,fallback]of [['q',query.value,''],['status',state.value,'all'],['sort',sort.value,'updated'],['page',String(page),'1'],['take',take,'10'],['selected',String(selectedID),'0']])if(value!==fallback)url.searchParams.set(key,value);
  history.replaceState(null,'',url.pathname+url.search);
 }
 function selection(){
  document.getElementById('publishSourceSelected').textContent=selected?t('已选择：','Selected: ')+selected.title:t('尚未选择文章','No article selected');
  next.disabled=!selected;
  rows.querySelectorAll('input[name=publish_source]').forEach(input=>input.checked=Number(input.value)===selectedID);
 }
 function dateText(value){const date=new Date(value);return Number.isNaN(date.getTime())?'—':new Intl.DateTimeFormat(document.documentElement.lang,{dateStyle:'short',timeStyle:'short'}).format(date);}
 function showLoading(){
  next.disabled=true;root.setAttribute('aria-busy','true');list.disabled=true;list.hidden=false;empty.hidden=true;
  rows.innerHTML=skeletons;pagination.replaceChildren();document.getElementById('publishSourceCount').textContent='';
  document.getElementById('publishSourceRetry').hidden=true;status.className='market-muted';status.hidden=false;status.textContent=t('正在读取文章…','Loading articles…');
 }
 async function load(){
  const token=++loadVersion;showLoading();
  const p=new URLSearchParams({q:query.value,status:state.value,sort:sort.value,take,page:String(page),selected:String(selectedID)});
  try{
   const result=await api('/api/tool-market/articles?'+p);if(token!==loadVersion)return;
   articles=result.articles;page=result.page;selected=result.selected;selectedID=selected?selected.id:0;
   document.getElementById('publishSourceCount').textContent=t('共 ','')+result.total+t(' 篇',result.total===1?' article':' articles');
   rows.innerHTML=articles.map(article=>'<label class="publish-source-row" for="publish-source-'+article.id+'" data-source-id="'+article.id+'"><input type="radio" id="publish-source-'+article.id+'" name="publish_source" value="'+article.id+'"><span class="publish-source-body"><span class="publish-source-title"><strong>'+e(article.title)+'</strong><span class="tag-badge">HTML</span></span><span class="publish-source-description">'+e(article.description||'')+'</span></span><span class="publish-source-status"><span class="tag-badge'+(article.published?' is-published':'')+'">'+(article.published?t('工具','Tool'):t('未发布','Unpublished'))+'</span>'+(article.published?'<span>v'+e(article.version)+'</span>':'')+'</span><time class="publish-source-updated" datetime="'+escAttr(article.updated)+'">'+e(dateText(article.updated))+'</time></label>').join('');
   list.hidden=!articles.length;empty.hidden=!!articles.length;
   renderPagination('publishSourcePagination',page,result.total_pages,value=>{page=value;load();});status.hidden=true;selection();updateURL();
  }catch(error){if(token!==loadVersion)return;rows.replaceChildren();list.hidden=true;status.textContent=U.errorText(error);status.className='market-error';document.getElementById('publishSourceRetry').hidden=false;}
  finally{if(token===loadVersion){root.removeAttribute('aria-busy');list.disabled=false;}}
 }
 rows.addEventListener('change',event=>{const input=event.target.closest('input[name=publish_source]');if(!input)return;selectedID=Number(input.value);selected=articles.find(article=>article.id===selectedID)||null;selection();updateURL();});
 next.onclick=()=>{if(!selected||next.disabled)return;location.assign('/market/publish/'+selected.id+'?selection='+encodeURIComponent(location.pathname+location.search));};
 function filter(){clearTimeout(timer);page=1;load();}
 query.oninput=()=>{clearTimeout(timer);++loadVersion;showLoading();timer=setTimeout(filter,220);};
 document.getElementById('publishSourceSearch').onsubmit=event=>{event.preventDefault();filter();};
 state.onchange=sort.onchange=filter;document.getElementById('publishSourceRetry').onclick=()=>load();
 load();
})();
