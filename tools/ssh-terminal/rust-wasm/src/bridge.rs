use std::collections::VecDeque;
use std::io;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::task::{Context, Poll, Waker};

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::oneshot;

use crate::{emit_bytes, emit_dial_write, emit_json};

/// Callback invoked whenever a chunk is pulled from the JS -> WASM inbound queue
/// so JS can resume reading from BookStark.sockets (backpressure).
pub enum BridgeKind {
    Ssh { session_id: String },
    Dial { dial_id: String },
}

struct BridgeState {
    kind: BridgeKind,
    inbound: VecDeque<Vec<u8>>,
    closed: bool,
    read_waker: Option<Waker>,
    pending_write: Option<oneshot::Receiver<bool>>,
}

#[derive(Clone)]
pub struct BridgeHandle {
    state: Arc<Mutex<BridgeState>>,
}

pub struct BridgeStream {
    state: Arc<Mutex<BridgeState>>,
}

pub fn create_bridge(kind: BridgeKind) -> (BridgeHandle, BridgeStream) {
    let state = Arc::new(Mutex::new(BridgeState {
        kind,
        inbound: VecDeque::new(),
        closed: false,
        read_waker: None,
        pending_write: None,
    }));
    (
        BridgeHandle {
            state: state.clone(),
        },
        BridgeStream { state },
    )
}

impl BridgeHandle {
    pub fn push_inbound(&self, data: Vec<u8>) {
        let mut st = self.state.lock().unwrap();
        if st.closed {
            return;
        }
        st.inbound.push_back(data);
        if let Some(w) = st.read_waker.take() {
            w.wake();
        }
    }

    pub fn close(&self) {
        let mut st = self.state.lock().unwrap();
        if st.closed {
            return;
        }
        st.closed = true;
        if let Some(w) = st.read_waker.take() {
            w.wake();
        }
    }
}

/// Write-ack slot stored in a shared registry keyed by session_id or dial_id.
pub struct WriteAckSlot {
    tx: Mutex<Option<oneshot::Sender<bool>>>,
}

impl WriteAckSlot {
    pub fn new() -> Self {
        Self {
            tx: Mutex::new(None),
        }
    }
    pub fn arm(&self) -> oneshot::Receiver<bool> {
        let (tx, rx) = oneshot::channel();
        *self.tx.lock().unwrap() = Some(tx);
        rx
    }
    pub fn notify(&self, ok: bool) {
        if let Some(tx) = self.tx.lock().unwrap().take() {
            let _ = tx.send(ok);
        }
    }
}

// We hold write-ack slots in a thread-local map (wasm32 is single-threaded).
use std::cell::RefCell;
use std::collections::HashMap;

thread_local! {
    static SSH_WRITE_ACKS: RefCell<HashMap<String, Arc<WriteAckSlot>>> = RefCell::new(HashMap::new());
    static DIAL_WRITE_ACKS: RefCell<HashMap<String, Arc<WriteAckSlot>>> = RefCell::new(HashMap::new());
}

pub fn register_ssh_write_ack(id: &str) {
    SSH_WRITE_ACKS.with(|m| {
        m.borrow_mut()
            .insert(id.to_string(), Arc::new(WriteAckSlot::new()));
    });
}
pub fn notify_ssh_write_ack(id: &str, ok: bool) {
    SSH_WRITE_ACKS.with(|m| {
        if let Some(slot) = m.borrow().get(id) {
            slot.notify(ok);
        }
    });
}
pub fn remove_ssh_write_ack(id: &str) {
    SSH_WRITE_ACKS.with(|m| {
        if let Some(slot) = m.borrow_mut().remove(id) {
            slot.notify(false);
        }
    });
}

pub fn register_dial_write_ack(id: &str) {
    DIAL_WRITE_ACKS.with(|m| {
        m.borrow_mut()
            .insert(id.to_string(), Arc::new(WriteAckSlot::new()));
    });
}
pub fn notify_dial_write_ack(id: &str, ok: bool) {
    DIAL_WRITE_ACKS.with(|m| {
        if let Some(slot) = m.borrow().get(id) {
            slot.notify(ok);
        }
    });
}
pub fn remove_dial_write_ack(id: &str) {
    DIAL_WRITE_ACKS.with(|m| {
        if let Some(slot) = m.borrow_mut().remove(id) {
            slot.notify(false);
        }
    });
}

fn arm_write_ack(kind: &BridgeKind) -> Option<oneshot::Receiver<bool>> {
    match kind {
        BridgeKind::Ssh { session_id } => SSH_WRITE_ACKS.with(|m| {
            m.borrow().get(session_id).map(|s| s.arm())
        }),
        BridgeKind::Dial { dial_id } => DIAL_WRITE_ACKS.with(|m| {
            m.borrow().get(dial_id).map(|s| s.arm())
        }),
    }
}

impl AsyncRead for BridgeStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let mut st = self.state.lock().unwrap();
        if let Some(mut front) = st.inbound.pop_front() {
            let take = front.len().min(buf.remaining());
            buf.put_slice(&front[..take]);
            if take < front.len() {
                st.inbound.push_front(front.split_off(take));
            } else {
                // Entire chunk consumed -> ack back to JS reader
                match &st.kind {
                    BridgeKind::Ssh { session_id } => {
                        emit_json(session_id, "read-ack", serde_json::json!({}));
                    }
                    BridgeKind::Dial { dial_id } => {
                        emit_json("", "dial-read-ack", serde_json::json!({ "dialId": dial_id }));
                    }
                }
            }
            return Poll::Ready(Ok(()));
        }
        if st.closed {
            return Poll::Ready(Ok(()));
        }
        st.read_waker = Some(cx.waker().clone());
        Poll::Pending
    }
}

impl AsyncWrite for BridgeStream {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<io::Result<usize>> {
        let mut st = self.state.lock().unwrap();
        if st.closed {
            return Poll::Ready(Err(io::Error::new(
                io::ErrorKind::BrokenPipe,
                "socket closed",
            )));
        }
        if let Some(rx) = st.pending_write.as_mut() {
            match Pin::new(rx).poll(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Ok(true)) => {
                    st.pending_write = None;
                }
                Poll::Ready(_) => {
                    st.pending_write = None;
                    return Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::BrokenPipe,
                        "TCP 写入失败",
                    )));
                }
            }
        }
        if buf.is_empty() {
            return Poll::Ready(Ok(0));
        }
        let n = buf.len().min(32 * 1024);
        let chunk = &buf[..n];
        let rx = arm_write_ack(&st.kind);
        match &st.kind {
            BridgeKind::Ssh { session_id } => {
                emit_bytes(session_id, "transport-write", chunk);
            }
            BridgeKind::Dial { dial_id } => {
                emit_dial_write(dial_id, chunk);
            }
        }
        st.pending_write = rx;
        // Poll immediately once in case ack resolved synchronously; otherwise we still report `n`
        // written and gate the NEXT write / flush on the ack (matches Go bridge backpressure!).
        Poll::Ready(Ok(n))
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let mut st = self.state.lock().unwrap();
        if let Some(rx) = st.pending_write.as_mut() {
            match Pin::new(rx).poll(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Ok(true)) => {
                    st.pending_write = None;
                    return Poll::Ready(Ok(()));
                }
                Poll::Ready(_) => {
                    st.pending_write = None;
                    return Poll::Ready(Err(io::Error::new(
                        io::ErrorKind::BrokenPipe,
                        "TCP 写入失败",
                    )));
                }
            }
        }
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let mut st = self.state.lock().unwrap();
        st.closed = true;
        if let Some(w) = st.read_waker.take() {
            w.wake();
        }
        Poll::Ready(Ok(()))
    }
}
