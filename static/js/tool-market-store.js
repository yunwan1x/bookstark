(function () {
  'use strict';
  const workspace=document.body.dataset.marketWorkspace||'guest';
  const authenticated=workspace!=='guest';
  const channel=typeof BroadcastChannel==='function'?new BroadcastChannel('bookstark-market-'+workspace):null;
  function announce(){window.dispatchEvent(new Event('tool-market-changed'));if(channel)channel.postMessage('changed');}
  if(channel)channel.onmessage=()=>window.dispatchEvent(new Event('tool-market-changed'));
  async function request(path,method='GET',body){
    if(!authenticated)throw Error('login');
    const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),150000);
    try{
      const options={method,cache:'no-store',signal:controller.signal};
      if(body!==undefined){options.headers={'Content-Type':'application/json'};options.body=JSON.stringify(body);}
      const response=await fetchWithCurrentCSRF('/api/tool-installs'+path,options);
      if(!response.ok){const error=await response.json().catch(()=>({}));throw Error(response.status===401?'login':error.error||'storage');}
      return await response.json();
    }finally{clearTimeout(timer);}
  }
  async function list(){if(!authenticated)return [];return (await request('')).tools;}
  async function get(name,id){try{return await request('/'+id+(name==='packages'?'?part=package':name==='data'?'?part=data':''));}catch(error){if(error.message==='not_found')return undefined;throw error;}}
  async function install(pkg,expected,instance){await request('/'+pkg.id,'PUT',{revision:pkg.revision,hash:pkg.hash||'',expected:expected||'',instance:instance||''});announce();}
  async function remove(id,revision,instance,keep_data=false){await request('/'+id,'DELETE',{revision,instance,keep_data});announce();}
  async function patch(id,values){await request('/'+id,'PATCH',values);announce();}
  async function writeData(id,revision,instance,op,key,value){await request('/'+id+'/data','POST',{revision,instance,op,key,value});}
  async function file(id,revision,instance,method,name,content){
    const url='/api/tool-installs/'+id+'/files/'+name.split('/').map(encodeURIComponent).join('/');
    const options={method,cache:'no-store',headers:{'X-Tool-Revision':revision,'X-Tool-Instance':instance}};
    if(method==='PUT'){options.headers['Content-Type']='application/octet-stream';options.body=content;}
    const response=await fetchWithCurrentCSRF(url,options);if(!response.ok)throw Error('storage');return method==='GET'?response.arrayBuffer():undefined;
  }
  window.BookStarkMarketStore={authenticated,list,get,install,remove,patch,writeData,file,snapshot:id=>request('/'+id+'?part=runtime')};
})();
