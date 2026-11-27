mod bridge;
mod ssh_sftp;
mod webdav;

use js_sys::{JSON, Object, Reflect, Uint8Array};
use wasm_bindgen::prelude::*;

use bridge::{notify_dial_write_ack, notify_ssh_write_ack};
use ssh_sftp::{
    FsReq, SshCmd, SshConfig, close_ssh, handle_ssh_output_ack, handle_ssh_trust, push_ssh_data,
    send_ssh_cmd, start_ssh,
};
use webdav::{
    DavConfig, close_dav, handle_dial_close, handle_dial_data, handle_dial_open, start_dav,
    test_dav, try_handle_dav_fs,
};

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_name = postMessage)]
    fn worker_post_message(val: &JsValue);
}

fn get_str(obj: &JsValue, key: &str) -> String {
    Reflect::get(obj, &JsValue::from_str(key))
        .ok()
        .and_then(|v| v.as_string())
        .unwrap_or_default()
}

fn get_bool(obj: &JsValue, key: &str) -> bool {
    Reflect::get(obj, &JsValue::from_str(key))
        .ok()
        .and_then(|v| v.as_bool())
        .unwrap_or(false)
}

fn get_u32(obj: &JsValue, key: &str) -> u32 {
    Reflect::get(obj, &JsValue::from_str(key))
        .ok()
        .and_then(|v| v.as_f64())
        .map(|n| n.max(0.0) as u32)
        .unwrap_or(0)
}

fn get_bytes(obj: &JsValue, key: &str) -> Vec<u8> {
    Reflect::get(obj, &JsValue::from_str(key))
        .ok()
        .filter(|v| !v.is_undefined() && !v.is_null())
        .map(|v| Uint8Array::new(&v).to_vec())
        .unwrap_or_default()
}

pub fn emit_json(id: &str, kind: &str, mut val: serde_json::Value) {
    if let Some(map) = val.as_object_mut() {
        map.insert("id".into(), serde_json::Value::String(id.into()));
        map.insert("type".into(), serde_json::Value::String(kind.into()));
    }
    if let Ok(s) = serde_json::to_string(&val) {
        if let Ok(js_val) = JSON::parse(&s) {
            worker_post_message(&js_val);
        }
    }
}

pub fn emit_bytes(id: &str, kind: &str, data: &[u8]) {
    let obj = Object::new();
    let _ = Reflect::set(&obj, &JsValue::from_str("id"), &JsValue::from_str(id));
    let _ = Reflect::set(&obj, &JsValue::from_str("type"), &JsValue::from_str(kind));
    let arr = Uint8Array::from(data);
    let _ = Reflect::set(&obj, &JsValue::from_str("data"), &arr);
    worker_post_message(&obj.into());
}

pub fn emit_dial_write(dial_id: &str, data: &[u8]) {
    let obj = Object::new();
    let _ = Reflect::set(&obj, &JsValue::from_str("type"), &JsValue::from_str("dial-write"));
    let _ = Reflect::set(&obj, &JsValue::from_str("dialId"), &JsValue::from_str(dial_id));
    let arr = Uint8Array::from(data);
    let _ = Reflect::set(&obj, &JsValue::from_str("data"), &arr);
    worker_post_message(&obj.into());
}

pub fn emit_fs_ok(id: &str, req_id: &str, mut payload: serde_json::Value) {
    if let Some(map) = payload.as_object_mut() {
        map.insert("reqId".into(), serde_json::Value::String(req_id.into()));
        map.insert("ok".into(), serde_json::Value::Bool(true));
    }
    emit_json(id, "fs-res", payload);
}

pub fn emit_fs_err(id: &str, req_id: &str, msg: &str) {
    emit_json(
        id,
        "fs-res",
        serde_json::json!({ "reqId": req_id, "ok": false, "error": msg }),
    );
}

pub fn emit_fs_progress(id: &str, req_id: &str, done: u64, total: u64) {
    emit_json(
        id,
        "fs-progress",
        serde_json::json!({ "reqId": req_id, "done": done, "total": total }),
    );
}

pub fn emit_fs_bytes(id: &str, req_id: &str, data: &[u8], size: u64, truncated: bool) {
    let obj = Object::new();
    let _ = Reflect::set(&obj, &JsValue::from_str("id"), &JsValue::from_str(id));
    let _ = Reflect::set(&obj, &JsValue::from_str("type"), &JsValue::from_str("fs-res"));
    let _ = Reflect::set(&obj, &JsValue::from_str("reqId"), &JsValue::from_str(req_id));
    let _ = Reflect::set(&obj, &JsValue::from_str("ok"), &JsValue::from_bool(true));
    let _ = Reflect::set(&obj, &JsValue::from_str("data"), &Uint8Array::from(data));
    let _ = Reflect::set(&obj, &JsValue::from_str("size"), &JsValue::from_f64(size as f64));
    let _ = Reflect::set(&obj, &JsValue::from_str("truncated"), &JsValue::from_bool(truncated));
    worker_post_message(&obj.into());
}

#[wasm_bindgen]
pub fn init_engine() {
    emit_json("", "ready", serde_json::json!({}));
}

#[wasm_bindgen]
pub fn dispatch_message(m: JsValue) {
    let kind = get_str(&m, "type");
    match kind.as_str() {
        "dial-open" => {
            handle_dial_open(&get_str(&m, "dialId"), get_bool(&m, "ok"), get_str(&m, "error"));
            return;
        }
        "dial-data" => {
            handle_dial_data(&get_str(&m, "dialId"), get_bytes(&m, "data"));
            return;
        }
        "dial-write-ack" => {
            notify_dial_write_ack(&get_str(&m, "dialId"), get_bool(&m, "ok"));
            return;
        }
        "dial-close" => {
            handle_dial_close(&get_str(&m, "dialId"));
            return;
        }
        "dav-test" => {
            let req_id = get_str(&m, "reqId");
            if let Ok(s) = JSON::stringify(&m) {
                if let Ok(cfg) = serde_json::from_str::<DavConfig>(&s.as_string().unwrap_or_default()) {
                    test_dav(req_id, cfg);
                    return;
                }
            }
            emit_json("", "dav-test-res", serde_json::json!({ "reqId": req_id, "ok": false, "error": "配置解析失败" }));
            return;
        }
        _ => {}
    }

    let id = get_str(&m, "id");
    match kind.as_str() {
        "connect" => {
            if let Ok(s) = JSON::stringify(&m) {
                if let Ok(cfg) = serde_json::from_str::<SshConfig>(&s.as_string().unwrap_or_default()) {
                    start_ssh(id, cfg);
                }
            }
        }
        "data" => push_ssh_data(&id, get_bytes(&m, "data")),
        "write-ack" => notify_ssh_write_ack(&id, get_bool(&m, "ok")),
        "trust" => handle_ssh_trust(&id, get_bool(&m, "accept")),
        "input" => {
            let _ = send_ssh_cmd(&id, SshCmd::Input(get_bytes(&m, "data")));
        }
        "output-ack" => handle_ssh_output_ack(&id),
        "resize" => {
            let _ = send_ssh_cmd(&id, SshCmd::Resize(get_u32(&m, "cols"), get_u32(&m, "rows")));
        }
        "close" => close_ssh(&id, "连接已断开".into()),
        "dav-connect" => {
            if let Ok(s) = JSON::stringify(&m) {
                if let Ok(cfg) = serde_json::from_str::<DavConfig>(&s.as_string().unwrap_or_default()) {
                    start_dav(id, cfg);
                    return;
                }
            }
            emit_json(&id, "dav-error", serde_json::json!({ "reason": "无效的 WebDAV 配置" }));
        }
        "dav-close" => close_dav(&id),
        "fs-req" => {
            let req = FsReq {
                req_id: get_str(&m, "reqId"),
                op: get_str(&m, "op"),
                path: get_str(&m, "path"),
                to: get_str(&m, "to"),
                mode: get_str(&m, "mode"),
                max_bytes: get_u32(&m, "maxBytes") as usize,
                data: get_bytes(&m, "data"),
            };
            if let Err(req) = try_handle_dav_fs(&id, req) {
                let req_id = req.req_id.clone();
                if !send_ssh_cmd(&id, SshCmd::FsReq(req)) {
                    emit_fs_err(&id, &req_id, "会话已断开");
                }
            }
        }
        _ => {}
    }
}
