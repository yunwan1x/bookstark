'use strict';

var SHA256_CONSTANTS = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
]);

function rotateRight(value, bits) {
  return (value >>> bits) | (value << (32 - bits));
}

function SHA256() {
  this.state = new Uint32Array([
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
  ]);
  this.pending = new Uint8Array(64);
  this.pendingLength = 0;
  this.bytesHashed = 0;
}

SHA256.prototype.update = function (input) {
  var bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  var offset = 0;
  this.bytesHashed += bytes.length;
  while (offset < bytes.length) {
    var count = Math.min(64 - this.pendingLength, bytes.length - offset);
    this.pending.set(bytes.subarray(offset, offset + count), this.pendingLength);
    this.pendingLength += count;
    offset += count;
    if (this.pendingLength === 64) {
      this.process(this.pending);
      this.pendingLength = 0;
    }
  }
};

SHA256.prototype.process = function (block) {
  var words = new Uint32Array(64);
  var i;
  for (i = 0; i < 16; i += 1) {
    var offset = i * 4;
    words[i] = ((block[offset] << 24) | (block[offset + 1] << 16) |
      (block[offset + 2] << 8) | block[offset + 3]) >>> 0;
  }
  for (i = 16; i < 64; i += 1) {
    var a = words[i - 15];
    var b = words[i - 2];
    var s0 = rotateRight(a, 7) ^ rotateRight(a, 18) ^ (a >>> 3);
    var s1 = rotateRight(b, 17) ^ rotateRight(b, 19) ^ (b >>> 10);
    words[i] = (words[i - 16] + s0 + words[i - 7] + s1) >>> 0;
  }

  var h0 = this.state[0];
  var h1 = this.state[1];
  var h2 = this.state[2];
  var h3 = this.state[3];
  var h4 = this.state[4];
  var h5 = this.state[5];
  var h6 = this.state[6];
  var h7 = this.state[7];
  for (i = 0; i < 64; i += 1) {
    var upper = rotateRight(h4, 6) ^ rotateRight(h4, 11) ^ rotateRight(h4, 25);
    var choose = (h4 & h5) ^ (~h4 & h6);
    var temp1 = (h7 + upper + choose + SHA256_CONSTANTS[i] + words[i]) >>> 0;
    var lower = rotateRight(h0, 2) ^ rotateRight(h0, 13) ^ rotateRight(h0, 22);
    var majority = (h0 & h1) ^ (h0 & h2) ^ (h1 & h2);
    var temp2 = (lower + majority) >>> 0;
    h7 = h6;
    h6 = h5;
    h5 = h4;
    h4 = (h3 + temp1) >>> 0;
    h3 = h2;
    h2 = h1;
    h1 = h0;
    h0 = (temp1 + temp2) >>> 0;
  }
  this.state[0] = (this.state[0] + h0) >>> 0;
  this.state[1] = (this.state[1] + h1) >>> 0;
  this.state[2] = (this.state[2] + h2) >>> 0;
  this.state[3] = (this.state[3] + h3) >>> 0;
  this.state[4] = (this.state[4] + h4) >>> 0;
  this.state[5] = (this.state[5] + h5) >>> 0;
  this.state[6] = (this.state[6] + h6) >>> 0;
  this.state[7] = (this.state[7] + h7) >>> 0;
};

SHA256.prototype.hex = function () {
  var bitLength = this.bytesHashed * 8;
  var tailLength = this.pendingLength < 56 ? 64 : 128;
  var tail = new Uint8Array(tailLength);
  tail.set(this.pending.subarray(0, this.pendingLength));
  tail[this.pendingLength] = 0x80;
  var high = Math.floor(bitLength / 0x100000000);
  var low = bitLength >>> 0;
  var end = tail.length;
  tail[end - 8] = (high >>> 24) & 0xff;
  tail[end - 7] = (high >>> 16) & 0xff;
  tail[end - 6] = (high >>> 8) & 0xff;
  tail[end - 5] = high & 0xff;
  tail[end - 4] = (low >>> 24) & 0xff;
  tail[end - 3] = (low >>> 16) & 0xff;
  tail[end - 2] = (low >>> 8) & 0xff;
  tail[end - 1] = low & 0xff;
  for (var offset = 0; offset < tail.length; offset += 64) {
    this.process(tail.subarray(offset, offset + 64));
  }
  return Array.from(this.state).map(function (value) {
    return value.toString(16).padStart(8, '0');
  }).join('');
};

self.onmessage = async function (event) {
  try {
    var file = event.data.file;
    var chunkSize = event.data.chunkSize || (2 * 1024 * 1024);
    var hash = new SHA256();
    for (var offset = 0; offset < file.size; offset += chunkSize) {
      hash.update(new Uint8Array(await file.slice(offset, offset + chunkSize).arrayBuffer()));
      self.postMessage({ progress: Math.min(1, (offset + chunkSize) / Math.max(file.size, 1)) });
    }
    self.postMessage({ hash: hash.hex() });
  } catch (error) {
    self.postMessage({ error: String(error && error.message || error) });
  }
};
