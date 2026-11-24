(function(){
 'use strict';
 const U=ToolMarketUI,t=U.text,e=U.esc,params=new URLSearchParams(location.search),article=document.getElementById('publishArticlePanel'),panel=document.getElementById('publishPackagePanel');if(!panel)return;
 const input=document.getElementById('publishPackageFile'),choose=document.getElementById('publishPackageChoose'),drop=document.getElementById('publishPackageDrop'),status=document.getElementById('publishPackageStatus'),next=document.getElementById('publishPackageNext'),progress=document.getElementById('publishPackageProgress'),bar=document.getElementById('publishPackageProgressBar'),checked=document.getElementById('publishPackageCheck'),entry=document.getElementById('publishPackageEntry');
 let xhr=null,uploadVersion=0,selected=null,tool=Number(params.get('tool'))||0;
 const draftKey='bookstark:tool-package:'+U.workspace()+':'+tool;
 function source(kind){article.hidden=kind==='package';panel.hidden=kind!=='package';for(const [id,value]of [['publishArticleTab','article'],['publishPackageTab','package']]){const b=document.getElementById(id);b.setAttribute('aria-pressed',String(value===kind));b.classList.toggle('active',value===kind)}const url=new URL(location.href);url.searchParams.set('source',kind);history.replaceState(null,'',url.pathname+url.search)}
 document.getElementById('publishArticleTab').onclick=()=>source('article');document.getElementById('publishPackageTab').onclick=()=>source('package');
 function message(text,error=false){status.textContent=text;status.className=error?'market-error':'market-muted';status.setAttribute('role',error?'alert':'status')}
 function persist(){if(selected)try{sessionStorage.setItem(draftKey,JSON.stringify({id:tool,token:selected.token,entry:entry.value}));sessionStorage.setItem('bookstark:tool-package:'+U.workspace()+':'+tool,JSON.stringify({id:tool,token:selected.token,entry:entry.value}))}catch(_){}}
 function show(p,id){selected=p;tool=id;progress.hidden=true;checked.hidden=false;drop.hidden=true;next.disabled=false;
  document.getElementById('publishPackageCheckedName').textContent=p.name;
  document.getElementById('publishPackageSummary').textContent=U.size(p.size)+' · '+t('解压后 ','Extracted ')+U.size(p.expanded_size)+' · '+p.files.length+t(' 项资源',' files');
  document.getElementById('publishPackageFiles').innerHTML=p.files.map(f=>'<li><code>'+e(f.name)+'</code><span class="market-muted">'+U.size(f.size)+'</span></li>').join('');entry.replaceChildren(...p.entries.map(name=>{const option=document.createElement('option');option.value=name;option.textContent=name;return option}));entry.value=p.entry;
  document.getElementById('publishPackageManifest').textContent=p.config?t('已读取 tool.json，下一步可修改发布设置。','tool.json loaded. Review settings on the next page.'):t('没有 tool.json，下一步手动填写发布设置。','No tool.json. Fill in publishing settings on the next page.');message(t('工具包检查通过。','Package checks passed.'));persist();
 }
 entry.onchange=persist;
 function reset(){next.disabled=true;checked.hidden=true;progress.hidden=true;drop.hidden=false;choose.disabled=false;input.value='';selected=null}
 function upload(file){if(!file||xhr)return;if(!/\.zip$/i.test(file.name)){message(t('请选择 ZIP 工具包。','Choose a ZIP package.'),true);return}if(file.size>64*1024*1024){message(t('压缩包不能超过 64 MiB。','The archive must not exceed 64 MiB.'),true);return}
  const version=++uploadVersion;reset();progress.hidden=false;choose.disabled=true;bar.value=0;document.getElementById('publishPackageName').textContent=file.name;message(t('正在上传…','Uploading…'));
  const start=()=>{if(version!==uploadVersion)return;const data=new FormData();data.append('file',file);if(tool)data.append('tool_id',String(tool));const req=xhr=new XMLHttpRequest();req.open('POST','/api/tool-packages');req.timeout=180000;req.setRequestHeader('X-CSRF-Token',readCSRFCookie());
   req.upload.onprogress=event=>{if(event.lengthComputable){bar.value=Math.round(event.loaded/event.total*100);message(bar.value===100?t('上传完成，正在解包检查…','Upload complete. Checking package…'):t('正在上传 ','Uploading ')+bar.value+'%')}};
   req.onload=()=>{if(version!==uploadVersion)return;xhr=null;choose.disabled=false;let result;try{result=JSON.parse(req.responseText)}catch(_){result={error:'invalid_archive'}}if(req.status>=200&&req.status<300)show(result.package,result.id);else{reset();message(U.errorText(Error(result.error))+(result.detail?' · '+result.detail:''),true)}};
   req.onerror=req.ontimeout=()=>{if(version!==uploadVersion)return;xhr=null;reset();message(t('上传失败，请重新选择文件重试。','Upload failed. Choose the file to retry.'),true)};req.onabort=()=>{};req.send(data);
  };if(readCSRFCookie())start();else refreshCSRFCookie().then(start).catch(()=>{reset();message(t('无法读取会话，请刷新后重试。','Could not load session. Refresh and retry.'),true)});
 }
 choose.onclick=()=>input.click();document.getElementById('publishPackageReplace').onclick=()=>input.click();input.onchange=()=>upload(input.files[0]);
 drop.ondragover=event=>{event.preventDefault();drop.classList.add('is-dragging')};drop.ondragleave=()=>drop.classList.remove('is-dragging');drop.ondrop=event=>{event.preventDefault();drop.classList.remove('is-dragging');upload(event.dataTransfer.files[0])};
 document.getElementById('publishPackageCancel').onclick=()=>{++uploadVersion;xhr?.abort();xhr=null;reset();message(t('已取消上传。','Upload cancelled.'))};
 next.onclick=()=>{if(!selected)return;persist();const query=new URLSearchParams({package:selected.token,entry:entry.value});location.assign('/market/packages/'+tool+'?'+query)};
 source(params.get('source')==='package'?'package':'article');
 U.api('/api/tool-publications').then(result=>{
  const items=result.tools||[];document.getElementById('publishPackageDrafts').hidden=!items.length;
  document.getElementById('publishPackageDraftRows').innerHTML=items.map(row=>'<div class="market-review publish-package-draft-row"><div><strong>'+e(row.title||row.name)+'</strong><p class="market-muted">'+e(row.name)+'</p></div><span class="tag-badge">'+(row.status==='published'?t('已发布','Published'):t('草稿','Draft'))+'</span><a class="bs-btn bs-btn-cancel" href="/market/packages/'+row.id+'?package='+encodeURIComponent(row.package)+'">'+t('发布设置','Publish settings')+'</a></div>').join('');
 }).catch(()=>{});
 (async()=>{try{const saved=JSON.parse(sessionStorage.getItem(draftKey)||'null');if(saved){show(await U.api('/api/tool-packages/'+encodeURIComponent(saved.token)),saved.id);entry.value=saved.entry||entry.value}}catch(_){}})();
})();
