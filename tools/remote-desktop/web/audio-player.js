/* BookStark Remote Desktop — Web Audio API RDPSND PCM Player (AudioWorklet + Autoplay Unlock) */
(function (global) {
  "use strict";

  class RdpAudioPlayer {
    constructor(callbacks = {}) {
      this.onVu = callbacks.onVu || (() => {});
      this.onSuspended = callbacks.onSuspended || (() => {});
      this.onActive = callbacks.onActive || (() => {});
      this.ctx = null;
      this.node = null;
      this.ready = false;
      this.initPromise = null;
      this.muted = false;
      this.volume = 0.85;
      this.bufferMs = 80;
      this.lastFormatLabel = "";
      this.fallbackTime = 0;
      this.useFallback = false;
    }

    async ensureInit() {
      if (this.ready) return true;
      if (this.initPromise) return this.initPromise;
      this.initPromise = (async () => {
        const AC = global.AudioContext || global.webkitAudioContext;
        if (!AC) return false;
        this.ctx = new AC({ latencyHint: "interactive" });
        this.ctx.onstatechange = () => {
          if (this.ctx && this.ctx.state === "running") this.onActive();
          else if (this.ctx && this.ctx.state === "suspended") this.onSuspended();
        };

        if (this.ctx.audioWorklet) {
          try {
            // Load via fetch -> Blob URL so it works cleanly inside BookStark opaque srcdoc iframes
            const resp = await fetch("audio-worklet.js");
            const code = await resp.text();
            const blobUrl = URL.createObjectURL(new Blob([code], { type: "application/javascript" }));
            try {
              await this.ctx.audioWorklet.addModule(blobUrl);
            } finally {
              setTimeout(() => URL.revokeObjectURL(blobUrl), 5000);
            }
            this.node = new AudioWorkletNode(this.ctx, "rdp-audio-processor", {
              numberOfInputs: 0,
              numberOfOutputs: 1,
              outputChannelCount: [2],
              processorOptions: { bufferMs: this.bufferMs },
            });
            this.node.port.onmessage = (ev) => {
              if (ev.data && ev.data.type === "vu") {
                this.onVu(ev.data.left, ev.data.right, ev.data.bufferedMs);
              }
            };
            this.node.connect(this.ctx.destination);
            this.syncConfig();
            this.ready = true;
            return true;
          } catch (_) {
            // Graceful fallback to AudioBufferSource scheduling
            this.useFallback = true;
            this.ready = true;
            return true;
          }
        }
        this.useFallback = true;
        this.ready = true;
        return true;
      })();
      return this.initPromise;
    }

    async unlock() {
      await this.ensureInit();
      if (this.ctx && this.ctx.state !== "running") {
        await this.ctx.resume();
      }
      if (this.ctx && this.ctx.state === "running") {
        this.onActive();
      }
    }

    setMuted(muted) {
      this.muted = !!muted;
      this.syncConfig();
    }

    setVolume(vol01) {
      this.volume = Math.max(0, Math.min(1, Number(vol01) || 0));
      this.syncConfig();
    }

    setBufferMs(ms) {
      this.bufferMs = Math.max(20, Math.min(400, Number(ms) || 80));
      this.syncConfig();
    }

    syncConfig() {
      if (this.node && this.node.port) {
        this.node.port.postMessage({
          type: "config",
          muted: this.muted,
          gain: this.volume,
          bufferMs: this.bufferMs,
        });
      }
    }

    async feedPcm(sampleRate, channels, bitsPerSample, buffer) {
      if (this.muted) return;
      const ok = await this.ensureInit();
      if (!ok || !this.ctx) return;

      if (this.ctx.state === "suspended") {
        this.onSuspended();
        return;
      }

      const bytes = new Uint8Array(buffer);
      const ch = channels === 1 ? 1 : 2;
      const bps = bitsPerSample === 8 ? 1 : 2;
      const frameBytes = ch * bps;
      const srcFrames = Math.floor(bytes.byteLength / frameBytes);
      if (srcFrames <= 0) return;

      const srcL = new Float32Array(srcFrames);
      const srcR = new Float32Array(srcFrames);
      const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);

      if (bps === 2) {
        for (let i = 0; i < srcFrames; i++) {
          const off = i * frameBytes;
          const l = view.getInt16(off, true) / 32768;
          const r = ch === 2 ? view.getInt16(off + 2, true) / 32768 : l;
          srcL[i] = l;
          srcR[i] = r;
        }
      } else {
        for (let i = 0; i < srcFrames; i++) {
          const off = i * frameBytes;
          const l = (bytes[off] - 128) / 128;
          const r = ch === 2 ? (bytes[off + 1] - 128) / 128 : l;
          srcL[i] = l;
          srcR[i] = r;
        }
      }

      const targetRate = this.ctx.sampleRate;
      const { left, right } =
        sampleRate === targetRate
          ? { left: srcL, right: srcR }
          : resampleLinear(srcL, srcR, sampleRate, targetRate);

      if (this.node && !this.useFallback) {
        this.node.port.postMessage(
          { type: "pcm", left, right },
          [left.buffer, right.buffer]
        );
      } else {
        // Fallback BufferSource playback
        const audioBuf = this.ctx.createBuffer(2, left.length, targetRate);
        audioBuf.copyToChannel(left, 0);
        audioBuf.copyToChannel(right, 1);
        const src = this.ctx.createBufferSource();
        const gain = this.ctx.createGain();
        gain.gain.value = this.muted ? 0 : this.volume;
        src.buffer = audioBuf;
        src.connect(gain);
        gain.connect(this.ctx.destination);
        const now = this.ctx.currentTime;
        if (this.fallbackTime < now || this.fallbackTime - now > 0.3) {
          this.fallbackTime = now + this.bufferMs / 1000;
        }
        src.start(this.fallbackTime);
        this.fallbackTime += audioBuf.duration;
      }
    }

    reset() {
      if (this.node && this.node.port) {
        this.node.port.postMessage({ type: "reset" });
      }
      this.fallbackTime = 0;
    }

    destroy() {
      this.reset();
      if (this.node) {
        try { this.node.disconnect(); } catch (_) {}
        this.node = null;
      }
      if (this.ctx) {
        try { this.ctx.close(); } catch (_) {}
        this.ctx = null;
      }
      this.ready = false;
      this.initPromise = null;
    }
  }

  function resampleLinear(srcL, srcR, srcRate, dstRate) {
    const ratio = srcRate / dstRate;
    const dstLen = Math.max(1, Math.round(srcL.length / ratio));
    const left = new Float32Array(dstLen);
    const right = new Float32Array(dstLen);
    for (let i = 0; i < dstLen; i++) {
      const pos = i * ratio;
      const idx = Math.floor(pos);
      const frac = pos - idx;
      const next = Math.min(idx + 1, srcL.length - 1);
      left[i] = srcL[idx] + (srcL[next] - srcL[idx]) * frac;
      right[i] = srcR[idx] + (srcR[next] - srcR[idx]) * frac;
    }
    return { left, right };
  }

  global.RdpAudioPlayer = RdpAudioPlayer;
})(window);
