(function (root, factory) {
  const api = factory();
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = api;
  }
  root.P2PProtocol = api;
})(typeof globalThis !== 'undefined' ? globalThis : this, function () {
  'use strict';

  const FRAME_MAGIC = new Uint8Array([0x42, 0x53, 0x50, 0x32]); // "BSP2"
  const DEFAULT_CHUNK_SIZE = 64 * 1024; // 64 KiB
  const MAX_HEADER_BYTES = 8 * 1024;
  const ROOM_PREFIX = 'drop-';

  const encoder = new TextEncoder();
  const decoder = new TextDecoder();

  function randomBytes(len) {
    const out = new Uint8Array(len);
    const cryptoObj = typeof globalThis !== 'undefined' ? globalThis.crypto : null;
    if (cryptoObj && typeof cryptoObj.getRandomValues === 'function') {
      cryptoObj.getRandomValues(out);
      return out;
    }
    for (let i = 0; i < len; i += 1) {
      out[i] = Math.floor(Math.random() * 256);
    }
    return out;
  }

  function generateRoomCode() {
    const bytes = randomBytes(4);
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    // Avoid 000000; range 100000..999999 for crisp 6-digit codes
    const num = 100000 + (view.getUint32(0, false) % 900000);
    return String(num);
  }

  function generatePeerId() {
    const bytes = randomBytes(6);
    let hex = '';
    for (let i = 0; i < bytes.length; i += 1) {
      hex += bytes[i].toString(16).padStart(2, '0');
    }
    return 'p-' + hex;
  }

  function generateTransferId() {
    const bytes = randomBytes(8);
    let hex = '';
    for (let i = 0; i < bytes.length; i += 1) {
      hex += bytes[i].toString(16).padStart(2, '0');
    }
    return 't-' + hex;
  }

  function normalizeRoomCode(raw) {
    if (raw == null) return '';
    const text = String(raw).trim();
    if (!text) return '';

    // Check pairing URI or URL query (?room=...)
    if (text.includes('://') || text.includes('room=')) {
      const parsed = parsePairingPayload(text);
      if (parsed.code) return parsed.code;
    }

    // Check JSON payload
    if (text.startsWith('{') && text.endsWith('}')) {
      try {
        const obj = JSON.parse(text);
        if (obj && obj.room) return normalizeRoomCode(obj.room);
        if (obj && obj.code) return normalizeRoomCode(obj.code);
      } catch (_) {}
    }

    // Strip optional "drop-" prefix and whitespace/dashes
    const stripped = text.replace(/^drop[-_]?/i, '').replace(/[\s-]+/g, '');
    if (/^\d{6}$/.test(stripped)) {
      return stripped;
    }
    return '';
  }

  function formatRoomCode(code) {
    const clean = normalizeRoomCode(code);
    if (!clean) return '';
    return clean.slice(0, 3) + ' ' + clean.slice(3);
  }

  function toSignalingRoomId(code) {
    const clean = normalizeRoomCode(code);
    if (!clean) return '';
    return ROOM_PREFIX + clean;
  }

  function buildPairingPayload(code, signalingBase) {
    const clean = normalizeRoomCode(code);
    if (!clean) return '';
    let uri = 'bookstark-p2p://join?room=' + encodeURIComponent(clean);
    const sig = typeof signalingBase === 'string' ? signalingBase.trim() : '';
    if (sig) {
      uri += '&sig=' + encodeURIComponent(sig);
    }
    return uri;
  }

  function parsePairingPayload(raw) {
    const text = String(raw || '').trim();
    if (!text) return { code: '', signalingBase: '' };

    // Try URL parsing (supports bookstark-p2p://join?room=... and https://...?room=...)
    try {
      const normalized = text.startsWith('bookstark-p2p://')
        ? text.replace(/^bookstark-p2p:\/\//, 'https://p2p.local/')
        : text;
      if (/^https?:\/\//i.test(normalized)) {
        const url = new URL(normalized);
        const roomParam = url.searchParams.get('room') || url.searchParams.get('code') || '';
        const sigParam = url.searchParams.get('sig') || '';
        const stripped = roomParam.replace(/^drop[-_]?/i, '').replace(/[\s-]+/g, '');
        if (/^\d{6}$/.test(stripped)) {
          return { code: stripped, signalingBase: sigParam.trim() };
        }
      }
    } catch (_) {}

    // Fallback: regex search for room=xxxxxx
    const match = text.match(/(?:^|[?&\s])(?:room|code)=(?:drop[-_]?)?(\d{6})(?:$|[&\s])/i);
    if (match) {
      return { code: match[1], signalingBase: '' };
    }

    // Plain 6-digit code
    const stripped = text.replace(/^drop[-_]?/i, '').replace(/[\s-]+/g, '');
    if (/^\d{6}$/.test(stripped)) {
      return { code: stripped, signalingBase: '' };
    }
    return { code: '', signalingBase: '' };
  }

  function encodeChunkFrame(transferId, seq, payloadBytes) {
    if (!transferId || typeof transferId !== 'string') {
      throw new Error('transferId is required');
    }
    if (!Number.isInteger(seq) || seq < 0) {
      throw new Error('seq must be a non-negative integer');
    }
    const payload =
      payloadBytes instanceof Uint8Array
        ? payloadBytes
        : payloadBytes instanceof ArrayBuffer
          ? new Uint8Array(payloadBytes)
          : new Uint8Array(0);

    const headerBytes = encoder.encode(JSON.stringify({ id: transferId, seq }));
    if (headerBytes.byteLength > MAX_HEADER_BYTES) {
      throw new Error('frame header too large');
    }

    const totalLen = 4 + 4 + headerBytes.byteLength + payload.byteLength;
    const out = new Uint8Array(totalLen);
    out.set(FRAME_MAGIC, 0);
    const view = new DataView(out.buffer, out.byteOffset, out.byteLength);
    view.setUint32(4, headerBytes.byteLength, false);
    out.set(headerBytes, 8);
    out.set(payload, 8 + headerBytes.byteLength);
    return out;
  }

  function decodeChunkFrame(buffer) {
    const bytes =
      buffer instanceof Uint8Array
        ? buffer
        : buffer instanceof ArrayBuffer
          ? new Uint8Array(buffer)
          : null;
    if (!bytes || bytes.byteLength < 8) {
      throw new Error('invalid frame: too short');
    }
    for (let i = 0; i < 4; i += 1) {
      if (bytes[i] !== FRAME_MAGIC[i]) {
        throw new Error('invalid frame: bad magic');
      }
    }
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
    const headerLen = view.getUint32(4, false);
    if (headerLen === 0 || headerLen > MAX_HEADER_BYTES || 8 + headerLen > bytes.byteLength) {
      throw new Error('invalid frame: bad header length');
    }
    const headerStr = decoder.decode(bytes.subarray(8, 8 + headerLen));
    let header;
    try {
      header = JSON.parse(headerStr);
    } catch (_) {
      throw new Error('invalid frame: malformed header JSON');
    }
    if (!header || typeof header.id !== 'string' || !Number.isInteger(header.seq) || header.seq < 0) {
      throw new Error('invalid frame: missing id or seq');
    }
    const payload = bytes.slice(8 + headerLen);
    return {
      id: header.id,
      seq: header.seq,
      payload,
    };
  }

  function bytesToHex(bytes) {
    const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    let out = '';
    for (let i = 0; i < u8.length; i += 1) {
      out += u8[i].toString(16).padStart(2, '0');
    }
    return out;
  }

  function concatChunks(chunks, expectedSize) {
    let total = 0;
    for (let i = 0; i < chunks.length; i += 1) {
      total += chunks[i] ? chunks[i].byteLength : 0;
    }
    if (typeof expectedSize === 'number' && expectedSize >= 0 && total !== expectedSize) {
      throw new Error('reassembled size mismatch: expected ' + expectedSize + ', got ' + total);
    }
    const out = new Uint8Array(total);
    let offset = 0;
    for (let i = 0; i < chunks.length; i += 1) {
      const part = chunks[i];
      if (!part) continue;
      out.set(part, offset);
      offset += part.byteLength;
    }
    return out;
  }

  async function sha256Hex(input) {
    const subtle =
      typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle
        ? globalThis.crypto.subtle
        : null;
    if (!subtle) {
      throw new Error('WebCrypto SHA-256 unavailable');
    }
    let buffer;
    if (input instanceof ArrayBuffer) {
      buffer = input;
    } else if (input instanceof Uint8Array) {
      buffer = input.buffer.slice(input.byteOffset, input.byteOffset + input.byteLength);
    } else if (Array.isArray(input)) {
      const joined = concatChunks(input);
      buffer = joined.buffer;
    } else if (input && typeof input.arrayBuffer === 'function') {
      buffer = await input.arrayBuffer();
    } else if (typeof input === 'string') {
      buffer = encoder.encode(input).buffer;
    } else {
      throw new Error('unsupported sha256 input');
    }
    const digest = await subtle.digest('SHA-256', buffer);
    return bytesToHex(new Uint8Array(digest));
  }

  function formatBytes(bytes) {
    const n = Number(bytes);
    if (!Number.isFinite(n) || n < 0) return '0 B';
    if (n < 1024) return Math.round(n) + ' B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    let val = n / 1024;
    let idx = 0;
    while (val >= 1024 && idx < units.length - 1) {
      val /= 1024;
      idx += 1;
    }
    return (val >= 100 ? val.toFixed(0) : val >= 10 ? val.toFixed(1) : val.toFixed(2)) + ' ' + units[idx];
  }

  function formatSpeed(bytesPerSec) {
    const n = Number(bytesPerSec);
    if (!Number.isFinite(n) || n <= 0) return '0 B/s';
    return formatBytes(n) + '/s';
  }

  function formatEta(seconds) {
    const s = Number(seconds);
    if (!Number.isFinite(s) || s < 0) return '--';
    if (s < 1) return '< 1s';
    const rounded = Math.ceil(s);
    const mins = Math.floor(rounded / 60);
    const secs = rounded % 60;
    if (mins >= 60) {
      const hrs = Math.floor(mins / 60);
      const remMins = mins % 60;
      return hrs + ':' + String(remMins).padStart(2, '0') + ':' + String(secs).padStart(2, '0');
    }
    return mins + ':' + String(secs).padStart(2, '0');
  }

  function classifyIceCandidate(candidateType) {
    const t = String(candidateType || '').toLowerCase();
    if (t === 'host') return { mode: 'lan', code: 'host' };
    if (t === 'srflx' || t === 'prflx') return { mode: 'stun', code: t };
    if (t === 'relay') return { mode: 'relay', code: 'relay' };
    return { mode: 'unknown', code: t || 'unknown' };
  }

  function defaultDeviceName(uaString) {
    const ua = String(
      uaString != null
        ? uaString
        : typeof navigator !== 'undefined' && navigator.userAgent
          ? navigator.userAgent
          : ''
    );
    let os = 'Desktop';
    if (/iPhone/i.test(ua)) os = 'iPhone';
    else if (/iPad/i.test(ua)) os = 'iPad';
    else if (/Android/i.test(ua)) os = 'Android';
    else if (/Macintosh|Mac OS X/i.test(ua)) os = 'Mac';
    else if (/Windows/i.test(ua)) os = 'Windows';
    else if (/Linux/i.test(ua)) os = 'Linux';

    let browser = 'Browser';
    if (/Edg\//i.test(ua)) browser = 'Edge';
    else if (/Chrome\//i.test(ua) && !/OPR\//i.test(ua)) browser = 'Chrome';
    else if (/Firefox\//i.test(ua)) browser = 'Firefox';
    else if (/Safari\//i.test(ua) && !/Chrome\//i.test(ua)) browser = 'Safari';

    return os + ' · ' + browser;
  }

  function detectDeviceType(uaString) {
    const ua = String(
      uaString != null
        ? uaString
        : typeof navigator !== 'undefined' && navigator.userAgent
          ? navigator.userAgent
          : ''
    );
    if (/iPhone|Android.*Mobile|Mobile/i.test(ua)) return 'mobile';
    if (/iPad|Tablet/i.test(ua)) return 'tablet';
    return 'desktop';
  }

  return {
    FRAME_MAGIC,
    DEFAULT_CHUNK_SIZE,
    ROOM_PREFIX,
    generateRoomCode,
    generatePeerId,
    generateTransferId,
    normalizeRoomCode,
    formatRoomCode,
    toSignalingRoomId,
    buildPairingPayload,
    parsePairingPayload,
    encodeChunkFrame,
    decodeChunkFrame,
    concatChunks,
    sha256Hex,
    formatBytes,
    formatSpeed,
    formatEta,
    classifyIceCandidate,
    defaultDeviceName,
    detectDeviceType,
  };
});
