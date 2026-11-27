/* BookStark Remote Desktop — Low-latency Ring-Buffer PCM AudioWorkletProcessor */
class RdpAudioProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const opts = (options && options.processorOptions) || {};
    this.targetBufferMs = opts.bufferMs || 80;
    this.maxSeconds = 1.2;
    this.capacity = Math.max(8192, Math.floor(sampleRate * this.maxSeconds));
    this.left = new Float32Array(this.capacity);
    this.right = new Float32Array(this.capacity);
    this.readPos = 0;
    this.writePos = 0;
    this.queued = 0;
    this.primed = false;
    this.muted = false;
    this.gain = 0.85;
    this.meterCounter = 0;
    this.peakL = 0;
    this.peakR = 0;

    this.port.onmessage = (event) => {
      const msg = event.data;
      if (!msg) return;
      if (msg.type === "pcm") {
        this.pushPcm(msg.left, msg.right);
      } else if (msg.type === "config") {
        if (typeof msg.muted === "boolean") this.muted = msg.muted;
        if (typeof msg.gain === "number") this.gain = Math.max(0, Math.min(1.5, msg.gain));
        if (typeof msg.bufferMs === "number") {
          this.targetBufferMs = Math.max(20, Math.min(400, msg.bufferMs));
        }
      } else if (msg.type === "reset") {
        this.readPos = 0;
        this.writePos = 0;
        this.queued = 0;
        this.primed = false;
      }
    };
  }

  pushPcm(lArr, rArr) {
    const len = lArr.length;
    if (!len) return;
    // Drop oldest audio if buffer exceeds 3x target latency to keep real-time sync
    const maxQueued = Math.max(
      Math.floor((sampleRate * this.targetBufferMs * 3) / 1000),
      4096
    );
    if (this.queued + len > maxQueued) {
      const drop = Math.min(this.queued, this.queued + len - Math.floor((sampleRate * this.targetBufferMs) / 1000));
      this.readPos = (this.readPos + drop) % this.capacity;
      this.queued -= drop;
    }
    for (let i = 0; i < len; i++) {
      if (this.queued >= this.capacity) {
        this.readPos = (this.readPos + 1) % this.capacity;
        this.queued--;
      }
      this.left[this.writePos] = lArr[i];
      this.right[this.writePos] = rArr ? rArr[i] : lArr[i];
      this.writePos = (this.writePos + 1) % this.capacity;
      this.queued++;
    }
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    if (!out || !out.length) return true;
    const outL = out[0];
    const outR = out.length > 1 ? out[1] : null;
    const frames = outL.length;

    const minPrime = Math.floor((sampleRate * this.targetBufferMs) / 1000);
    if (!this.primed) {
      if (this.queued >= minPrime) {
        this.primed = true;
      } else {
        outL.fill(0);
        if (outR) outR.fill(0);
        return true;
      }
    }

    if (this.queued < frames) {
      // Underrun: play whatever remains and re-prime cleanly
      for (let i = 0; i < frames; i++) {
        if (this.queued > 0) {
          const g = this.muted ? 0 : this.gain;
          const sl = this.left[this.readPos] * g;
          const sr = this.right[this.readPos] * g;
          this.readPos = (this.readPos + 1) % this.capacity;
          this.queued--;
          outL[i] = sl;
          if (outR) outR[i] = sr;
        } else {
          outL[i] = 0;
          if (outR) outR[i] = 0;
        }
      }
      this.primed = false;
    } else {
      const g = this.muted ? 0 : this.gain;
      for (let i = 0; i < frames; i++) {
        const sl = this.left[this.readPos] * g;
        const sr = this.right[this.readPos] * g;
        this.readPos = (this.readPos + 1) % this.capacity;
        this.queued--;
        outL[i] = sl;
        if (outR) outR[i] = sr;
        const al = Math.abs(sl);
        const ar = Math.abs(sr);
        if (al > this.peakL) this.peakL = al;
        if (ar > this.peakR) this.peakR = ar;
      }
    }

    this.meterCounter += frames;
    if (this.meterCounter >= 2048) {
      this.port.postMessage({
        type: "vu",
        left: this.peakL,
        right: this.peakR,
        bufferedMs: Math.round((this.queued / sampleRate) * 1000),
      });
      this.peakL = 0;
      this.peakR = 0;
      this.meterCounter = 0;
    }
    return true;
  }
}

registerProcessor("rdp-audio-processor", RdpAudioProcessor);
