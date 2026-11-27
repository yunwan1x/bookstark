'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');

const P = require('../web/p2p-protocol.js');

test('room code generation, normalization, and formatting', () => {
  for (let i = 0; i < 20; i += 1) {
    const code = P.generateRoomCode();
    assert.match(code, /^[1-9]\d{5}$/);
    assert.equal(P.formatRoomCode(code), code.slice(0, 3) + ' ' + code.slice(3));
    assert.equal(P.toSignalingRoomId(code), 'drop-' + code);
  }

  assert.equal(P.normalizeRoomCode('729 405'), '729405');
  assert.equal(P.normalizeRoomCode('729-405'), '729405');
  assert.equal(P.normalizeRoomCode('drop-729405'), '729405');
  assert.equal(P.normalizeRoomCode('DROP_729405'), '729405');
  assert.equal(P.normalizeRoomCode('{"room":"729405"}'), '729405');
  assert.equal(P.normalizeRoomCode('bookstark-p2p://join?room=729405'), '729405');
  assert.equal(P.normalizeRoomCode('https://cloud.vs2010wy.top/tools?room=drop-729405'), '729405');
  assert.equal(P.normalizeRoomCode('12345'), '');
  assert.equal(P.normalizeRoomCode('abcdef'), '');
});

test('pairing payload URI build and parse round-trip', () => {
  const uri1 = P.buildPairingPayload('729 405');
  assert.equal(uri1, 'bookstark-p2p://join?room=729405');
  assert.deepEqual(P.parsePairingPayload(uri1), { code: '729405', signalingBase: '' });

  const uri2 = P.buildPairingPayload('804123', 'https://cloud.vs2010wy.top');
  assert.equal(
    uri2,
    'bookstark-p2p://join?room=804123&sig=https%3A%2F%2Fcloud.vs2010wy.top'
  );
  assert.deepEqual(P.parsePairingPayload(uri2), {
    code: '804123',
    signalingBase: 'https://cloud.vs2010wy.top',
  });
});

test('peer ID and transfer ID conform to BookStark signaling rules', () => {
  for (let i = 0; i < 10; i += 1) {
    const peerId = P.generatePeerId();
    assert.match(peerId, /^[A-Za-z0-9_-]{3,96}$/);
    assert.notEqual(peerId, 'host');
    const trId = P.generateTransferId();
    assert.match(trId, /^t-[0-9a-f]{16}$/);
  }
});

test('binary chunk frame encode/decode round-trip and validation', () => {
  const payload = crypto.randomBytes(65536);
  const frame = P.encodeChunkFrame('t-abc123', 42, new Uint8Array(payload));
  const decoded = P.decodeChunkFrame(frame);

  assert.equal(decoded.id, 't-abc123');
  assert.equal(decoded.seq, 42);
  assert.equal(Buffer.compare(Buffer.from(decoded.payload), payload), 0);

  // Empty payload chunk
  const emptyFrame = P.encodeChunkFrame('t-empty', 0, new Uint8Array(0));
  const emptyDec = P.decodeChunkFrame(emptyFrame);
  assert.equal(emptyDec.id, 't-empty');
  assert.equal(emptyDec.seq, 0);
  assert.equal(emptyDec.payload.byteLength, 0);

  // Corrupt magic rejected
  const bad = new Uint8Array(frame);
  bad[0] = 0x00;
  assert.throws(() => P.decodeChunkFrame(bad), /bad magic/);

  // Truncated frame rejected
  assert.throws(() => P.decodeChunkFrame(new Uint8Array([0x42, 0x53])), /too short/);
});

test('chunked file reassembly and SHA-256 verification', async () => {
  const original = crypto.randomBytes(200 * 1024 + 37);
  const expectedHash = crypto.createHash('sha256').update(original).digest('hex');

  const chunkSize = P.DEFAULT_CHUNK_SIZE;
  const frames = [];
  for (let offset = 0, seq = 0; offset < original.length; offset += chunkSize, seq += 1) {
    const slice = original.subarray(offset, Math.min(original.length, offset + chunkSize));
    frames.push(P.encodeChunkFrame('t-file1', seq, new Uint8Array(slice)));
  }

  // Decode in reverse order to simulate out-of-order reassembly by seq
  const parts = new Array(frames.length);
  for (let i = frames.length - 1; i >= 0; i -= 1) {
    const dec = P.decodeChunkFrame(frames[i]);
    parts[dec.seq] = dec.payload;
  }

  const reassembled = P.concatChunks(parts, original.length);
  assert.equal(Buffer.compare(Buffer.from(reassembled), original), 0);

  const actualHash = await P.sha256Hex(reassembled);
  assert.equal(actualHash, expectedHash);

  // Known empty SHA-256 vector
  assert.equal(
    await P.sha256Hex(new Uint8Array(0)),
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
  );

  // Size mismatch throws
  assert.throws(() => P.concatChunks(parts, original.length + 1), /mismatch/);
});

test('formatters and ICE candidate classification', () => {
  assert.equal(P.formatBytes(0), '0 B');
  assert.equal(P.formatBytes(512), '512 B');
  assert.equal(P.formatBytes(1024), '1.00 KB');
  assert.equal(P.formatBytes(128.4 * 1024 * 1024), '128 MB');
  assert.equal(P.formatSpeed(64.2 * 1024 * 1024), '64.2 MB/s');
  assert.equal(P.formatEta(0.4), '< 1s');
  assert.equal(P.formatEta(65), '1:05');

  assert.deepEqual(P.classifyIceCandidate('host'), { mode: 'lan', code: 'host' });
  assert.deepEqual(P.classifyIceCandidate('srflx'), { mode: 'stun', code: 'srflx' });
  assert.deepEqual(P.classifyIceCandidate('relay'), { mode: 'relay', code: 'relay' });
  assert.equal(
    P.defaultDeviceName('Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/126.0.0.0'),
    'Mac · Chrome'
  );
  assert.equal(
    P.defaultDeviceName('Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/604.1'),
    'iPhone · Safari'
  );
});
