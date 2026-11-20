/* Format cached publication dates after initial render and AJAX navigation. */
(()=>{'use strict';
function hydrate(){document.querySelectorAll('[data-news-time]').forEach(e=>{const n=Number(e.dataset.newsTime);e.textContent=n?new Date(n*1000).toLocaleString(document.documentElement.lang==='zh'?'zh-CN':'en-US',{month:'short',day:'numeric',hour:'2-digit',minute:'2-digit'}):window.__('news.unknown_date');if(n>0)e.dateTime=new Date(n*1000).toISOString();else e.removeAttribute('datetime');});}
document.addEventListener('bookstark:public-feed-updated',hydrate);hydrate();
})();
