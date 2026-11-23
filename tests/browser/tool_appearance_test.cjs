const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const context = {window:{}};
vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../static/js/tool-appearance.js'),'utf8'), context);
const appearance = context.window.BookStarkToolAppearance;

test('remote icon and color values cannot introduce HTML or CSS', () => {
    for(const row of [
        {icon:'image" onerror="alert(1)',icon_color:'red;background:url(https://example.test)'},
        {icon:null,icon_color:{}}, {icon:'x'.repeat(1000),icon_color:'#bad'}, {icon:'cube',icon_style:'brands" onclick=alert(1)'},
    ]) {
        const html = appearance.html(row);
        assert.match(html,/fa-cube/);
        assert.match(html,/--tool-icon-color:#2563eb/);
        assert.doesNotMatch(html,/onerror|url\(|alert/);
    }
});

test('configured icons remain consistent in full and compact entries', () => {
    const row = {category:'document',icon:'palette',icon_color:'#7C3AED'};
    for(const small of [false,true]) {
        const html = appearance.html(row,small);
        assert.match(html,/fa-palette/);
        assert.match(html,/--tool-icon-color:#7c3aed/);
        assert.equal(html.includes('market-icon-small'),small);
    }
});

test('brand and regular families are rendered with their own fonts', () => {
    assert.match(appearance.html({icon:'github',icon_style:'brands'}),/fa-brands fa-github/);
    assert.match(appearance.html({icon:'file-pdf',icon_style:'regular'}),/fa-regular fa-file-pdf/);
});
