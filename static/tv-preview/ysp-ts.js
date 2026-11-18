/* SuperLive public-live TS preprocessing, reconstructed from observed APK behavior.
 * Input keys are per-NAL bytes; no stored account/session/private keys.
 * Mode 1 = YSP AVC; mode 2 = H5E AVC. */
(function(root){
'use strict';
function unescapeNal(n){const out=[];for(let i=0;i<n.length;i++){if(i+3<n.length&&n[i]===0&&n[i+1]===0&&n[i+2]===3&&n[i+3]<=3){out.push(0,0);i+=2;}else out.push(n[i]);}return Uint8Array.from(out);}
class Bits{constructor(d,p=0){this.d=d;this.p=p;}read(n){if(n>32||this.p+n>this.d.length*8)throw Error('Truncated AVC header');let v=0;for(let i=0;i<n;i++)v=v*2+((this.d[this.p>>>3]>>>(7-(this.p++&7)))&1);return v;}ue(){let n=0;while(this.read(1)===0){if(++n>30)throw Error('Invalid AVC header');}return 2**n-1+this.read(n);}se(){const x=this.ue();return x&1?(x+1)/2:-x/2;}}
function frameBits(n){try{const b=new Bits(unescapeNal(n),8),profile=b.read(8);b.read(8);b.read(8);b.ue();if([100,110,122,244,44,83,86,118,128,138,139,134,135].includes(profile)){const chroma=b.ue();if(chroma===3)b.read(1);b.ue();b.ue();b.read(1);if(b.read(1)){for(let i=0;i<(chroma!==3?8:12);i++)if(b.read(1)){let last=8,next=8;for(let j=0;j<(i<6?16:64);j++){if(next!==0)next=(last+b.se()+256)%256;last=next===0?last:next;}}}}const bits=b.ue()+4;return bits<=16?bits:4;}catch{return 4;}}
function tea(n,o,k){const v=new DataView(n.buffer,n.byteOffset,n.byteLength);let a=v.getUint32(o,true),b=v.getUint32(o+4,true),sum=0xe3779b90;for(let i=0;i<16;i++){b=(b-((((a<<4)+k[2])^((a+sum)|0)^((a>>>5)+k[3]))))>>>0;a=(a-((((b<<4)+k[0])^((b+sum)|0)^((b>>>5)+k[1]))))>>>0;sum=(sum-0x9e3779b9)>>>0;}v.setUint32(o,a,true);v.setUint32(o+4,b,true);}
function starts(d){const a=[];for(let i=0;i+3<d.length;i++){if(d[i]===0&&d[i+1]===0){if(d[i+2]===1){a.push({s:i,a:i+3});i+=2;}else if(d[i+2]===0&&d[i+3]===1){a.push({s:i,a:i+4});i+=3;}}}return a;}
function transformPes(d,mode,state){const st=starts(d),parts=[];let prev=0,total=0;for(let j=0;j<st.length;j++){const {a}=st[j],end=j+1<st.length?st[j+1].s:d.length;let n=d.subarray(a,end);const t=n[0]&31;parts.push(d.subarray(prev,a));total+=a-prev;
if((mode===1||state.normalizeAvc)&&t===7&&n.length>2){n=n.slice();state.encrypted=[1,2].includes(n[2]&3);n[2]&=252;state.frameBits=frameBits(n);}
if((mode===2?[1,5,25].includes(t):t>=1&&t<=5)&&n.length>128&&(mode===2||state.encrypted)){n=unescapeNal(n);const v=new DataView(n.buffer,n.byteOffset,n.byteLength),keyOff=mode===2?16:t===5?5:1,k=[0,1,2,3].map(i=>v.getUint32(keyOff+i*4,true));let stride=80;if(mode===1){if(t===5)stride=160+(n[5]&3)*32;else{try{const b=new Bits(n,8);b.ue();b.ue();b.ue();stride=(b.read(state.frameBits)&(1<<(state.frameBits-1)))?256:224;}catch{stride=224;}}}for(let o=32;o+(mode===1?17:8)<=n.length;o+=stride)tea(n,o,k);state.nals++;}
parts.push(n);total+=n.length;prev=end;}parts.push(d.subarray(prev));total+=d.length-prev;const out=new Uint8Array(total);let o=0;for(const p of parts){out.set(p,o);o+=p.length;}
// Unescaping can shorten video PES. TS video permits an unspecified length;
// discard the stale bound for browser demuxers while preserving native oracle mode.
if(state.normalizeAvc&&out.length>=6&&out[0]===0&&out[1]===0&&out[2]===1&&out[3]>=224&&out[3]<=239){out[4]=0;out[5]=0;}
return out;}
// Select AVC from PAT/PMT instead of assuming PID 0x100. Some CCTV1 muxes use 0x101.
function avcPid(src){
 const pmts=new Set();
 function payload(at){const af=(src[at+3]>>>4)&3;if(!(af&1))return -1;const p=af===3?5+src[at+4]:4;return p<188?p:-1;}
 function section(at){const p=payload(at);if(p<0||!(src[at+1]&64))return null;const start=at+p+1+src[at+p];if(start+3>at+188)return null;const end=start+3+((src[start+1]&15)<<8)+src[start+2];return end<=at+188?{start,end}:null;}
 for(let at=0;at+188<=src.length;at+=188){if(src[at]!==71)throw Error('Invalid TS sync byte');const pid=((src[at+1]&31)<<8)|src[at+2];if(pid!==0)continue;const s=section(at);if(!s||src[s.start]!==0)continue;for(let i=s.start+8;i+4<=s.end-4;i+=4)if(src[i]||src[i+1])pmts.add(((src[i+2]&31)<<8)|src[i+3]);}
 for(let at=0;at+188<=src.length;at+=188){const pid=((src[at+1]&31)<<8)|src[at+2];if(!pmts.has(pid))continue;const s=section(at);if(!s||src[s.start]!==2||s.start+12>s.end-4)continue;let i=s.start+12+((src[s.start+10]&15)<<8)+src[s.start+11];for(;i+5<=s.end-4;){const len=((src[i+3]&15)<<8)|src[i+4];if(i+5+len>s.end-4)break;if(src[i]===27)return ((src[i+1]&31)<<8)|src[i+2];i+=5+len;}}
 // A fragment may omit PSI. A video PES start still identifies the payload PID.
 for(let at=0;at+188<=src.length;at+=188){const p=payload(at);if(p<0||!(src[at+1]&64)||p+4>188)continue;const i=at+p;if(src[i]===0&&src[i+1]===0&&src[i+2]===1&&src[i+3]>=224&&src[i+3]<=239)return ((src[at+1]&31)<<8)|src[at+2];}
 return 256;
}
function transform(input,mode=2,options={}){if(mode!==1&&mode!==2)throw Error('Unsupported live transform mode');const src=new Uint8Array(input);if(src.length%188!==0)throw Error('Incomplete TS segment');const videoPid=avcPid(src),out=src.slice(),state={encrypted:false,frameBits:4,nals:0,normalizeAvc:options.normalizeAvc===true};let packets=[],size=0;
function flush(){if(!packets.length)return;const pes=new Uint8Array(size);let pos=0;for(const p of packets){pes.set(src.subarray(p.at+p.off,p.at+188),pos);pos+=188-p.off;}const cooked=transformPes(pes,mode,state);if(cooked.length>size)throw Error('Live transform expanded unexpectedly');pos=0;for(const p of packets){const cap=188-p.off,n=Math.min(cap,cooked.length-pos),at=p.at;if(n===cap){out.set(cooked.subarray(pos,pos+n),at+p.off);}else{const adaptationLength=183-n;out[at+3]=(out[at+3]&0xcf)|0x30;out[at+4]=adaptationLength;if(adaptationLength>0){const old=(src[at+3]>>>4)&3;out[at+5]=old===3&&src[at+4]>0?src[at+5]:0;out.fill(255,at+6,at+5+adaptationLength);}out.set(cooked.subarray(pos,pos+n),at+188-n);}pos+=n;}packets=[];size=0;}
for(let at=0;at<src.length;at+=188){if(src[at]!==71)throw Error('Invalid TS sync byte');const pid=((src[at+1]&31)<<8)|src[at+2],af=(src[at+3]>>>4)&3;if(pid!==videoPid||!(af&1))continue;const off=af===3?5+src[at+4]:4;if(off>188)throw Error('Invalid TS adaptation length');if(src[at+1]&64)flush();packets.push({at,off});size+=188-off;}flush();return out;}
root.SuperliveTsTransform={transform};if(typeof module!=='undefined')module.exports=root.SuperliveTsTransform;
})(typeof window!=='undefined'?window:globalThis);
