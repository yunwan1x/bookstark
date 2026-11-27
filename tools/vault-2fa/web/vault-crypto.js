(function (root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  }
  root.VaultCrypto = api;
})(typeof globalThis !== 'undefined' ? globalThis : window, function () {
  'use strict';

  const BASE32_ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  const DEFAULT_ITERATIONS = 600000;
  const MIN_ITERATIONS = 100000;

  function getCrypto() {
    if (typeof globalThis !== 'undefined' && globalThis.crypto && globalThis.crypto.subtle) {
      return globalThis.crypto;
    }
    throw new Error('webcrypto_unavailable');
  }

  function bytesToBase64(bytes) {
    let bin = '';
    const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    const chunk = 0x8000;
    for (let i = 0; i < arr.length; i += chunk) {
      bin += String.fromCharCode.apply(null, arr.subarray(i, i + chunk));
    }
    return btoa(bin);
  }

  function base64ToBytes(b64) {
    const clean = String(b64 || '').replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/');
    const pad = clean.length % 4 === 0 ? '' : '='.repeat(4 - (clean.length % 4));
    const bin = atob(clean + pad);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  function normalizeBase32(str) {
    return String(str || '').toUpperCase().replace(/[\s\-=]+/g, '');
  }

  function isValidBase32(str) {
    const clean = normalizeBase32(str);
    return clean.length >= 8 && /^[A-Z2-7]+$/.test(clean);
  }

  function base32Decode(str) {
    const clean = normalizeBase32(str);
    if (!clean || !/^[A-Z2-7]+$/.test(clean)) {
      throw new Error('invalid_base32');
    }
    let bits = 0;
    let value = 0;
    const out = [];
    for (let i = 0; i < clean.length; i++) {
      const idx = BASE32_ALPHABET.indexOf(clean[i]);
      if (idx < 0) throw new Error('invalid_base32');
      value = (value << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        out.push((value >>> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }
    return new Uint8Array(out);
  }

  function base32Encode(bytes) {
    const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    let bits = 0;
    let value = 0;
    let out = '';
    for (let i = 0; i < arr.length; i++) {
      value = (value << 8) | arr[i];
      bits += 8;
      while (bits >= 5) {
        out += BASE32_ALPHABET[(value >>> (bits - 5)) & 31];
        bits -= 5;
      }
    }
    if (bits > 0) {
      out += BASE32_ALPHABET[(value << (5 - bits)) & 31];
    }
    return out;
  }

  function normalizeAlgorithm(algo) {
    const up = String(algo || 'SHA-1').toUpperCase().replace(/[^A-Z0-9]/g, '');
    if (up === 'SHA256') return 'SHA-256';
    if (up === 'SHA512') return 'SHA-512';
    return 'SHA-1';
  }

  function remainingSeconds(period, timestamp) {
    const p = Math.max(5, Math.min(300, Number(period) || 30));
    const sec = Math.floor((timestamp == null ? Date.now() : timestamp) / 1000);
    return p - (sec % p);
  }

  async function generateTOTP(base32Secret, options) {
    const opts = options || {};
    const digits = Number(opts.digits) === 8 ? 8 : 6;
    const period = Math.max(5, Math.min(300, Number(opts.period) || 30));
    const algorithm = normalizeAlgorithm(opts.algorithm);
    const ts = opts.timestamp == null ? Date.now() : Number(opts.timestamp);
    const counter = Math.floor(ts / 1000 / period);

    const keyBytes = base32Decode(base32Secret);
    const counterBuf = new ArrayBuffer(8);
    const view = new DataView(counterBuf);
    view.setUint32(0, Math.floor(counter / 0x100000000), false);
    view.setUint32(4, counter >>> 0, false);

    const cryptoObj = getCrypto();
    const cryptoKey = await cryptoObj.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'HMAC', hash: { name: algorithm } },
      false,
      ['sign']
    );
    const sig = new Uint8Array(await cryptoObj.subtle.sign('HMAC', cryptoKey, counterBuf));
    const offset = sig[sig.length - 1] & 0x0f;
    const binary =
      ((sig[offset] & 0x7f) << 24) |
      ((sig[offset + 1] & 0xff) << 16) |
      ((sig[offset + 2] & 0xff) << 8) |
      (sig[offset + 3] & 0xff);
    const mod = Math.pow(10, digits);
    return String(binary % mod).padStart(digits, '0');
  }

  function formatTOTP(code) {
    const s = String(code || '');
    if (s.length === 6) return s.slice(0, 3) + ' ' + s.slice(3);
    if (s.length === 8) return s.slice(0, 4) + ' ' + s.slice(4);
    return s;
  }

  async function deriveVaultKey(masterPassword, saltBytes, iterations) {
    const pwd = String(masterPassword || '');
    if (!pwd) throw new Error('empty_password');
    const iters = Math.max(MIN_ITERATIONS, Number(iterations) || DEFAULT_ITERATIONS);
    const cryptoObj = getCrypto();
    const baseKey = await cryptoObj.subtle.importKey(
      'raw',
      new TextEncoder().encode(pwd),
      { name: 'PBKDF2' },
      false,
      ['deriveKey']
    );
    return cryptoObj.subtle.deriveKey(
      {
        name: 'PBKDF2',
        salt: saltBytes,
        iterations: iters,
        hash: 'SHA-256',
      },
      baseKey,
      { name: 'AES-GCM', length: 256 },
      false,
      ['encrypt', 'decrypt']
    );
  }

  async function encryptVaultWithKey(plaintextObj, cryptoKey, meta) {
    const cryptoObj = getCrypto();
    const iv = cryptoObj.getRandomValues(new Uint8Array(12));
    const encoded = new TextEncoder().encode(JSON.stringify(plaintextObj));
    const cipherBuf = await cryptoObj.subtle.encrypt(
      { name: 'AES-GCM', iv: iv },
      cryptoKey,
      encoded
    );
    return {
      v: 1,
      kdf: 'PBKDF2-SHA256',
      iterations: meta.iterations,
      salt: meta.salt,
      iv: bytesToBase64(iv),
      cipher: 'AES-256-GCM',
      ct: bytesToBase64(new Uint8Array(cipherBuf)),
    };
  }

  async function encryptVault(plaintextObj, masterPassword, options) {
    const cryptoObj = getCrypto();
    const iterations = Math.max(
      MIN_ITERATIONS,
      Number((options && options.iterations) || DEFAULT_ITERATIONS)
    );
    const saltBytes = cryptoObj.getRandomValues(new Uint8Array(16));
    const salt = bytesToBase64(saltBytes);
    const key = await deriveVaultKey(masterPassword, saltBytes, iterations);
    const meta = { iterations: iterations, salt: salt };
    const envelope = await encryptVaultWithKey(plaintextObj, key, meta);
    return { envelope: envelope, key: key, meta: meta };
  }

  async function decryptVault(envelopeInput, masterPassword) {
    let envelope = envelopeInput;
    if (typeof envelope === 'string') {
      try {
        envelope = JSON.parse(envelope);
      } catch (_) {
        throw new Error('invalid_envelope');
      }
    }
    if (
      !envelope ||
      envelope.v !== 1 ||
      envelope.kdf !== 'PBKDF2-SHA256' ||
      envelope.cipher !== 'AES-256-GCM' ||
      typeof envelope.salt !== 'string' ||
      typeof envelope.iv !== 'string' ||
      typeof envelope.ct !== 'string'
    ) {
      throw new Error('invalid_envelope');
    }
    const iterations = Number(envelope.iterations);
    if (!Number.isFinite(iterations) || iterations < MIN_ITERATIONS || iterations > 5000000) {
      throw new Error('invalid_envelope');
    }
    const saltBytes = base64ToBytes(envelope.salt);
    const ivBytes = base64ToBytes(envelope.iv);
    const ctBytes = base64ToBytes(envelope.ct);
    const key = await deriveVaultKey(masterPassword, saltBytes, iterations);
    const cryptoObj = getCrypto();
    let plainBuf;
    try {
      plainBuf = await cryptoObj.subtle.decrypt(
        { name: 'AES-GCM', iv: ivBytes },
        key,
        ctBytes
      );
    } catch (_) {
      throw new Error('wrong_password');
    }
    let data;
    try {
      data = JSON.parse(new TextDecoder().decode(plainBuf));
    } catch (_) {
      throw new Error('corrupt_payload');
    }
    return {
      data: data,
      key: key,
      meta: { iterations: iterations, salt: envelope.salt },
    };
  }

  function randomInt(max) {
    const cryptoObj = getCrypto();
    if (max <= 1) return 0;
    const limit = Math.floor(0x100000000 / max) * max;
    const buf = new Uint32Array(1);
    while (true) {
      cryptoObj.getRandomValues(buf);
      if (buf[0] < limit) return buf[0] % max;
    }
  }

  function generatePassword(options) {
    const opts = Object.assign(
      { length: 20, upper: true, lower: true, digits: true, symbols: true },
      options || {}
    );
    const sets = [];
    if (opts.upper) sets.push('ABCDEFGHJKLMNPQRSTUVWXYZ');
    if (opts.lower) sets.push('abcdefghijkmnopqrstuvwxyz');
    if (opts.digits) sets.push('23456789');
    if (opts.symbols) sets.push('!@#$%^&*-_=+?');
    if (!sets.length) sets.push('abcdefghijkmnopqrstuvwxyz23456789');

    const length = Math.max(Math.max(8, sets.length), Math.min(128, Number(opts.length) || 20));
    const all = sets.join('');
    const chars = [];
    for (let i = 0; i < sets.length; i++) {
      chars.push(sets[i][randomInt(sets[i].length)]);
    }
    while (chars.length < length) {
      chars.push(all[randomInt(all.length)]);
    }
    for (let i = chars.length - 1; i > 0; i--) {
      const j = randomInt(i + 1);
      const tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }
    return chars.join('');
  }

  function passwordStrength(password) {
    const s = String(password || '');
    if (!s) return { score: 0, key: 'empty' };
    let score = 0;
    if (s.length >= 8) score++;
    if (s.length >= 12) score++;
    let classes = 0;
    if (/[a-z]/.test(s)) classes++;
    if (/[A-Z]/.test(s)) classes++;
    if (/[0-9]/.test(s)) classes++;
    if (/[^a-zA-Z0-9]/.test(s)) classes++;
    if (classes >= 3) score++;
    if (s.length >= 16 && classes >= 3) score++;
    const keys = ['weak', 'weak', 'fair', 'good', 'strong'];
    return { score: Math.min(4, score), key: keys[Math.min(4, score)] };
  }

  function buildSshCommand(entry) {
    if (!entry) return '';
    const host = String(entry.host || '').trim();
    if (!host) return '';
    const user = String(entry.username || 'root').trim() || 'root';
    const portNum = Number(entry.port);
    const port = Number.isInteger(portNum) && portNum > 0 && portNum <= 65535 ? portNum : 22;
    return port === 22 ? 'ssh ' + user + '@' + host : 'ssh -p ' + port + ' ' + user + '@' + host;
  }

  function daysUntilExpiry(expiresAt, nowMs) {
    const raw = String(expiresAt || '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) return null;
    const parts = raw.split('-').map(Number);
    const targetUtc = Date.UTC(parts[0], parts[1] - 1, parts[2], 23, 59, 59);
    if (!Number.isFinite(targetUtc)) return null;
    const now = typeof nowMs === 'number' ? nowMs : Date.now();
    return Math.floor((targetUtc - now) / (24 * 60 * 60 * 1000));
  }

  function auditVaultEntries(entries, nowMs) {
    const list = Array.isArray(entries) ? entries : [];
    const byId = Object.create(null);
    const pwdCounts = Object.create(null);

    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      if (!e || !e.id) continue;
      if (e.category === 'totp' || e.category === 'note') continue;
      const p = String(e.password || '');
      if (p) {
        pwdCounts[p] = (pwdCounts[p] || 0) + 1;
      }
    }

    let flaggedCount = 0;
    for (let i = 0; i < list.length; i++) {
      const e = list[i];
      if (!e || !e.id) continue;
      const issues = [];

      if (e.category !== 'totp' && e.category !== 'note') {
        const p = String(e.password || '');
        if (p) {
          if (e.category !== 'token' && passwordStrength(p).score <= 1) {
            issues.push({ type: 'weak_password' });
          }
          if (pwdCounts[p] > 1) {
            issues.push({ type: 'reused_password', count: pwdCounts[p] });
          }
        }
      }

      if (e.expiresAt) {
        const days = daysUntilExpiry(e.expiresAt, nowMs);
        if (days !== null) {
          if (days < 0) {
            issues.push({ type: 'expired_token', days: days });
          } else if (days <= 14) {
            issues.push({ type: 'expiring_token', days: days });
          }
        }
      }

      if (issues.length) {
        byId[e.id] = issues;
        flaggedCount++;
      }
    }

    return { flaggedCount: flaggedCount, byId: byId };
  }

  return {
    DEFAULT_ITERATIONS: DEFAULT_ITERATIONS,
    bytesToBase64: bytesToBase64,
    base64ToBytes: base64ToBytes,
    normalizeBase32: normalizeBase32,
    isValidBase32: isValidBase32,
    base32Decode: base32Decode,
    base32Encode: base32Encode,
    normalizeAlgorithm: normalizeAlgorithm,
    remainingSeconds: remainingSeconds,
    generateTOTP: generateTOTP,
    formatTOTP: formatTOTP,
    deriveVaultKey: deriveVaultKey,
    encryptVault: encryptVault,
    encryptVaultWithKey: encryptVaultWithKey,
    decryptVault: decryptVault,
    generatePassword: generatePassword,
    passwordStrength: passwordStrength,
    buildSshCommand: buildSshCommand,
    daysUntilExpiry: daysUntilExpiry,
    auditVaultEntries: auditVaultEntries,
  };
});
