(function () {
    'use strict';
    const categories = {
        document: ['file-pdf', '#dc2626'], image: ['image', '#7c3aed'],
        media: ['photo-film', '#db2777'], development: ['code', '#0891b2'],
        productivity: ['diagram-project', '#d97706'], other: ['cube', '#2563eb']
    };
    function values(row) {
        row = row || {};
        const fallback = categories[row.category] || categories.other;
        const custom = typeof row.icon === 'string' && row.icon.length <= 48 && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(row.icon);
        return {
            icon: custom ? row.icon : fallback[0],
            style: custom && ['regular', 'brands'].includes(row.icon_style) ? row.icon_style : 'solid',
            color: typeof row.icon_color === 'string' && /^#[0-9a-fA-F]{6}$/.test(row.icon_color) ? row.icon_color.toLowerCase() : fallback[1]
        };
    }
    function html(row, small) {
        const v = values(row);
        return '<span class="market-icon' + (small ? ' market-icon-small' : '') + '" style="--tool-icon-color:' + v.color + ';--tool-icon-bg:' + v.color + '18"><i class="fa-' + v.style + ' fa-' + v.icon + '" aria-hidden="true"></i></span>';
    }
    function mount(form, metadata, icons) {
        const {text:t, esc:e} = ToolMarketUI;
        const panel = document.createElement('fieldset');
        panel.className = 'market-appearance';
        const family = style => ({solid:t('实心','Solid'),regular:t('常规','Regular'),brands:t('品牌','Brands')})[style];
        panel.innerHTML = `<legend>${t('工具外观','Tool appearance')}</legend>
            <input type="hidden" name="icon" value="${e(metadata.icon || '')}">
            <input type="hidden" name="icon_style" value="${e(metadata.icon ? metadata.icon_style || 'solid' : '')}">
            <div class="market-appearance-preview" id="toolAppearancePreview"></div>
            <label class="market-icon-automatic" for="toolIconAutomatic"><input id="toolIconAutomatic" type="radio" name="tool_icon_choice" value="auto">${t('按分类自动选择图标','Choose an icon automatically by category')}</label>
            <div class="market-icon-filters">
                <label class="sr-only" for="toolIconQuery">${t('搜索图标名称、品牌或关键词','Search icon names, brands or keywords')}</label>
                <input id="toolIconQuery" class="dialog-input" type="search" placeholder="${t('搜索图标、品牌，如 GitHub、微信…','Search icons or brands, e.g. GitHub, WeChat…')}">
                <label class="sr-only" for="toolIconStyle">${t('图标类型','Icon style')}</label>
                <select id="toolIconStyle" class="dialog-input"><option value="all">${t('全部类型','All styles')}</option>${['solid','regular','brands'].map(style=>`<option value="${style}">${family(style)}</option>`).join('')}</select>
            </div>
            <div class="market-icon-results"><span id="toolIconCount" role="status"></span><label for="toolIconPageSize">${t('每页','Per page')} <select id="toolIconPageSize" class="dialog-input"><option>24</option><option>48</option><option>96</option></select></label></div>
            <div class="market-icon-picker" id="toolIconChoices"></div>
            <nav class="market-icon-pagination" id="toolIconPagination" aria-label="${t('图标分页','Icon pagination')}"></nav>
            <div class="market-color-settings"><div><p class="market-muted">${t('预设颜色','Preset colors')}</p><div class="market-color-swatches">${
                [['#2563eb','蓝色','Blue'],['#7c3aed','紫色','Purple'],['#db2777','粉色','Pink'],['#dc2626','红色','Red'],['#d97706','橙色','Orange'],['#16a34a','绿色','Green'],['#0891b2','青色','Cyan'],['#475569','石板灰','Slate']].map(([color,zh,en])=>`<button class="row-action" type="button" data-tool-color="${color}" aria-label="${e(t(zh,en))}" aria-pressed="false"><span style="--tool-swatch-color:${color}"></span></button>`).join('')
            }</div></div>
            <label>${t('自定义颜色','Custom color')}<input type="color" name="icon_color" value="${values({...metadata,category:form.elements.category.value}).color}"></label>
            <button class="bs-btn bs-btn-cancel" type="button" data-tool-reset>${t('恢复默认','Reset to default')}</button></div>
            <p class="market-muted">${t('图标和颜色会同步到市场卡片、工具详情和安装后的快捷入口。','The icon and color are used in marketplace cards, tool details and installed shortcuts.')}</p>`;
        const placeholder=form.querySelector('#toolAppearancePlaceholder');
        if(placeholder)placeholder.replaceWith(panel);else form.elements.description.closest('label').after(panel);
        let customColor = !!metadata.icon_color, page = 1;
        const query = panel.querySelector('#toolIconQuery'), styleSelect = panel.querySelector('#toolIconStyle'), pageSize = panel.querySelector('#toolIconPageSize');
        pageSize.value = matchMedia('(max-width: 640px)').matches ? '24' : '48';
        const selectedKey = () => form.elements.icon.value ? (form.elements.icon_style.value || 'solid') + ':' + form.elements.icon.value : 'auto';
        function syncSelection() {
            panel.querySelectorAll('[name=tool_icon_choice]').forEach(input=>{input.checked = input.value === selectedKey();});
        }
        function choices() {
            const search = query.value.trim().toLocaleLowerCase(), style = styleSelect.value, take = Number(pageSize.value);
            const filtered = icons.filter(option=>(style === 'all' || style === option.style) && [option.id,option.zh,option.en,option.search].some(value=>(value || '').toLocaleLowerCase().includes(search)));
            const pages = Math.max(1,Math.ceil(filtered.length/take));
            page = Math.min(Math.max(1,page),pages);
            panel.querySelector('#toolIconCount').textContent = `${filtered.length} ${t('个图标','icons')} · ${page} / ${pages}`;
            panel.querySelector('#toolIconChoices').innerHTML = filtered.slice((page-1)*take,page*take).map(option=>{
                const key = option.style + ':' + option.id, label = t(option.zh,option.en), id = 'tool-icon-' + option.style + '-' + option.id;
                return `<label class="row-action market-icon-choice" for="${id}" title="${e(label+' · '+family(option.style))}"><input class="sr-only" id="${id}" type="radio" name="tool_icon_choice" value="${key}"><i class="fa-${option.style} fa-${option.id}" aria-hidden="true"></i><span>${e(label)}</span></label>`;
            }).join('') || `<p class="market-muted">${t('没有匹配的图标','No matching icons')}</p>`;
            renderPagination('toolIconPagination',page,pages,value=>{page=value;choices();},{compact:true,maxVisible:5});
            syncSelection();
        }
        function refresh(custom) {
            if(custom === true) customColor = true;
            const f = form.elements, row = {icon:f.icon.value,icon_style:f.icon_style.value,icon_color:f.icon_color.value,category:f.category.value};
            panel.querySelector('#toolAppearancePreview').innerHTML = html(row) + '<div><strong>' + e(f.title.value || t('工具名称','Tool name')) + '</strong><p class="market-muted">' + e(f.description.value || t('工具效果预览','Tool preview')) + '</p></div>';
            panel.querySelectorAll('[data-tool-color]').forEach(button=>button.setAttribute('aria-pressed',String(button.dataset.toolColor === row.icon_color.toLowerCase())));
            panel.style.setProperty('--tool-icon-color',values(row).color);
            syncSelection();
        }
        form.addEventListener('input',event=>{if(event.target.name === 'tool_icon_choice') return;if(event.target.name === 'icon_color') customColor = true;refresh();});
        panel.addEventListener('change',event=>{
            if(event.target.name !== 'tool_icon_choice') return;
            const key = event.target.value, parts = key.split(':');
            form.elements.icon.value = key === 'auto' ? '' : parts[1];
            form.elements.icon_style.value = key === 'auto' ? '' : parts[0];
            refresh();
        });
        query.oninput = styleSelect.onchange = pageSize.onchange = ()=>{page=1;choices();};
        form.elements.category.addEventListener('change',()=>{if(!customColor) form.elements.icon_color.value = values({category:form.elements.category.value}).color;refresh();});
        panel.querySelectorAll('[data-tool-color]').forEach(button=>{button.onclick = ()=>{customColor=true;form.elements.icon_color.value=button.dataset.toolColor;refresh();};});
        panel.querySelector('[data-tool-reset]').onclick=()=>{customColor=false;form.elements.icon.value='';form.elements.icon_style.value='';form.elements.icon_color.value=values({category:form.elements.category.value}).color;refresh();};
        choices();
        return refresh;
    }
    window.BookStarkToolAppearance = {values,html,mount};
})();
