/* Go SSH runs off the UI thread. Only the parent owns the authenticated bridge. */
importScripts("wasm_exec.js");
const pending = [];
self.onmessage = (event) => {
  if (self.bookstarkSSH) self.bookstarkSSH(event.data);
  else pending.push(event.data);
};
(async () => {
  const go = new Go();
  const response = await fetch("ssh.wasm");
  if (!response.ok) throw Error("Cannot load SSH module");
  const result = await WebAssembly.instantiate(
    await response.arrayBuffer(),
    go.importObject,
  );
  go.run(result.instance).catch(() =>
    postMessage({ type: "fatal", reason: "SSH 模块已停止，请刷新工具" }),
  );
  for (const item of pending.splice(0)) self.bookstarkSSH(item);
})().catch(() =>
  postMessage({ type: "fatal", reason: "SSH 模块加载失败，请重新安装工具" }),
);
