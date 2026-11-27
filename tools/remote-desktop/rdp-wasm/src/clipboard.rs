use std::sync::{Arc, Mutex};

use ironrdp_cliprdr::backend::CliprdrBackend;
use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags,
    FileContentsFlags, FileContentsRequest, FileContentsResponse, FileDescriptor, FormatDataRequest,
    FormatDataResponse, LockDataId,
};
use ironrdp_core::impl_as_any;
use serde::Serialize;

#[derive(Debug, Clone, Serialize)]
pub struct RemoteClipFile {
    pub index: usize,
    pub name: String,
    pub size: u64,
    pub is_dir: bool,
}

#[derive(Debug, Clone)]
pub enum ClipEvent {
    Ready,
    RemoteText(String),
    RemoteFiles {
        files: Vec<RemoteClipFile>,
        clip_data_id: Option<u32>,
    },
    FileContentsChunk {
        stream_id: u32,
        data: Vec<u8>,
        is_error: bool,
    },
    RemoteFileRequest {
        stream_id: u32,
        file_index: i32,
        is_size: bool,
        offset: u64,
        length: u32,
    },
}

#[derive(Debug, Clone)]
pub enum ClipPendingAction {
    RequestFormat(ClipboardFormatId),
    SendLocalText(ClipboardFormatId),
    SendEmptyFormatList,
}

#[derive(Debug, Default)]
pub struct SharedClipState {
    pub ready: bool,
    pub local_text: String,
    pub remote_text_format: Option<ClipboardFormatId>,
    pub remote_file_format: Option<ClipboardFormatId>,
    pub events: Vec<ClipEvent>,
    pub pending_actions: Vec<ClipPendingAction>,
}

impl SharedClipState {
    pub fn new() -> Arc<Mutex<Self>> {
        Arc::new(Mutex::new(Self::default()))
    }
}

#[derive(Debug)]
pub struct BookStarkCliprdrBackend {
    state: Arc<Mutex<SharedClipState>>,
    negotiated: ClipboardGeneralCapabilityFlags,
}

impl BookStarkCliprdrBackend {
    pub fn new(state: Arc<Mutex<SharedClipState>>) -> Self {
        Self {
            state,
            negotiated: ClipboardGeneralCapabilityFlags::empty(),
        }
    }
}

impl_as_any!(BookStarkCliprdrBackend);

fn now_ms_portable() -> u64 {
    #[cfg(target_arch = "wasm32")]
    {
        js_sys::Date::now() as u64
    }
    #[cfg(not(target_arch = "wasm32"))]
    {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0)
    }
}

impl CliprdrBackend for BookStarkCliprdrBackend {
    fn temporary_directory(&self) -> &str {
        "C:\\Temp\\BookStark"
    }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        ClipboardGeneralCapabilityFlags::USE_LONG_FORMAT_NAMES
            | ClipboardGeneralCapabilityFlags::STREAM_FILECLIP_ENABLED
            | ClipboardGeneralCapabilityFlags::FILECLIP_NO_FILE_PATHS
            | ClipboardGeneralCapabilityFlags::CAN_LOCK_CLIPDATA
            | ClipboardGeneralCapabilityFlags::HUGE_FILE_SUPPORT_ENABLED
    }

    fn on_ready(&mut self) {
        if let Ok(mut st) = self.state.lock() {
            st.ready = true;
            st.events.push(ClipEvent::Ready);
        }
    }

    fn on_request_format_list(&mut self) {
        if let Ok(mut st) = self.state.lock() {
            st.pending_actions.push(ClipPendingAction::SendEmptyFormatList);
        }
    }

    fn on_process_negotiated_capabilities(&mut self, capabilities: ClipboardGeneralCapabilityFlags) {
        self.negotiated = capabilities;
    }

    fn on_remote_copy(&mut self, available_formats: &[ClipboardFormat]) {
        let mut unicode_fmt: Option<ClipboardFormatId> = None;
        let mut ansi_fmt: Option<ClipboardFormatId> = None;
        let mut file_fmt: Option<ClipboardFormatId> = None;

        for fmt in available_formats {
            if fmt.id == ClipboardFormatId::CF_UNICODETEXT {
                unicode_fmt = Some(fmt.id);
            } else if fmt.id == ClipboardFormatId::CF_TEXT {
                ansi_fmt = Some(fmt.id);
            }
            if let Some(name) = &fmt.name {
                if name.value().eq_ignore_ascii_case("FileGroupDescriptorW") {
                    file_fmt = Some(fmt.id);
                }
            }
        }

        if let Ok(mut st) = self.state.lock() {
            st.remote_file_format = file_fmt;
            st.remote_text_format = unicode_fmt.or(ansi_fmt);
            if let Some(fid) = file_fmt {
                st.pending_actions.push(ClipPendingAction::RequestFormat(fid));
            } else if let Some(tid) = unicode_fmt.or(ansi_fmt) {
                st.pending_actions.push(ClipPendingAction::RequestFormat(tid));
            }
        }
    }

    fn on_format_data_request(&mut self, request: FormatDataRequest) {
        if let Ok(mut st) = self.state.lock() {
            st.pending_actions
                .push(ClipPendingAction::SendLocalText(request.format));
        }
    }

    fn on_format_data_response(&mut self, response: FormatDataResponse<'_>) {
        if response.is_error() {
            return;
        }
        let raw = response.data();
        if raw.is_empty() {
            return;
        }
        // Decode UTF-16LE (CF_UNICODETEXT) or fallback UTF-8/ASCII
        let text = if raw.len() >= 2 && raw.len() % 2 == 0 {
            let units: Vec<u16> = raw
                .chunks_exact(2)
                .map(|c| u16::from_le_bytes([c[0], c[1]]))
                .take_while(|&u| u != 0)
                .collect();
            String::from_utf16_lossy(&units)
        } else {
            let trimmed = raw.split(|&b| b == 0).next().unwrap_or(raw);
            String::from_utf8_lossy(trimmed).into_owned()
        };

        if let Ok(mut st) = self.state.lock() {
            st.events.push(ClipEvent::RemoteText(text));
        }
    }

    fn on_file_contents_request(&mut self, request: FileContentsRequest) {
        if let Ok(mut st) = self.state.lock() {
            st.events.push(ClipEvent::RemoteFileRequest {
                stream_id: request.stream_id,
                file_index: request.index,
                is_size: request.flags.contains(FileContentsFlags::SIZE),
                offset: request.position,
                length: request.requested_size,
            });
        }
    }

    fn on_file_contents_response(&mut self, response: FileContentsResponse<'_>) {
        if let Ok(mut st) = self.state.lock() {
            st.events.push(ClipEvent::FileContentsChunk {
                stream_id: response.stream_id(),
                data: response.data().to_vec(),
                is_error: response.is_error(),
            });
        }
    }

    fn on_lock(&mut self, _data_id: LockDataId) {}
    fn on_unlock(&mut self, _data_id: LockDataId) {}

    fn on_remote_file_list(&mut self, files: &[FileDescriptor], clip_data_id: Option<u32>) {
        let mapped: Vec<RemoteClipFile> = files
            .iter()
            .enumerate()
            .map(|(index, fd)| {
                let is_dir = fd
                    .attributes
                    .map(|a| a.bits() & 0x10 != 0)
                    .unwrap_or(false);
                RemoteClipFile {
                    index,
                    name: fd.name.clone(),
                    size: fd.file_size.unwrap_or(0),
                    is_dir,
                }
            })
            .collect();
        if let Ok(mut st) = self.state.lock() {
            st.events.push(ClipEvent::RemoteFiles {
                files: mapped,
                clip_data_id,
            });
        }
    }

    fn now_ms(&self) -> u64 {
        now_ms_portable()
    }
}

pub fn encode_utf16le_nul(text: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity((text.len() + 1) * 2);
    for u in text.encode_utf16() {
        out.extend_from_slice(&u.to_le_bytes());
    }
    out.extend_from_slice(&[0u8, 0u8]);
    out
}
