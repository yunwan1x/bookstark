/* BookStark Remote Desktop — Rust IronRDP WASM Web Worker
 * Runs all RDP TLS, CredSSP/NLA, bitmap decoding, CLIPRDR, RDPSND, and RDPDR off the UI thread.
 */
importScripts("rdp_wasm.js");

let wasmReady = false;
const pendingMessages = [];
const sessions = new Map();

function postEvents(sessionId, events) {
  if (!events || !events.length) return;
  const transfers = [];
  const out = [];
  for (let i = 0; i < events.length; i++) {
    const ev = events[i];
    if (!ev) continue;
    if (ev.data instanceof Uint8Array) {
      const buf = ev.data.buffer.slice(ev.data.byteOffset, ev.data.byteOffset + ev.data.byteLength);
      ev.data = buf;
      transfers.push(buf);
    }
    if (ev.rgba instanceof Uint8Array) {
      const buf = ev.rgba.buffer.slice(ev.rgba.byteOffset, ev.rgba.byteOffset + ev.rgba.byteLength);
      ev.rgba = buf;
      transfers.push(buf);
    }
    out.push(ev);
  }
  if (out.length) {
    self.postMessage({ type: "events", sessionId, events: out }, transfers);
  }
}

function handleMessage(msg) {
  if (!msg || !msg.type) return;
  const sid = msg.sessionId;
  try {
    if (msg.type === "create") {
      if (sessions.has(sid)) {
        try { sessions.get(sid).free(); } catch (_) {}
        sessions.delete(sid);
      }
      const client = new wasm_bindgen.RdpWasmClient(JSON.stringify(msg.options));
      sessions.set(sid, client);
      postEvents(sid, client.start());
      return;
    }

    const client = sessions.get(sid);
    if (!client) return;

    switch (msg.type) {
      case "tcp_rx": {
        const bytes = new Uint8Array(msg.data);
        postEvents(sid, client.on_tcp_data(bytes));
        break;
      }
      case "approve_tls": {
        postEvents(sid, client.approve_tls(!!msg.trusted));
        break;
      }
      case "mouse": {
        postEvents(sid, client.send_mouse(msg.x | 0, msg.y | 0, msg.flags | 0));
        break;
      }
      case "wheel": {
        postEvents(sid, client.send_wheel(msg.x | 0, msg.y | 0, msg.delta | 0, !!msg.horizontal));
        break;
      }
      case "scancode": {
        postEvents(sid, client.send_scancode(msg.scancode & 0xff, !!msg.extended, !!msg.pressed));
        break;
      }
      case "unicode": {
        postEvents(sid, client.send_unicode_text(String(msg.text || "")));
        break;
      }
      case "clip_text": {
        postEvents(sid, client.send_clipboard_text(String(msg.text || "")));
        break;
      }
      case "clip_files_advertise": {
        postEvents(sid, client.advertise_local_files(JSON.stringify(msg.files || [])));
        break;
      }
      case "clip_file_chunk_reply": {
        const bytes = msg.data ? new Uint8Array(msg.data) : new Uint8Array(0);
        postEvents(
          sid,
          client.respond_local_file_chunk(
            msg.streamId >>> 0,
            !!msg.isSize,
            Number(msg.fileSize || 0),
            bytes,
            !!msg.isError
          )
        );
        break;
      }
      case "clip_file_request": {
        const res = client.request_remote_file_range(
          msg.fileIndex | 0,
          Number(msg.offset || 0),
          msg.length >>> 0,
          msg.clipDataId == null ? undefined : (msg.clipDataId >>> 0)
        );
        self.postMessage({
          type: "clip_file_stream_started",
          sessionId: sid,
          reqId: msg.reqId,
          streamId: res.stream_id,
        });
        postEvents(sid, res.events);
        break;
      }
      case "resize": {
        postEvents(sid, client.request_resize(msg.width >>> 0, msg.height >>> 0));
        break;
      }
      case "audio_enabled": {
        client.set_audio_enabled(!!msg.enabled);
        break;
      }
      case "vdrive_put": {
        const bytes = new Uint8Array(msg.data);
        postEvents(sid, client.vdrive_put_file(String(msg.name || ""), bytes));
        break;
      }
      case "vdrive_get": {
        const bytes = client.vdrive_get_file(String(msg.name || ""));
        if (bytes instanceof Uint8Array) {
          const buf = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
          self.postMessage(
            { type: "vdrive_file_data", sessionId: sid, reqId: msg.reqId, name: msg.name, data: buf },
            [buf]
          );
        } else {
          self.postMessage({
            type: "vdrive_file_data",
            sessionId: sid,
            reqId: msg.reqId,
            name: msg.name,
            error: "not_found",
          });
        }
        break;
      }
      case "vdrive_delete": {
        postEvents(sid, client.vdrive_delete_file(String(msg.name || "")));
        break;
      }
      case "vdrive_list": {
        const json = client.vdrive_list_json();
        self.postMessage({ type: "vdrive_list", sessionId: sid, filesJson: json });
        break;
      }
      case "destroy": {
        sessions.delete(sid);
        try { client.free(); } catch (_) {}
        break;
      }
    }
  } catch (err) {
    self.postMessage({
      type: "events",
      sessionId: sid,
      events: [{ type: "error", message: String(err && err.message ? err.message : err) }],
    });
  }
}

self.onmessage = (event) => {
  if (wasmReady) handleMessage(event.data);
  else pendingMessages.push(event.data);
};

(async () => {
  const resp = await fetch("rdp_wasm_bg.wasm");
  if (!resp.ok) throw new Error("Failed to fetch rdp_wasm_bg.wasm (" + resp.status + ")");
  const bytes = await resp.arrayBuffer();
  await wasm_bindgen({ module_or_path: bytes });
  wasmReady = true;
  self.postMessage({ type: "ready" });
  while (pendingMessages.length) {
    handleMessage(pendingMessages.shift());
  }
})().catch((err) => {
  self.postMessage({
    type: "fatal",
    reason: "Rust IronRDP WASM 引擎加载失败: " + String(err && err.message ? err.message : err),
  });
});
