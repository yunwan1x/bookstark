use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use ironrdp_core::impl_as_any;
use ironrdp_pdu::PduResult;
use ironrdp_rdpdr::backend::RdpdrBackend;
use ironrdp_rdpdr::pdu::efs::{
    Boolean, Characteristics, ClientDriveQueryDirectoryResponse,
    ClientDriveQueryInformationResponse, ClientDriveQueryVolumeInformationResponse,
    ClientDriveSetInformationResponse, CreateDisposition, CreateOptions, DeviceCloseRequest,
    DeviceCloseResponse, DeviceControlRequest, DeviceControlResponse, DeviceCreateRequest,
    DeviceCreateResponse, DeviceFlushBuffersRequest, DeviceFlushBuffersResponse, DeviceIoRequest,
    DeviceIoResponse, DeviceReadRequest, DeviceReadResponse, DeviceWriteRequest,
    DeviceWriteResponse, FileAttributes, FileBasicInformation, FileBothDirectoryInformation,
    FileDirectoryInformation, FileFsAttributeInformation, FileFsDeviceInformation,
    FileFsFullSizeInformation, FileFsSizeInformation, FileFsVolumeInformation,
    FileFullDirectoryInformation, FileInformationClass, FileInformationClassLevel,
    FileNamesInformation, FileStandardInformation, FileSystemAttributes,
    FileSystemInformationClass, FileSystemInformationClassLevel, Information, NtStatus,
    ServerDeviceAnnounceResponse, ServerDriveIoRequest, ServerDriveQueryDirectoryRequest,
    ServerDriveQueryInformationRequest, ServerDriveQueryVolumeInformationRequest,
    ServerDriveSetInformationRequest,
};
use ironrdp_rdpdr::pdu::esc::{ScardCall, ScardIoCtlCode};
use ironrdp_rdpdr::pdu::RdpdrPdu;
use ironrdp_svc::SvcMessage;
use serde::Serialize;

const WINDOWS_EPOCH_DIFF_100NS: i64 = 116_444_736_000_000_000;

fn now_filetime() -> i64 {
    #[cfg(target_arch = "wasm32")]
    let ms = js_sys::Date::now() as i64;
    #[cfg(not(target_arch = "wasm32"))]
    let ms = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0);
    WINDOWS_EPOCH_DIFF_100NS + ms * 10_000
}

#[derive(Debug, Clone, Serialize)]
pub struct VDriveFileMeta {
    pub name: String,
    pub size: usize,
    pub updated_ms: u64,
}

#[derive(Debug, Clone)]
struct VDriveEntry {
    data: Vec<u8>,
    created_ft: i64,
    modified_ft: i64,
    updated_ms: u64,
}

#[derive(Debug, Clone)]
struct OpenHandle {
    path: String, // "" for root dir, or sanitized file name
    is_dir: bool,
    delete_on_close: bool,
    dir_cursor: usize,
    dir_pattern: Option<String>,
    modified: bool,
}

#[derive(Debug, Default)]
pub struct SharedVDrive {
    files: BTreeMap<String, VDriveEntry>,
    handles: BTreeMap<u32, OpenHandle>,
    next_file_id: u32,
    pub dirty_notify: bool,
    pub mounted: bool,
}

impl SharedVDrive {
    pub fn new() -> Arc<Mutex<Self>> {
        let mut st = Self {
            files: BTreeMap::new(),
            handles: BTreeMap::new(),
            next_file_id: 1,
            dirty_notify: false,
            mounted: false,
        };
        let ft = now_filetime();
        let ms = now_ms();
        let readme = b"BookStark Virtual Shared Drive (\\\\tsclient\\BookStark)\r\n\
                       Drop files in the browser File Transfer drawer or save files here from Windows.\r\n";
        st.files.insert(
            "README-BookStark.txt".to_string(),
            VDriveEntry {
                data: readme.to_vec(),
                created_ft: ft,
                modified_ft: ft,
                updated_ms: ms,
            },
        );
        Arc::new(Mutex::new(st))
    }

    pub fn put_file(&mut self, name: &str, data: Vec<u8>) {
        let clean = sanitize_name(name);
        if clean.is_empty() {
            return;
        }
        let ft = now_filetime();
        self.files.insert(
            clean,
            VDriveEntry {
                data,
                created_ft: ft,
                modified_ft: ft,
                updated_ms: now_ms(),
            },
        );
        self.dirty_notify = true;
    }

    pub fn get_file(&self, name: &str) -> Option<Vec<u8>> {
        let clean = sanitize_name(name);
        self.files.get(&clean).map(|e| e.data.clone())
    }

    pub fn delete_file(&mut self, name: &str) -> bool {
        let clean = sanitize_name(name);
        let removed = self.files.remove(&clean).is_some();
        if removed {
            self.dirty_notify = true;
        }
        removed
    }

    pub fn list_files(&self) -> Vec<VDriveFileMeta> {
        self.files
            .iter()
            .map(|(name, e)| VDriveFileMeta {
                name: name.clone(),
                size: e.data.len(),
                updated_ms: e.updated_ms,
            })
            .collect()
    }

    fn alloc_id(&mut self) -> u32 {
        let id = self.next_file_id;
        self.next_file_id = self.next_file_id.wrapping_add(1).max(1);
        id
    }
}

fn now_ms() -> u64 {
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

fn sanitize_name(raw: &str) -> String {
    let trimmed = raw
        .trim_matches(|c| c == '\\' || c == '/' || c == '\0')
        .replace('/', "\\");
    // Keep flat root files cleanly; strip traversal
    let last = trimmed.rsplit('\\').next().unwrap_or("");
    if last == "." || last == ".." {
        String::new()
    } else {
        last.to_string()
    }
}

fn wildcard_match(pattern: &str, name: &str) -> bool {
    if pattern.is_empty() || pattern == "*" || pattern == "*.*" {
        return true;
    }
    let p: Vec<char> = pattern.to_lowercase().chars().collect();
    let s: Vec<char> = name.to_lowercase().chars().collect();
    let (mut pi, mut si) = (0usize, 0usize);
    let (mut star_p, mut star_s) = (None, 0usize);
    while si < s.len() {
        if pi < p.len() && (p[pi] == '?' || p[pi] == s[si]) {
            pi += 1;
            si += 1;
        } else if pi < p.len() && p[pi] == '*' {
            star_p = Some(pi);
            star_s = si;
            pi += 1;
        } else if let Some(sp) = star_p {
            pi = sp + 1;
            star_s += 1;
            si = star_s;
        } else {
            return false;
        }
    }
    while pi < p.len() && p[pi] == '*' {
        pi += 1;
    }
    pi == p.len()
}

#[derive(Debug)]
pub struct BookStarkRdpdrBackend {
    store: Arc<Mutex<SharedVDrive>>,
}

impl BookStarkRdpdrBackend {
    pub fn new(store: Arc<Mutex<SharedVDrive>>) -> Self {
        Self { store }
    }

    fn handle_create(&self, req: DeviceCreateRequest) -> SvcMessage {
        let mut st = self.store.lock().unwrap();
        let raw_path = req.path.trim_matches(|c| c == '\0');
        let norm = raw_path.trim_matches(|c| c == '\\' || c == '/');
        let is_root = norm.is_empty() || norm == ".";

        if is_root {
            let file_id = st.alloc_id();
            st.handles.insert(
                file_id,
                OpenHandle {
                    path: String::new(),
                    is_dir: true,
                    delete_on_close: false,
                    dir_cursor: 0,
                    dir_pattern: None,
                    modified: false,
                },
            );
            return SvcMessage::from(RdpdrPdu::DeviceCreateResponse(DeviceCreateResponse {
                device_io_reply: DeviceIoResponse::new(req.device_io_request, NtStatus::SUCCESS),
                file_id,
                information: Information::FILE_OPENED,
            }));
        }

        // Only flat single-level files in root virtual drive
        if norm.contains('\\') || norm.contains('/') {
            return SvcMessage::from(RdpdrPdu::DeviceCreateResponse(DeviceCreateResponse {
                device_io_reply: DeviceIoResponse::new(
                    req.device_io_request,
                    NtStatus::OBJECT_PATH_NOT_FOUND,
                ),
                file_id: 0,
                information: Information::empty(),
            }));
        }

        let name = norm.to_string();
        let exists = st.files.contains_key(&name);
        let wants_dir = req.create_options.contains(CreateOptions::FILE_DIRECTORY_FILE);
        if wants_dir {
            return SvcMessage::from(RdpdrPdu::DeviceCreateResponse(DeviceCreateResponse {
                device_io_reply: DeviceIoResponse::new(
                    req.device_io_request,
                    NtStatus::NOT_A_DIRECTORY,
                ),
                file_id: 0,
                information: Information::empty(),
            }));
        }

        let disp = req.create_disposition;
        let (status, info) = match disp {
            CreateDisposition::FILE_OPEN => {
                if exists {
                    (NtStatus::SUCCESS, Information::FILE_OPENED)
                } else {
                    (NtStatus::OBJECT_PATH_NOT_FOUND, Information::empty())
                }
            }
            CreateDisposition::FILE_CREATE => {
                if exists {
                    (NtStatus::OBJECT_NAME_COLLISION, Information::empty())
                } else {
                    let ft = now_filetime();
                    st.files.insert(
                        name.clone(),
                        VDriveEntry {
                            data: Vec::new(),
                            created_ft: ft,
                            modified_ft: ft,
                            updated_ms: now_ms(),
                        },
                    );
                    st.dirty_notify = true;
                    (NtStatus::SUCCESS, Information::FILE_CREATED)
                }
            }
            CreateDisposition::FILE_OPEN_IF => {
                if exists {
                    (NtStatus::SUCCESS, Information::FILE_OPENED)
                } else {
                    let ft = now_filetime();
                    st.files.insert(
                        name.clone(),
                        VDriveEntry {
                            data: Vec::new(),
                            created_ft: ft,
                            modified_ft: ft,
                            updated_ms: now_ms(),
                        },
                    );
                    st.dirty_notify = true;
                    (NtStatus::SUCCESS, Information::FILE_CREATED)
                }
            }
            CreateDisposition::FILE_OVERWRITE => {
                if exists {
                    if let Some(e) = st.files.get_mut(&name) {
                        e.data.clear();
                        e.modified_ft = now_filetime();
                        e.updated_ms = now_ms();
                    }
                    st.dirty_notify = true;
                    (NtStatus::SUCCESS, Information::FILE_OVERWRITTEN)
                } else {
                    (NtStatus::OBJECT_PATH_NOT_FOUND, Information::empty())
                }
            }
            CreateDisposition::FILE_OVERWRITE_IF | CreateDisposition::FILE_SUPERSEDE => {
                let ft = now_filetime();
                let was_existing = st.files.contains_key(&name);
                st.files.insert(
                    name.clone(),
                    VDriveEntry {
                        data: Vec::new(),
                        created_ft: ft,
                        modified_ft: ft,
                        updated_ms: now_ms(),
                    },
                );
                st.dirty_notify = true;
                (
                    NtStatus::SUCCESS,
                    if was_existing {
                        Information::FILE_OVERWRITTEN
                    } else {
                        Information::FILE_CREATED
                    },
                )
            }
            _ => (NtStatus::NOT_SUPPORTED, Information::empty()),
        };

        if status != NtStatus::SUCCESS {
            return SvcMessage::from(RdpdrPdu::DeviceCreateResponse(DeviceCreateResponse {
                device_io_reply: DeviceIoResponse::new(req.device_io_request, status),
                file_id: 0,
                information: Information::empty(),
            }));
        }

        let file_id = st.alloc_id();
        st.handles.insert(
            file_id,
            OpenHandle {
                path: name,
                is_dir: false,
                delete_on_close: req.create_options.contains(CreateOptions::FILE_DELETE_ON_CLOSE),
                dir_cursor: 0,
                dir_pattern: None,
                modified: false,
            },
        );
        SvcMessage::from(RdpdrPdu::DeviceCreateResponse(DeviceCreateResponse {
            device_io_reply: DeviceIoResponse::new(req.device_io_request, NtStatus::SUCCESS),
            file_id,
            information: info,
        }))
    }

    fn handle_query_info(&self, req: ServerDriveQueryInformationRequest) -> SvcMessage {
        let st = self.store.lock().unwrap();
        let Some(handle) = st.handles.get(&req.device_io_request.file_id) else {
            return SvcMessage::from(RdpdrPdu::ClientDriveQueryInformationResponse(
                ClientDriveQueryInformationResponse {
                    device_io_response: DeviceIoResponse::new(
                        req.device_io_request,
                        NtStatus::INVALID_HANDLE,
                    ),
                    buffer: None,
                },
            ));
        };

        let (size, ft_c, ft_m, attrs, is_dir) = if handle.is_dir {
            let ft = now_filetime();
            (0i64, ft, ft, FileAttributes::FILE_ATTRIBUTE_DIRECTORY, true)
        } else if let Some(entry) = st.files.get(&handle.path) {
            (
                entry.data.len() as i64,
                entry.created_ft,
                entry.modified_ft,
                FileAttributes::FILE_ATTRIBUTE_ARCHIVE,
                false,
            )
        } else {
            return SvcMessage::from(RdpdrPdu::ClientDriveQueryInformationResponse(
                ClientDriveQueryInformationResponse {
                    device_io_response: DeviceIoResponse::new(
                        req.device_io_request,
                        NtStatus::OBJECT_PATH_NOT_FOUND,
                    ),
                    buffer: None,
                },
            ));
        };

        let info_class = match req.file_info_class_lvl {
            FileInformationClassLevel::FILE_BASIC_INFORMATION => {
                Some(FileInformationClass::Basic(FileBasicInformation {
                    creation_time: ft_c,
                    last_access_time: ft_m,
                    last_write_time: ft_m,
                    change_time: ft_m,
                    file_attributes: attrs,
                }))
            }
            FileInformationClassLevel::FILE_STANDARD_INFORMATION => {
                Some(FileInformationClass::Standard(FileStandardInformation {
                    allocation_size: ((size + 4095) / 4096) * 4096,
                    end_of_file: size,
                    number_of_links: 1,
                    delete_pending: Boolean::from(u8::from(handle.delete_on_close)),
                    directory: Boolean::from(u8::from(is_dir)),
                }))
            }
            _ => None,
        };

        let status = if info_class.is_some() {
            NtStatus::SUCCESS
        } else {
            NtStatus::NOT_SUPPORTED
        };

        SvcMessage::from(RdpdrPdu::ClientDriveQueryInformationResponse(
            ClientDriveQueryInformationResponse {
                device_io_response: DeviceIoResponse::new(req.device_io_request, status),
                buffer: info_class,
            },
        ))
    }

    fn handle_query_volume(&self, req: ServerDriveQueryVolumeInformationRequest) -> SvcMessage {
        let st = self.store.lock().unwrap();
        let used_bytes: usize = st.files.values().map(|e| e.data.len()).sum();
        let total_units = 262_144i64; // 1 GiB virtual disk (4096 bytes/unit)
        let used_units = ((used_bytes as i64) + 4095) / 4096;
        let free_units = (total_units - used_units).max(1024);

        let buffer = match req.fs_info_class_lvl {
            FileSystemInformationClassLevel::FILE_FS_VOLUME_INFORMATION => Some(
                FileSystemInformationClass::FileFsVolumeInformation(FileFsVolumeInformation {
                    volume_creation_time: now_filetime(),
                    volume_serial_number: 0xB005_7A2C,
                    supports_objects: Boolean::False,
                    volume_label: "BookStark".to_string(),
                }),
            ),
            FileSystemInformationClassLevel::FILE_FS_SIZE_INFORMATION => Some(
                FileSystemInformationClass::FileFsSizeInformation(FileFsSizeInformation {
                    total_alloc_units: total_units,
                    available_alloc_units: free_units,
                    sectors_per_alloc_unit: 8,
                    bytes_per_sector: 512,
                }),
            ),
            FileSystemInformationClassLevel::FILE_FS_FULL_SIZE_INFORMATION => Some(
                FileSystemInformationClass::FileFsFullSizeInformation(FileFsFullSizeInformation {
                    total_alloc_units: total_units,
                    caller_available_alloc_units: free_units,
                    actual_available_alloc_units: free_units,
                    sectors_per_alloc_unit: 8,
                    bytes_per_sector: 512,
                }),
            ),
            FileSystemInformationClassLevel::FILE_FS_ATTRIBUTE_INFORMATION => Some(
                FileSystemInformationClass::FileFsAttributeInformation(
                    FileFsAttributeInformation {
                        file_system_attributes: FileSystemAttributes::FILE_CASE_PRESERVED_NAMES
                            | FileSystemAttributes::FILE_UNICODE_ON_DISK,
                        max_component_name_len: 255,
                        file_system_name: "BookStarkFS".to_string(),
                    },
                ),
            ),
            FileSystemInformationClassLevel::FILE_FS_DEVICE_INFORMATION => Some(
                FileSystemInformationClass::FileFsDeviceInformation(FileFsDeviceInformation {
                    device_type: 0x0000_0007, // FILE_DEVICE_DISK
                    characteristics: Characteristics::FILE_REMOTE_DEVICE,
                }),
            ),
            _ => None,
        };

        let status = if buffer.is_some() {
            NtStatus::SUCCESS
        } else {
            NtStatus::NOT_SUPPORTED
        };

        SvcMessage::from(RdpdrPdu::ClientDriveQueryVolumeInformationResponse(
            ClientDriveQueryVolumeInformationResponse {
                device_io_reply: DeviceIoResponse::new(req.device_io_request, status),
                buffer,
            },
        ))
    }

    fn handle_query_dir(&self, req: ServerDriveQueryDirectoryRequest) -> SvcMessage {
        let mut st = self.store.lock().unwrap();
        let file_id = req.device_io_request.file_id;
        let Some(handle) = st.handles.get(&file_id).cloned() else {
            return SvcMessage::from(RdpdrPdu::ClientDriveQueryDirectoryResponse(
                ClientDriveQueryDirectoryResponse {
                    device_io_reply: DeviceIoResponse::new(
                        req.device_io_request,
                        NtStatus::INVALID_HANDLE,
                    ),
                    buffer: None,
                },
            ));
        };

        if !handle.is_dir {
            return SvcMessage::from(RdpdrPdu::ClientDriveQueryDirectoryResponse(
                ClientDriveQueryDirectoryResponse {
                    device_io_reply: DeviceIoResponse::new(
                        req.device_io_request,
                        NtStatus::NOT_A_DIRECTORY,
                    ),
                    buffer: None,
                },
            ));
        }

        let pattern = if req.initial_query != 0 {
            let p = req
                .path
                .trim_matches(|c| c == '\0')
                .rsplit('\\')
                .next()
                .unwrap_or("*")
                .to_string();
            if let Some(h) = st.handles.get_mut(&file_id) {
                h.dir_cursor = 0;
                h.dir_pattern = Some(p.clone());
            }
            p
        } else {
            handle.dir_pattern.unwrap_or_else(|| "*".to_string())
        };

        let cursor = st.handles.get(&file_id).map(|h| h.dir_cursor).unwrap_or(0);
        let matching: Vec<(String, VDriveEntry)> = st
            .files
            .iter()
            .filter(|(name, _)| wildcard_match(&pattern, name))
            .map(|(k, v)| (k.clone(), v.clone()))
            .collect();

        if cursor >= matching.len() {
            let status = if req.initial_query != 0 && matching.is_empty() {
                NtStatus::NO_SUCH_FILE
            } else {
                NtStatus::NO_MORE_FILES
            };
            return SvcMessage::from(RdpdrPdu::ClientDriveQueryDirectoryResponse(
                ClientDriveQueryDirectoryResponse {
                    device_io_reply: DeviceIoResponse::new(req.device_io_request, status),
                    buffer: None,
                },
            ));
        }

        let (name, entry) = &matching[cursor];
        if let Some(h) = st.handles.get_mut(&file_id) {
            h.dir_cursor = cursor + 1;
        }

        let size = entry.data.len() as i64;
        let alloc = ((size + 4095) / 4096) * 4096;
        let attrs = FileAttributes::FILE_ATTRIBUTE_ARCHIVE;

        let info = match req.file_info_class_lvl {
            FileInformationClassLevel::FILE_DIRECTORY_INFORMATION => {
                Some(FileInformationClass::Directory(FileDirectoryInformation {
                    next_entry_offset: 0,
                    file_index: cursor as u32,
                    creation_time: entry.created_ft,
                    last_access_time: entry.modified_ft,
                    last_write_time: entry.modified_ft,
                    change_time: entry.modified_ft,
                    end_of_file: size,
                    allocation_size: alloc,
                    file_attributes: attrs,
                    file_name: name.clone(),
                }))
            }
            FileInformationClassLevel::FILE_FULL_DIRECTORY_INFORMATION => Some(
                FileInformationClass::FullDirectory(FileFullDirectoryInformation {
                    next_entry_offset: 0,
                    file_index: cursor as u32,
                    creation_time: entry.created_ft,
                    last_access_time: entry.modified_ft,
                    last_write_time: entry.modified_ft,
                    change_time: entry.modified_ft,
                    end_of_file: size,
                    allocation_size: alloc,
                    file_attributes: attrs,
                    ea_size: 0,
                    file_name: name.clone(),
                }),
            ),
            FileInformationClassLevel::FILE_BOTH_DIRECTORY_INFORMATION => Some(
                FileInformationClass::BothDirectory(FileBothDirectoryInformation {
                    next_entry_offset: 0,
                    file_index: cursor as u32,
                    creation_time: entry.created_ft,
                    last_access_time: entry.modified_ft,
                    last_write_time: entry.modified_ft,
                    change_time: entry.modified_ft,
                    end_of_file: size,
                    allocation_size: alloc,
                    file_attributes: attrs,
                    ea_size: 0,
                    short_name_length: 0,
                    short_name: [0u8; 24],
                    file_name: name.clone(),
                }),
            ),
            FileInformationClassLevel::FILE_NAMES_INFORMATION => {
                Some(FileInformationClass::Names(FileNamesInformation {
                    next_entry_offset: 0,
                    file_index: cursor as u32,
                    file_name: name.clone(),
                }))
            }
            _ => None,
        };

        let status = if info.is_some() {
            NtStatus::SUCCESS
        } else {
            NtStatus::NOT_SUPPORTED
        };

        SvcMessage::from(RdpdrPdu::ClientDriveQueryDirectoryResponse(
            ClientDriveQueryDirectoryResponse {
                device_io_reply: DeviceIoResponse::new(req.device_io_request, status),
                buffer: info,
            },
        ))
    }

    fn handle_read(&self, req: DeviceReadRequest) -> SvcMessage {
        let st = self.store.lock().unwrap();
        let Some(handle) = st.handles.get(&req.device_io_request.file_id) else {
            return SvcMessage::from(RdpdrPdu::DeviceReadResponse(DeviceReadResponse {
                device_io_reply: DeviceIoResponse::new(
                    req.device_io_request,
                    NtStatus::INVALID_HANDLE,
                ),
                read_data: Vec::new(),
            }));
        };
        let Some(entry) = st.files.get(&handle.path) else {
            return SvcMessage::from(RdpdrPdu::DeviceReadResponse(DeviceReadResponse {
                device_io_reply: DeviceIoResponse::new(
                    req.device_io_request,
                    NtStatus::OBJECT_PATH_NOT_FOUND,
                ),
                read_data: Vec::new(),
            }));
        };
        let offset = req.offset as usize;
        let len = req.length as usize;
        let slice = if offset >= entry.data.len() {
            Vec::new()
        } else {
            let end = (offset.saturating_add(len)).min(entry.data.len());
            entry.data[offset..end].to_vec()
        };
        SvcMessage::from(RdpdrPdu::DeviceReadResponse(DeviceReadResponse {
            device_io_reply: DeviceIoResponse::new(req.device_io_request, NtStatus::SUCCESS),
            read_data: slice,
        }))
    }

    fn handle_write(&self, req: DeviceWriteRequest) -> SvcMessage {
        let mut st = self.store.lock().unwrap();
        let file_id = req.device_io_request.file_id;
        let Some(path) = st.handles.get(&file_id).map(|h| h.path.clone()) else {
            return SvcMessage::from(RdpdrPdu::DeviceWriteResponse(DeviceWriteResponse {
                device_io_reply: DeviceIoResponse::new(
                    req.device_io_request,
                    NtStatus::INVALID_HANDLE,
                ),
                length: 0,
            }));
        };
        let Some(entry) = st.files.get_mut(&path) else {
            return SvcMessage::from(RdpdrPdu::DeviceWriteResponse(DeviceWriteResponse {
                device_io_reply: DeviceIoResponse::new(
                    req.device_io_request,
                    NtStatus::OBJECT_PATH_NOT_FOUND,
                ),
                length: 0,
            }));
        };
        let offset = req.offset as usize;
        let end = offset.saturating_add(req.write_data.len());
        // Cap individual virtual file to 128 MiB to protect browser memory
        if end > 128 * 1024 * 1024 {
            return SvcMessage::from(RdpdrPdu::DeviceWriteResponse(DeviceWriteResponse {
                device_io_reply: DeviceIoResponse::new(req.device_io_request, NtStatus::DISK_FULL),
                length: 0,
            }));
        }
        if entry.data.len() < end {
            entry.data.resize(end, 0);
        }
        entry.data[offset..end].copy_from_slice(&req.write_data);
        entry.modified_ft = now_filetime();
        entry.updated_ms = now_ms();
        let written = req.write_data.len() as u32;
        if let Some(h) = st.handles.get_mut(&file_id) {
            h.modified = true;
        }
        st.dirty_notify = true;

        SvcMessage::from(RdpdrPdu::DeviceWriteResponse(DeviceWriteResponse {
            device_io_reply: DeviceIoResponse::new(req.device_io_request, NtStatus::SUCCESS),
            length: written,
        }))
    }

    fn handle_set_info(&self, req: ServerDriveSetInformationRequest) -> SvcMessage {
        let mut st = self.store.lock().unwrap();
        let file_id = req.device_io_request.file_id;
        let Some(handle) = st.handles.get(&file_id).cloned() else {
            return match ClientDriveSetInformationResponse::new(&req, NtStatus::INVALID_HANDLE) {
                Ok(r) => SvcMessage::from(RdpdrPdu::ClientDriveSetInformationResponse(r)),
                Err(_) => unsupported_io(req.device_io_request),
            };
        };

        let status = match &req.set_buffer {
            FileInformationClass::Disposition(disp) => {
                if let Some(h) = st.handles.get_mut(&file_id) {
                    h.delete_on_close = disp.delete_pending != 0;
                }
                NtStatus::SUCCESS
            }
            FileInformationClass::EndOfFile(eof) => {
                if let Some(entry) = st.files.get_mut(&handle.path) {
                    let new_len = (eof.end_of_file.max(0) as usize).min(128 * 1024 * 1024);
                    entry.data.resize(new_len, 0);
                    entry.modified_ft = now_filetime();
                    entry.updated_ms = now_ms();
                    st.dirty_notify = true;
                    NtStatus::SUCCESS
                } else {
                    NtStatus::OBJECT_PATH_NOT_FOUND
                }
            }
            FileInformationClass::Allocation(_) | FileInformationClass::Basic(_) => {
                NtStatus::SUCCESS
            }
            FileInformationClass::Rename(rename) => {
                let new_name = sanitize_name(&rename.file_name);
                if new_name.is_empty() {
                    NtStatus::OBJECT_NAME_INVALID
                } else if let Some(entry) = st.files.remove(&handle.path) {
                    st.files.insert(new_name.clone(), entry);
                    if let Some(h) = st.handles.get_mut(&file_id) {
                        h.path = new_name;
                    }
                    st.dirty_notify = true;
                    NtStatus::SUCCESS
                } else {
                    NtStatus::OBJECT_PATH_NOT_FOUND
                }
            }
            _ => NtStatus::SUCCESS,
        };

        match ClientDriveSetInformationResponse::new(&req, status) {
            Ok(resp) => SvcMessage::from(RdpdrPdu::ClientDriveSetInformationResponse(resp)),
            Err(_) => unsupported_io(req.device_io_request),
        }
    }

    fn handle_close(&self, req: DeviceCloseRequest) -> SvcMessage {
        let mut st = self.store.lock().unwrap();
        if let Some(handle) = st.handles.remove(&req.device_io_request.file_id) {
            if handle.delete_on_close && !handle.is_dir {
                st.files.remove(&handle.path);
                st.dirty_notify = true;
            } else if handle.modified {
                st.dirty_notify = true;
            }
        }
        SvcMessage::from(RdpdrPdu::DeviceCloseResponse(DeviceCloseResponse {
            device_io_response: DeviceIoResponse::new(req.device_io_request, NtStatus::SUCCESS),
        }))
    }
}

impl_as_any!(BookStarkRdpdrBackend);

impl RdpdrBackend for BookStarkRdpdrBackend {
    fn handle_server_device_announce_response(
        &mut self,
        pdu: ServerDeviceAnnounceResponse,
    ) -> PduResult<()> {
        if let Ok(mut st) = self.store.lock() {
            st.mounted = pdu.result_code == NtStatus::SUCCESS;
            st.dirty_notify = true;
        }
        Ok(())
    }

    fn handle_scard_call(
        &mut self,
        req: DeviceControlRequest<ScardIoCtlCode>,
        _call: ScardCall,
    ) -> PduResult<Vec<SvcMessage>> {
        Ok(vec![SvcMessage::from(RdpdrPdu::DeviceControlResponse(
            DeviceControlResponse::new(req, NtStatus::NOT_SUPPORTED, None),
        ))])
    }

    fn handle_drive_io_request(&mut self, req: ServerDriveIoRequest) -> PduResult<Vec<SvcMessage>> {
        let msg = match req {
            ServerDriveIoRequest::ServerCreateDriveRequest(r) => self.handle_create(r),
            ServerDriveIoRequest::ServerDriveQueryInformationRequest(r) => {
                self.handle_query_info(r)
            }
            ServerDriveIoRequest::ServerDriveQueryVolumeInformationRequest(r) => {
                self.handle_query_volume(r)
            }
            ServerDriveIoRequest::ServerDriveQueryDirectoryRequest(r) => self.handle_query_dir(r),
            ServerDriveIoRequest::DeviceReadRequest(r) => self.handle_read(r),
            ServerDriveIoRequest::DeviceWriteRequest(r) => self.handle_write(r),
            ServerDriveIoRequest::ServerDriveSetInformationRequest(r) => self.handle_set_info(r),
            ServerDriveIoRequest::DeviceCloseRequest(r) => self.handle_close(r),
            ServerDriveIoRequest::DeviceFlushBuffersRequest(DeviceFlushBuffersRequest {
                device_io_request,
            }) => SvcMessage::from(RdpdrPdu::DeviceFlushBuffersResponse(
                DeviceFlushBuffersResponse {
                    device_io_response: DeviceIoResponse::new(device_io_request, NtStatus::SUCCESS),
                },
            )),
            ServerDriveIoRequest::DeviceControlRequest(r) => {
                SvcMessage::from(RdpdrPdu::DeviceControlResponse(DeviceControlResponse::new(
                    r,
                    NtStatus::NOT_SUPPORTED,
                    None,
                )))
            }
            ServerDriveIoRequest::ServerDriveNotifyChangeDirectoryRequest(r) => {
                // Defer / not supported without hanging
                let _ = r;
                return Ok(Vec::new());
            }
            ServerDriveIoRequest::ServerDriveLockControlRequest(r) => {
                SvcMessage::from(RdpdrPdu::DeviceCloseResponse(DeviceCloseResponse {
                    device_io_response: DeviceIoResponse::new(
                        r.device_io_request,
                        NtStatus::SUCCESS,
                    ),
                }))
            }
            ServerDriveIoRequest::ServerDriveQuerySecurityRequest(r) => {
                unsupported_io(r.device_io_request)
            }
            ServerDriveIoRequest::ServerDriveSetSecurityRequest(r) => {
                unsupported_io(r.device_io_request)
            }
        };
        Ok(vec![msg])
    }
}

fn unsupported_io(req: DeviceIoRequest) -> SvcMessage {
    SvcMessage::from(RdpdrPdu::DeviceCloseResponse(DeviceCloseResponse {
        device_io_response: DeviceIoResponse::new(req, NtStatus::NOT_SUPPORTED),
    }))
}
