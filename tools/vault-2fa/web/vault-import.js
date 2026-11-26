(function (root, factory) {
  const cryptoApi =
    typeof module === 'object' && module.exports
      ? require('./vault-crypto.js')
      : root.VaultCrypto;
  const api = factory(cryptoApi);
  if (typeof module === 'object' && module.exports) {
    module.exports = api;
  }
  root.VaultImport = api;
})(typeof globalThis !== 'undefined' ? globalThis : window, function (VaultCrypto) {
  'use strict';

  function parseOtpAuthURI(raw) {
    const trimmed = String(raw || '').trim();
    let url;
    try {
      url = new URL(trimmed);
    } catch (_) {
      throw new Error('invalid_otpauth');
    }
    if (url.protocol !== 'otpauth:') throw new Error('invalid_otpauth');
    const type = (url.hostname || '').toLowerCase();
    if (type !== 'totp') {
      throw new Error(type === 'hotp' ? 'unsupported_hotp' : 'invalid_otpauth');
    }
    const secret = VaultCrypto.normalizeBase32(url.searchParams.get('secret') || '');
    if (!VaultCrypto.isValidBase32(secret)) throw new Error('invalid_secret');

    const rawLabel = decodeURIComponent((url.pathname || '').replace(/^\/+/, ''));
    let labelIssuer = '';
    let account = rawLabel;
    const colon = rawLabel.indexOf(':');
    if (colon >= 0) {
      labelIssuer = rawLabel.slice(0, colon).trim();
      account = rawLabel.slice(colon + 1).trim();
    }
    const issuer = (url.searchParams.get('issuer') || labelIssuer || '').trim();
    const algorithm = VaultCrypto.normalizeAlgorithm(url.searchParams.get('algorithm') || 'SHA-1');
    const digits = Number(url.searchParams.get('digits')) === 8 ? 8 : 6;
    const periodNum = Number(url.searchParams.get('period')) || 30;
    const period = Math.max(5, Math.min(300, periodNum));
    const title = issuer || account || '2FA';

    return {
      title: title,
      issuer: issuer,
      username: account,
      password: '',
      url: '',
      notes: '',
      category: 'totp',
      favorite: false,
      totp: {
        secret: secret,
        algorithm: algorithm,
        digits: digits,
        period: period,
      },
    };
  }

  function buildOtpAuthURI(entry) {
    if (!entry || !entry.totp || !entry.totp.secret) return '';
    const issuer = (entry.issuer || entry.title || 'BookStark').trim();
    const account = (entry.username || entry.title || 'account').trim();
    const label = issuer && account && issuer !== account ? issuer + ':' + account : account || issuer;
    const params = new URLSearchParams();
    params.set('secret', VaultCrypto.normalizeBase32(entry.totp.secret));
    if (issuer) params.set('issuer', issuer);
    const algo = VaultCrypto.normalizeAlgorithm(entry.totp.algorithm).replace('-', '');
    if (algo !== 'SHA1') params.set('algorithm', algo);
    const digits = Number(entry.totp.digits) === 8 ? 8 : 6;
    if (digits !== 6) params.set('digits', String(digits));
    const period = Math.max(5, Math.min(300, Number(entry.totp.period) || 30));
    if (period !== 30) params.set('period', String(period));
    return 'otpauth://totp/' + encodeURIComponent(label) + '?' + params.toString();
  }

  // Minimal Protobuf wire reader for Google Authenticator otpauth-migration://
  function readVarint(bytes, state) {
    let result = 0;
    let shift = 0;
    while (state.pos < bytes.length) {
      const b = bytes[state.pos++];
      result += (b & 0x7f) * Math.pow(2, shift);
      if ((b & 0x80) === 0) return result;
      shift += 7;
      if (shift > 56) throw new Error('invalid_migration');
    }
    throw new Error('invalid_migration');
  }

  function readFields(bytes) {
    const fields = [];
    const state = { pos: 0 };
    while (state.pos < bytes.length) {
      const tag = readVarint(bytes, state);
      const fieldNum = Math.floor(tag / 8);
      const wireType = tag & 7;
      if (wireType === 0) {
        fields.push({ num: fieldNum, type: 0, value: readVarint(bytes, state) });
      } else if (wireType === 2) {
        const len = readVarint(bytes, state);
        if (state.pos + len > bytes.length) throw new Error('invalid_migration');
        const slice = bytes.subarray(state.pos, state.pos + len);
        state.pos += len;
        fields.push({ num: fieldNum, type: 2, value: slice });
      } else if (wireType === 1) {
        state.pos += 8;
      } else if (wireType === 5) {
        state.pos += 4;
      } else {
        throw new Error('invalid_migration');
      }
    }
    return fields;
  }

  function parseGoogleMigrationURI(raw) {
    const trimmed = String(raw || '').trim();
    if (!trimmed.startsWith('otpauth-migration://')) {
      throw new Error('invalid_migration');
    }
    let dataParam = '';
    const q = trimmed.indexOf('?');
    if (q >= 0) {
      const params = new URLSearchParams(trimmed.slice(q + 1));
      dataParam = params.get('data') || '';
    }
    if (!dataParam) throw new Error('invalid_migration');
    // URLSearchParams turns '+' into space if unencoded; restore '+'
    const bytes = VaultCrypto.base64ToBytes(dataParam.replace(/ /g, '+'));
    const topFields = readFields(bytes);
    const dec = new TextDecoder();
    const entries = [];
    let skippedHotp = 0;

    for (let i = 0; i < topFields.length; i++) {
      const f = topFields[i];
      if (f.num !== 1 || f.type !== 2) continue;
      const sub = readFields(f.value);
      let secretBytes = null;
      let name = '';
      let issuer = '';
      let algoCode = 1;
      let digitsCode = 1;
      let typeCode = 2;
      for (let j = 0; j < sub.length; j++) {
        const sf = sub[j];
        if (sf.num === 1 && sf.type === 2) secretBytes = sf.value;
        else if (sf.num === 2 && sf.type === 2) name = dec.decode(sf.value).trim();
        else if (sf.num === 3 && sf.type === 2) issuer = dec.decode(sf.value).trim();
        else if (sf.num === 4 && sf.type === 0) algoCode = sf.value;
        else if (sf.num === 5 && sf.type === 0) digitsCode = sf.value;
        else if (sf.num === 6 && sf.type === 0) typeCode = sf.value;
      }
      if (!secretBytes || !secretBytes.length) continue;
      if (typeCode === 1) {
        skippedHotp++;
        continue;
      }
      const algoMap = { 1: 'SHA-1', 2: 'SHA-256', 3: 'SHA-512' };
      const algorithm = algoMap[algoCode] || 'SHA-1';
      const digits = digitsCode === 2 ? 8 : 6;
      let account = name;
      let labelIssuer = issuer;
      const colon = name.indexOf(':');
      if (colon >= 0) {
        if (!labelIssuer) labelIssuer = name.slice(0, colon).trim();
        account = name.slice(colon + 1).trim();
      }
      entries.push({
        title: labelIssuer || account || '2FA',
        issuer: labelIssuer,
        username: account,
        password: '',
        url: '',
        notes: '',
        category: 'totp',
        favorite: false,
        totp: {
          secret: VaultCrypto.base32Encode(secretBytes),
          algorithm: algorithm,
          digits: digits,
          period: 30,
        },
      });
    }
    return { entries: entries, skippedHotp: skippedHotp };
  }

  function parseAnyOtpText(text) {
    const raw = String(text || '').trim();
    if (!raw) return { entries: [], skippedHotp: 0 };
    if (raw.startsWith('otpauth-migration://')) {
      return parseGoogleMigrationURI(raw);
    }
    const lines = raw.split(/\r?\n/).map(function (l) { return l.trim(); }).filter(Boolean);
    const entries = [];
    let skippedHotp = 0;
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith('otpauth-migration://')) {
        const res = parseGoogleMigrationURI(line);
        entries.push.apply(entries, res.entries);
        skippedHotp += res.skippedHotp;
      } else if (line.startsWith('otpauth://')) {
        try {
          entries.push(parseOtpAuthURI(line));
        } catch (err) {
          if (err.message === 'unsupported_hotp') skippedHotp++;
          else if (lines.length === 1) throw err;
        }
      } else if (lines.length === 1 && VaultCrypto.isValidBase32(line)) {
        entries.push({
          title: '2FA',
          issuer: '',
          username: '',
          password: '',
          url: '',
          notes: '',
          category: 'totp',
          favorite: false,
          totp: {
            secret: VaultCrypto.normalizeBase32(line),
            algorithm: 'SHA-1',
            digits: 6,
            period: 30,
          },
        });
      }
    }
    return { entries: entries, skippedHotp: skippedHotp };
  }

  // RFC 4180 CSV parser supporting Chrome, Edge, Bitwarden, 1Password, KeePass, iCloud
  function parseCSVRows(text) {
    const s = String(text || '').replace(/^\uFEFF/, '');
    const rows = [];
    let row = [];
    let field = '';
    let inQuotes = false;
    for (let i = 0; i < s.length; i++) {
      const ch = s[i];
      if (inQuotes) {
        if (ch === '"') {
          if (s[i + 1] === '"') {
            field += '"';
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field += ch;
        }
      } else {
        if (ch === '"' && field === '') {
          inQuotes = true;
        } else if (ch === ',') {
          row.push(field);
          field = '';
        } else if (ch === '\r') {
          if (s[i + 1] === '\n') i++;
          row.push(field);
          rows.push(row);
          row = [];
          field = '';
        } else if (ch === '\n') {
          row.push(field);
          rows.push(row);
          row = [];
          field = '';
        } else {
          field += ch;
        }
      }
    }
    if (field !== '' || row.length > 0) {
      row.push(field);
      rows.push(row);
    }
    return rows.filter(function (r) {
      return r.some(function (cell) { return String(cell).trim() !== ''; });
    });
  }

  function guessCategory(folder, url, hasTotp, hasPassword) {
    const f = String(folder || '').toLowerCase();
    if (f.includes('server') || f.includes('vps') || f.includes('ssh') || f.includes('cloud') || f.includes('服务器') || f.includes('云')) {
      return 'server';
    }
    if (f.includes('token') || f.includes('api') || f.includes('key') || f.includes('密钥')) {
      return 'token';
    }
    if (hasTotp && !hasPassword) return 'totp';
    if (url || hasPassword) return 'web';
    return 'other';
  }

  function parsePasswordCSV(text) {
    const rows = parseCSVRows(text);
    if (rows.length < 2) return [];
    const headers = rows[0].map(function (h) {
      return String(h || '').trim().toLowerCase().replace(/[\s_-]+/g, '');
    });

    function findCol(candidates) {
      for (let i = 0; i < candidates.length; i++) {
        const idx = headers.indexOf(candidates[i]);
        if (idx >= 0) return idx;
      }
      return -1;
    }

    const idxTitle = findCol(['name', 'title', 'account', 'service']);
    const idxUrl = findCol(['url', 'website', 'loginuri', 'uri', 'origin', 'homepage']);
    const idxUser = findCol(['username', 'loginusername', 'user', 'email', 'login']);
    const idxPass = findCol(['password', 'loginpassword', 'pass']);
    const idxTotp = findCol(['logintotp', 'totp', 'otpauth', 'otp', '2fa', 'totpsecret']);
    const idxNotes = findCol(['note', 'notes', 'extra', 'comments', 'comment']);
    const idxFolder = findCol(['folder', 'group', 'category', 'vault']);
    const idxFav = findCol(['favorite', 'starred', 'fav']);

    if (idxTitle < 0 && idxUrl < 0 && idxUser < 0 && idxPass < 0 && idxTotp < 0) {
      throw new Error('unrecognized_csv');
    }

    const entries = [];
    for (let r = 1; r < rows.length; r++) {
      const cols = rows[r];
      const get = function (idx) { return idx >= 0 && idx < cols.length ? String(cols[idx] || '').trim() : ''; };
      const title = get(idxTitle);
      const url = get(idxUrl);
      const username = get(idxUser);
      const password = get(idxPass);
      const rawTotp = get(idxTotp);
      const notes = get(idxNotes);
      const folder = get(idxFolder);
      const favRaw = get(idxFav).toLowerCase();

      if (!title && !url && !username && !password && !rawTotp) continue;

      let totp = null;
      let issuer = '';
      if (rawTotp) {
        try {
          if (rawTotp.startsWith('otpauth://')) {
            const parsed = parseOtpAuthURI(rawTotp);
            totp = parsed.totp;
            issuer = parsed.issuer || '';
          } else if (VaultCrypto.isValidBase32(rawTotp)) {
            totp = {
              secret: VaultCrypto.normalizeBase32(rawTotp),
              algorithm: 'SHA-1',
              digits: 6,
              period: 30,
            };
          }
        } catch (_) {
          // Ignore malformed TOTP cell while preserving login row
        }
      }

      let derivedTitle = title;
      if (!derivedTitle && url) {
        try {
          derivedTitle = new URL(url.includes('://') ? url : 'https://' + url).hostname.replace(/^www\./, '');
        } catch (_) {
          derivedTitle = url;
        }
      }
      if (!derivedTitle) derivedTitle = username || 'Untitled';

      entries.push({
        title: derivedTitle,
        issuer: issuer || derivedTitle,
        username: username,
        password: password,
        url: url,
        notes: notes,
        category: guessCategory(folder, url, !!totp, !!password),
        favorite: favRaw === '1' || favRaw === 'true' || favRaw === 'yes',
        totp: totp,
      });
    }
    return entries;
  }

  return {
    parseOtpAuthURI: parseOtpAuthURI,
    buildOtpAuthURI: buildOtpAuthURI,
    parseGoogleMigrationURI: parseGoogleMigrationURI,
    parseAnyOtpText: parseAnyOtpText,
    parseCSVRows: parseCSVRows,
    parsePasswordCSV: parsePasswordCSV,
  };
});
