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
    function render() {
        body.replaceChildren();
        const query = filter.value.trim().toLowerCase();
        const matches = channels.filter(ch => ch.name.toLowerCase().includes(query));
        for (const {name,pid,stream} of matches) {
            const row = body.insertRow();
            for (const value of [name,pid,stream]) row.insertCell().textContent = value;
        }
        status.textContent = matches.length ? '显示 ' + matches.length + ' 条频道记录。' : '没有匹配的台名，请换个关键词。';
    }
    input.addEventListener('change', async () => {
        const file = input.files[0];
        channels = [];
        body.replaceChildren();
        box.hidden = true;
        status.textContent = '';
        if (!file) return;
        try {
            if (file.size > 2 * 1024 * 1024) throw Error('size');
            const bytes = new Uint8Array(await file.arrayBuffer());
            if (input.files[0] !== file) return;
            channels = read(bytes);
            if (!channels.length) throw Error('empty');
            filter.value = '';
            render();
            box.hidden = false;
        } catch {
            if (input.files[0] === file) status.textContent = '未读到电视频道。请选择官方频道列表原文件（最多 2 MB）；若官方格式已变，可用下方的浏览器方法查编号。';
        }
    });
    filter.addEventListener('input', render);
})();
