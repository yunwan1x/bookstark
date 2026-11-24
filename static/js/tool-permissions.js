(function(){'use strict';
 const catalog=window.BookStarkPermissionCatalog||[],zh=()=>document.documentElement.lang.startsWith('zh'),text=(a,b)=>zh()?a:b,e=value=>escHtml(String(value));
 function effective(p){p={...p};if(!p.schema){p.downloads=true;p.forms=true;}return p;}
 function collect(form){const p={schema:1};for(const el of form.querySelectorAll('[data-tool-permission]'))p[el.dataset.toolPermission]=el.checked;return p;}
 function selected(p){p=effective(p);return catalog.filter(spec=>p[spec.key]===true);}
 function list(p){const items=selected(p);return '<ul class="tool-permission-list">'+(items.length?items.map(spec=>'<li><strong>'+e(zh()?spec.zh:spec.en)+'</strong><span class="market-muted">'+e(zh()?spec.description_zh:spec.description_en)+'</span></li>').join(''):'<li>'+text('未声明额外权限','No additional capabilities declared')+'</li>')+'</ul>'+(!p?.network?'<p class="market-muted">'+text('网页网络接口请求受限','Browser network requests are restricted.')+'</p>':'')+'<p class="market-muted">'+text('权限声明不等于浏览器授权。摄像头、麦克风等仍由你确认；远端使用设备能力需配置独立运行来源。','Declarations do not grant browser consent. You still approve device access; remote device APIs require a configured isolated runtime origin.')+'</p>';}
 function sandbox(p,isolated){const flags=effective(p),tokens=['allow-scripts'];if(isolated)tokens.push('allow-same-origin');for(const spec of catalog)if(spec.sandbox&&flags[spec.key])tokens.push(spec.sandbox);return tokens.join(' ');}
 function allow(p,isolated){const flags=effective(p),supported=document.featurePolicy?.features();return catalog.filter(spec=>spec.policy&&(!supported||supported.includes(spec.policy))).map(spec=>spec.policy+' '+(flags[spec.key]&&(isolated||['fullscreen','autoplay','picture-in-picture'].includes(spec.policy))?(isolated?"'src'":'*'):"'none'")).join('; ');}
 function added(old,next){const before=effective(old),after=effective(next);return catalog.filter(spec=>after[spec.key]&&!before[spec.key]);}
 window.BookStarkToolPermissions={catalog,effective,collect,selected,list,sandbox,allow,added};
})();
