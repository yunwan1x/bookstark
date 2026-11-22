const assert = require('node:assert/strict');
const { merge } = require('../assets/complex_editors/host-merge.js');

let passed = 0;
function contract(name, run) {
  run();
  passed += 1;
  console.log('PASS ' + name);
}
function json(value) { return JSON.stringify(value); }
function decoded(kind, source, baseline, edited) {
  return JSON.parse(merge(kind, json(source), json(baseline), json(edited)));
}

contract('HTML edits preserve uniform CRLF and BOM without changing Unicode', () => {
 const original='\ufeff<p>原文😀</p>\r\n<script>window.keep=1;</script>\r\n';
 const engine=original.replace(/\r\n/g,'\n');
 const edit=engine+'<!-- 编辑🧪 -->\n';
 assert.equal(merge('html',original,engine,edit),original+'<!-- 编辑🧪 -->\r\n');
});
contract('HTML uniform CR is retained; LF and mixed files keep engine output', () => {
 assert.equal(merge('html','a\rb\r','a\nb\n','a\nc\n'),'a\rc\r');
 assert.equal(merge('html','a\nb\n','a\nb\n','a\nc\n'),'a\nc\n');
 assert.equal(merge('html','a\r\nb\n','a\nb\n','a\nc\n'),'a\nc\n');
});

contract('known root, cell, and style edits preserve unknown source properties', () => {
  const source = {
    title: 'Old',
    sourceRootExtra: { opaque: 'keep' },
    styles: [{ id: 's1', color: 'black', vendorStyle: { x: 1 } }],
    sheets: { s1: { cellData: { 0: { 0: { v: 1, t: 2, vendorCell: 'keep' } } } } },
  };
  const baseline = {
    title: 'Old',
    styles: [{ id: 's1', color: 'black' }],
    sheets: { s1: { cellData: { 0: { 0: { v: 1, t: 2 } } } } },
  };
  const edited = {
    title: 'New',
    styles: [{ id: 's1', color: 'blue' }],
    sheets: { s1: { cellData: { 0: { 0: { v: 2, t: 2 } } } } },
  };
  const result = decoded('drawing', source, baseline, edited);
  assert.equal(result.title, 'New');
  assert.deepEqual(result.sourceRootExtra, { opaque: 'keep' });
  assert.equal(result.styles[0].color, 'blue');
  assert.deepEqual(result.styles[0].vendorStyle, { x: 1 });
  assert.equal(result.sheets.s1.cellData[0][0].v, 2);
  assert.equal(result.sheets.s1.cellData[0][0].vendorCell, 'keep');
});

contract('engine defaults absent in source stay absent unless edited', () => {
  const source = { title: 'A', settings: { zoom: 1 }, extension: true };
  const baseline = { title: 'A', settings: { zoom: 1, grid: true, theme: 'light' }, engineVersion: 7 };
  const edited = { title: 'B', settings: { zoom: 1, grid: true, theme: 'light' }, engineVersion: 7 };
  const result = decoded('drawing', source, baseline, edited);
  assert.equal(result.title, 'B');
  assert.deepEqual(result.settings, { zoom: 1 });
  assert.equal(Object.hasOwn(result, 'engineVersion'), false);
  assert.equal(result.extension, true);

  const explicitlyEdited = decoded('drawing', source, baseline,
    { ...edited, settings: { zoom: 1, grid: false, theme: 'light' } });
  assert.deepEqual(explicitlyEdited.settings, { zoom: 1, grid: false });
});

contract('known property deletion is retained', () => {
  const result = decoded('drawing',
    { name: 'Doc', description: 'remove me', future: 9 },
    { name: 'Doc', description: 'remove me' },
    { name: 'Renamed' });
  assert.deepEqual(result, { name: 'Renamed', future: 9 });
});

contract('keyed arrays preserve IDs and extras through reorder, deletion, and addition', () => {
  const source = { objects: [
    { id: 'a', text: 'A', opaque: 'keep-a' },
    { id: 'b', text: 'B', opaque: 'keep-b' },
  ], future: 'keep' };
  const baseline = { objects: [
    { id: 'a', text: 'A' },
    { id: 'b', text: 'B' },
  ] };
  const edited = { objects: [
    { id: 'b', text: 'B2' },
    { id: 'c', text: 'C' },
  ] };
  const result = decoded('mindmap', source, baseline, edited);
  assert.deepEqual(result.objects, [
    { id: 'b', text: 'B2', opaque: 'keep-b' },
    { id: 'c', text: 'C' },
  ]);
  assert.equal(result.future, 'keep');
});

contract('mismatched keyed original and baseline IDs reject instead of dropping unknown fields', () => {
  const source = { objects: [
    { id: 'source-a', label: 'A', vendor: { keep: 'from-a' } },
    { id: 'source-b', label: 'B', vendor: { keep: 'from-b' } },
  ] };
  const baseline = { objects: [
    { id: 'engine-a', label: 'A' },
    { id: 'engine-b', label: 'B' },
  ] };
  const edited = { objects: [
    { id: 'engine-b', label: 'B2' },
    { id: 'engine-a', label: 'A' },
  ] };
  assert.throws(
    () => merge('drawing', json(source), json(baseline), json(edited)),
    /ambiguous_array_preservation/,
    'Do not silently omit source-only fields when IDs cannot map the keyed entries',
  );
});

contract('engine-generated baseline IDs align original anonymous array entries', () => {
  const source = { objects: [{ label: 'one', vendor: 11 }, { label: 'two', vendor: 22 }] };
  const baseline = { objects: [{ id: 'generated-1', label: 'one' }, { id: 'generated-2', label: 'two' }] };
  const edited = { objects: [
    { id: 'generated-2', label: 'TWO' },
    { id: 'generated-1', label: 'one' },
  ] };
  const result = decoded('drawing', source, baseline, edited);
  assert.deepEqual(result.objects, [
    { label: 'TWO', vendor: 22 },
    { label: 'one', vendor: 11 },
  ]);
});

contract('ambiguous anonymous length change with hidden original extras is rejected', () => {
  const source = { objects: [{ label: 'one', vendor: 11 }, { label: 'two', vendor: 22 }] };
  const baseline = { objects: [{ label: 'one' }, { label: 'two' }] };
  const edited = { objects: [{ label: 'one' }, { label: 'two' }, { label: 'three' }] };
  assert.throws(
    () => merge('drawing', json(source), json(baseline), json(edited)),
    /ambiguous_array_preservation/,
  );
});

contract('spreadsheet keeps original workbook ID and applies edited formula cache over recalculated baseline', () => {
  const source = {
    id: 'original-workbook-id',
    title: 'B',
    sheets: { s: { cellData: {
      0: { 0: { v: 2, t: 2 }, 1: { v: 3, t: 2 } },
      1: { 0: { v: -999, t: 2, f: '=SUM(A1:B1)' } },
    } } },
    vendorWorkbook: 'preserve',
  };
  const baseline = {
    id: 'engine-generated-id',
    title: 'B',
    sheets: { s: { cellData: {
      0: { 0: { v: 2, t: 2 }, 1: { v: 4, t: 2 } },
      1: { 0: { v: 4800, t: 2, f: '=SUM(A1:B1)' } },
    } } },
  };
  const edited = {
    id: 'engine-generated-id',
    title: 'C',
    sheets: { s: { cellData: {
      0: { 0: { v: 2, t: 2 }, 1: { v: 4, t: 2 } },
      1: { 0: { v: 4800, t: 2, f: '=SUM(A1:B1)' } },
    } } },
  };
  const result = decoded('spreadsheet', source, baseline, edited);
  assert.equal(result.id, 'original-workbook-id');
  assert.equal(result.vendorWorkbook, 'preserve');
  assert.equal(result.sheets.s.cellData[1][0].v, 4800);
  assert.equal(result.sheets.s.cellData[1][0].t, 2);
  assert.equal(result.title, 'C');
  const changedIdentity = { ...edited, id: 'attempted-workbook-id' };
  assert.throws(() => merge('spreadsheet', json(source), json(baseline), json(changedIdentity)), /workbook_identity_changed/);
});

contract('prototype-pollution keys remain inert JSON data', () => {
  const source = Object.assign(Object.create(null), { title: "old", constructor: { prototype: { polluted: "constructor" } } });
  Object.defineProperty(source, "__proto__", { value: { polluted: "source" }, enumerable: true });
  const baseline = JSON.parse(JSON.stringify(source));
  const edited = Object.assign(Object.create(null), { title: "new", constructor: { prototype: { polluted: "edited" } } });
  Object.defineProperty(edited, "__proto__", { value: { polluted: "edited" }, enumerable: true });
  const result = decoded('drawing', source, baseline, edited);
  assert.equal(result.title, 'new');
  assert.equal(Object.prototype.polluted, undefined);
  assert.equal(Object.hasOwn(result, '__proto__'), true);
  assert.deepEqual(result['__proto__'], { polluted: 'edited' });
  assert.equal(result.constructor.prototype.polluted, 'edited');
});

console.log('RESULT ' + passed + ' merge contracts passed');
