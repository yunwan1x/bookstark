use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::Arc;

use base64::Engine;
use russh::client::{self, AuthResult, KeyboardInteractiveAuthResponse};
use russh::keys::{self, HashAlg, PrivateKeyWithHashAlg, PublicKeyBase64, PublicKeyOrCertificate};
use russh::{ChannelMsg, Pty};
use russh_sftp::client::SftpSession;
use russh_sftp::protocol::{FileAttributes, OpenFlags};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::{mpsc, oneshot};

use crate::bridge::{
    BridgeHandle, BridgeKind, create_bridge, register_ssh_write_ack, remove_ssh_write_ack,
};
use crate::{emit_bytes, emit_fs_bytes, emit_fs_err, emit_fs_ok, emit_fs_progress, emit_json};

#[derive(Deserialize)]
pub struct SshConfig {
    pub host: String,
    #[serde(default)]
    pub shell: String,
    pub port: u16,
    pub user: String,
    #[serde(default)]
    pub auth: String,
    #[serde(default)]
    pub password: String,
    #[serde(default)]
    pub key: String,
    #[serde(default)]
    pub passphrase: String,
    #[serde(default = "default_cols")]
    pub cols: u32,
    #[serde(default = "default_rows")]
    pub rows: u32,
}

fn default_cols() -> u32 {
    80
}
fn default_rows() -> u32 {
    24
}

#[derive(Serialize)]
pub struct FsEntry {
    pub name: String,
    pub path: String,
    #[serde(rename = "isDir")]
    pub is_dir: bool,
    pub size: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mode: Option<String>,
    #[serde(rename = "modTime")]
    pub mod_time: i64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mime: Option<String>,
}

pub enum SshCmd {
    Input(Vec<u8>),
    Resize(u32, u32),
    FsReq(FsReq),
    ExecReq(ExecReq),
    ExecStreamStart(ExecStreamReq),
    ExecStreamStop(String),
    Close(String),
}

pub struct ExecReq {
    pub req_id: String,
    pub command: String,
}

pub struct ExecStreamReq {
    pub stream_id: String,
    pub command: String,
}

pub struct FsReq {
    pub req_id: String,
    pub op: String,
    pub path: String,
    pub to: String,
    pub mode: String,
    pub max_bytes: usize,
    pub data: Vec<u8>,
}

struct SessionSlot {
    bridge: BridgeHandle,
    cmd_tx: mpsc::UnboundedSender<SshCmd>,
    trust_tx: Option<oneshot::Sender<bool>>,
    output_ack_tx: Option<oneshot::Sender<()>>,
}

thread_local! {
    static SESSIONS: RefCell<HashMap<String, SessionSlot>> = RefCell::new(HashMap::new());
}

fn validate_shell(shell: &str) -> Result<Option<String>, &'static str> {
    let s = shell.trim();
    if s.is_empty() {
        return Ok(None);
    }
    if matches!(s, "sh" | "bash" | "zsh" | "fish") {
        return Ok(Some(format!("exec {} -l", s)));
    }
    if !s.starts_with('/') || s.bytes().any(|b| b == 0 || b == b'\r' || b == b'\n' || b.is_ascii_whitespace() || matches!(b, b';' | b'&' | b'|' | b'`' | b'$' | b'(' | b')' | b'<' | b'>' | b'\'' | b'"' | b'\\')) {
        return Err("Shell 程序无效，请使用程序名或绝对路径");
    }
    Ok(Some(format!("exec '{}' -l", s)))
}

struct ClientHandler {
    id: String,
    host: String,
    port: u16,
}

impl client::Handler for ClientHandler {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        server_public_key: &PublicKeyOrCertificate,
    ) -> Result<bool, Self::Error> {
        let pk = match server_public_key {
            PublicKeyOrCertificate::PublicKey { key, .. } => key.clone(),
            PublicKeyOrCertificate::Certificate(cert) => cert.public_key().clone().into(),
        };
        let raw_bytes = pk.public_key_bytes();
        let b64 = base64::engine::general_purpose::STANDARD.encode(&raw_bytes);
        let fp = pk.fingerprint(HashAlg::Sha256).to_string();
        let alg = pk.algorithm().as_str().to_string();

        let (tx, rx) = oneshot::channel();
        SESSIONS.with(|m| {
            if let Some(slot) = m.borrow_mut().get_mut(&self.id) {
                slot.trust_tx = Some(tx);
            }
        });
        emit_json(
            &self.id,
            "host-key",
            serde_json::json!({
                "host": self.host,
                "port": self.port,
                "algorithm": alg,
                "fingerprint": fp,
                "key": b64,
            }),
        );
        match rx.await {
            Ok(true) => Ok(true),
            _ => Ok(false),
        }
    }
}

pub fn start_ssh(id: String, cfg: SshConfig) {
    let exists = SESSIONS.with(|m| m.borrow().contains_key(&id));
    if exists {
        return;
    }
    register_ssh_write_ack(&id);
    let (bridge_handle, stream) = create_bridge(BridgeKind::Ssh {
        session_id: id.clone(),
    });
    let (cmd_tx, cmd_rx) = mpsc::unbounded_channel();
    SESSIONS.with(|m| {
        m.borrow_mut().insert(
            id.clone(),
            SessionSlot {
                bridge: bridge_handle.clone(),
                cmd_tx,
                trust_tx: None,
                output_ack_tx: None,
            },
        );
    });

    wasm_bindgen_futures::spawn_local(async move {
        let reason = run_ssh(id.clone(), cfg, stream, cmd_rx).await;
        cleanup_session(&id, &reason);
    });
}

fn cleanup_session(id: &str, reason: &str) {
    let removed = SESSIONS.with(|m| m.borrow_mut().remove(id));
    if let Some(slot) = removed {
        slot.bridge.close();
        remove_ssh_write_ack(id);
        emit_json(id, "closed", serde_json::json!({ "reason": reason }));
    }
}

pub fn push_ssh_data(id: &str, data: Vec<u8>) {
    SESSIONS.with(|m| {
        if let Some(slot) = m.borrow().get(id) {
            slot.bridge.push_inbound(data);
        }
    });
}

pub fn handle_ssh_trust(id: &str, accept: bool) {
    SESSIONS.with(|m| {
        if let Some(slot) = m.borrow_mut().get_mut(id) {
            if let Some(tx) = slot.trust_tx.take() {
                let _ = tx.send(accept);
            }
        }
    });
}

pub fn handle_ssh_output_ack(id: &str) {
    SESSIONS.with(|m| {
        if let Some(slot) = m.borrow_mut().get_mut(id) {
            if let Some(tx) = slot.output_ack_tx.take() {
                let _ = tx.send(());
            }
        }
    });
}

pub fn send_ssh_cmd(id: &str, cmd: SshCmd) -> bool {
    SESSIONS.with(|m| {
        if let Some(slot) = m.borrow().get(id) {
            let _ = slot.cmd_tx.send(cmd);
            true
        } else {
            false
        }
    })
}

pub fn close_ssh(id: &str, reason: String) {
    let sent = send_ssh_cmd(id, SshCmd::Close(reason.clone()));
    if !sent {
        cleanup_session(id, &reason);
    }
}

async fn run_ssh(
    id: String,
    cfg: SshConfig,
    stream: crate::bridge::BridgeStream,
    mut cmd_rx: mpsc::UnboundedReceiver<SshCmd>,
) -> String {
    let shell_cmd = match validate_shell(&cfg.shell) {
        Ok(c) => c,
        Err(msg) => return msg.to_string(),
    };

    let mut russh_cfg = client::Config::default();
    // On wasm32 there is no Tokio time driver; keepalive_interval/inactivity_timeout must be None.
    russh_cfg.keepalive_interval = None;
    russh_cfg.inactivity_timeout = None;
    let handler = ClientHandler {
        id: id.clone(),
        host: cfg.host.clone(),
        port: cfg.port,
    };

    let mut handle = match client::connect_stream(Arc::new(russh_cfg), stream, handler).await {
        Ok(h) => h,
        Err(err) => {
            let msg = err.to_string();
            if msg.contains("UnknownKey") || msg.contains("unknown") {
                return "主机密钥未确认".to_string();
            }
            return format!("SSH 连接失败：{}", msg);
        }
    };

    // Authenticate
    let authed = if cfg.auth == "key" {
        let pass = if cfg.passphrase.is_empty() {
            None
        } else {
            Some(cfg.passphrase.as_str())
        };
        let key_pair = match keys::decode_secret_key(&cfg.key, pass) {
            Ok(k) => k,
            Err(_) => return "无法解析私钥，请检查格式和口令".to_string(),
        };
        let best_hash = handle
            .best_supported_rsa_hash()
            .await
            .ok()
            .flatten()
            .flatten();
        let priv_with_hash = PrivateKeyWithHashAlg::new(Arc::new(key_pair), best_hash);
        match handle.authenticate_publickey(&cfg.user, priv_with_hash).await {
            Ok(AuthResult::Success) => true,
            Ok(_) => false,
            Err(err) => return format!("SSH 连接失败：{}", err),
        }
    } else {
        match handle.authenticate_password(&cfg.user, &cfg.password).await {
            Ok(AuthResult::Success) => true,
            Ok(_) => {
                // Fallback to keyboard-interactive (single hidden prompt)
                match handle
                    .authenticate_keyboard_interactive_start(&cfg.user, None)
                    .await
                {
                    Ok(KeyboardInteractiveAuthResponse::Success) => true,
                    Ok(KeyboardInteractiveAuthResponse::InfoRequest { prompts, .. })
                        if prompts.len() == 1 && !prompts[0].echo =>
                    {
                        matches!(
                            handle
                                .authenticate_keyboard_interactive_respond(vec![
                                    cfg.password.clone()
                                ])
                                .await,
                            Ok(KeyboardInteractiveAuthResponse::Success)
                        )
                    }
                    _ => false,
                }
            }
            Err(err) => return format!("SSH 连接失败：{}", err),
        }
    };

    if !authed {
        return "SSH 连接失败：认证被拒绝，请检查用户名、密码或私钥".to_string();
    }

    let mut channel = match handle.channel_open_session().await {
        Ok(ch) => ch,
        Err(err) => return format!("无法创建 SSH 会话：{}", err),
    };

    let cols = cfg.cols.max(2);
    let rows = cfg.rows.max(2);
    if let Err(err) = channel
        .request_pty(
            true,
            "xterm-256color",
            cols,
            rows,
            0,
            0,
            &[(Pty::ECHO, 1), (Pty::TTY_OP_ISPEED, 14400), (Pty::TTY_OP_OSPEED, 14400)],
        )
        .await
    {
        return format!("服务器拒绝 PTY：{}", err);
    }

    let start_res = if let Some(cmd) = shell_cmd {
        channel.exec(true, cmd.into_bytes()).await
    } else {
        channel.request_shell(true).await
    };
    if let Err(err) = start_res {
        return format!("无法启动 Shell：{}", err);
    }

    emit_json(&id, "connected", serde_json::json!({}));

    let handle = Arc::new(handle);
    let mut sftp: Option<Arc<SftpSession>> = None;
    let exec_streams: Rc<RefCell<HashMap<String, oneshot::Sender<()>>>> =
        Rc::new(RefCell::new(HashMap::new()));

    let cancel_all_streams = |streams: &Rc<RefCell<HashMap<String, oneshot::Sender<()>>>>| {
        let drained: Vec<_> = streams.borrow_mut().drain().collect();
        for (_, tx) in drained {
            let _ = tx.send(());
        }
    };

    loop {
        tokio::select! {
            msg = channel.wait() => {
                match msg {
                    Some(ChannelMsg::Data { data }) => {
                        let (ack_tx, ack_rx) = oneshot::channel();
                        SESSIONS.with(|m| {
                            if let Some(slot) = m.borrow_mut().get_mut(&id) {
                                slot.output_ack_tx = Some(ack_tx);
                            }
                        });
                        emit_bytes(&id, "output", &data);
                        let _ = ack_rx.await;
                    }
                    Some(ChannelMsg::ExtendedData { data, .. }) => {
                        let (ack_tx, ack_rx) = oneshot::channel();
                        SESSIONS.with(|m| {
                            if let Some(slot) = m.borrow_mut().get_mut(&id) {
                                slot.output_ack_tx = Some(ack_tx);
                            }
                        });
                        emit_bytes(&id, "output", &data);
                        let _ = ack_rx.await;
                    }
                    Some(ChannelMsg::ExitStatus { exit_status }) => {
                        cancel_all_streams(&exec_streams);
                        if exit_status != 0 {
                            return format!("Shell 已退出：status {}", exit_status);
                        }
                        return "会话已结束".to_string();
                    }
                    Some(ChannelMsg::Eof) | Some(ChannelMsg::Close) | None => {
                        cancel_all_streams(&exec_streams);
                        return "会话已结束".to_string();
                    }
                    _ => {}
                }
            }
            cmd = cmd_rx.recv() => {
                match cmd {
                    Some(SshCmd::Input(bytes)) => {
                        if channel.data(&bytes[..]).await.is_err() {
                            cancel_all_streams(&exec_streams);
                            return "输入失败".to_string();
                        }
                        emit_json(&id, "input-ack", serde_json::json!({}));
                    }
                    Some(SshCmd::Resize(c, r)) => {
                        if c > 1 && r > 1 {
                            let _ = channel.window_change(c, r, 0, 0).await;
                        }
                    }
                    Some(SshCmd::FsReq(req)) => {
                        // Lazily open multiplexed SFTP channel on the SAME SSH connection!
                        if sftp.is_none() {
                            match open_sftp(&handle).await {
                                Ok(s) => sftp = Some(Arc::new(s)),
                                Err(err) => {
                                    emit_fs_err(&id, &req.req_id, &err);
                                    continue;
                                }
                            }
                        }
                        if let Some(client) = sftp.clone() {
                            let sid = id.clone();
                            wasm_bindgen_futures::spawn_local(async move {
                                execute_sftp_op(&sid, &client, req).await;
                            });
                        }
                    }
                    Some(SshCmd::ExecReq(req)) => {
                        let h = handle.clone();
                        let sid = id.clone();
                        wasm_bindgen_futures::spawn_local(async move {
                            execute_ssh_exec(&sid, &h, req).await;
                        });
                    }
                    Some(SshCmd::ExecStreamStart(req)) => {
                        if let Some(old_tx) = exec_streams.borrow_mut().remove(&req.stream_id) {
                            let _ = old_tx.send(());
                        }
                        let (cancel_tx, cancel_rx) = oneshot::channel();
                        exec_streams.borrow_mut().insert(req.stream_id.clone(), cancel_tx);
                        let h = handle.clone();
                        let sid = id.clone();
                        let streams = exec_streams.clone();
                        wasm_bindgen_futures::spawn_local(async move {
                            execute_ssh_stream(&sid, &h, req, cancel_rx, streams).await;
                        });
                    }
                    Some(SshCmd::ExecStreamStop(stream_id)) => {
                        if let Some(tx) = exec_streams.borrow_mut().remove(&stream_id) {
                            let _ = tx.send(());
                        }
                    }
                    Some(SshCmd::Close(reason)) => {
                        cancel_all_streams(&exec_streams);
                        let _ = channel.eof().await;
                        let _ = handle.disconnect(russh::Disconnect::ByApplication, "", "en").await;
                        return reason;
                    }
                    None => {
                        cancel_all_streams(&exec_streams);
                        return "连接已断开".to_string();
                    }
                }
            }
        }
    }
}

async fn execute_ssh_exec(sid: &str, handle: &client::Handle<ClientHandler>, req: ExecReq) {
    let mut ch = match handle.channel_open_session().await {
        Ok(c) => c,
        Err(err) => {
            emit_json(
                sid,
                "exec-res",
                serde_json::json!({
                    "reqId": req.req_id,
                    "ok": false,
                    "code": -1,
                    "stdout": "",
                    "stderr": "",
                    "error": format!("无法打开 SSH Exec 通道：{}", err),
                }),
            );
            return;
        }
    };
    if let Err(err) = ch.exec(true, req.command.into_bytes()).await {
        emit_json(
            sid,
            "exec-res",
            serde_json::json!({
                "reqId": req.req_id,
                "ok": false,
                "code": -1,
                "stdout": "",
                "stderr": "",
                "error": format!("命令执行失败：{}", err),
            }),
        );
        return;
    }

    const MAX_STDOUT: usize = 8 * 1024 * 1024;
    const MAX_STDERR: usize = 2 * 1024 * 1024;
    let mut stdout: Vec<u8> = Vec::new();
    let mut stderr: Vec<u8> = Vec::new();
    let mut exit_code: i32 = 0;

    while let Some(msg) = ch.wait().await {
        match msg {
            ChannelMsg::Data { data } => {
                if stdout.len() < MAX_STDOUT {
                    let take = (MAX_STDOUT - stdout.len()).min(data.len());
                    stdout.extend_from_slice(&data[..take]);
                }
            }
            ChannelMsg::ExtendedData { data, .. } => {
                if stderr.len() < MAX_STDERR {
                    let take = (MAX_STDERR - stderr.len()).min(data.len());
                    stderr.extend_from_slice(&data[..take]);
                }
            }
            ChannelMsg::ExitStatus { exit_status } => {
                exit_code = exit_status as i32;
            }
            ChannelMsg::Close => break,
            _ => {}
        }
    }

    let out_str = String::from_utf8_lossy(&stdout).into_owned();
    let err_str = String::from_utf8_lossy(&stderr).into_owned();
    emit_json(
        sid,
        "exec-res",
        serde_json::json!({
            "reqId": req.req_id,
            "ok": exit_code == 0,
            "code": exit_code,
            "stdout": out_str,
            "stderr": err_str,
            "error": if exit_code == 0 { "" } else { err_str.trim() },
        }),
    );
}

async fn execute_ssh_stream(
    sid: &str,
    handle: &client::Handle<ClientHandler>,
    req: ExecStreamReq,
    mut cancel_rx: oneshot::Receiver<()>,
    streams: Rc<RefCell<HashMap<String, oneshot::Sender<()>>>>,
) {
    let stream_id = req.stream_id;
    let mut ch = match handle.channel_open_session().await {
        Ok(c) => c,
        Err(err) => {
            streams.borrow_mut().remove(&stream_id);
            emit_json(
                sid,
                "exec-stream-end",
                serde_json::json!({
                    "streamId": stream_id,
                    "code": -1,
                    "error": format!("无法打开 SSH 流通道：{}", err),
                }),
            );
            return;
        }
    };
    if let Err(err) = ch.exec(true, req.command.into_bytes()).await {
        streams.borrow_mut().remove(&stream_id);
        emit_json(
            sid,
            "exec-stream-end",
            serde_json::json!({
                "streamId": stream_id,
                "code": -1,
                "error": format!("无法启动命令流：{}", err),
            }),
        );
        return;
    }

    let mut exit_code: i32 = 0;
    let mut cancelled = false;

    loop {
        tokio::select! {
            _ = &mut cancel_rx => {
                cancelled = true;
                let _ = ch.eof().await;
                let _ = ch.close().await;
                break;
            }
            msg = ch.wait() => {
                match msg {
                    Some(ChannelMsg::Data { data }) => {
                        let chunk = String::from_utf8_lossy(&data).into_owned();
                        emit_json(
                            sid,
                            "exec-stream",
                            serde_json::json!({ "streamId": stream_id, "chunk": chunk, "isErr": false }),
                        );
                    }
                    Some(ChannelMsg::ExtendedData { data, .. }) => {
                        let chunk = String::from_utf8_lossy(&data).into_owned();
                        emit_json(
                            sid,
                            "exec-stream",
                            serde_json::json!({ "streamId": stream_id, "chunk": chunk, "isErr": true }),
                        );
                    }
                    Some(ChannelMsg::ExitStatus { exit_status }) => {
                        exit_code = exit_status as i32;
                    }
                    Some(ChannelMsg::Close) | None => break,
                    _ => {}
                }
            }
        }
    }

    streams.borrow_mut().remove(&stream_id);
    emit_json(
        sid,
        "exec-stream-end",
        serde_json::json!({
            "streamId": stream_id,
            "code": exit_code,
            "cancelled": cancelled,
            "error": "",
        }),
    );
}

async fn open_sftp(handle: &client::Handle<ClientHandler>) -> Result<SftpSession, String> {
    let ch = handle
        .channel_open_session()
        .await
        .map_err(|e| format!("无法打开 SFTP 通道：{}", e))?;
    ch.request_subsystem(true, "sftp")
        .await
        .map_err(|e| format!("服务器未启用 SFTP 子系统：{}", e))?;
    SftpSession::new(ch.into_stream())
        .await
        .map_err(|e| format!("SFTP 初始化失败：{}", e))
}

fn clean_posix_path(p: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    let abs = p.starts_with('/');
    for seg in p.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            s => parts.push(s),
        }
    }
    if abs {
        format!("/{}", parts.join("/"))
    } else if parts.is_empty() {
        ".".to_string()
    } else {
        parts.join("/")
    }
}

fn join_posix(dir: &str, name: &str) -> String {
    if dir == "/" {
        format!("/{}", name.trim_start_matches('/'))
    } else {
        format!("{}/{}", dir.trim_end_matches('/'), name.trim_start_matches('/'))
    }
}

pub fn guess_mime(name: &str) -> Option<String> {
    let ext = name.rsplit('.').next()?.to_ascii_lowercase();
    let m = match ext.as_str() {
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "pdf" => "application/pdf",
        "json" => "application/json",
        "xml" => "application/xml",
        "html" | "htm" => "text/html",
        "css" => "text/css",
        "js" | "mjs" | "cjs" => "application/javascript",
        "txt" | "md" | "log" | "conf" | "yml" | "yaml" | "toml" | "ini" | "sh" | "env" => "text/plain",
        _ => return None,
    };
    Some(m.to_string())
}

async fn execute_sftp_op(sid: &str, sftp: &SftpSession, req: FsReq) {
    match req.op.as_str() {
        "list" => {
            let raw_dir = req.path.trim();
            let dir = if raw_dir.is_empty() || raw_dir == "~" {
                sftp.canonicalize(".")
                    .await
                    .unwrap_or_else(|_| "/".to_string())
            } else {
                clean_posix_path(raw_dir)
            };
            match sftp.read_dir(&dir).await {
                Ok(entries_iter) => {
                    let mut entries = Vec::new();
                    for item in entries_iter {
                        let name = item.file_name();
                        if name == "." || name == ".." {
                            continue;
                        }
                        let full = join_posix(&dir, &name);
                        let meta = item.metadata();
                        let mut is_dir = meta.is_dir();
                        if meta.is_symlink() {
                            if let Ok(target_meta) = sftp.metadata(&full).await {
                                is_dir = target_meta.is_dir();
                            }
                        }
                        let perms = meta.permissions.map(|p| format!("{:04o}", p & 0o7777));
                        entries.push(FsEntry {
                            mime: if is_dir { None } else { guess_mime(&name) },
                            name,
                            path: full,
                            is_dir,
                            size: meta.size.unwrap_or(0),
                            mode: perms,
                            mod_time: meta.mtime.unwrap_or(0) as i64,
                        });
                    }
                    entries.sort_by(|a, b| {
                        b.is_dir
                            .cmp(&a.is_dir)
                            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
                    });
                    let json_entries = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".into());
                    emit_fs_ok(
                        sid,
                        &req.req_id,
                        serde_json::json!({ "cwd": dir, "entries": json_entries }),
                    );
                }
                Err(err) => emit_fs_err(sid, &req.req_id, &format!("无法读取目录：{}", err)),
            }
        }
        "read" => {
            let mut file = match sftp.open(&req.path).await {
                Ok(f) => f,
                Err(err) => {
                    emit_fs_err(sid, &req.req_id, &format!("无法打开文件：{}", err));
                    return;
                }
            };
            let total = file.metadata().await.ok().and_then(|m| m.size).unwrap_or(0);
            let mut out = Vec::new();
            let mut buf = vec![0u8; 32 * 1024];
            let mut done: u64 = 0;
            let mut truncated = false;
            loop {
                match file.read(&mut buf).await {
                    Ok(0) => break,
                    Ok(n) => {
                        if req.max_bytes > 0 && (done as usize) + n > req.max_bytes {
                            let remain = req.max_bytes.saturating_sub(done as usize);
                            if remain > 0 {
                                out.extend_from_slice(&buf[..remain]);
                                done += remain as u64;
                            }
                            truncated = true;
                            break;
                        }
                        out.extend_from_slice(&buf[..n]);
                        done += n as u64;
                        emit_fs_progress(sid, &req.req_id, done, total);
                    }
                    Err(err) => {
                        emit_fs_err(sid, &req.req_id, &format!("读取文件失败：{}", err));
                        return;
                    }
                }
            }
            emit_fs_bytes(sid, &req.req_id, &out, if total > 0 { total } else { done }, truncated);
        }
        "write" => {
            let mut file = match sftp
                .open_with_flags(
                    &req.path,
                    OpenFlags::CREATE | OpenFlags::TRUNCATE | OpenFlags::WRITE,
                )
                .await
            {
                Ok(f) => f,
                Err(err) => {
                    emit_fs_err(sid, &req.req_id, &format!("无法写入文件：{}", err));
                    return;
                }
            };
            let total = req.data.len() as u64;
            let mut written: u64 = 0;
            for chunk in req.data.chunks(32 * 1024) {
                if let Err(err) = file.write_all(chunk).await {
                    emit_fs_err(sid, &req.req_id, &format!("上传失败：{}", err));
                    return;
                }
                written += chunk.len() as u64;
                emit_fs_progress(sid, &req.req_id, written, total);
            }
            if let Err(err) = file.shutdown().await {
                emit_fs_err(sid, &req.req_id, &format!("保存文件失败：{}", err));
                return;
            }
            emit_fs_progress(sid, &req.req_id, total, total);
            emit_fs_ok(sid, &req.req_id, serde_json::json!({ "size": total }));
        }
        "mkdir" => {
            if let Err(err) = mkdir_all(sftp, &req.path).await {
                emit_fs_err(sid, &req.req_id, &format!("创建目录失败：{}", err));
            } else {
                emit_fs_ok(sid, &req.req_id, serde_json::json!({}));
            }
        }
        "rename" => {
            if let Err(err) = sftp.rename(&req.path, &req.to).await {
                emit_fs_err(sid, &req.req_id, &format!("重命名失败：{}", err));
            } else {
                emit_fs_ok(sid, &req.req_id, serde_json::json!({}));
            }
        }
        "chmod" => {
            let mode = match u32::from_str_radix(req.mode.trim(), 8) {
                Ok(m) if m <= 0o7777 => m,
                _ => {
                    emit_fs_err(sid, &req.req_id, "权限格式无效，请输入如 0644 或 0755");
                    return;
                }
            };
            let mut attrs = FileAttributes::empty();
            attrs.permissions = Some(mode);
            if let Err(err) = sftp.set_metadata(&req.path, attrs).await {
                emit_fs_err(sid, &req.req_id, &format!("修改权限失败：{}", err));
            } else {
                emit_fs_ok(sid, &req.req_id, serde_json::json!({}));
            }
        }
        "delete" => {
            if let Err(err) = remove_recursive(sftp, &req.path).await {
                emit_fs_err(sid, &req.req_id, &format!("删除失败：{}", err));
            } else {
                emit_fs_ok(sid, &req.req_id, serde_json::json!({}));
            }
        }
        other => emit_fs_err(sid, &req.req_id, &format!("不支持的 SFTP 操作：{}", other)),
    }
}

async fn mkdir_all(sftp: &SftpSession, target: &str) -> Result<(), String> {
    let clean = clean_posix_path(target);
    let mut acc = String::new();
    for seg in clean.split('/').filter(|s| !s.is_empty()) {
        acc.push('/');
        acc.push_str(seg);
        if !sftp.try_exists(&acc).await.unwrap_or(false) {
            sftp.create_dir(&acc).await.map_err(|e| e.to_string())?;
        }
    }
    Ok(())
}

async fn remove_recursive(sftp: &SftpSession, target: &str) -> Result<(), String> {
    let meta = sftp
        .symlink_metadata(target)
        .await
        .map_err(|e| e.to_string())?;
    if !meta.is_dir() {
        return sftp.remove_file(target).await.map_err(|e| e.to_string());
    }
    // Iterative DFS post-order to avoid async recursion boxing overhead
    let mut stack = vec![(target.to_string(), false)];
    while let Some((dir, visited)) = stack.pop() {
        if visited {
            sftp.remove_dir(&dir).await.map_err(|e| e.to_string())?;
            continue;
        }
        stack.push((dir.clone(), true));
        let entries = sftp.read_dir(&dir).await.map_err(|e| e.to_string())?;
        for item in entries {
            let name = item.file_name();
            if name == "." || name == ".." {
                continue;
            }
            let child = join_posix(&dir, &name);
            if item.metadata().is_dir() && !item.metadata().is_symlink() {
                stack.push((child, false));
            } else {
                sftp.remove_file(&child).await.map_err(|e| e.to_string())?;
            }
        }
    }
    Ok(())
}
