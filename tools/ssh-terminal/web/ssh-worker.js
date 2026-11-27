/* Rust SSH + SFTP + WebDAV engine runs off the UI thread. Only the parent owns the authenticated bridge. */
importScripts("ssh_wasm.js");
const pending = [];
let ready = false;
self.onmessage = (event) => {
  if (ready) wasm_bindgen.dispatch_message(event.data);
  else pending.push(event.data);
};
(async () => {
  const response = await fetch("ssh_wasm_bg.wasm");
  if (!response.ok) throw Error("Cannot load SSH module");
  await wasm_bindgen({ module_or_path: await response.arrayBuffer() });
  ready = true;
  wasm_bindgen.init_engine();
  for (const item of pending.splice(0)) wasm_bindgen.dispatch_message(item);
})().catch((err) => {
  console.error("SSH WASM init failed:", err);
  postMessage({ type: "fatal", reason: "SSH 模块加载失败，请重新安装工具" });
});
