(() => {
'use strict';
let term, fit, lease, generation, retired = false, enabled = false, writing = false;
const bridge = window.BookStarkTerminalMessages;
// Capture on the ancestor before xterm's own textarea paste listener runs.
for (const type of ['paste','drop','dragover','contextmenu']) {
  document.addEventListener(type, event => {
    event.preventDefault(); event.stopImmediatePropagation();
  }, true);
}
document.addEventListener('beforeinput', event => {
  if (event.inputType === 'insertFromPaste' || event.inputType === 'insertFromDrop') {
    event.preventDefault(); event.stopImmediatePropagation();
  }
}, true);
const send = value => { if (!retired) bridge.postMessage(JSON.stringify(value)); };
const scoped = value => send({...value, lease, generation});
const valid = message => !retired && message && message.lease === lease && message.generation === generation;
function dimensions() {
  if (!term || retired) return;
  fit.fit();
  scoped({type:'resize', cols:Math.max(1, Math.min(500,term.cols)), rows:Math.max(1,Math.min(300,term.rows))});
}
bridge.onmessage = event => {
  try {
    const message = JSON.parse(event.data);
    if (message.type === 'configure' && !term && typeof message.lease === 'string') {
      lease = message.lease; generation = message.generation;
      term = new Terminal({cursorBlink:true, convertEol:false, screenReaderMode:true,
        scrollback:Math.max(500,Math.min(50000,message.scrollback)), fontSize:13, lineHeight:1.2,
        fontFamily:'monospace', allowProposedApi:false, disableStdin:true,
        theme:{background:'#080b10',foreground:'#d8e4f0',cursor:'#d8e4f0'}});
      fit = new FitAddon.FitAddon(); term.loadAddon(fit); term.open(document.getElementById('terminal'));
      // Remote output cannot request clipboard writes, links or browser actions.
      term.parser.registerOscHandler(52, () => true);
      term.parser.registerOscHandler(8, () => true);
      term.attachCustomKeyEventHandler(event => {
        // Android 229 triggers xterm's timer-based textarea diff. Our input
        // fallback already owns these DOM edits; running both races and can send
        // a prefix twice or a spurious DEL. Do not prevent the browser's default
        // IME edit. Composition events still go to xterm's preedit/commit handler.
        if (event.keyCode === 229 || event.which === 229 || event.key === 'Process') return false;
        if ((event.ctrlKey || event.metaKey) && ['v','V'].includes(event.key)) {
          event.preventDefault(); return false;
        }
        return true;
      });
      const input = term.textarea;
      input.setAttribute('autocomplete','off'); input.setAttribute('autocorrect','off');
      input.setAttribute('autocapitalize','off'); input.setAttribute('spellcheck','false');
      input.setAttribute('aria-label',message.english ? 'Terminal input' : '终端输入');
      input.addEventListener('paste', event => event.preventDefault());
      input.addEventListener('beforeinput', event => {
        if (event.inputType === 'insertFromPaste' || event.inputType === 'insertFromDrop') event.preventDefault();
      });
      // xterm screenReaderMode intentionally skips its insertText fallback.
      // Keep its accessible output and bridge IME-only input without duplicating
      // hardware keypresses or xterm's asynchronous composition commit.
      let keyProduced = false, keyDispatch = false, composing = false, compositionCommit = false;
      for (const type of ['keydown','keypress']) {
        document.addEventListener(type, event => {
          if (event.target !== input) return;
          if (type === 'keydown') keyProduced = false;
          keyDispatch = true;
          setTimeout(() => { keyDispatch = false; }, 0);
        }, true);
      }
      document.addEventListener('keyup', () => { keyProduced = false; keyDispatch = false; }, true);
      input.addEventListener('compositionstart', () => { composing = true; compositionCommit = false; });
      input.addEventListener('compositionend', () => {
        composing = false; compositionCommit = true;
        setTimeout(() => { compositionCommit = false; }, 0);
      });
      input.addEventListener('input', event => {
        // Keep Chromium's IME surrounding-text state intact. xterm itself clears
        // its textarea at Enter/Ctrl+C; clearing after every commit corrupts a
        // following native composition or delete transaction.
        if (input.value.length > 65536 || new TextEncoder().encode(input.value).length > 65536) {
          enabled = false; term.options.disableStdin = true; scoped({type:'failed'}); return;
        }
        if (!enabled || composing || compositionCommit || event.isComposing || keyProduced) return;
        let data;
        if (event.inputType === 'insertText') data = event.data;
        else if (event.inputType === 'deleteContentBackward') data = '\x7f';
        else if (['insertLineBreak','insertParagraph'].includes(event.inputType)) data = '\r';
        if (typeof data === 'string' && data.length && data.length <= 65536 &&
            new TextEncoder().encode(data).length <= 65536) {
          scoped({type:'input',data});
        }
      });
      term.onData(data => {
        if (keyDispatch) keyProduced = true;
        if (enabled && data.length <= 65536 && new TextEncoder().encode(data).length <= 65536)
          scoped({type:'input',data});
      });
      new ResizeObserver(dimensions).observe(document.getElementById('terminal'));
      window.addEventListener('resize', dimensions);
      dimensions(); scoped({type:'ready'}); return;
    }
    if (!valid(message) || !term) return;
    if (message.type === 'output' && !writing && typeof message.data === 'string' &&
        new TextEncoder().encode(message.data).length <= 65536) {
      writing = true;
      term.write(message.data, () => { writing = false; scoped({type:'written',id:message.id}); });
    } else if (message.type === 'enabled') {
      enabled = message.value === true; term.options.disableStdin = !enabled;
      dimensions();
    } else if (message.type === 'focus' && enabled) {
      term.focus();
      if (document.activeElement === term.textarea) scoped({type:'focused'});
      else scoped({type:'failed'});
    } else if (message.type === 'shortcut' && enabled) {
      if (message.key === 'interrupt') {
        const event = {key:'c',code:'KeyC',keyCode:67,which:67,ctrlKey:true,bubbles:true,cancelable:true};
        term.textarea.dispatchEvent(new KeyboardEvent('keydown',event));
        term.textarea.dispatchEvent(new KeyboardEvent('keyup',event));
        return;
      }
      const arrows = {up:'A',down:'B',right:'C',left:'D'};
      const controls = {escape:'\x1b',tab:'\t',interrupt:'\x03'};
      const data = arrows[message.key] ? '\x1b' + (term.modes.applicationCursorKeysMode ? 'O' : '[') + arrows[message.key] : controls[message.key];
      if (data) scoped({type:'input',data});
    }
  } catch (_) { scoped({type:'failed'}); }
};
document.addEventListener('contextmenu', event => event.preventDefault());
document.addEventListener('dragover', event => event.preventDefault());
document.addEventListener('drop', event => event.preventDefault());
window.addEventListener('pagehide', () => { retired = true; enabled = false; term?.dispose(); term = null; });
send({type:'boot'});
})();
