use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};

use base64::Engine;
use md5::{Digest as Md5Digest, Md5};
use quick_xml::Reader;
use quick_xml::events::Event;
use rustls::client::UnbufferedClientConnection;
use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::unbuffered::{ConnectionState, EncodeError, EncryptError, UnbufferedStatus};
use rustls::{ClientConfig, DigitallySignedStruct, RootCertStore, SignatureScheme};
use rustls_pki_types::{CertificateDer, ServerName, UnixTime};
use serde::Deserialize;
use sha2::Sha256;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::oneshot;
use url::Url;

use crate::bridge::{
    BridgeHandle, BridgeKind, BridgeStream, create_bridge, register_dial_write_ack,
    remove_dial_write_ack,
};
use crate::ssh_sftp::{FsEntry, FsReq, guess_mime};
use crate::{emit_fs_bytes, emit_fs_err, emit_fs_ok, emit_fs_progress, emit_json};

#[derive(Deserialize, Clone)]
pub struct DavConfig {
    pub url: String,
    #[serde(default)]
    pub user: String,
    #[serde(default)]
    pub password: String,
    #[serde(default, rename = "basePath")]
    pub base_path: String,
    #[serde(default, rename = "insecureSkipVerify")]
    pub insecure_skip_verify: bool,
}

struct DialSlot {
    bridge: BridgeHandle,
    open_tx: Option<oneshot::Sender<Result<(), String>>>,
}

static DIAL_SEQ: AtomicU64 = AtomicU64::new(1);
static DIGEST_NC: AtomicU32 = AtomicU32::new(1);

thread_local! {
    static DIALS: RefCell<HashMap<String, DialSlot>> = RefCell::new(HashMap::new());
    static DAV_SESSIONS: RefCell<HashMap<String, Arc<DavClient>>> = RefCell::new(HashMap::new());
}

pub fn handle_dial_open(dial_id: &str, ok: bool, err: String) {
    DIALS.with(|m| {
        if let Some(slot) = m.borrow_mut().get_mut(dial_id) {
            if let Some(tx) = slot.open_tx.take() {
                let _ = tx.send(if ok { Ok(()) } else { Err(err) });
            }
        }
    });
}

pub fn handle_dial_data(dial_id: &str, data: Vec<u8>) {
    DIALS.with(|m| {
        if let Some(slot) = m.borrow().get(dial_id) {
            slot.bridge.push_inbound(data);
        }
    });
}

pub fn handle_dial_close(dial_id: &str) {
    let removed = DIALS.with(|m| m.borrow_mut().remove(dial_id));
    if let Some(slot) = removed {
        if let Some(tx) = slot.open_tx {
            let _ = tx.send(Err("TCP 连接已关闭".to_string()));
        }
        slot.bridge.close();
        remove_dial_write_ack(dial_id);
    }
}

async fn dial_tcp(session_id: &str, host: &str, port: u16) -> Result<(String, BridgeStream), String> {
    let dial_id = format!("d-{}", DIAL_SEQ.fetch_add(1, Ordering::Relaxed));
    register_dial_write_ack(&dial_id);
    let (bridge_handle, stream) = create_bridge(BridgeKind::Dial {
        dial_id: dial_id.clone(),
    });
    let (tx, rx) = oneshot::channel();
    DIALS.with(|m| {
        m.borrow_mut().insert(
            dial_id.clone(),
            DialSlot {
                bridge: bridge_handle,
                open_tx: Some(tx),
            },
        );
    });
    emit_json(
        session_id,
        "dial-socket",
        serde_json::json!({ "dialId": dial_id, "host": host, "port": port }),
    );
    match rx.await {
        Ok(Ok(())) => Ok((dial_id, stream)),
        Ok(Err(e)) => {
            close_dial(&dial_id);
            Err(if e.is_empty() { "无法建立 TCP 连接".into() } else { e })
        }
        Err(_) => {
            close_dial(&dial_id);
            Err("TCP 连接失败".into())
        }
    }
}

fn close_dial(dial_id: &str) {
    handle_dial_close(dial_id);
    emit_json("", "dial-close", serde_json::json!({ "dialId": dial_id }));
}

#[derive(Debug)]
struct NoCertVerify;

impl ServerCertVerifier for NoCertVerify {
    fn verify_server_cert(
        &self,
        _end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, rustls::Error> {
        Ok(ServerCertVerified::assertion())
    }
    fn verify_tls12_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }
    fn verify_tls13_signature(
        &self,
        _message: &[u8],
        _cert: &CertificateDer<'_>,
        _dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, rustls::Error> {
        Ok(HandshakeSignatureValid::assertion())
    }
    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

#[derive(Debug)]
struct JsTimeProvider;

impl rustls::time_provider::TimeProvider for JsTimeProvider {
    fn current_time(&self) -> Option<UnixTime> {
        let secs = (js_sys::Date::now() / 1000.0).max(0.0) as u64;
        Some(UnixTime::since_unix_epoch(std::time::Duration::from_secs(secs)))
    }
}

fn build_tls_config(insecure: bool) -> Result<Arc<ClientConfig>, String> {
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    let builder = ClientConfig::builder_with_details(provider, Arc::new(JsTimeProvider))
        .with_safe_default_protocol_versions()
        .map_err(|e| format!("TLS 初始化失败：{}", e))?;
    let cfg = if insecure {
        builder
            .dangerous()
            .with_custom_certificate_verifier(Arc::new(NoCertVerify))
            .with_no_client_auth()
    } else {
        let mut roots = RootCertStore::empty();
        roots.extend(webpki_roots::TLS_SERVER_ROOTS.iter().cloned());
        builder.with_root_certificates(roots).with_no_client_auth()
    };
    Ok(Arc::new(cfg))
}

struct TlsState {
    conn: UnbufferedClientConnection,
    incoming_tls: Vec<u8>,
    outgoing_tls: Vec<u8>,
    pending_plain_out: Vec<u8>,
    decrypted_in: Vec<u8>,
    handshake_done: bool,
    peer_closed: bool,
}

impl TlsState {
    fn new(cfg: Arc<ClientConfig>, server_name: ServerName<'static>) -> Result<Self, String> {
        let conn = UnbufferedClientConnection::new(cfg, server_name)
            .map_err(|e| format!("TLS 创建失败：{}", e))?;
        let mut st = Self {
            conn,
            incoming_tls: Vec::new(),
            outgoing_tls: Vec::new(),
            pending_plain_out: Vec::new(),
            decrypted_in: Vec::new(),
            handshake_done: false,
            peer_closed: false,
        };
        st.pump()?;
        Ok(st)
    }

    fn pump(&mut self) -> Result<(), String> {
        let mut scratch = vec![0u8; 32768];
        loop {
            let UnbufferedStatus { discard, state } =
                self.conn.process_tls_records(&mut self.incoming_tls);
            let state = match state {
                Ok(s) => s,
                Err(e) => {
                    if discard > 0 {
                        self.incoming_tls.drain(..discard.min(self.incoming_tls.len()));
                    }
                    return Err(format!("TLS 证书或握手失败：{}", e));
                }
            };
            let mut progressed = false;
            match state {
                ConnectionState::EncodeTlsData(mut enc) => loop {
                    match enc.encode(&mut scratch) {
                        Ok(n) => {
                            self.outgoing_tls.extend_from_slice(&scratch[..n]);
                            progressed = true;
                            break;
                        }
                        Err(EncodeError::InsufficientSize(ise)) => {
                            scratch.resize(ise.required_size.max(scratch.len() * 2), 0);
                        }
                        Err(EncodeError::AlreadyEncoded) => break,
                    }
                },
                ConnectionState::TransmitTlsData(tx) => {
                    tx.done();
                    progressed = true;
                }
                ConnectionState::BlockedHandshake => {}
                ConnectionState::ReadTraffic(mut rt) => {
                    self.handshake_done = true;
                    while let Some(res) = rt.next_record() {
                        let rec = res.map_err(|e| format!("TLS 解密失败：{}", e))?;
                        self.decrypted_in.extend_from_slice(rec.payload);
                        progressed = true;
                    }
                }
                ConnectionState::WriteTraffic(mut wt) => {
                    self.handshake_done = true;
                    while !self.pending_plain_out.is_empty() {
                        let take = self.pending_plain_out.len().min(16384);
                        loop {
                            match wt.encrypt(&self.pending_plain_out[..take], &mut scratch) {
                                Ok(n) => {
                                    self.outgoing_tls.extend_from_slice(&scratch[..n]);
                                    self.pending_plain_out.drain(..take);
                                    progressed = true;
                                    break;
                                }
                                Err(EncryptError::InsufficientSize(ise)) => {
                                    scratch.resize(ise.required_size.max(scratch.len() * 2), 0);
                                }
                                Err(EncryptError::EncryptExhausted) => {
                                    return Err("TLS 加密流已耗尽".into());
                                }
                            }
                        }
                    }
                }
                ConnectionState::Closed => {
                    self.peer_closed = true;
                }
                _ => {}
            }
            if discard > 0 {
                self.incoming_tls.drain(..discard.min(self.incoming_tls.len()));
                progressed = true;
            }
            if !progressed {
                break;
            }
        }
        Ok(())
    }
}

enum HttpTransport {
    Plain(BridgeStream),
    Tls {
        stream: BridgeStream,
        tls: Box<TlsState>,
    },
}

impl HttpTransport {
    async fn connect(
        session_id: &str,
        host: &str,
        port: u16,
        is_https: bool,
        insecure: bool,
    ) -> Result<(String, Self), String> {
        let (dial_id, mut stream) = dial_tcp(session_id, host, port).await?;
        if !is_https {
            return Ok((dial_id, HttpTransport::Plain(stream)));
        }
        let tls_cfg = build_tls_config(insecure)?;
        let server_name = ServerName::try_from(host.to_string())
            .map_err(|_| format!("无效的主机名：{}", host))?;
        let mut tls = Box::new(TlsState::new(tls_cfg, server_name)?);

        let mut read_buf = vec![0u8; 16 * 1024];
        while !tls.handshake_done {
            flush_tls_out(&mut stream, &mut tls).await?;
            if tls.handshake_done {
                break;
            }
            let n = stream
                .read(&mut read_buf)
                .await
                .map_err(|e| format!("TLS 握手读取失败：{}", e))?;
            if n == 0 {
                return Err("TLS 握手期间连接关闭".into());
            }
            tls.incoming_tls.extend_from_slice(&read_buf[..n]);
            tls.pump()?;
        }
        flush_tls_out(&mut stream, &mut tls).await?;
        Ok((dial_id, HttpTransport::Tls { stream, tls }))
    }

    async fn write_all(&mut self, data: &[u8]) -> Result<(), String> {
        match self {
            HttpTransport::Plain(s) => {
                s.write_all(data).await.map_err(|e| e.to_string())?;
                s.flush().await.map_err(|e| e.to_string())
            }
            HttpTransport::Tls { stream, tls } => {
                tls.pending_plain_out.extend_from_slice(data);
                tls.pump()?;
                flush_tls_out(stream, tls).await
            }
        }
    }

    async fn read_chunk(&mut self, dst: &mut [u8]) -> Result<usize, String> {
        match self {
            HttpTransport::Plain(s) => s.read(dst).await.map_err(|e| e.to_string()),
            HttpTransport::Tls { stream, tls } => {
                let mut raw = vec![0u8; 16 * 1024];
                loop {
                    if !tls.decrypted_in.is_empty() {
                        let take = tls.decrypted_in.len().min(dst.len());
                        dst[..take].copy_from_slice(&tls.decrypted_in[..take]);
                        tls.decrypted_in.drain(..take);
                        return Ok(take);
                    }
                    if tls.peer_closed {
                        return Ok(0);
                    }
                    let n = stream.read(&mut raw).await.map_err(|e| e.to_string())?;
                    if n == 0 {
                        return Ok(0);
                    }
                    tls.incoming_tls.extend_from_slice(&raw[..n]);
                    tls.pump()?;
                    flush_tls_out(stream, tls).await?;
                }
            }
        }
    }
}

async fn flush_tls_out(stream: &mut BridgeStream, tls: &mut TlsState) -> Result<(), String> {
    if !tls.outgoing_tls.is_empty() {
        let out = std::mem::take(&mut tls.outgoing_tls);
        stream.write_all(&out).await.map_err(|e| e.to_string())?;
        stream.flush().await.map_err(|e| e.to_string())?;
    }
    Ok(())
}

struct HttpResp {
    status: u16,
    headers: HashMap<String, String>,
    body: Vec<u8>,
    total_len: u64,
    truncated: bool,
}

pub struct DavClient {
    session_id: String,
    scheme: String,
    host: String,
    port: u16,
    host_header: String,
    root_path: String,
    user: String,
    password: String,
    insecure: bool,
}

impl DavClient {
    pub fn new(session_id: String, cfg: DavConfig) -> Result<Self, String> {
        let parsed = Url::parse(cfg.url.trim())
            .map_err(|_| "无效的 WebDAV 地址，请使用 http:// 或 https://".to_string())?;
        let scheme = parsed.scheme().to_ascii_lowercase();
        if scheme != "http" && scheme != "https" {
            return Err("无效的 WebDAV 地址，请使用 http:// 或 https://".to_string());
        }
        let host = parsed
            .host_str()
            .ok_or_else(|| "WebDAV 缺少主机名".to_string())?
            .to_string();
        let default_port = if scheme == "https" { 443 } else { 80 };
        let port = parsed.port().unwrap_or(default_port);
        let host_header = if parsed.port().is_some() {
            format!("{}:{}", host, port)
        } else {
            host.clone()
        };

        let mut root_path = clean_dav_path(parsed.path());
        if !cfg.base_path.trim().is_empty() {
            let bp = clean_dav_path(&cfg.base_path);
            if bp != "/" {
                if root_path == "/" {
                    root_path = bp;
                } else if !bp.starts_with(&root_path) {
                    root_path = clean_dav_path(&format!("{}/{}", root_path, bp));
                } else {
                    root_path = bp;
                }
            }
        }
        Ok(Self {
            session_id,
            scheme,
            host,
            port,
            host_header,
            root_path,
            user: cfg.user,
            password: cfg.password,
            insecure: cfg.insecure_skip_verify,
        })
    }

    fn full_path(&self, rel: &str) -> String {
        let rel = clean_dav_path(rel);
        if self.root_path == "/" {
            rel
        } else if rel == "/" {
            self.root_path.clone()
        } else {
            format!("{}{}", self.root_path.trim_end_matches('/'), rel)
        }
    }

    fn encode_uri_path(path: &str, trailing_slash: bool) -> String {
        let mut encoded = String::new();
        for seg in path.split('/').filter(|s| !s.is_empty()) {
            encoded.push('/');
            for &b in seg.as_bytes() {
                if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_' | b'.' | b'~') {
                    encoded.push(b as char);
                } else {
                    encoded.push_str(&format!("%{:02X}", b));
                }
            }
        }
        if encoded.is_empty() {
            encoded.push('/');
        } else if trailing_slash && !encoded.ends_with('/') {
            encoded.push('/');
        }
        encoded
    }

    fn full_url(&self, rel: &str, trailing_slash: bool) -> String {
        let uri = Self::encode_uri_path(&self.full_path(rel), trailing_slash);
        format!("{}://{}{}", self.scheme, self.host_header, uri)
    }

    async fn request_once(
        &self,
        method: &str,
        uri_path: &str,
        extra_headers: &[(&str, String)],
        body: &[u8],
        auth_header: Option<String>,
        max_bytes: usize,
        progress_req: Option<&str>,
    ) -> Result<HttpResp, String> {
        let is_https = self.scheme == "https";
        let (dial_id, mut transport) =
            HttpTransport::connect(&self.session_id, &self.host, self.port, is_https, self.insecure)
                .await?;
        let res = self
            .do_http(
                &mut transport,
                method,
                uri_path,
                extra_headers,
                body,
                auth_header,
                max_bytes,
                progress_req,
            )
            .await;
        close_dial(&dial_id);
        res
    }

    async fn do_http(
        &self,
        transport: &mut HttpTransport,
        method: &str,
        uri_path: &str,
        extra_headers: &[(&str, String)],
        body: &[u8],
        auth_header: Option<String>,
        max_bytes: usize,
        progress_req: Option<&str>,
    ) -> Result<HttpResp, String> {
        let mut req = format!(
            "{} {} HTTP/1.1\r\nHost: {}\r\nUser-Agent: BookStark-WebDAV/1.2\r\nConnection: close\r\nContent-Length: {}\r\n",
            method,
            uri_path,
            self.host_header,
            body.len()
        );
        if let Some(auth) = auth_header {
            req.push_str(&format!("Authorization: {}\r\n", auth));
        } else if !self.user.is_empty() || !self.password.is_empty() {
            let cred = base64::engine::general_purpose::STANDARD
                .encode(format!("{}:{}", self.user, self.password));
            req.push_str(&format!("Authorization: Basic {}\r\n", cred));
        }
        for (k, v) in extra_headers {
            req.push_str(&format!("{}: {}\r\n", k, v));
        }
        req.push_str("\r\n");

        if body.len() <= 32 * 1024 {
            let mut combined = Vec::with_capacity(req.len() + body.len());
            combined.extend_from_slice(req.as_bytes());
            combined.extend_from_slice(body);
            transport.write_all(&combined).await?;
            if let Some(rid) = progress_req {
                if !body.is_empty() {
                    emit_fs_progress(&self.session_id, rid, body.len() as u64, body.len() as u64);
                }
            }
        } else {
            transport.write_all(req.as_bytes()).await?;
            let total = body.len() as u64;
            let mut sent: u64 = 0;
            for chunk in body.chunks(32 * 1024) {
                transport.write_all(chunk).await?;
                sent += chunk.len() as u64;
                if let Some(rid) = progress_req {
                    emit_fs_progress(&self.session_id, rid, sent, total);
                }
            }
        }

        // Read response headers
        let mut raw = Vec::new();
        let mut tmp = vec![0u8; 16 * 1024];
        let header_end = loop {
            if let Some(pos) = find_crlfcrlf(&raw) {
                break pos;
            }
            if raw.len() > 128 * 1024 {
                return Err("HTTP 响应头过大".into());
            }
            let n = transport.read_chunk(&mut tmp).await?;
            if n == 0 {
                return Err("服务器意外关闭了连接".into());
            }
            raw.extend_from_slice(&tmp[..n]);
        };

        let header_str = String::from_utf8_lossy(&raw[..header_end]);
        let mut lines = header_str.split("\r\n");
        let status_line = lines.next().ok_or("无效的 HTTP 响应")?;
        let status: u16 = status_line
            .split_whitespace()
            .nth(1)
            .and_then(|s| s.parse().ok())
            .ok_or("无法解析 HTTP 状态码")?;

        let mut headers = HashMap::new();
        for line in lines {
            if let Some((k, v)) = line.split_once(':') {
                headers.insert(k.trim().to_ascii_lowercase(), v.trim().to_string());
            }
        }

        let mut rest = raw[header_end + 4..].to_vec();
        let chunked = headers
            .get("transfer-encoding")
            .is_some_and(|v| v.to_ascii_lowercase().contains("chunked"));
        let content_len: Option<u64> = headers
            .get("content-length")
            .and_then(|v| v.parse().ok());

        let mut out = Vec::new();
        let mut truncated = false;

        if status == 204 || status == 304 || method == "HEAD" {
            // No body
        } else if chunked {
            // Read remaining stream and decode chunked transfer encoding
            while !rest.ends_with(b"0\r\n\r\n") {
                let n = transport.read_chunk(&mut tmp).await?;
                if n == 0 {
                    break;
                }
                rest.extend_from_slice(&tmp[..n]);
                if max_bytes > 0 && rest.len() > max_bytes + 64 * 1024 {
                    truncated = true;
                    break;
                }
            }
            out = decode_chunked(&rest, max_bytes, &mut truncated);
        } else {
            let total = content_len.unwrap_or(0);
            let push_slice = |out: &mut Vec<u8>, slice: &[u8], truncated: &mut bool| -> bool {
                if max_bytes > 0 && out.len() + slice.len() > max_bytes {
                    let rem = max_bytes.saturating_sub(out.len());
                    if rem > 0 {
                        out.extend_from_slice(&slice[..rem]);
                    }
                    *truncated = true;
                    return false;
                }
                out.extend_from_slice(slice);
                true
            };
            if push_slice(&mut out, &rest, &mut truncated) {
                if let Some(rid) = progress_req {
                    if total > 0 {
                        emit_fs_progress(&self.session_id, rid, out.len() as u64, total);
                    }
                }
                while content_len.map_or(true, |cl| (out.len() as u64) < cl) {
                    let n = transport.read_chunk(&mut tmp).await?;
                    if n == 0 {
                        break;
                    }
                    if !push_slice(&mut out, &tmp[..n], &mut truncated) {
                        break;
                    }
                    if let Some(rid) = progress_req {
                        emit_fs_progress(&self.session_id, rid, out.len() as u64, total);
                    }
                }
            }
        }

        let total_len = content_len.unwrap_or(out.len() as u64);
        Ok(HttpResp {
            status,
            headers,
            body: out,
            total_len,
            truncated,
        })
    }

    async fn request(
        &self,
        method: &str,
        uri_path: &str,
        extra_headers: &[(&str, String)],
        body: &[u8],
        max_bytes: usize,
        progress_req: Option<&str>,
    ) -> Result<HttpResp, String> {
        let resp = self
            .request_once(method, uri_path, extra_headers, body, None, max_bytes, progress_req)
            .await?;
        if resp.status == 401 && (!self.user.is_empty() || !self.password.is_empty()) {
            if let Some(chal) = resp.headers.get("www-authenticate") {
                if chal.to_ascii_lowercase().starts_with("digest ") {
                    if let Some(auth) = build_digest_auth(chal, method, uri_path, &self.user, &self.password) {
                        return self
                            .request_once(
                                method,
                                uri_path,
                                extra_headers,
                                body,
                                Some(auth),
                                max_bytes,
                                progress_req,
                            )
                            .await;
                    }
                }
            }
        }
        Ok(resp)
    }

    pub async fn list(&self, rel_path: &str) -> Result<(String, Vec<FsEntry>), String> {
        let cwd = clean_dav_path(rel_path);
        let uri = Self::encode_uri_path(&self.full_path(&cwd), true);
        const PROPFIND_XML: &[u8] = br#"<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/><d:getlastmodified/><d:getcontenttype/></d:prop></d:propfind>"#;
        let resp = self
            .request(
                "PROPFIND",
                &uri,
                &[
                    ("Depth", "1".into()),
                    ("Content-Type", "application/xml; charset=utf-8".into()),
                ],
                PROPFIND_XML,
                8 * 1024 * 1024,
                None,
            )
            .await?;
        if resp.status == 401 || resp.status == 403 {
            return Err(format!("认证失败（HTTP {}），请检查用户名和密码", resp.status));
        }
        if resp.status == 404 {
            return Err(format!("目录不存在：{}", cwd));
        }
        if resp.status != 207 && !(200..300).contains(&resp.status) {
            return Err(format!("WebDAV 请求失败（HTTP {}）", resp.status));
        }
        let entries = parse_multistatus(&resp.body, &self.root_path, &self.full_path(&cwd), &cwd)?;
        Ok((cwd, entries))
    }
}

pub fn start_dav(id: String, cfg: DavConfig) {
    wasm_bindgen_futures::spawn_local(async move {
        let client = match DavClient::new(id.clone(), cfg) {
            Ok(c) => Arc::new(c),
            Err(err) => {
                emit_json(&id, "dav-error", serde_json::json!({ "reason": err }));
                return;
            }
        };
        match client.list("/").await {
            Ok((cwd, entries)) => {
                DAV_SESSIONS.with(|m| {
                    m.borrow_mut().insert(id.clone(), client);
                });
                let raw = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".into());
                emit_json(
                    &id,
                    "dav-connected",
                    serde_json::json!({ "cwd": cwd, "entries": raw }),
                );
            }
            Err(err) => {
                emit_json(&id, "dav-error", serde_json::json!({ "reason": err }));
            }
        }
    });
}

pub fn test_dav(req_id: String, cfg: DavConfig) {
    wasm_bindgen_futures::spawn_local(async move {
        let t0 = js_sys::Date::now();
        let client = match DavClient::new(String::new(), cfg) {
            Ok(c) => c,
            Err(err) => {
                emit_json("", "dav-test-res", serde_json::json!({ "reqId": req_id, "ok": false, "error": err }));
                return;
            }
        };
        match client.list("/").await {
            Ok((_, entries)) => {
                let ms = (js_sys::Date::now() - t0).max(0.0) as u64;
                emit_json(
                    "",
                    "dav-test-res",
                    serde_json::json!({ "reqId": req_id, "ok": true, "ms": ms, "count": entries.len() }),
                );
            }
            Err(err) => {
                emit_json("", "dav-test-res", serde_json::json!({ "reqId": req_id, "ok": false, "error": err }));
            }
        }
    });
}

pub fn close_dav(id: &str) {
    DAV_SESSIONS.with(|m| {
        m.borrow_mut().remove(id);
    });
}

pub fn try_handle_dav_fs(id: &str, req: FsReq) -> Result<(), FsReq> {
    let client = DAV_SESSIONS.with(|m| m.borrow().get(id).cloned());
    let Some(client) = client else {
        return Err(req);
    };
    let sid = id.to_string();
    wasm_bindgen_futures::spawn_local(async move {
        match req.op.as_str() {
            "list" => match client.list(&req.path).await {
                Ok((cwd, entries)) => {
                    let raw = serde_json::to_string(&entries).unwrap_or_else(|_| "[]".into());
                    emit_fs_ok(&sid, &req.req_id, serde_json::json!({ "cwd": cwd, "entries": raw }));
                }
                Err(e) => emit_fs_err(&sid, &req.req_id, &e),
            },
            "read" => {
                let uri = DavClient::encode_uri_path(&client.full_path(&req.path), false);
                match client
                    .request("GET", &uri, &[], &[], req.max_bytes, Some(&req.req_id))
                    .await
                {
                    Ok(r) if (200..300).contains(&r.status) => {
                        emit_fs_bytes(&sid, &req.req_id, &r.body, r.total_len, r.truncated);
                    }
                    Ok(r) => emit_fs_err(&sid, &req.req_id, &format!("读取文件失败（HTTP {}）", r.status)),
                    Err(e) => emit_fs_err(&sid, &req.req_id, &e),
                }
            }
            "write" => {
                let uri = DavClient::encode_uri_path(&client.full_path(&req.path), false);
                let size = req.data.len();
                match client
                    .request(
                        "PUT",
                        &uri,
                        &[("Content-Type", "application/octet-stream".into())],
                        &req.data,
                        64 * 1024,
                        Some(&req.req_id),
                    )
                    .await
                {
                    Ok(r) if (200..300).contains(&r.status) => {
                        emit_fs_ok(&sid, &req.req_id, serde_json::json!({ "size": size }));
                    }
                    Ok(r) => emit_fs_err(&sid, &req.req_id, &format!("写入文件失败（HTTP {}）", r.status)),
                    Err(e) => emit_fs_err(&sid, &req.req_id, &e),
                }
            }
            "mkdir" => {
                let uri = DavClient::encode_uri_path(&client.full_path(&req.path), true);
                match client.request("MKCOL", &uri, &[], &[], 64 * 1024, None).await {
                    Ok(r) if (200..300).contains(&r.status) => {
                        emit_fs_ok(&sid, &req.req_id, serde_json::json!({}));
                    }
                    Ok(r) => emit_fs_err(&sid, &req.req_id, &format!("创建目录失败（HTTP {}）", r.status)),
                    Err(e) => emit_fs_err(&sid, &req.req_id, &e),
                }
            }
            "rename" => {
                let uri = DavClient::encode_uri_path(&client.full_path(&req.path), false);
                let dst = client.full_url(&req.to, false);
                match client
                    .request(
                        "MOVE",
                        &uri,
                        &[("Destination", dst), ("Overwrite", "T".into())],
                        &[],
                        64 * 1024,
                        None,
                    )
                    .await
                {
                    Ok(r) if (200..300).contains(&r.status) => {
                        emit_fs_ok(&sid, &req.req_id, serde_json::json!({}));
                    }
                    Ok(r) => emit_fs_err(&sid, &req.req_id, &format!("重命名失败（HTTP {}）", r.status)),
                    Err(e) => emit_fs_err(&sid, &req.req_id, &e),
                }
            }
            "delete" => {
                let uri = DavClient::encode_uri_path(&client.full_path(&req.path), false);
                match client.request("DELETE", &uri, &[], &[], 64 * 1024, None).await {
                    Ok(r) if (200..300).contains(&r.status) => {
                        emit_fs_ok(&sid, &req.req_id, serde_json::json!({}));
                    }
                    Ok(r) => emit_fs_err(&sid, &req.req_id, &format!("删除失败（HTTP {}）", r.status)),
                    Err(e) => emit_fs_err(&sid, &req.req_id, &e),
                }
            }
            other => emit_fs_err(&sid, &req.req_id, &format!("WebDAV 不支持此操作：{}", other)),
        }
    });
    Ok(())
}

// ---------------- Helpers: Path, HTTP Chunked, Digest Auth, XML PROPFIND ----------------

fn clean_dav_path(p: &str) -> String {
    let norm = p.trim().replace('\\', "/");
    let mut parts = Vec::new();
    for seg in norm.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            s => parts.push(s),
        }
    }
    format!("/{}", parts.join("/"))
}

fn find_crlfcrlf(buf: &[u8]) -> Option<usize> {
    buf.windows(4).position(|w| w == b"\r\n\r\n")
}

fn decode_chunked(data: &[u8], max_bytes: usize, truncated: &mut bool) -> Vec<u8> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < data.len() {
        let Some(rel_end) = data[i..].windows(2).position(|w| w == b"\r\n") else {
            break;
        };
        let line = String::from_utf8_lossy(&data[i..i + rel_end]);
        let hex_len = line.split(';').next().unwrap_or("").trim();
        let Ok(sz) = usize::from_str_radix(hex_len, 16) else {
            break;
        };
        i += rel_end + 2;
        if sz == 0 {
            break;
        }
        let end = (i + sz).min(data.len());
        let slice = &data[i..end];
        if max_bytes > 0 && out.len() + slice.len() > max_bytes {
            let rem = max_bytes.saturating_sub(out.len());
            out.extend_from_slice(&slice[..rem]);
            *truncated = true;
            break;
        }
        out.extend_from_slice(slice);
        i = end;
        if i + 2 <= data.len() && &data[i..i + 2] == b"\r\n" {
            i += 2;
        }
    }
    out
}

fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(v) = u8::from_str_radix(&String::from_utf8_lossy(&bytes[i + 1..i + 3]), 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

fn local_name(raw: &[u8]) -> &[u8] {
    raw.rsplit(|&b| b == b':').next().unwrap_or(raw)
}

fn parse_multistatus(
    xml: &[u8],
    root_path: &str,
    req_full: &str,
    cwd: &str,
) -> Result<Vec<FsEntry>, String> {
    let mut reader = Reader::from_reader(xml);
    reader.config_mut().trim_text(true);

    let mut entries = Vec::new();
    let mut seen = HashMap::<String, bool>::new();
    let req_full_clean = clean_dav_path(req_full).trim_end_matches('/').to_string();
    let root_clean = clean_dav_path(root_path).trim_end_matches('/').to_string();

    let mut in_response = false;
    let mut cur_tag = String::new();
    let mut href = String::new();
    let mut display_name = String::new();
    let mut content_len = String::new();
    let mut last_mod = String::new();
    let mut content_type = String::new();
    let mut is_collection = false;

    loop {
        match reader.read_event() {
            Ok(Event::Start(e)) => {
                let name = String::from_utf8_lossy(local_name(e.name().as_ref())).to_ascii_lowercase();
                if name == "response" {
                    in_response = true;
                    href.clear();
                    display_name.clear();
                    content_len.clear();
                    last_mod.clear();
                    content_type.clear();
                    is_collection = false;
                } else if in_response {
                    if name == "collection" {
                        is_collection = true;
                    }
                    cur_tag = name;
                }
            }
            Ok(Event::Empty(e)) => {
                if in_response {
                    let name = String::from_utf8_lossy(local_name(e.name().as_ref())).to_ascii_lowercase();
                    if name == "collection" {
                        is_collection = true;
                    }
                }
            }
            Ok(Event::Text(t)) => {
                if in_response {
                    let txt = t.unescape().map(|c| c.into_owned()).unwrap_or_default();
                    match cur_tag.as_str() {
                        "href" => href.push_str(&txt),
                        "displayname" => display_name.push_str(&txt),
                        "getcontentlength" => content_len.push_str(&txt),
                        "getlastmodified" => last_mod.push_str(&txt),
                        "getcontenttype" => content_type.push_str(&txt),
                        _ => {}
                    }
                }
            }
            Ok(Event::End(e)) => {
                let name = String::from_utf8_lossy(local_name(e.name().as_ref())).to_ascii_lowercase();
                if name == "response" && in_response {
                    in_response = false;
                    let raw_href = href.trim();
                    let raw_path = Url::parse(raw_href)
                        .map(|u| u.path().to_string())
                        .unwrap_or_else(|_| raw_href.to_string());
                    let decoded = percent_decode(&raw_path);
                    let href_clean = clean_dav_path(&decoded).trim_end_matches('/').to_string();
                    if href_clean != req_full_clean && !(href_clean.is_empty() && req_full_clean.is_empty()) {
                        let mut rel = href_clean.clone();
                        if !root_clean.is_empty() && root_clean != "/" {
                            if let Some(stripped) = href_clean.strip_prefix(&format!("{}/", root_clean)) {
                                rel = format!("/{}", stripped);
                            } else if href_clean == root_clean {
                                continue;
                            }
                        }
                        let rel = clean_dav_path(&rel);
                        if rel != cwd && !seen.contains_key(&rel) {
                            seen.insert(rel.clone(), true);
                            let is_dir = is_collection || raw_href.ends_with('/');
                            let name = rel
                                .rsplit('/')
                                .next()
                                .filter(|s| !s.is_empty())
                                .map(|s| s.to_string())
                                .unwrap_or_else(|| display_name.trim().to_string());
                            if !name.is_empty() {
                                let size = content_len.trim().parse::<u64>().unwrap_or(0);
                                let mod_time = parse_http_date_js(last_mod.trim());
                                let mime = if is_dir {
                                    None
                                } else if !content_type.trim().is_empty() {
                                    Some(content_type.trim().to_string())
                                } else {
                                    guess_mime(&name)
                                };
                                entries.push(FsEntry {
                                    name,
                                    path: rel,
                                    is_dir,
                                    size,
                                    mode: None,
                                    mod_time,
                                    mime,
                                });
                            }
                        }
                    }
                }
                cur_tag.clear();
            }
            Ok(Event::Eof) => break,
            Err(e) => return Err(format!("解析 WebDAV XML 失败：{}", e)),
            _ => {}
        }
    }

    entries.sort_by(|a, b| {
        b.is_dir
            .cmp(&a.is_dir)
            .then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase()))
    });
    Ok(entries)
}

fn parse_http_date_js(s: &str) -> i64 {
    if s.is_empty() {
        return 0;
    }
    let ms = js_sys::Date::parse(s);
    if ms.is_finite() {
        (ms / 1000.0) as i64
    } else {
        0
    }
}

fn build_digest_auth(
    header: &str,
    method: &str,
    uri: &str,
    user: &str,
    pass: &str,
) -> Option<String> {
    let params = parse_digest_params(header);
    let realm = params.get("realm")?;
    let nonce = params.get("nonce")?;
    let alg = params
        .get("algorithm")
        .map(|s| s.to_ascii_uppercase())
        .unwrap_or_default();
    let hash = |s: &str| -> String {
        if alg.starts_with("SHA-256") {
            let d = Sha256::digest(s.as_bytes());
            hex_lower(&d)
        } else {
            let d = Md5::digest(s.as_bytes());
            hex_lower(&d)
        }
    };
    let ha1 = hash(&format!("{}:{}:{}", user, realm, pass));
    let ha2 = hash(&format!("{}:{}", method, uri));
    let mut parts = vec![
        format!(r#"username="{}""#, esc_q(user)),
        format!(r#"realm="{}""#, esc_q(realm)),
        format!(r#"nonce="{}""#, esc_q(nonce)),
        format!(r#"uri="{}""#, esc_q(uri)),
    ];
    if params.contains_key("qop") {
        let nc = format!("{:08x}", DIGEST_NC.fetch_add(1, Ordering::Relaxed));
        let cnonce = format!("{:016x}", (js_sys::Math::random() * 1e16) as u64);
        let resp = hash(&format!("{}:{}:{}:{}:auth:{}", ha1, nonce, nc, cnonce, ha2));
        parts.push("qop=auth".into());
        parts.push(format!("nc={}", nc));
        parts.push(format!(r#"cnonce="{}""#, cnonce));
        parts.push(format!(r#"response="{}""#, resp));
    } else {
        let resp = hash(&format!("{}:{}:{}", ha1, nonce, ha2));
        parts.push(format!(r#"response="{}""#, resp));
    }
    if let Some(op) = params.get("opaque") {
        parts.push(format!(r#"opaque="{}""#, esc_q(op)));
    }
    if !alg.is_empty() {
        parts.push(format!("algorithm={}", alg));
    }
    Some(format!("Digest {}", parts.join(", ")))
}

fn hex_lower(bytes: &[u8]) -> String {
    let mut s = String::with_capacity(bytes.len() * 2);
    for b in bytes {
        s.push_str(&format!("{:02x}", b));
    }
    s
}

fn esc_q(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

fn parse_digest_params(h: &str) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let lower = h.to_ascii_lowercase();
    let Some(idx) = lower.find("digest ") else {
        return map;
    };
    let mut rest = h[idx + 7..].trim();
    while !rest.is_empty() {
        let Some(eq) = rest.find('=') else { break };
        let key = rest[..eq].trim().to_ascii_lowercase();
        rest = rest[eq + 1..].trim_start();
        let val = if let Some(after) = rest.strip_prefix('"') {
            let mut v = String::new();
            let mut esc = false;
            let mut end_idx = after.len();
            for (i, ch) in after.char_indices() {
                if esc {
                    v.push(ch);
                    esc = false;
                } else if ch == '\\' {
                    esc = true;
                } else if ch == '"' {
                    end_idx = i + 1;
                    break;
                } else {
                    v.push(ch);
                }
            }
            rest = after[end_idx..].trim_start_matches(|c| c == ',' || c == ' ');
            v
        } else if let Some(comma) = rest.find(',') {
            let v = rest[..comma].trim().to_string();
            rest = rest[comma + 1..].trim_start();
            v
        } else {
            let v = rest.trim().to_string();
            rest = "";
            v
        };
        map.insert(key, val);
    }
    map
}
