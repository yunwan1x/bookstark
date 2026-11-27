mod audio;
mod clipboard;
mod tls;
mod vdrive;

use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::sync::{Arc, Mutex};

use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, FileContentsFlags, FileContentsRequest,
    FileContentsResponse, FileDescriptor, OwnedFormatDataResponse,
};
use ironrdp_cliprdr::CliprdrClient;
use ironrdp_connector::credssp::CredsspSequence;
use ironrdp_connector::{
    BitmapConfig, ClientConnector, Config, Credentials, DesktopSize, Sequence as _, ServerName,
    State as _,
};
use ironrdp_core::WriteBuf;
use ironrdp_displaycontrol::client::DisplayControlClient;
use ironrdp_displaycontrol::pdu::MonitorLayoutEntry;
use ironrdp_dvc::DrdynvcClient;
use ironrdp_graphics::image_processing::PixelFormat;
use ironrdp_pdu::gcc::{ConnectionType, KeyboardType};
use ironrdp_pdu::input::fast_path::{FastPathInputEvent, KeyboardFlags};
use ironrdp_pdu::input::mouse::{MousePdu, PointerFlags};
use ironrdp_pdu::rdp::capability_sets::{BitmapCodecs, MajorPlatformType, RailSupportLevel};
use ironrdp_pdu::rdp::client_info::{PerformanceFlags, TimezoneInfo};
use ironrdp_rdpdr::Rdpdr;
use ironrdp_rdpsnd::client::{Rdpsnd, RdpsndDvcState};
use ironrdp_session::image::DecodedImage;
use ironrdp_session::{ActiveStage, ActiveStageBuilder, ActiveStageOutput};
use js_sys::{Array, Object, Reflect, Uint8Array};
use serde::Deserialize;
use wasm_bindgen::prelude::*;

use crate::audio::{BookStarkRdpsndHandler, SharedAudioState};
use crate::clipboard::{
    encode_utf16le_nul, BookStarkCliprdrBackend, ClipEvent, ClipPendingAction, SharedClipState,
};
use crate::tls::{PeerCertInfo, SansIoTls};
use crate::vdrive::{BookStarkRdpdrBackend, SharedVDrive};

const VDRIVE_DEVICE_ID: u32 = 1;

#[derive(Debug, Deserialize)]
pub struct RdpConnectOptions {
    pub host: String,
    pub username: String,
    pub password: String,
    #[serde(default)]
    pub domain: String,
    #[serde(default = "default_width")]
    pub width: u16,
    #[serde(default = "default_height")]
    pub height: u16,
    #[serde(default = "default_true")]
    pub enable_audio: bool,
    #[serde(default = "default_true")]
    pub enable_vdrive: bool,
    #[serde(default = "default_true")]
    pub enable_nla: bool,
    #[serde(default)]
    pub trusted_fingerprint: Option<String>,
}

fn default_width() -> u16 {
    1280
}
fn default_height() -> u16 {
    800
}
fn default_true() -> bool {
    true
}

#[derive(Debug)]
pub enum RdpOutEvent {
    TcpSend(Vec<u8>),
    State {
        status: String,
        detail: String,
    },
    TlsVerify {
        subject: String,
        issuer: String,
        fingerprint: String,
        protocol: String,
    },
    Connected {
        width: u16,
        height: u16,
        tls_info: String,
    },
    FrameRect {
        x: u16,
        y: u16,
        w: u16,
        h: u16,
        rgba: Vec<u8>,
    },
    Resize {
        width: u16,
        height: u16,
    },
    AudioPcm {
        sample_rate: u32,
        channels: u16,
        bits_per_sample: u16,
        format_label: String,
        data: Vec<u8>,
    },
    ClipText(String),
    ClipFiles {
        files_json: String,
        clip_data_id: Option<u32>,
    },
    ClipFileChunk {
        stream_id: u32,
        data: Vec<u8>,
        is_error: bool,
    },
    ClipFileUploadReq {
        stream_id: u32,
        file_index: i32,
        is_size: bool,
        offset: u64,
        length: u32,
    },
    VDriveState {
        mounted: bool,
        files_json: String,
    },
    Disconnected(String),
    Error(String),
}

enum Phase {
    PreTls {
        connector: Box<ClientConnector>,
    },
    TlsHandshaking {
        connector: Box<ClientConnector>,
        tls: Box<SansIoTls>,
    },
    AwaitTlsApproval {
        connector: Box<ClientConnector>,
        tls: Box<SansIoTls>,
        cert: PeerCertInfo,
    },
    Credssp {
        connector: Box<ClientConnector>,
        tls: Box<SansIoTls>,
        credssp: Box<CredsspSequence>,
    },
    PostTls {
        connector: Box<ClientConnector>,
        tls: Box<SansIoTls>,
    },
    Active {
        tls: Box<SansIoTls>,
        stage: Box<ActiveStage>,
        image: Box<DecodedImage>,
    },
    Closed,
}

pub struct RdpCore {
    opts: RdpConnectOptions,
    phase: Phase,
    rx_plain: Vec<u8>,
    audio: Arc<Mutex<SharedAudioState>>,
    clip: Arc<Mutex<SharedClipState>>,
    vdrive: Arc<Mutex<SharedVDrive>>,
    next_stream_id: u32,
    events: Vec<RdpOutEvent>,
}

impl RdpCore {
    pub fn new(opts: RdpConnectOptions) -> Self {
        let width = opts.width.clamp(640, 4096) & !1;
        let height = opts.height.clamp(480, 2160) & !1;
        let audio = SharedAudioState::new(opts.enable_audio);
        let clip = SharedClipState::new();
        let vdrive = SharedVDrive::new();

        let config = Config {
            desktop_size: DesktopSize { width, height },
            monitor_layout: None,
            desktop_scale_factor: 100,
            desktop_physical_size: None,
            desktop_orientation: None,
            device_scale_factor: None,
            monitor_extended_layout: None,
            relative_mouse_input: false,
            // Support BOTH CredSSP/NLA (Windows) and TLS-only (xrdp / non-NLA Windows)
            enable_tls: true,
            enable_credssp: opts.enable_nla,
            enable_standard_rdp_security: false,
            credentials: Credentials::UsernamePassword {
                username: opts.username.clone(),
                password: opts.password.clone(),
            },
            domain: if opts.domain.trim().is_empty() {
                None
            } else {
                Some(opts.domain.trim().to_string())
            },
            client_build: 0,
            client_name: "BookStark".to_string(),
            keyboard_type: KeyboardType::IBM_ENHANCED,
            keyboard_subtype: 0,
            keyboard_functional_keys_count: 12,
            keyboard_layout: 0x0000_0409,
            connection_type: ConnectionType::Lan,
            ime_file_name: String::new(),
            bitmap: Some(BitmapConfig {
                lossy_compression: true,
                color_depth: 32,
                codecs: BitmapCodecs::default(),
            }),
            dig_product_id: String::new(),
            client_dir: "C:\\Windows\\System32\\mstscax.dll".to_string(),
            alternate_shell: String::new(),
            work_dir: String::new(),
            remote_application_mode: false,
            rail_support_level: RailSupportLevel::empty(),
            platform: MajorPlatformType::UNIX,
            hardware_id: None,
            request_data: None,
            autologon: !opts.username.is_empty() && !opts.password.is_empty(),
            enable_audio_playback: opts.enable_audio,
            enable_audio_capture: false,
            performance_flags: PerformanceFlags::default(),
            license_cache: None,
            timezone_info: TimezoneInfo::default(),
            compression_type: None,
            enable_server_pointer: true,
            pointer_software_rendering: true,
            multitransport_flags: None,
            support_dyn_vc_gfx_protocol: false,
        };

        let client_addr = SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), 0);
        let mut connector = ClientConnector::new(config, client_addr);

        // 1. CLIPRDR (bidirectional text + file list)
        let clip_backend = BookStarkCliprdrBackend::new(clip.clone());
        connector.attach_static_channel(CliprdrClient::new(Box::new(clip_backend)));

        // 2. RDPSND (static channel — also required by MS-RDPEFS for RDPDR!)
        let rdpsnd_static = Rdpsnd::new(Box::new(BookStarkRdpsndHandler::new(audio.clone())));
        connector.attach_static_channel(rdpsnd_static);

        // 3. RDPDR (optional virtual shared drive \\tsclient\BookStark)
        if opts.enable_vdrive {
            let rdpdr = Rdpdr::new(
                Box::new(BookStarkRdpdrBackend::new(vdrive.clone())),
                "BookStark".to_string(),
            )
            .with_drives(Some(vec![(VDRIVE_DEVICE_ID, "BookStark".to_string())]));
            connector.attach_static_channel(rdpdr);
        }

        // 4. DRDYNVC: Display Control (dynamic resize) + AUDIO_PLAYBACK_DVC (Win10/11 audio)
        let mut drdynvc = DrdynvcClient::new().with_dynamic_channel(DisplayControlClient::new(
            |_caps| Ok(Vec::new()),
        ));
        if opts.enable_audio {
            let dvc_audio =
                RdpsndDvcState::new(Box::new(BookStarkRdpsndHandler::new(audio.clone())));
            drdynvc = drdynvc.with_dynamic_channel(dvc_audio.channel());
        }
        connector.attach_static_channel(drdynvc);

        Self {
            opts,
            phase: Phase::PreTls {
                connector: Box::new(connector),
            },
            rx_plain: Vec::new(),
            audio,
            clip,
            vdrive,
            next_stream_id: 1,
            events: Vec::new(),
        }
    }

    /// Kick off the X.224 Connection Request.
    pub fn start(&mut self) -> Vec<RdpOutEvent> {
        self.events.push(RdpOutEvent::State {
            status: "connecting".to_string(),
            detail: "正在发起 RDP X.224 协商…".to_string(),
        });
        if let Err(e) = self.drive() {
            self.fail(e);
        }
        std::mem::take(&mut self.events)
    }

    /// Feed raw bytes received from TCP (`BookStark.sockets`).
    pub fn on_tcp_data(&mut self, data: &[u8]) -> Vec<RdpOutEvent> {
        if let Err(e) = self.ingest_tcp(data) {
            self.fail(e);
        }
        std::mem::take(&mut self.events)
    }

    /// Resume after user approves (or rejects) the RDP TLS certificate fingerprint.
    pub fn approve_tls(&mut self, trusted: bool) -> Vec<RdpOutEvent> {
        let phase = std::mem::replace(&mut self.phase, Phase::Closed);
        match phase {
            Phase::AwaitTlsApproval {
                connector,
                tls,
                cert,
            } => {
                if !trusted {
                    self.events
                        .push(RdpOutEvent::Disconnected("用户取消了不受信任的 TLS 证书连接".to_string()));
                } else {
                    self.phase = Phase::PostTls { connector, tls };
                    if let Err(e) = self.after_tls_approved(cert) {
                        self.fail(e);
                    }
                }
            }
            other => {
                self.phase = other;
            }
        }
        std::mem::take(&mut self.events)
    }

    pub fn send_mouse(&mut self, x: u16, y: u16, flags_bits: u16) -> Vec<RdpOutEvent> {
        let ev = FastPathInputEvent::MouseEvent(MousePdu {
            flags: PointerFlags::from_bits_retain(flags_bits),
            number_of_wheel_rotation_units: 0,
            x_position: x,
            y_position: y,
        });
        self.send_fastpath_events(&[ev]);
        std::mem::take(&mut self.events)
    }

    pub fn send_wheel(&mut self, x: u16, y: u16, delta: i16, horizontal: bool) -> Vec<RdpOutEvent> {
        let mut flags = if horizontal {
            PointerFlags::HORIZONTAL_WHEEL
        } else {
            PointerFlags::VERTICAL_WHEEL
        };
        let units = delta.clamp(-255, 255);
        if units < 0 {
            flags |= PointerFlags::WHEEL_NEGATIVE;
        }
        let ev = FastPathInputEvent::MouseEvent(MousePdu {
            flags,
            number_of_wheel_rotation_units: units.unsigned_abs() as i16,
            x_position: x,
            y_position: y,
        });
        self.send_fastpath_events(&[ev]);
        std::mem::take(&mut self.events)
    }

    pub fn send_scancode(&mut self, scancode: u8, extended: bool, pressed: bool) -> Vec<RdpOutEvent> {
        let mut flags = KeyboardFlags::empty();
        if !pressed {
            flags |= KeyboardFlags::RELEASE;
        }
        if extended {
            flags |= KeyboardFlags::EXTENDED;
        }
        let ev = FastPathInputEvent::KeyboardEvent(flags, scancode);
        self.send_fastpath_events(&[ev]);
        std::mem::take(&mut self.events)
    }

    pub fn send_unicode_text(&mut self, text: &str) -> Vec<RdpOutEvent> {
        let mut events = Vec::with_capacity(text.len() * 2);
        for u in text.encode_utf16() {
            events.push(FastPathInputEvent::UnicodeKeyboardEvent(
                KeyboardFlags::empty(),
                u,
            ));
            events.push(FastPathInputEvent::UnicodeKeyboardEvent(
                KeyboardFlags::RELEASE,
                u,
            ));
        }
        if !events.is_empty() {
            self.send_fastpath_events(&events);
        }
        std::mem::take(&mut self.events)
    }

    pub fn send_clipboard_text(&mut self, text: String) -> Vec<RdpOutEvent> {
        if let Ok(mut st) = self.clip.lock() {
            st.local_text = text;
        }
        if let Phase::Active { tls, stage, .. } = &mut self.phase {
            let formats = vec![ClipboardFormat::new(ClipboardFormatId::CF_UNICODETEXT)];
            let svc_msgs = stage
                .get_svc_processor_mut::<CliprdrClient>()
                .and_then(|c| c.initiate_copy(&formats).ok());
            if let Some(msgs) = svc_msgs {
                if let Ok(frame) = stage.process_svc_processor_messages(msgs) {
                    let _ = Self::write_tls_frame(tls, &frame, &mut self.events);
                }
            }
        }
        std::mem::take(&mut self.events)
    }

    /// Advertise local files (drag-and-drop / file picker) to remote Windows clipboard.
    pub fn advertise_local_files(&mut self, files_json: &str) -> Vec<RdpOutEvent> {
        #[derive(Deserialize)]
        struct LocalFileDesc {
            name: String,
            size: u64,
        }
        let parsed: Vec<LocalFileDesc> = match serde_json::from_str(files_json) {
            Ok(v) => v,
            Err(_) => return std::mem::take(&mut self.events),
        };
        let descriptors: Vec<FileDescriptor> = parsed
            .into_iter()
            .map(|f| FileDescriptor::new(f.name).with_file_size(f.size))
            .collect();
        if descriptors.is_empty() {
            return std::mem::take(&mut self.events);
        }
        if let Phase::Active { tls, stage, .. } = &mut self.phase {
            let svc_msgs = stage
                .get_svc_processor_mut::<CliprdrClient>()
                .and_then(|c| c.initiate_file_copy(descriptors).ok());
            if let Some(msgs) = svc_msgs {
                if let Ok(frame) = stage.process_svc_processor_messages(msgs) {
                    let _ = Self::write_tls_frame(tls, &frame, &mut self.events);
                }
            }
        }
        std::mem::take(&mut self.events)
    }

    /// Respond to a remote FileContentsRequest (SIZE or RANGE) from browser File bytes.
    pub fn respond_local_file_chunk(
        &mut self,
        stream_id: u32,
        is_size: bool,
        file_size: u64,
        chunk: &[u8],
        is_error: bool,
    ) -> Vec<RdpOutEvent> {
        if let Phase::Active { tls, stage, .. } = &mut self.phase {
            let resp = if is_error {
                FileContentsResponse::new_error(stream_id)
            } else if is_size {
                FileContentsResponse::new_size_response(stream_id, file_size)
            } else {
                FileContentsResponse::new_data_response(stream_id, chunk.to_vec())
            };
            let svc_msgs = stage
                .get_svc_processor_mut::<CliprdrClient>()
                .and_then(|c| c.submit_file_contents(resp).ok());
            if let Some(msgs) = svc_msgs {
                if let Ok(frame) = stage.process_svc_processor_messages(msgs) {
                    let _ = Self::write_tls_frame(tls, &frame, &mut self.events);
                }
            }
        }
        std::mem::take(&mut self.events)
    }

    /// Request a chunk of a remote clipboard file (MS-RDPECLIP FileContentsRequest RANGE).
    pub fn request_remote_file_range(
        &mut self,
        file_index: i32,
        offset: u64,
        length: u32,
        clip_data_id: Option<u32>,
    ) -> (u32, Vec<RdpOutEvent>) {
        let stream_id = self.next_stream_id;
        self.next_stream_id = self.next_stream_id.wrapping_add(1).max(1);

        if let Phase::Active { tls, stage, .. } = &mut self.phase {
            let req = FileContentsRequest {
                stream_id,
                index: file_index,
                flags: FileContentsFlags::RANGE,
                position: offset,
                requested_size: length,
                data_id: clip_data_id,
            };
            let svc_msgs = stage
                .get_svc_processor_mut::<CliprdrClient>()
                .and_then(|c| c.request_file_contents(req).ok());
            if let Some(msgs) = svc_msgs {
                if let Ok(frame) = stage.process_svc_processor_messages(msgs) {
                    let _ = Self::write_tls_frame(tls, &frame, &mut self.events);
                }
            }
        }
        (stream_id, std::mem::take(&mut self.events))
    }

    pub fn request_resize(&mut self, width: u32, height: u32) -> Vec<RdpOutEvent> {
        let (adj_w, adj_h) = MonitorLayoutEntry::adjust_display_size(width, height);
        if let Phase::Active { tls, stage, .. } = &mut self.phase {
            if let Some(Ok(frame)) = stage.encode_resize(adj_w, adj_h, Some(100), None) {
                let _ = Self::write_tls_frame(tls, &frame, &mut self.events);
            }
        }
        std::mem::take(&mut self.events)
    }

    pub fn set_audio_enabled(&mut self, enabled: bool) {
        if let Ok(mut st) = self.audio.lock() {
            st.enabled = enabled;
            if !enabled {
                st.pending_chunks.clear();
            }
        }
    }

    pub fn vdrive_put_file(&mut self, name: &str, data: Vec<u8>) -> Vec<RdpOutEvent> {
        if let Ok(mut st) = self.vdrive.lock() {
            st.put_file(name, data);
        }
        self.flush_side_channels();
        std::mem::take(&mut self.events)
    }

    pub fn vdrive_get_file(&self, name: &str) -> Option<Vec<u8>> {
        self.vdrive.lock().ok().and_then(|st| st.get_file(name))
    }

    pub fn vdrive_delete_file(&mut self, name: &str) -> Vec<RdpOutEvent> {
        if let Ok(mut st) = self.vdrive.lock() {
            st.delete_file(name);
        }
        self.flush_side_channels();
        std::mem::take(&mut self.events)
    }

    pub fn vdrive_list_json(&self) -> String {
        let files = self
            .vdrive
            .lock()
            .map(|st| st.list_files())
            .unwrap_or_default();
        serde_json::to_string(&files).unwrap_or_else(|_| "[]".to_string())
    }

    fn send_fastpath_events(&mut self, events: &[FastPathInputEvent]) {
        if let Phase::Active { tls, stage, image } = &mut self.phase {
            if let Ok(outputs) = stage.process_fastpath_input(image, events) {
                for out in outputs {
                    match out {
                        ActiveStageOutput::ResponseFrame(frame) => {
                            let _ = Self::write_tls_frame(tls, &frame, &mut self.events);
                        }
                        ActiveStageOutput::GraphicsUpdate(rect) => {
                            self.events.push(extract_rect_event(image, rect));
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    fn write_tls_frame(
        tls: &mut SansIoTls,
        frame: &[u8],
        events: &mut Vec<RdpOutEvent>,
    ) -> Result<(), String> {
        if frame.is_empty() {
            return Ok(());
        }
        tls.write_plaintext(frame)?;
        let ct = tls.drain_ciphertext()?;
        if !ct.is_empty() {
            events.push(RdpOutEvent::TcpSend(ct));
        }
        Ok(())
    }

    fn ingest_tcp(&mut self, data: &[u8]) -> Result<(), String> {
        match &mut self.phase {
            Phase::PreTls { .. } => {
                self.rx_plain.extend_from_slice(data);
                self.drive()
            }
            Phase::TlsHandshaking { tls, .. } => {
                let plain = tls.feed_ciphertext(data)?;
                let ct = tls.drain_ciphertext()?;
                if !ct.is_empty() {
                    self.events.push(RdpOutEvent::TcpSend(ct));
                }
                if !plain.is_empty() {
                    self.rx_plain.extend_from_slice(&plain);
                }
                if !tls.is_handshaking() {
                    self.on_tls_handshake_complete()?;
                }
                Ok(())
            }
            Phase::AwaitTlsApproval { tls, .. } => {
                let plain = tls.feed_ciphertext(data)?;
                if !plain.is_empty() {
                    self.rx_plain.extend_from_slice(&plain);
                }
                Ok(())
            }
            Phase::Credssp { tls, .. }
            | Phase::PostTls { tls, .. }
            | Phase::Active { tls, .. } => {
                let plain = tls.feed_ciphertext(data)?;
                let ct = tls.drain_ciphertext()?;
                if !ct.is_empty() {
                    self.events.push(RdpOutEvent::TcpSend(ct));
                }
                if !plain.is_empty() {
                    self.rx_plain.extend_from_slice(&plain);
                }
                self.drive()
            }
            Phase::Closed => Ok(()),
        }
    }

    fn on_tls_handshake_complete(&mut self) -> Result<(), String> {
        let phase = std::mem::replace(&mut self.phase, Phase::Closed);
        let Phase::TlsHandshaking { connector, tls } = phase else {
            self.phase = phase;
            return Ok(());
        };
        let cert = tls.peer_cert_info().unwrap_or(PeerCertInfo {
            subject: "CN=Unknown".to_string(),
            issuer: "Unknown".to_string(),
            fingerprint_sha256: "UNKNOWN".to_string(),
            server_public_key: Vec::new(),
        });
        let trusted_match = self
            .opts
            .trusted_fingerprint
            .as_deref()
            .map(|fp| fp.eq_ignore_ascii_case(&cert.fingerprint_sha256))
            .unwrap_or(false);

        if trusted_match {
            self.phase = Phase::PostTls { connector, tls };
            self.after_tls_approved(cert)
        } else {
            let protocol = tls.protocol_label();
            self.events.push(RdpOutEvent::TlsVerify {
                subject: cert.subject.clone(),
                issuer: cert.issuer.clone(),
                fingerprint: cert.fingerprint_sha256.clone(),
                protocol,
            });
            self.phase = Phase::AwaitTlsApproval {
                connector,
                tls,
                cert,
            };
            Ok(())
        }
    }

    fn after_tls_approved(&mut self, cert: PeerCertInfo) -> Result<(), String> {
        let phase = std::mem::replace(&mut self.phase, Phase::Closed);
        let Phase::PostTls { mut connector, mut tls } = phase else {
            self.phase = phase;
            return Ok(());
        };

        connector.mark_security_upgrade_as_done();

        if connector.should_perform_credssp() {
            if cert.server_public_key.is_empty() {
                return Err("未能从服务器证书提取公钥，无法完成 NLA / CredSSP 认证".to_string());
            }
            let selected = match &connector.state {
                ironrdp_connector::ClientConnectorState::Credssp { selected_protocol } => {
                    *selected_protocol
                }
                _ => ironrdp_pdu::nego::SecurityProtocol::HYBRID,
            };
            self.events.push(RdpOutEvent::State {
                status: "authenticating".to_string(),
                detail: "正在进行 CredSSP / NLA (NTLMv2) 身份认证…".to_string(),
            });
            let (mut seq, initial_req) = CredsspSequence::init(
                connector.config.credentials.clone(),
                connector.config.domain.as_deref(),
                selected,
                ServerName::new(self.opts.host.clone()),
                cert.server_public_key,
                None,
            )
            .map_err(|e| format!("CredSSP 初始化失败: {e}"))?;

            let mut buf = WriteBuf::new();
            let state = {
                let mut gen = seq.process_ts_request(initial_req);
                match gen.start() {
                    ironrdp_connector::sspi::generator::GeneratorState::Completed(res) => {
                        res.map_err(|e| format!("CredSSP NTLM 初始化失败: {e}"))?
                    }
                    ironrdp_connector::sspi::generator::GeneratorState::Suspended(_) => {
                        return Err("不支持依赖外部 KDC 网络请求的 Kerberos 模式，请使用 NTLM 凭据".to_string());
                    }
                }
            };
            seq.handle_process_result(state, &mut buf)
                .map_err(|e| format!("CredSSP 编码失败: {e}"))?;
            Self::write_tls_frame(&mut tls, buf.filled(), &mut self.events)?;

            self.phase = Phase::Credssp {
                connector,
                tls,
                credssp: Box::new(seq),
            };
            self.drive()
        } else {
            self.events.push(RdpOutEvent::State {
                status: "negotiating".to_string(),
                detail: "TLS 握手完成，正在协商 RDP 通道与桌面参数…".to_string(),
            });
            self.phase = Phase::PostTls { connector, tls };
            self.drive()
        }
    }

    fn drive(&mut self) -> Result<(), String> {
        loop {
            match &mut self.phase {
                Phase::PreTls { connector } => {
                    if connector.should_perform_security_upgrade() {
                        let phase = std::mem::replace(&mut self.phase, Phase::Closed);
                        let Phase::PreTls { connector } = phase else {
                            unreachable!()
                        };
                        let mut tls = SansIoTls::new(&self.opts.host)?;
                        let ct = tls.drain_ciphertext()?;
                        if !ct.is_empty() {
                            self.events.push(RdpOutEvent::TcpSend(ct));
                        }
                        self.events.push(RdpOutEvent::State {
                            status: "tls".to_string(),
                            detail: "正在建立纯 Rust TLS 加密隧道…".to_string(),
                        });
                        self.phase = Phase::TlsHandshaking {
                            connector,
                            tls: Box::new(tls),
                        };
                        return Ok(());
                    }

                    let mut out = WriteBuf::new();
                    if let Some(hint) = connector.next_pdu_hint() {
                        match hint
                            .find_size(&self.rx_plain)
                            .map_err(|e| format!("X.224 帧解析错误: {e}"))?
                        {
                            Some((_matched, size)) if self.rx_plain.len() >= size => {
                                let pdu: Vec<u8> = self.rx_plain.drain(..size).collect();
                                connector
                                    .step(&pdu, None, &mut out)
                                    .map_err(|e| format!("RDP 协商失败: {e}"))?;
                            }
                            _ => return Ok(()),
                        }
                    } else {
                        connector
                            .step_no_input(&mut out)
                            .map_err(|e| format!("RDP 建连请求失败: {e}"))?;
                    }
                    if !out.filled().is_empty() {
                        self.events.push(RdpOutEvent::TcpSend(out.filled().to_vec()));
                    }
                }
                Phase::Credssp {
                    connector,
                    tls,
                    credssp,
                } => {
                    let Some(hint) = credssp.next_pdu_hint() else {
                        connector.mark_credssp_as_done();
                        let phase = std::mem::replace(&mut self.phase, Phase::Closed);
                        if let Phase::Credssp { connector, tls, .. } = phase {
                            self.events.push(RdpOutEvent::State {
                                status: "negotiating".to_string(),
                                detail: "身份认证通过，正在初始化远程桌面会话…".to_string(),
                            });
                            self.phase = Phase::PostTls { connector, tls };
                            continue;
                        }
                        return Ok(());
                    };
                    match hint
                        .find_size(&self.rx_plain)
                        .map_err(|e| format!("CredSSP 帧解析失败: {e}"))?
                    {
                        Some((_matched, size)) if self.rx_plain.len() >= size => {
                            let pdu: Vec<u8> = self.rx_plain.drain(..size).collect();
                            let ts_req_opt = credssp
                                .decode_server_message(&pdu)
                                .map_err(|e| format!("CredSSP 认证被拒绝或用户名/密码错误: {e}"))?;
                            if let Some(ts_req) = ts_req_opt {
                                let state = {
                                    let mut gen = credssp.process_ts_request(ts_req);
                                    match gen.start() {
                                        ironrdp_connector::sspi::generator::GeneratorState::Completed(r) => {
                                            r.map_err(|e| format!("NTLM 认证失败: {e}"))?
                                        }
                                        ironrdp_connector::sspi::generator::GeneratorState::Suspended(_) => {
                                            return Err("CredSSP 请求了不支持的外部网络调用".to_string());
                                        }
                                    }
                                };
                                let mut out = WriteBuf::new();
                                credssp
                                    .handle_process_result(state, &mut out)
                                    .map_err(|e| format!("CredSSP 响应编码失败: {e}"))?;
                                Self::write_tls_frame(tls, out.filled(), &mut self.events)?;
                            }
                        }
                        _ => return Ok(()),
                    }
                }
                Phase::PostTls { connector, tls } => {
                    if connector.state.is_terminal() {
                        let phase = std::mem::replace(&mut self.phase, Phase::Closed);
                        let Phase::PostTls {
                            mut connector,
                            tls,
                        } = phase
                        else {
                            unreachable!()
                        };
                        let outcome = connector
                            .state
                            .take_outcome()
                            .ok_or_else(|| "连接器未返回会话结果".to_string())?;
                        let res = outcome
                            .into_connected()
                            .map_err(|e| format!("RDP 会话未就绪: {e}"))?;

                        let width = res.desktop_size.width;
                        let height = res.desktop_size.height;
                        let tls_info = tls.protocol_label();

                        let stage = ActiveStageBuilder {
                            static_channels: res.static_channels,
                            user_channel_id: res.user_channel_id,
                            io_channel_id: res.io_channel_id,
                            message_channel_id: res.message_channel_id,
                            share_id: res.share_id,
                            compression_type: res.compression_type,
                            enable_server_pointer: res.enable_server_pointer,
                            pointer_software_rendering: res.pointer_software_rendering,
                        }
                        .build();

                        let image = DecodedImage::new(PixelFormat::RgbA32, width, height);
                        self.events.push(RdpOutEvent::Connected {
                            width,
                            height,
                            tls_info,
                        });
                        self.phase = Phase::Active {
                            tls,
                            stage: Box::new(stage),
                            image: Box::new(image),
                        };
                        continue;
                    }

                    if connector.should_perform_multitransport() {
                        let mut out = WriteBuf::new();
                        connector
                            .skip_multitransport(&mut out)
                            .map_err(|e| format!("跳过 UDP 多传输失败: {e}"))?;
                        Self::write_tls_frame(tls, out.filled(), &mut self.events)?;
                        continue;
                    }

                    let mut out = WriteBuf::new();
                    if let Some(hint) = connector.next_pdu_hint() {
                        match hint
                            .find_size(&self.rx_plain)
                            .map_err(|e| format!("RDP 握手帧解析错误: {e}"))?
                        {
                            Some((_matched, size)) if self.rx_plain.len() >= size => {
                                let pdu: Vec<u8> = self.rx_plain.drain(..size).collect();
                                connector
                                    .step(&pdu, None, &mut out)
                                    .map_err(|e| format!("RDP 握手失败: {e}"))?;
                            }
                            _ => return Ok(()),
                        }
                    } else {
                        connector
                            .step_no_input(&mut out)
                            .map_err(|e| format!("RDP 握手步骤失败: {e}"))?;
                    }
                    Self::write_tls_frame(tls, out.filled(), &mut self.events)?;
                }
                Phase::Active { tls, stage, image } => {
                    let info = match ironrdp_pdu::find_size(&self.rx_plain)
                        .map_err(|e| format!("RDP 会话帧头解析失败: {e}"))?
                    {
                        Some(i) if self.rx_plain.len() >= i.length => i,
                        _ => {
                            self.flush_side_channels();
                            return Ok(());
                        }
                    };

                    let frame: Vec<u8> = self.rx_plain.drain(..info.length).collect();
                    let outputs = stage
                        .process(image, info.action, &frame, None)
                        .map_err(|e| format!("RDP 帧处理异常: {e}"))?;

                    let mut terminate_msg: Option<String> = None;
                    for out in outputs {
                        match out {
                            ActiveStageOutput::ResponseFrame(resp) => {
                                Self::write_tls_frame(tls, &resp, &mut self.events)?;
                            }
                            ActiveStageOutput::GraphicsUpdate(rect) => {
                                self.events.push(extract_rect_event(image, rect));
                            }
                            ActiveStageOutput::DeactivateAll => {
                                // Note: full reactivation resize could be handled here
                                self.events.push(RdpOutEvent::Resize {
                                    width: image.width(),
                                    height: image.height(),
                                });
                            }
                            ActiveStageOutput::Terminate(reason) => {
                                terminate_msg = Some(format!("远端主动断开会话: {reason:?}"));
                            }
                            _ => {}
                        }
                    }

                    // Drain pending clipboard actions (like FormatDataRequest reply or auto-paste)
                    let pending_clip = self
                        .clip
                        .lock()
                        .map(|mut st| std::mem::take(&mut st.pending_actions))
                        .unwrap_or_default();
                    for act in pending_clip {
                        match act {
                            ClipPendingAction::RequestFormat(fmt_id) => {
                                if let Some(Ok(msgs)) = stage
                                    .get_svc_processor_mut::<CliprdrClient>()
                                    .map(|c| c.initiate_paste(fmt_id))
                                {
                                    if let Ok(resp) = stage.process_svc_processor_messages(msgs) {
                                        Self::write_tls_frame(tls, &resp, &mut self.events)?;
                                    }
                                }
                            }
                            ClipPendingAction::SendLocalText(fmt_id) => {
                                let local_text = self
                                    .clip
                                    .lock()
                                    .map(|st| st.local_text.clone())
                                    .unwrap_or_default();
                                let resp_pdu = if fmt_id == ClipboardFormatId::CF_UNICODETEXT {
                                    OwnedFormatDataResponse::new_data(encode_utf16le_nul(&local_text))
                                } else if fmt_id == ClipboardFormatId::CF_TEXT {
                                    let mut bytes = local_text.into_bytes();
                                    bytes.push(0);
                                    OwnedFormatDataResponse::new_data(bytes)
                                } else {
                                    OwnedFormatDataResponse::new_error()
                                };
                                if let Some(Ok(msgs)) = stage
                                    .get_svc_processor_mut::<CliprdrClient>()
                                    .map(|c| c.submit_format_data(resp_pdu))
                                {
                                    if let Ok(resp) = stage.process_svc_processor_messages(msgs) {
                                        Self::write_tls_frame(tls, &resp, &mut self.events)?;
                                    }
                                }
                            }
                            ClipPendingAction::SendEmptyFormatList => {
                                if let Some(Ok(msgs)) = stage
                                    .get_svc_processor_mut::<CliprdrClient>()
                                    .map(|c| c.initiate_copy(&[]))
                                {
                                    if let Ok(resp) = stage.process_svc_processor_messages(msgs) {
                                        Self::write_tls_frame(tls, &resp, &mut self.events)?;
                                    }
                                }
                            }
                        }
                    }

                    self.flush_side_channels();

                    if let Some(msg) = terminate_msg {
                        self.phase = Phase::Closed;
                        self.events.push(RdpOutEvent::Disconnected(msg));
                        return Ok(());
                    }
                }
                Phase::TlsHandshaking { .. } | Phase::AwaitTlsApproval { .. } | Phase::Closed => {
                    return Ok(());
                }
            }
        }
    }

    fn flush_side_channels(&mut self) {
        if let Ok(mut st) = self.audio.lock() {
            let label = st
                .active_format
                .clone()
                .unwrap_or_else(|| "PCM 44.1kHz · 16-bit Stereo".to_string());
            for chunk in st.pending_chunks.drain(..) {
                self.events.push(RdpOutEvent::AudioPcm {
                    sample_rate: chunk.sample_rate,
                    channels: chunk.channels,
                    bits_per_sample: chunk.bits_per_sample,
                    format_label: label.clone(),
                    data: chunk.data,
                });
            }
        }

        if let Ok(mut st) = self.clip.lock() {
            for ev in st.events.drain(..) {
                match ev {
                    ClipEvent::Ready => {}
                    ClipEvent::RemoteText(t) => self.events.push(RdpOutEvent::ClipText(t)),
                    ClipEvent::RemoteFiles {
                        files,
                        clip_data_id,
                    } => {
                        let json = serde_json::to_string(&files).unwrap_or_else(|_| "[]".to_string());
                        self.events.push(RdpOutEvent::ClipFiles {
                            files_json: json,
                            clip_data_id,
                        });
                    }
                    ClipEvent::FileContentsChunk {
                        stream_id,
                        data,
                        is_error,
                    } => {
                        self.events.push(RdpOutEvent::ClipFileChunk {
                            stream_id,
                            data,
                            is_error,
                        });
                    }
                    ClipEvent::RemoteFileRequest {
                        stream_id,
                        file_index,
                        is_size,
                        offset,
                        length,
                        ..
                    } => {
                        self.events.push(RdpOutEvent::ClipFileUploadReq {
                            stream_id,
                            file_index,
                            is_size,
                            offset,
                            length,
                        });
                    }
                }
            }
        }

        if let Ok(mut st) = self.vdrive.lock() {
            if st.dirty_notify {
                st.dirty_notify = false;
                let files_json =
                    serde_json::to_string(&st.list_files()).unwrap_or_else(|_| "[]".to_string());
                self.events.push(RdpOutEvent::VDriveState {
                    mounted: st.mounted,
                    files_json,
                });
            }
        }
    }

    fn fail(&mut self, msg: String) {
        self.phase = Phase::Closed;
        self.events.push(RdpOutEvent::Error(msg));
    }
}

fn extract_rect_event(
    image: &DecodedImage,
    rect: ironrdp_pdu::geometry::InclusiveRectangle,
) -> RdpOutEvent {
    let img_w = usize::from(image.width());
    let img_h = usize::from(image.height());
    let x0 = usize::from(rect.left).min(img_w.saturating_sub(1));
    let y0 = usize::from(rect.top).min(img_h.saturating_sub(1));
    let x1 = usize::from(rect.right).min(img_w.saturating_sub(1));
    let y1 = usize::from(rect.bottom).min(img_h.saturating_sub(1));
    let w = x1.saturating_sub(x0) + 1;
    let h = y1.saturating_sub(y0) + 1;
    let stride = img_w * 4;
    let src = image.data();
    let mut rgba = Vec::with_capacity(w * h * 4);
    for row in y0..=y1 {
        let start = row * stride + x0 * 4;
        let end = start + w * 4;
        if end <= src.len() {
            rgba.extend_from_slice(&src[start..end]);
        }
    }
    RdpOutEvent::FrameRect {
        x: x0 as u16,
        y: y0 as u16,
        w: w as u16,
        h: h as u16,
        rgba,
    }
}

// =========================================================================
// wasm-bindgen JS Bridge
// =========================================================================

fn events_to_js(events: Vec<RdpOutEvent>) -> Array {
    let arr = Array::new();
    for ev in events {
        let obj = Object::new();
        let set = |k: &str, v: JsValue| {
            let _ = Reflect::set(&obj, &JsValue::from_str(k), &v);
        };
        match ev {
            RdpOutEvent::TcpSend(bytes) => {
                set("type", JsValue::from_str("tcp_send"));
                set("data", Uint8Array::from(bytes.as_slice()).into());
            }
            RdpOutEvent::State { status, detail } => {
                set("type", JsValue::from_str("state"));
                set("status", JsValue::from_str(&status));
                set("detail", JsValue::from_str(&detail));
            }
            RdpOutEvent::TlsVerify {
                subject,
                issuer,
                fingerprint,
                protocol,
            } => {
                set("type", JsValue::from_str("tls_verify"));
                set("subject", JsValue::from_str(&subject));
                set("issuer", JsValue::from_str(&issuer));
                set("fingerprint", JsValue::from_str(&fingerprint));
                set("protocol", JsValue::from_str(&protocol));
            }
            RdpOutEvent::Connected {
                width,
                height,
                tls_info,
            } => {
                set("type", JsValue::from_str("connected"));
                set("width", JsValue::from_f64(f64::from(width)));
                set("height", JsValue::from_f64(f64::from(height)));
                set("tls_info", JsValue::from_str(&tls_info));
            }
            RdpOutEvent::FrameRect { x, y, w, h, rgba } => {
                set("type", JsValue::from_str("frame_rect"));
                set("x", JsValue::from_f64(f64::from(x)));
                set("y", JsValue::from_f64(f64::from(y)));
                set("w", JsValue::from_f64(f64::from(w)));
                set("h", JsValue::from_f64(f64::from(h)));
                set("rgba", Uint8Array::from(rgba.as_slice()).into());
            }
            RdpOutEvent::Resize { width, height } => {
                set("type", JsValue::from_str("resize"));
                set("width", JsValue::from_f64(f64::from(width)));
                set("height", JsValue::from_f64(f64::from(height)));
            }
            RdpOutEvent::AudioPcm {
                sample_rate,
                channels,
                bits_per_sample,
                format_label,
                data,
            } => {
                set("type", JsValue::from_str("audio_pcm"));
                set("sample_rate", JsValue::from_f64(f64::from(sample_rate)));
                set("channels", JsValue::from_f64(f64::from(channels)));
                set("bits_per_sample", JsValue::from_f64(f64::from(bits_per_sample)));
                set("format_label", JsValue::from_str(&format_label));
                set("data", Uint8Array::from(data.as_slice()).into());
            }
            RdpOutEvent::ClipText(text) => {
                set("type", JsValue::from_str("clip_text"));
                set("text", JsValue::from_str(&text));
            }
            RdpOutEvent::ClipFiles {
                files_json,
                clip_data_id,
            } => {
                set("type", JsValue::from_str("clip_files"));
                set("files_json", JsValue::from_str(&files_json));
                if let Some(id) = clip_data_id {
                    set("clip_data_id", JsValue::from_f64(f64::from(id)));
                }
            }
            RdpOutEvent::ClipFileChunk {
                stream_id,
                data,
                is_error,
            } => {
                set("type", JsValue::from_str("clip_file_chunk"));
                set("stream_id", JsValue::from_f64(f64::from(stream_id)));
                set("is_error", JsValue::from_bool(is_error));
                set("data", Uint8Array::from(data.as_slice()).into());
            }
            RdpOutEvent::ClipFileUploadReq {
                stream_id,
                file_index,
                is_size,
                offset,
                length,
            } => {
                set("type", JsValue::from_str("clip_file_upload_req"));
                set("stream_id", JsValue::from_f64(f64::from(stream_id)));
                set("file_index", JsValue::from_f64(f64::from(file_index)));
                set("is_size", JsValue::from_bool(is_size));
                set("offset", JsValue::from_f64(offset as f64));
                set("length", JsValue::from_f64(f64::from(length)));
            }
            RdpOutEvent::VDriveState {
                mounted,
                files_json,
            } => {
                set("type", JsValue::from_str("vdrive_state"));
                set("mounted", JsValue::from_bool(mounted));
                set("files_json", JsValue::from_str(&files_json));
            }
            RdpOutEvent::Disconnected(reason) => {
                set("type", JsValue::from_str("disconnected"));
                set("reason", JsValue::from_str(&reason));
            }
            RdpOutEvent::Error(msg) => {
                set("type", JsValue::from_str("error"));
                set("message", JsValue::from_str(&msg));
            }
        }
        arr.push(&obj);
    }
    arr
}

#[wasm_bindgen]
pub struct RdpWasmClient {
    core: RdpCore,
}

#[wasm_bindgen]
impl RdpWasmClient {
    #[wasm_bindgen(constructor)]
    pub fn new(options_json: &str) -> Result<RdpWasmClient, JsValue> {
        let opts: RdpConnectOptions = serde_json::from_str(options_json)
            .map_err(|e| JsValue::from_str(&format!("Invalid RDP options: {e}")))?;
        Ok(Self {
            core: RdpCore::new(opts),
        })
    }

    pub fn start(&mut self) -> Array {
        events_to_js(self.core.start())
    }

    pub fn on_tcp_data(&mut self, data: &[u8]) -> Array {
        events_to_js(self.core.on_tcp_data(data))
    }

    pub fn approve_tls(&mut self, trusted: bool) -> Array {
        events_to_js(self.core.approve_tls(trusted))
    }

    pub fn send_mouse(&mut self, x: u16, y: u16, flags: u16) -> Array {
        events_to_js(self.core.send_mouse(x, y, flags))
    }

    pub fn send_wheel(&mut self, x: u16, y: u16, delta: i16, horizontal: bool) -> Array {
        events_to_js(self.core.send_wheel(x, y, delta, horizontal))
    }

    pub fn send_scancode(&mut self, scancode: u8, extended: bool, pressed: bool) -> Array {
        events_to_js(self.core.send_scancode(scancode, extended, pressed))
    }

    pub fn send_unicode_text(&mut self, text: &str) -> Array {
        events_to_js(self.core.send_unicode_text(text))
    }

    pub fn send_clipboard_text(&mut self, text: &str) -> Array {
        events_to_js(self.core.send_clipboard_text(text.to_string()))
    }

    pub fn advertise_local_files(&mut self, files_json: &str) -> Array {
        events_to_js(self.core.advertise_local_files(files_json))
    }

    pub fn respond_local_file_chunk(
        &mut self,
        stream_id: u32,
        is_size: bool,
        file_size: f64,
        chunk: &[u8],
        is_error: bool,
    ) -> Array {
        events_to_js(self.core.respond_local_file_chunk(
            stream_id,
            is_size,
            file_size as u64,
            chunk,
            is_error,
        ))
    }

    pub fn request_remote_file_range(
        &mut self,
        file_index: i32,
        offset: f64,
        length: u32,
        clip_data_id: Option<u32>,
    ) -> JsValue {
        let (stream_id, evs) = self.core.request_remote_file_range(
            file_index,
            offset as u64,
            length,
            clip_data_id,
        );
        let res = Object::new();
        let _ = Reflect::set(
            &res,
            &JsValue::from_str("stream_id"),
            &JsValue::from_f64(f64::from(stream_id)),
        );
        let _ = Reflect::set(&res, &JsValue::from_str("events"), &events_to_js(evs));
        res.into()
    }

    pub fn request_resize(&mut self, width: u32, height: u32) -> Array {
        events_to_js(self.core.request_resize(width, height))
    }

    pub fn set_audio_enabled(&mut self, enabled: bool) {
        self.core.set_audio_enabled(enabled);
    }

    pub fn vdrive_put_file(&mut self, name: &str, data: &[u8]) -> Array {
        events_to_js(self.core.vdrive_put_file(name, data.to_vec()))
    }

    pub fn vdrive_get_file(&self, name: &str) -> Option<Uint8Array> {
        self.core
            .vdrive_get_file(name)
            .map(|bytes| Uint8Array::from(bytes.as_slice()))
    }

    pub fn vdrive_delete_file(&mut self, name: &str) -> Array {
        events_to_js(self.core.vdrive_delete_file(name))
    }

    pub fn vdrive_list_json(&self) -> String {
        self.core.vdrive_list_json()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpStream;
    use std::time::Duration;

    #[test]
    fn live_xrdp_localhost_handshake_and_frame() {
        let Ok(mut stream) = TcpStream::connect("127.0.0.1:3389") else {
            eprintln!("Skipping localhost xrdp test (port 3389 not open)");
            return;
        };
        let _ = stream.set_read_timeout(Some(Duration::from_secs(4)));
        let _ = stream.set_write_timeout(Some(Duration::from_secs(4)));

        let mut core = RdpCore::new(RdpConnectOptions {
            host: "127.0.0.1".to_string(),
            username: "".to_string(),
            password: "".to_string(),
            domain: "".to_string(),
            width: 1024,
            height: 768,
            enable_audio: true,
            enable_vdrive: true,
            enable_nla: false,
            trusted_fingerprint: None,
        });

        let mut pending = core.start();
        let mut saw_tls_verify = false;
        let mut saw_connected = false;
        let mut frame_rects = 0usize;
        let mut buf = [0u8; 32768];

        for _step in 0..80 {
            let mut to_approve = false;
            for ev in pending.drain(..) {
                match ev {
                    RdpOutEvent::TcpSend(bytes) => {
                        stream.write_all(&bytes).expect("tcp write");
                    }
                    RdpOutEvent::TlsVerify {
                        subject,
                        fingerprint,
                        protocol,
                        ..
                    } => {
                        eprintln!("TLS Verify: subject={subject} fp={fingerprint} proto={protocol}");
                        saw_tls_verify = true;
                        to_approve = true;
                    }
                    RdpOutEvent::Connected {
                        width,
                        height,
                        tls_info,
                    } => {
                        eprintln!("RDP Connected! {width}x{height} over {tls_info}");
                        saw_connected = true;
                    }
                    RdpOutEvent::FrameRect { x, y, w, h, .. } => {
                        frame_rects += 1;
                        if frame_rects <= 3 {
                            eprintln!("FrameRect #{frame_rects}: ({x},{y}) {w}x{h}");
                        }
                    }
                    RdpOutEvent::Error(e) => panic!("RDP error: {e}"),
                    RdpOutEvent::Disconnected(r) => {
                        eprintln!("RDP disconnected: {r}");
                        break;
                    }
                    _ => {}
                }
            }
            if to_approve {
                pending = core.approve_tls(true);
                continue;
            }
            if saw_connected && frame_rects > 0 {
                break;
            }
            match stream.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    pending = core.on_tcp_data(&buf[..n]);
                }
                Err(e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut =>
                {
                    break;
                }
                Err(e) => panic!("TCP read error: {e}"),
            }
        }

        assert!(saw_tls_verify, "expected TLS certificate verification prompt");
        assert!(saw_connected, "expected RDP ActiveStage connected");
        assert!(frame_rects > 0, "expected at least one decoded desktop FrameRect from xrdp");
    }
}
