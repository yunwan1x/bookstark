use std::sync::{Arc, Mutex};
use std::time::Duration;

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::client::UnbufferedClientConnection;
use rustls::crypto::{verify_tls12_signature, verify_tls13_signature, WebPkiSupportedAlgorithms};
use rustls::time_provider::TimeProvider;
use rustls::unbuffered::{ConnectionState, EncodeError, EncryptError, UnbufferedStatus};
use rustls::{ClientConfig, DigitallySignedStruct, Error as TlsError, SignatureScheme};
use rustls_pki_types::{CertificateDer, ServerName, UnixTime};
use sha2::{Digest, Sha256};
use x509_cert::der::Decode as DerDecode;

#[derive(Debug, Clone)]
pub struct PeerCertInfo {
    pub subject: String,
    pub issuer: String,
    pub fingerprint_sha256: String,
    pub server_public_key: Vec<u8>,
}

#[derive(Debug)]
struct WasmTimeProvider;

impl TimeProvider for WasmTimeProvider {
    fn current_time(&self) -> Option<UnixTime> {
        #[cfg(target_arch = "wasm32")]
        let millis = js_sys::Date::now() as u64;
        #[cfg(not(target_arch = "wasm32"))]
        let millis = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        Some(UnixTime::since_unix_epoch(Duration::from_millis(millis)))
    }
}

#[derive(Debug)]
struct TofuCertVerifier {
    algs: WebPkiSupportedAlgorithms,
    captured: Arc<Mutex<Option<PeerCertInfo>>>,
}

impl ServerCertVerifier for TofuCertVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> Result<ServerCertVerified, TlsError> {
        let der = end_entity.as_ref();
        let digest = Sha256::digest(der);
        let fingerprint_sha256 = digest
            .iter()
            .map(|b| format!("{b:02X}"))
            .collect::<Vec<_>>()
            .join(":");

        let (subject, issuer, server_public_key) = match x509_cert::Certificate::from_der(der) {
            Ok(cert) => {
                let subj = cert.tbs_certificate.subject.to_string();
                let iss = cert.tbs_certificate.issuer.to_string();
                let pk = cert
                    .tbs_certificate
                    .subject_public_key_info
                    .subject_public_key
                    .raw_bytes()
                    .to_vec();
                (subj, iss, pk)
            }
            Err(_) => ("CN=Unknown".to_string(), "Unknown".to_string(), Vec::new()),
        };

        if let Ok(mut guard) = self.captured.lock() {
            *guard = Some(PeerCertInfo {
                subject,
                issuer,
                fingerprint_sha256,
                server_public_key,
            });
        }

        // Actual host trust verification happens in the TOFU UI step before any credentials are sent.
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        verify_tls12_signature(message, cert, dss, &self.algs)
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> Result<HandshakeSignatureValid, TlsError> {
        verify_tls13_signature(message, cert, dss, &self.algs)
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        self.algs.supported_schemes()
    }
}

pub struct SansIoTls {
    conn: UnbufferedClientConnection,
    captured: Arc<Mutex<Option<PeerCertInfo>>>,
    incoming_tls: Vec<u8>,
    outgoing_tls: Vec<u8>,
    pending_plain_out: Vec<u8>,
    handshake_done: bool,
}

impl SansIoTls {
    pub fn new(host: &str) -> Result<Self, String> {
        let provider = Arc::new(rustls_rustcrypto::provider());
        let algs = provider.signature_verification_algorithms;
        let captured = Arc::new(Mutex::new(None));
        let verifier = Arc::new(TofuCertVerifier {
            algs,
            captured: captured.clone(),
        });

        let config = ClientConfig::builder_with_details(provider, Arc::new(WasmTimeProvider))
            .with_safe_default_protocol_versions()
            .map_err(|e| format!("TLS protocol config error: {e}"))?
            .dangerous()
            .with_custom_certificate_verifier(verifier)
            .with_no_client_auth();

        let server_name = ServerName::try_from(host.to_owned())
            .unwrap_or_else(|_| ServerName::try_from("rdp.local".to_owned()).expect("valid fallback SNI"));

        let conn = UnbufferedClientConnection::new(Arc::new(config), server_name)
            .map_err(|e| format!("TLS client init failed: {e}"))?;

        let mut this = Self {
            conn,
            captured,
            incoming_tls: Vec::new(),
            outgoing_tls: Vec::new(),
            pending_plain_out: Vec::new(),
            handshake_done: false,
        };
        let _ = this.pump()?;
        Ok(this)
    }

    pub fn is_handshaking(&self) -> bool {
        !self.handshake_done
    }

    pub fn peer_cert_info(&self) -> Option<PeerCertInfo> {
        self.captured.lock().ok().and_then(|g| g.clone())
    }

    pub fn protocol_label(&self) -> String {
        let proto = self
            .conn
            .protocol_version()
            .map(|v| format!("{v:?}"))
            .unwrap_or_else(|| "TLS".to_string());
        let cipher = self
            .conn
            .negotiated_cipher_suite()
            .map(|c| format!("{:?}", c.suite()))
            .unwrap_or_default();
        if cipher.is_empty() {
            proto
        } else {
            format!("{proto} ({cipher})")
        }
    }

    /// Feed raw encrypted TCP bytes into TLS and return any newly decrypted plaintext bytes.
    pub fn feed_ciphertext(&mut self, bytes: &[u8]) -> Result<Vec<u8>, String> {
        self.incoming_tls.extend_from_slice(bytes);
        self.pump()
    }

    /// Encrypt application plaintext bytes into the TLS outbound buffer.
    pub fn write_plaintext(&mut self, data: &[u8]) -> Result<(), String> {
        if data.is_empty() {
            return Ok(());
        }
        self.pending_plain_out.extend_from_slice(data);
        let _ = self.pump()?;
        Ok(())
    }

    /// Drain encrypted ciphertext bytes ready to transmit over TCP.
    pub fn drain_ciphertext(&mut self) -> Result<Vec<u8>, String> {
        Ok(std::mem::take(&mut self.outgoing_tls))
    }

    fn pump(&mut self) -> Result<Vec<u8>, String> {
        let mut plaintext = Vec::new();
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
                    return Err(format!("TLS 握手或解密失败: {e}"));
                }
            };

            let mut progressed = false;
            match state {
                ConnectionState::EncodeTlsData(mut enc) => {
                    loop {
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
                    }
                }
                ConnectionState::TransmitTlsData(tx) => {
                    tx.done();
                    progressed = true;
                }
                ConnectionState::BlockedHandshake => {}
                ConnectionState::ReadTraffic(mut rt) => {
                    self.handshake_done = true;
                    while let Some(res) = rt.next_record() {
                        let rec = res.map_err(|e| format!("TLS 数据记录解码失败: {e}"))?;
                        plaintext.extend_from_slice(rec.payload);
                        progressed = true;
                    }
                }
                ConnectionState::WriteTraffic(mut wt) => {
                    self.handshake_done = true;
                    while !self.pending_plain_out.is_empty() {
                        let chunk_len = self.pending_plain_out.len().min(16384);
                        loop {
                            match wt.encrypt(&self.pending_plain_out[..chunk_len], &mut scratch) {
                                Ok(n) => {
                                    self.outgoing_tls.extend_from_slice(&scratch[..n]);
                                    self.pending_plain_out.drain(..chunk_len);
                                    progressed = true;
                                    break;
                                }
                                Err(EncryptError::InsufficientSize(ise)) => {
                                    scratch.resize(ise.required_size.max(scratch.len() * 2), 0);
                                }
                                Err(EncryptError::EncryptExhausted) => {
                                    return Err("TLS 加密序列号耗尽".to_string());
                                }
                            }
                        }
                    }
                }
                ConnectionState::PeerClosed | ConnectionState::Closed => {}
                ConnectionState::ReadEarlyData(_) => {}
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
        Ok(plaintext)
    }
}
