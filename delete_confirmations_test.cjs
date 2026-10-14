const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const read = name => fs.readFileSync(__dirname + '/' + name, 'utf8');
const utils = read('static/js/utils.js');
const helpers = utils.slice(utils.indexOf('function formatDeleteConfirmation'), utils.indexOf('/**'));
const context = vm.createContext({});
vm.runInContext(helpers, context);
const format = context.formatDeleteConfirmation;
function translations(lang) {
  const entries = {};
  for (const m of read('i18n/' + lang + '.go').matchAll(/^\s*"([^"]+)":\s*("(?:[^"\\]|\\.)*")/gm)) entries[m[1]] = JSON.parse(m[2]);
  return entries;
}
test('names retain special characters, long titles and literal replacement tokens', () => {
  const name = '<img src=x onerror=alert(1)> $& $` $\' {name} ' + '长'.repeat(300);
  assert.equal(format('Delete {name}?', name, 3), 'Delete ' + name + '?');
  assert.equal(format('Delete {name}?', '  ', 3), 'Delete (#3)?');
});
test('untitled excerpts are bounded, Unicode-safe and identified', () => {
  assert.equal(format('{name}', 'a\n b', 7, true), 'a b (#7)');
  assert.equal(format('{name}', '😀'.repeat(100), 8, true), '😀'.repeat(80) + '… (#8)');
});
for (const lang of ['zh', 'en']) {
  const dict = translations(lang);
  test(lang + ': every updated confirmation contains a name placeholder', () => {
    for (const key of ['webdav.delete.folder_confirm', 'webdav.delete.file_confirm', 'note.confirm.delete', 'note.confirm.delete_article', 'task.confirm.delete', 'task.confirm.delete_children', 'topic.delete.confirm', 'topic.item.delete.confirm', 'topic.summary.delete.confirm', 'topic.comment.delete_confirm', 'topic.task.delete.confirm', 'profile.api_token.delete_confirm', 'share_comments.delete_confirm', 'editor.delete_doc.confirm']) {
      assert.ok(dict[key].includes('{name}'), key);
      assert.ok(format(dict[key], 'target-$&', 1).includes('target-$&'), key);
    }
  });
  test(lang + ': WebDAV file/folder menu shows escaped exact name and cancel/delete buttons', () => {
    const source = read('static/js/webdav.js');
    let dialog;
    const env = vm.createContext({window: {__: key => dict[key]}, state: {path: '/parent'}, joinPath: (p, n) => p + '/' + n, openModal: (...args) => { dialog = args; }});
    vm.runInContext(source.slice(source.indexOf('  function escapeHTML('), source.indexOf('  function request(')), env);
    vm.runInContext(source.slice(source.indexOf('  function handleAction('), source.indexOf('  function selectedModalFile(')), env);
    for (const type of ['dir', 'file']) {
      env.handleAction('delete', {type, name: '<test>-$&.txt'});
      assert.ok(dialog[1].includes('&lt;test&gt;-$&amp;.txt'));
      assert.equal(dialog[2][0].action, 'cancel');
      assert.equal(dialog[2][1].action, 'delete');
      assert.equal(dialog[2][1].danger, true);
    }
  });
  for (const [method, selector] of [['deleteNote', '.note-content'], ['deleteArticle', '.article-title']]) {
    test(lang + ': ' + method + ' identifies the item and cancellation sends no request', async () => {
      let message;
      const env = vm.createContext({window: {__: key => dict[key]}, NotesApp: function() {}, document: {querySelector: s => { assert.ok(s.endsWith(selector)); return {textContent: 'Example-$&'}; }}, BSDialog: {confirm2: text => {message = text; return Promise.resolve(false);}}, fetchWithCurrentCSRF: () => {throw new Error('Cancellation must not delete');}});
      vm.runInContext(helpers, env);
      const source = read('static/js/notes.js');
      const start = source.indexOf('NotesApp.prototype.' + method + ' =');
      vm.runInContext(source.slice(start, source.indexOf('\nNotesApp.prototype.', start + 1)), env);
      const app = new env.NotesApp();
      let pending;
      app._getCardActionButton = () => null;
      app._runSubmitRequest = (key, button, fn) => (pending = fn());
      app[method](42);
      assert.equal(await pending, null);
      assert.ok(message.includes('Example-$&'));
    });
  }
}
