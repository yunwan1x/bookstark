// Read the length-delimited fields used in Yangshipin's TV directory.
// Only descend through the known page, module and channel messages.
(() => {
    const input = document.getElementById('ysp-list-file');
    if (!input) return;
    const filter = document.getElementById('ysp-list-filter');
    const box = document.getElementById('ysp-list-box');
    const body = document.getElementById('ysp-list-rows');
    const status = document.getElementById('ysp-list-result');
    const decode = new TextDecoder();
    let channels = [];

    function fields(bytes) {
        let pos = 0;
        const parts = new Map();
        function integer() {
            let value = 0;
            for (let shift = 0; pos < bytes.length && shift < 53; shift += 7) {
                const b = bytes[pos++];
                value += (b & 127) * 2 ** shift;
                if (!(b & 128) && Number.isSafeInteger(value)) return value;
            }
            throw Error('varint');
        }
        while (pos < bytes.length) {
            const tag = integer(), wire = tag % 8, field = Math.floor(tag / 8);
            if (!field) throw Error('tag');
            if (wire === 0) { integer(); continue; }
            const length = wire === 2 ? integer() : wire === 1 ? 8 : wire === 5 ? 4 : -1;
            if (length < 0 || length > bytes.length - pos) throw Error('length');
            if (wire === 2) {
                if (!parts.has(field)) parts.set(field, []);
                parts.get(field).push(bytes.subarray(pos, pos + length));
            }
            pos += length;
        }
        return parts;
    }
    function read(bytes) {
        const text = (row, key) => decode.decode(row.get(key)?.[0]);
        const entries = [];
        for (const page of fields(bytes).get(2) || []) {
            for (const module of fields(page).get(2) || []) {
                const block = fields(module);
                if (text(block, 2) !== 'tvChannel') continue;
                for (const item of block.get(15) || []) {
                    const row = fields(item);
                    const name = text(row, 2), pid = text(row, 4), stream = text(row, 6);
                    if (name && [pid,stream].every(v => /^[1-9][0-9]{0,18}$/.test(v))) {
                        entries.push({name,pid,stream});
                    }
                }
            }
        }
        return entries;
    }
    const dialog = document.getElementById('tv-directory');
    let revision = 0;
    let choose;
    function render() {
        body.replaceChildren();
        const query = filter.value.trim().toLowerCase();
        const matches = channels.filter(ch => ch.name.toLowerCase().includes(query));
        for (const ch of matches) {
            const row = body.insertRow();
            for (const value of [ch.name,ch.pid,ch.stream]) row.insertCell().textContent = value;
            const action = document.createElement('button');
            action.type = 'button';
            action.textContent = '选用';
            action.onclick = () => { choose(ch); dialog.close(); };
            row.insertCell().append(action);
        }
        status.textContent = matches.length ? matches.length + ' 个频道' : '没有匹配的频道';
    }
    async function load(readBytes) {
        const request = ++revision;
        channels = [];
        box.hidden = true;
        status.textContent = '正在读取官方列表…';
        try {
            const rows = read(new Uint8Array(await readBytes()));
            if (request !== revision) return;
            if (!rows.length) throw Error('empty');
            channels = rows;
            render();
            box.hidden = false;
        } catch {
            if (request === revision) status.textContent = '读取失败，可手动导入官方列表。';
        }
    }
    window.openTVDirectory = onChoose => {
        choose = onChoose;
        filter.value = '';
        input.value = '';
        dialog.showModal();
        filter.focus();
        load(async () => {
            const r = await fetch('/api/admin/tv/official-directory', {cache:'no-store'});
            if (!r.ok) throw Error('directory unavailable');
            return r.arrayBuffer();
        });
    };
    input.onchange = () => {
        const file = input.files[0];
        if (file) load(async () => {
            if (file.size > 2 * 1024 * 1024) throw Error('size');
            return file.arrayBuffer();
        });
    };
    filter.oninput = () => { if (channels.length) render(); };
    dialog.onclose = () => { revision++; choose = null; };
})();
