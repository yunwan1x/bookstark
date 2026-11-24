(function(){'use strict';
 const catalog=window.BookStarkPermissionCatalog||[],zh=()=>document.documentElement.lang.startsWith('zh'),text=(a,b)=>zh()?a:b,e=value=>escHtml(String(value));
 const legacyManaged=new Set(['read_files','save_files','socket_tcp']);
 const managed=spec=>spec.managed??legacyManaged.has(spec.key);
 function effective(p){const flags={...p};for(const spec of catalog)if(!managed(spec))flags[spec.key]=true;return flags;}
 function collect(form){const p={schema:1};for(const el of form.querySelectorAll('[data-tool-permission]')){const key=el.dataset.toolPermission,spec=catalog.find(item=>item.key===key);if(spec&&managed(spec))p[key]=el.checked;}return p;}
 function selected(p){const flags=effective(p);return catalog.filter(spec=>managed(spec)&&flags[spec.key]===true);}
 function list(p){const items=selected(p);return '<ul class="tool-permission-list">'+(items.length?items.map(spec=>'<li><strong>'+e(zh()?spec.zh:spec.en)+'</strong><span class="market-muted">'+e(zh()?spec.description_zh:spec.description_en)+'</span></li>').join(''):'<li>'+text('无需额外的 BookStark 权限','No additional BookStark permissions required')+'</li>')+'</ul>';}
 function sandbox(p,isolated){const flags=effective(p),tokens=['allow-scripts'];if(isolated)tokens.push('allow-same-origin');for(const spec of catalog)if(spec.sandbox&&flags[spec.key])tokens.push(spec.sandbox);return tokens.join(' ');}
 function allow(p,isolated){const flags=effective(p),supported=document.featurePolicy?.features?.();return catalog.filter(spec=>spec.policy&&(!supported||supported.includes(spec.policy))).map(spec=>spec.policy+' '+(flags[spec.key]?(isolated?"'src'":'*'):"'none'")).join('; ');}
 function added(old,next){const before=effective(old),after=effective(next);return catalog.filter(spec=>managed(spec)&&after[spec.key]&&!before[spec.key]);}
 window.BookStarkToolPermissions={catalog,effective,collect,selected,list,sandbox,allow,added};
})();
