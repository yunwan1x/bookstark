(function () {
    'use strict';
    const list = document.getElementById('friend-links-list');
    if (!list) return;
    const saveButton = document.getElementById('footer-save');
    const simple = document.getElementById('footer-simple');
    const t = key => window.__(key);
    let loaded = false, saving = false, uploads = 0, serial = 0;
    function node(tag, cls, text) { const n = document.createElement(tag); n.className = cls || ''; if (text) n.textContent = text; return n; }
    function button(text, action, cls) { const b = node('button', cls || 'ai-dlg-btn ai-dlg-btn-cancel', text); b.type = 'button'; b.onclick = action; return b; }
    function field(parent, key, value, type, required) {
        const wrap = node('div', 'footer-editor-field'), id = 'footer-field-' + (++serial);
        const label = node('label', '', t(key)); label.htmlFor = id;
        const input = node('input', 'dialog-input'); input.id = id; input.type = type || 'text'; input.value = value == null ? '' : value; input.required = !!required;
        if (input.type === 'text') input.maxLength = 100;
        if (input.type === 'url') input.maxLength = 2048;
        wrap.append(label, input); parent.append(wrap); return input;
    }
    function busy() {
        saveButton.disabled = !loaded || saving || uploads > 0;
        simple.disabled = !loaded || saving || uploads > 0;
        list.querySelectorAll('input,button').forEach(n => { n.disabled = saving; });
        list.querySelectorAll('[data-uploading]').forEach(n => { n.disabled = true; });
    }
    function error(err, fallback) { BookStarkErrors.field('friend-links-error', err, fallback || t('profile.friend_links.save_error')); }
    function empty() { document.getElementById('friend-links-empty').classList.toggle('hidden', list.children.length > 0); }
    function mode() {
        list.classList.toggle('is-simple', simple.checked);
        document.getElementById('footer-add-group').hidden = simple.checked;
        document.getElementById('footer-simple-add').hidden = !simple.checked;
    }
    simple.addEventListener('change', mode);
    function moves(target) {
        const actions = node('div', 'footer-editor-moves');
        [-1,1].forEach(direction => {
            const key = direction < 0 ? 'footer.manage.up' : 'footer.manage.down';
            const b = button(direction < 0 ? '↑' : '↓', () => {
                const neighbor = direction < 0 ? target.previousElementSibling : target.nextElementSibling;
                if (neighbor) target.parentNode.insertBefore(direction < 0 ? target : neighbor, direction < 0 ? neighbor : target);
            }, 'row-action');
            b.title = t(key); b.setAttribute('aria-label', t(key)); actions.append(b);
        });
        return actions;
    }
    function addSimpleLink() {
        if (!loaded || saving) return;
        const group = list.firstElementChild || addGroup();
        addItem(group, {}, false);
    }
    function addItem(group, item, qr) {
        const row = node('div', 'footer-editor-item' + (qr ? ' is-qr' : ''));
        const fields = node('div', 'footer-editor-fields');
        const name = field(fields, 'profile.friend_links.col.name', item.link_name, 'text', true);
        const url = field(fields, qr ? 'footer.manage.optional_url' : 'profile.friend_links.col.url', item.link_url, 'url', !qr);
        const description = qr ? field(fields, 'footer.manage.description', item.description) : null;
        if (description) description.maxLength = 1000;
        const options = node('div', 'footer-editor-actions');
        options.append(moves(row));
        const remove = button(t('profile.friend_links.delete'), () => row.remove(), 'row-action del');
        remove.setAttribute('aria-label', t('profile.friend_links.delete')); options.append(remove);
        let qrCode = item.qr_code || '';
        if (qr) {
            const media = node('div', 'footer-editor-media');
            const preview = node('img'); preview.alt = t('footer.manage.qr'); preview.hidden = !qrCode;
            if (qrCode) preview.src = qrCode;
            const upload = field(media, 'footer.manage.upload', '', 'file'); upload.accept = 'image/png,image/jpeg,image/webp,image/gif';
            media.prepend(preview); media.append(node('p', '', t('footer.manage.upload_hint')));
            upload.addEventListener('change', async () => {
                const file = upload.files[0]; if (!file) return;
                if (!['image/png','image/jpeg','image/webp','image/gif'].includes(file.type) || file.size > 5 * 1024 * 1024) { error(t('footer.manage.upload_invalid')); upload.value = ''; return; }
                uploads++; upload.dataset.uploading = 'true'; busy();
                try {
                    const body = new FormData(); body.append('file', file); body.append('category', 'editor');
                    const response = await csrfFetch('/api/uploads', {method:'POST',body,offlinePolicy:'reject'});
                    const data = await response.json();
                    if (!response.ok || data.code !== 0 || !data.data || !/^\/upload-files\/[a-zA-Z0-9_./-]+\.(png|jpe?g|webp|gif)$/i.test(data.data.url)) throw new Error(data.message || t('footer.manage.upload_invalid'));
                    qrCode = data.data.url; preview.src = qrCode; preview.hidden = false;
                    BookStarkErrors.clearField('friend-links-error');
                } catch (err) { error(err, t('footer.manage.upload_invalid')); }
                finally { uploads--; delete upload.dataset.uploading; upload.value = ''; busy(); }
            });
            row.append(media);
        }
        row.append(fields, options);
        row.collect = () => {
            if (qr && !qrCode) throw new Error(t('footer.manage.qr_required'));
            for (const input of [name,url,description].filter(Boolean)) if (!input.reportValidity()) throw new Error(t('footer.manage.invalid'));
            return {link_name:name.value.trim(),link_url:url.value.trim(),description:description ? description.value.trim() : '',is_enabled:1,qr_code:qrCode};
        };
        group.querySelector('.footer-editor-items').append(row); return row;
    }
    function addGroup(data) {
        if (saving) return;
        data = data || {};
        const group = node('section', 'footer-editor-group'), head = node('div', 'footer-editor-group-head');
        const name = field(head, 'footer.manage.group', data.name || ''); name.placeholder = t('footer.friendlinks');
        head.append(moves(group));
        head.append(button(t('footer.manage.remove_group'), async () => {
            if (!group.querySelector('.footer-editor-item') || await BSDialog.confirm2(t('footer.manage.remove_group_confirm'))) { group.remove(); empty(); }
        }, 'row-action del'));
        const items = node('div', 'footer-editor-items'), actions = node('div', 'footer-editor-actions');
        actions.append(button(t('footer.manage.add_link'),()=>addItem(group,{},false)),button(t('footer.manage.add_qr'),()=>addItem(group,{},true)));
        group.append(head,items,actions); group.groupName = name; list.append(group);
        (data.items || []).forEach(item=>addItem(group,item,!!item.qr_code)); empty(); return group;
    }
    async function load() {
        if (saving || uploads) return;
        loaded = false; busy(); document.getElementById('footer-retry').hidden = true;
        try {
            const response = await csrfFetch('/api/admin/friend-links', {cache:'no-store'}), data = await response.json();
            if (!response.ok || data.code !== 0) throw new Error(data.message || t('profile.friend_links.load_error'));
            const groups = new Map();
            ((data.data && data.data.items) || []).forEach(item => {
                const name = item.group_name || '';
                if (!groups.has(name)) groups.set(name,{name,order:item.group_order||0,items:[]});
                groups.get(name).items.push(item);
            });
            list.replaceChildren(); groups.forEach(addGroup); simple.checked = !!data.data.simple_mode; mode(); loaded = true; empty(); BookStarkErrors.clearField('friend-links-error');
        } catch (err) { error(err,t('profile.friend_links.load_error')); document.getElementById('footer-retry').hidden = false; }
        finally { busy(); }
    }
    async function save() {
        if (!loaded || saving || uploads) return;
        try {
            const items = [], names = new Set();
            for (const [groupOrder,group] of Array.from(list.children).entries()) {
                const name = group.groupName.value.trim();
                if (names.has(name)) throw new Error(t('footer.manage.duplicate_group'));
                names.add(name);
                const rows = group.querySelectorAll('.footer-editor-item');
                if (!rows.length) continue;
                rows.forEach((row,index)=>items.push(Object.assign(row.collect(),{group_name:name,group_order:groupOrder,sort_weight:index})));
            }
            saving = true; busy();
            const response = await csrfFetch('/api/admin/friend-links',{method:'PUT',offlinePolicy:'reject',headers:{'Content-Type':'application/json'},body:JSON.stringify({items,simple_mode:simple.checked})});
            const data = await response.json();
            if (!response.ok || data.code !== 0) throw new Error(data.message || t('profile.friend_links.save_error'));
            BookStarkErrors.clearField('friend-links-error'); BSDialog.toast(t('profile.friend_links.save_success'),'success');
        } catch (err) { error(err); }
        finally { saving = false; busy(); }
    }
    window.FooterEditor = {addGroup,addSimpleLink,load,save}; load();
})();
