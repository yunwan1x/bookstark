use std::borrow::Cow;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use ironrdp_rdpsnd::client::RdpsndClientHandler;
use ironrdp_rdpsnd::pdu::{AudioFormat, AudioFormatFlags, PitchPdu, VolumePdu, WaveFormat};

#[derive(Debug, Clone)]
pub struct AudioPcmChunk {
    pub sample_rate: u32,
    pub channels: u16,
    pub bits_per_sample: u16,
    pub data: Vec<u8>,
}

#[derive(Debug, Default)]
pub struct SharedAudioState {
    pub enabled: bool,
    pub pending_chunks: Vec<AudioPcmChunk>,
    pub volume_left: u16,
    pub volume_right: u16,
    pub active_format: Option<String>,
    pub closed: bool,
}

impl SharedAudioState {
    pub fn new(enabled: bool) -> Arc<Mutex<Self>> {
        Arc::new(Mutex::new(Self {
            enabled,
            pending_chunks: Vec::new(),
            volume_left: 0xD000,
            volume_right: 0xD000,
            active_format: None,
            closed: false,
        }))
    }
}

#[derive(Debug)]
pub struct BookStarkRdpsndHandler {
    formats: Vec<AudioFormat>,
    state: Arc<Mutex<SharedAudioState>>,
}

impl BookStarkRdpsndHandler {
    pub fn new(state: Arc<Mutex<SharedAudioState>>) -> Self {
        // Advertise standard uncompressed PCM formats supported directly by Web Audio API.
        let formats = vec![
            AudioFormat {
                format: WaveFormat::PCM,
                n_channels: 2,
                n_samples_per_sec: 44_100,
                n_avg_bytes_per_sec: 44_100 * 4,
                n_block_align: 4,
                bits_per_sample: 16,
                data: None,
            },
            AudioFormat {
                format: WaveFormat::PCM,
                n_channels: 2,
                n_samples_per_sec: 48_000,
                n_avg_bytes_per_sec: 48_000 * 4,
                n_block_align: 4,
                bits_per_sample: 16,
                data: None,
            },
            AudioFormat {
                format: WaveFormat::PCM,
                n_channels: 1,
                n_samples_per_sec: 44_100,
                n_avg_bytes_per_sec: 44_100 * 2,
                n_block_align: 2,
                bits_per_sample: 16,
                data: None,
            },
            AudioFormat {
                format: WaveFormat::PCM,
                n_channels: 2,
                n_samples_per_sec: 22_050,
                n_avg_bytes_per_sec: 22_050 * 4,
                n_block_align: 4,
                bits_per_sample: 16,
                data: None,
            },
        ];
        Self { formats, state }
    }
}

impl RdpsndClientHandler for BookStarkRdpsndHandler {
    fn get_flags(&self) -> AudioFormatFlags {
        AudioFormatFlags::ALIVE | AudioFormatFlags::VOLUME
    }

    fn get_formats(&self) -> &[AudioFormat] {
        &self.formats
    }

    fn choose_formats(&self, server_formats: &[AudioFormat]) -> Vec<AudioFormat> {
        let mut chosen = Vec::new();
        for sf in server_formats {
            if sf.format == WaveFormat::PCM && (sf.bits_per_sample == 16 || sf.bits_per_sample == 8) {
                if sf.n_channels >= 1 && sf.n_channels <= 2 && sf.n_samples_per_sec >= 8_000 && sf.n_samples_per_sec <= 96_000 {
                    chosen.push(sf.clone());
                }
            }
        }
        if chosen.is_empty() {
            self.formats.clone()
        } else {
            chosen
        }
    }

    fn wave(&mut self, format: &AudioFormat, _ts: u32, data: Cow<'_, [u8]>) {
        if format.format != WaveFormat::PCM || data.is_empty() {
            return;
        }
        if let Ok(mut st) = self.state.lock() {
            st.active_format = Some(format!(
                "PCM {}Hz · {}-bit {}",
                format.n_samples_per_sec,
                format.bits_per_sample,
                if format.n_channels == 1 { "Mono" } else { "Stereo" }
            ));
            if !st.enabled {
                return;
            }
            // Bound queue to avoid unbounded memory growth if audio tab is backgrounded
            if st.pending_chunks.len() > 48 {
                st.pending_chunks.drain(0..24);
            }
            st.pending_chunks.push(AudioPcmChunk {
                sample_rate: format.n_samples_per_sec,
                channels: format.n_channels,
                bits_per_sample: format.bits_per_sample,
                data: data.into_owned(),
            });
        }
    }

    fn playback_latency(&self) -> Duration {
        Duration::from_millis(60)
    }

    fn set_volume(&mut self, volume: VolumePdu) {
        if let Ok(mut st) = self.state.lock() {
            st.volume_left = volume.volume_left;
            st.volume_right = volume.volume_right;
        }
    }

    fn set_pitch(&mut self, _pitch: PitchPdu) {}

    fn close(&mut self) {
        if let Ok(mut st) = self.state.lock() {
            st.closed = true;
        }
    }
}
