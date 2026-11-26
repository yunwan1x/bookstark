const test = require('node:test');
const assert = require('node:assert/strict');
const VaultCrypto = require('../web/vault-crypto.js');
const VaultImport = require('../web/vault-import.js');

// RFC 6238 Appendix B official test vector: ASCII "12345678901234567890" -> Base32 "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
const RFC_SHA1_SECRET = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

test('RFC 6238 TOTP SHA-1 official test vectors match exactly', async () => {
  assert.equal(
    await VaultCrypto.generateTOTP(RFC_SHA1_SECRET, {
      digits: 8,
      period: 30,
      algorithm: 'SHA-1',
      timestamp: 59 * 1000,
    }),
    '94287082'
  );
  assert.equal(
    await VaultCrypto.generateTOTP(RFC_SHA1_SECRET, {
      digits: 8,
      period: 30,
      algorithm: 'SHA-1',
      timestamp: 1111111109 * 1000,
    }),
    '07081804'
  );
  assert.equal(
    await VaultCrypto.generateTOTP(RFC_SHA1_SECRET, {
      digits: 6,
      period: 30,
      algorithm: 'SHA-1',
      timestamp: 1234567890 * 1000,
    }),
    '005924'
  );
});

test('Base32 encode/decode round-trips cleanly', () => {
  const raw = new Uint8Array([0x48, 0x65, 0x6c, 0x6c, 0x6f, 0x21, 0xde, 0xad, 0xbe, 0xef]);
  const b32 = VaultCrypto.base32Encode(raw);
  assert.deepEqual(VaultCrypto.base32Decode(b32), raw);
  assert.deepEqual(VaultCrypto.base32Decode('jbsw y3dp-ehpk 3pxp===='), VaultCrypto.base32Decode('JBSWY3DPEHPK3PXP'));
});

test('Frontend master password PBKDF2 + AES-256-GCM encrypt/decrypt and wrong password rejection', async () => {
  const payload = {
    v: 1,
    entries: [
      { id: 'e1', title: 'GitHub', username: 'yunwan1x', password: 'super-secret-password', totp: { secret: 'JBSWY3DPEHPK3PXP', digits: 6, period: 30, algorithm: 'SHA-1' } },
    ],
  };

  // Use 100,000 iterations in test for speed while testing real PBKDF2 + AES-256-GCM
  const { envelope, key, meta } = await VaultCrypto.encryptVault(payload, 'MyMaster#2026', { iterations: 100000 });
  assert.equal(envelope.v, 1);
  assert.equal(envelope.cipher, 'AES-256-GCM');
  assert.equal(JSON.stringify(envelope).includes('super-secret-password'), false);
  assert.equal(JSON.stringify(envelope).includes('JBSWY3DPEHPK3PXP'), false);

  const decrypted = await VaultCrypto.decryptVault(envelope, 'MyMaster#2026');
  assert.deepEqual(decrypted.data, payload);

  await assert.rejects(
    () => VaultCrypto.decryptVault(envelope, 'WrongPassword!'),
    /wrong_password/
  );

  // Re-encrypting with derived key rotates IV every write
  const env2 = await VaultCrypto.encryptVaultWithKey(payload, key, meta);
  assert.notEqual(env2.iv, envelope.iv);
  const decrypted2 = await VaultCrypto.decryptVault(env2, 'MyMaster#2026');
  assert.deepEqual(decrypted2.data, payload);
});

test('Strong password generator respects constraints', () => {
  const p = VaultCrypto.generatePassword({ length: 24, upper: true, lower: true, digits: true, symbols: true });
  assert.equal(p.length, 24);
  assert.match(p, /[A-Z]/);
  assert.match(p, /[a-z]/);
  assert.match(p, /[0-9]/);
  assert.match(p, /[^A-Za-z0-9]/);
});

test('otpauth:// URI parsing and round-trip building', () => {
  const uri = 'otpauth://totp/GitHub:yunwan1x?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA256&digits=8&period=60';
  const entry = VaultImport.parseOtpAuthURI(uri);
  assert.equal(entry.title, 'GitHub');
  assert.equal(entry.issuer, 'GitHub');
  assert.equal(entry.username, 'yunwan1x');
  assert.equal(entry.totp.secret, 'JBSWY3DPEHPK3PXP');
  assert.equal(entry.totp.algorithm, 'SHA-256');
  assert.equal(entry.totp.digits, 8);
  assert.equal(entry.totp.period, 60);

  const rebuilt = VaultImport.buildOtpAuthURI(entry);
  const reparsed = VaultImport.parseOtpAuthURI(rebuilt);
  assert.deepEqual(reparsed.totp, entry.totp);
});

test('Google Authenticator otpauth-migration:// Protobuf decoding', () => {
  // Hand-encode a valid MigrationPayload with 2 OtpParameters (1 TOTP + 1 HOTP)
  function encodeVarint(n) {
    const out = [];
    while (n > 0x7f) {
      out.push((n & 0x7f) | 0x80);
      n = Math.floor(n / 128);
    }
    out.push(n & 0x7f);
    return out;
  }
  function fieldBytes(num, bytes) {
    return [...encodeVarint((num << 3) | 2), ...encodeVarint(bytes.length), ...bytes];
  }
  function fieldVarint(num, val) {
    return [...encodeVarint((num << 3) | 0), ...encodeVarint(val)];
  }
  const enc = new TextEncoder();
  const secretBytes = Array.from(VaultCrypto.base32Decode('JBSWY3DPEHPK3PXP'));
  const otp1 = [
    ...fieldBytes(1, secretBytes),
    ...fieldBytes(2, Array.from(enc.encode('Cloudflare:admin@vs2010wy.top'))),
    ...fieldBytes(3, Array.from(enc.encode('Cloudflare'))),
    ...fieldVarint(4, 1), // SHA1
    ...fieldVarint(5, 1), // 6 digits
    ...fieldVarint(6, 2), // TOTP
  ];
  const otp2 = [
    ...fieldBytes(1, secretBytes),
    ...fieldBytes(2, Array.from(enc.encode('LegacyHOTP'))),
    ...fieldVarint(6, 1), // HOTP (should be skipped)
  ];
  const payloadBytes = new Uint8Array([
    ...fieldBytes(1, otp1),
    ...fieldBytes(1, otp2),
    ...fieldVarint(2, 1),
  ]);
  const uri = 'otpauth-migration://offline?data=' + encodeURIComponent(VaultCrypto.bytesToBase64(payloadBytes));
  const res = VaultImport.parseGoogleMigrationURI(uri);
  assert.equal(res.skippedHotp, 1);
  assert.equal(res.entries.length, 1);
  assert.equal(res.entries[0].issuer, 'Cloudflare');
  assert.equal(res.entries[0].username, 'admin@vs2010wy.top');
  assert.equal(res.entries[0].totp.secret, 'JBSWY3DPEHPK3PXP');
  assert.equal(res.entries[0].totp.digits, 6);
});

test('CSV import supports Chrome and Bitwarden formats with quoted commas and TOTP', () => {
  const csv = [
    'folder,favorite,type,name,notes,login_uri,login_username,login_password,login_totp',
    'Cloud,1,login,"VPS, 113","line1\nline2",https://cloud.vs2010wy.top,root,"p@ss""word",otpauth://totp/VPS:root?secret=JBSWY3DPEHPK3PXP&issuer=VPS',
    'Web,0,login,Example,,https://example.com,alice,secret123,',
  ].join('\r\n');

  const items = VaultImport.parsePasswordCSV(csv);
  assert.equal(items.length, 2);
  assert.equal(items[0].title, 'VPS, 113');
  assert.equal(items[0].category, 'server');
  assert.equal(items[0].favorite, true);
  assert.equal(items[0].password, 'p@ss"word');
  assert.equal(items[0].notes, 'line1\nline2');
  assert.equal(items[0].totp.secret, 'JBSWY3DPEHPK3PXP');
  assert.equal(items[1].title, 'Example');
  assert.equal(items[1].category, 'web');
  assert.equal(items[1].totp, null);
});
