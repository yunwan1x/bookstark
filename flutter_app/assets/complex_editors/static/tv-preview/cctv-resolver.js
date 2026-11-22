/* Anonymous CCTV News public H5 resolver. No account, proxy or stored URLs. */
(() => {
'use strict';
const bytes = s => new TextEncoder().encode(s);
const hex = b => [...new Uint8Array(b)].map(v=>v.toString(16).padStart(2,'0')).join('');
const unhex = s => new Uint8Array(s.match(/../g).map(x=>parseInt(x,16)));
function md5(text) {
 const b=bytes(text), n=((b.length+8>>>6)+1)*16, x=new Int32Array(n);
 for(let i=0;i<b.length;i++)x[i>>2]|=b[i]<<((i%4)*8);
 x[b.length>>2]|=128<<((b.length%4)*8);x[n-2]=b.length*8;
 let a=0x67452301,b0=0xefcdab89|0,c=0x98badcfe|0,d=0x10325476;
 const shifts=[[7,12,17,22],[5,9,14,20],[4,11,16,23],[6,10,15,21]];
 for(let j=0;j<n;j+=16){let A=a,B=b0,D=d,E=c;
  for(let i=0;i<64;i++){let f,g;if(i<16){f=(B&E)|(~B&D);g=i;}else if(i<32){f=(D&B)|(~D&E);g=(5*i+1)%16;}else if(i<48){f=B^E^D;g=(3*i+5)%16;}else{f=E^(B|~D);g=7*i%16;}
   const sum=(A+f+x[j+g]+(Math.floor(Math.abs(Math.sin(i+1))*4294967296)|0))|0,s=shifts[i>>4][i%4];
   A=D;D=E;E=B;B=(B+((sum<<s)|(sum>>>(32-s))))|0;
  }a=(a+A)|0;b0=(b0+B)|0;c=(c+E)|0;d=(d+D)|0;
 }
 const out=new Uint8Array(16);[a,b0,c,d].forEach((v,i)=>{for(let k=0;k<4;k++)out[4*i+k]=(v>>>(8*k))&255;});return hex(out);
}
function random(n,alphabet='abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789') {return [...crypto.getRandomValues(new Uint8Array(n))].map(b=>alphabet[b%alphabet.length]).join('');}
function fail(stage,code){const error=new Error(stage+': '+code);error.stage=stage;error.code=code;return error;}
function find(object,key){if(!object||typeof object!=='object')return undefined;if(Object.hasOwn(object,key))return object[key];for(const value of Object.values(object)){const found=find(value,key);if(found!==undefined)return found;}}
const CCTV_CHANNELS = {"cctv1": "11200132825562653886", "cctv2": "12030532124776958103", "cctv4": "10620168294224708952", "cctv7": "8516529981177953694", "cctv9": "7252237247689203957", "cctv10": "14589146016461298119", "cctv12": "13180385922471124325", "cctv13": "16265686808730585228", "cctv17": "4496917190172866934", "cctv4k": "2127841942201075403"};
function cctvId(source){const raw=typeof source==='string'?source:source?.original||source?.url||'';const m=/^cctv:\/\/([^?$#\s]*)(?:\$[^\r\n]*)?$/.exec(raw);return m?(CCTV_CHANNELS[m[1]||'cctv1']||(/^\d+$/.test(m[1])?m[1]:null)):null;}
async function cctvResolve(source,{signal,onStage=()=>{}}={}) {
 const id=cctvId(source);if(!id)throw fail('input','UNSUPPORTED_SOURCE');
 const t=String(Math.floor(Date.now()/1000)),q='articleId='+id+'&scene_type=6';
 const key=await crypto.subtle.importKey('raw',bytes('emasgatewayh5'),{name:'HMAC',hash:'SHA-256'},false,['sign']);
 const sign=hex(await crypto.subtle.sign('HMAC',key,bytes('&&&20000009&'+md5(q)+'&'+t+'&emas.feed.article.live.detail&1.0.0&&&&&')));
 onStage({stage:'emas',state:'request'});
 let response;try{response=await fetch('https://emas-api.cctvnews.cctv.com/h5/emas.feed.article.live.detail/1.0.0?'+q,{signal:signal?AbortSignal.any([signal,AbortSignal.timeout(15000)]):AbortSignal.timeout(15000),mode:'cors',credentials:'omit',referrerPolicy:'no-referrer',headers:{cookieuid:md5(Date.now()+random(10)),'from-client':'h5','x-emas-gw-appkey':'20000009','x-emas-gw-pv':'6.1','x-emas-gw-sign':sign,'x-emas-gw-t':t,'x-req-ts':t+'000'}});}catch(error){if(signal?.aborted)throw signal.reason||error;throw fail('emas',error.name==='TimeoutError'?'TIMEOUT':'CORS_OR_NETWORK');}
 if(!response.ok)throw fail('emas','HTTP_'+response.status);
 const envelope=await response.json();onStage({stage:'emas',state:'response',httpStatus:response.status,code:envelope.code??null});
 const b64bytes=text=>Uint8Array.from(atob(text),c=>c.charCodeAt(0));
 let data;try{data=JSON.parse(new TextDecoder().decode(b64bytes(envelope.response)));}catch{throw fail('emas','INVALID_RESPONSE');}
 const dk=find(data,'dk'),enc=find(data,'authUrl');if(typeof dk!=='string'||dk.length<8||!enc)throw fail('emas','NO_PLAYURL_OR_KEY');
 const aes=await crypto.subtle.importKey('raw',bytes(dk.slice(0,8)+t.slice(-8)),'AES-CBC',false,['decrypt']);
 let url;try{url=new URL(new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-CBC',iv:bytes(dk.slice(-8)+t.slice(0,8))},aes,b64bytes(enc))));}catch{throw fail('emas','DECRYPT_OR_URL_FAILED');}
 if(url.protocol!=='https:'||url.username||url.password)throw fail('emas','INSECURE_PLAYURL');
 return {url:url.href,transform:null};
}
globalThis.SuperliveCctv=Object.freeze({canResolve:s=>Boolean(cctvId(s)),resolve:cctvResolve});

})();
