(function (root) {
  'use strict';

  const P = root.P2PProtocol;
  const DEFAULT_FALLBACK_ORIGIN = 'https://cloud.vs2010wy.top';
  const HIGH_WATER_MARK = 2 * 1024 * 1024; // 2 MiB
  const LOW_WATER_MARK = 512 * 1024; // 512 KiB
  const WS_PING_INTERVAL_MS = 25000;
  const STATS_INTERVAL_MS = 2500;

  function decodeTicketParentOrigin() {
    try {
      const search = typeof location !== 'undefined' ? location.search : '';
      if (!search) return '';
      const raw = new URLSearchParams(search).get('ticket');
      if (!raw) return '';
      const b64 = raw.replace(/-/g, '+').replace(/_/g, '/');
      const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4);
      const parsed = JSON.parse(atob(padded));
      if (parsed && typeof parsed.parent === 'string' && /^https?:\/\//i.test(parsed.parent)) {
        return new URL(parsed.parent).origin;
      }
    } catch (_) {}
    return '';
  }

  function detectSignalingBase(override) {
    const custom = typeof override === 'string' ? override.trim() : '';
    if (custom) {
      return custom.replace(/\/+$/, '');
    }
    const ticketParent = decodeTicketParentOrigin();
    if (ticketParent) {
      return ticketParent;
    }
    try {
      const base = document.baseURI || (typeof location !== 'undefined' ? location.href : '');
      if (base && /^https?:\/\//i.test(base)) {
        const u = new URL(base);
        // If running on an isolated tool-<hex>.<host> origin without ticket query, strip the sandbox prefix
        if (/^tool-[a-f0-9]{32}\./i.test(u.hostname)) {
          u.hostname = u.hostname.replace(/^tool-[a-f0-9]{32}\./i, '');
        }
        return u.origin;
      }
    } catch (_) {}
    return DEFAULT_FALLBACK_ORIGIN;
  }

  function toWsUrl(httpBase, configWsUrl) {
    if (configWsUrl && /^wss?:\/\//i.test(configWsUrl)) {
      return configWsUrl;
    }
    const base = httpBase.replace(/\/+$/, '');
    if (base.startsWith('https://')) {
      return 'wss://' + base.slice('https://'.length) + '/api/webrtc-signaling/ws';
    }
    if (base.startsWith('http://')) {
      return 'ws://' + base.slice('http://'.length) + '/api/webrtc-signaling/ws';
    }
    return base;
  }

  class P2PEngine {
    constructor(options) {
      this.options = Object.assign(
        {
          deviceName: P.defaultDeviceName(),
          deviceType: P.detectDeviceType(),
          autoAccept: true,
          signalingBase: '',
          onSignalingState: () => {},
          onPeersChanged: () => {},
          onTransferUpdate: () => {},
          onTransferIncoming: () => {},
          onClipboardMessage: () => {},
          onRoomClosed: () => {},
          onError: () => {},
        },
        options || {}
      );

      this.signalingConfig = null;
      this.signalingOrigin = detectSignalingBase(this.options.signalingBase);
      this.ws = null;
      this.wsPingTimer = null;
      this.statsTimer = null;

      this.role = null; // 'host' | 'guest'
      this.roomCode = '';
      this.roomId = '';
      this.selfPeerId = '';
      this.signalingState = 'idle'; // idle | connecting | ready | error | closed

      this.peers = new Map(); // peerId -> peer state
      this.transfers = new Map(); // transferId -> transfer state
      this.outgoingResolvers = new Map(); // transferId -> { resolve, reject }
      this.activeSends = new Set(); // transferIds currently streaming
    }

    setDeviceName(name) {
      this.options.deviceName = String(name || '').trim() || P.defaultDeviceName();
      for (const peer of this.peers.values()) {
        if (peer.dc && peer.dc.readyState === 'open') {
          this._sendControl(peer, {
            type: 'hello',
            name: this.options.deviceName,
            deviceType: this.options.deviceType,
            version: 1,
          });
        }
      }
    }

    setAutoAccept(enabled) {
      this.options.autoAccept = Boolean(enabled);
    }

    setSignalingBase(base) {
      this.options.signalingBase = String(base || '').trim();
      this.signalingOrigin = detectSignalingBase(this.options.signalingBase);
    }

    async fetchSignalingConfig() {
      const base = detectSignalingBase(this.options.signalingBase);
      this.signalingOrigin = base;
      const fallback = {
        enabled: true,
        iceServers: [
          { urls: ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302'] },
        ],
        maxPeers: 16,
        signalingUrl: toWsUrl(base, ''),
      };
      try {
        const url = base + '/api/webrtc-signaling/config';
        const resp = await fetch(url, { mode: 'cors', cache: 'no-store' });
        if (!resp.ok) {
          this.signalingConfig = fallback;
          return this.signalingConfig;
        }
        const cfg = await resp.json();
        if (cfg && cfg.enabled === false) {
          throw new Error('signaling_disabled');
        }
        this.signalingConfig = {
          enabled: true,
          iceServers:
            Array.isArray(cfg.ice_servers) && cfg.ice_servers.length
              ? cfg.ice_servers
              : fallback.iceServers,
          maxPeers: Number(cfg.max_peers) || 16,
          signalingUrl: toWsUrl(base, cfg.signaling_url),
        };
        return this.signalingConfig;
      } catch (err) {
        if (err && err.message === 'signaling_disabled') {
          throw err;
        }
        // Inside BookStark's opaque srcdoc sandbox iframe, HTTP fetch to /config may be blocked by CORS
        // while direct WebSocket upgrade to /api/webrtc-signaling/ws succeeds (Origin: null allowed).
        this.signalingConfig = fallback;
        return this.signalingConfig;
      }
    }

    async checkAvailability(roomId, peerId) {
      const base = detectSignalingBase(this.options.signalingBase);
      const q = new URLSearchParams({ room: roomId, peer: peerId });
      try {
        const resp = await fetch(base + '/api/webrtc-signaling/availability?' + q.toString(), {
          mode: 'cors',
          cache: 'no-store',
        });
        const data = await resp.json().catch(() => ({}));
        return { ok: resp.ok && Boolean(data.available), status: resp.status, data };
      } catch (_) {
        // Fallback: let the direct WebSocket upgrade validate room/peer availability
        return { ok: true, skipped: true, status: 0, data: {} };
      }
    }

    async createRoom(preferredCode) {
      this.disconnect(true);
      this._setSignalingState('connecting');
      const cfg = await this.fetchSignalingConfig();

      let lastErr = null;
      for (let attempt = 0; attempt < 3; attempt += 1) {
        const code =
          attempt === 0 && preferredCode ? P.normalizeRoomCode(preferredCode) : P.generateRoomCode();
        if (!code) continue;
        const roomId = P.toSignalingRoomId(code);
        const avail = await this.checkAvailability(roomId, 'host');
        if (!avail.ok && avail.data && avail.data.reason === 'peer_exists') {
          lastErr = new Error('room_code_in_use');
          continue;
        }
        if (!avail.ok && avail.data && avail.data.reason === 'disabled') {
          this._setSignalingState('error');
          throw new Error('signaling_disabled');
        }
        this.role = 'host';
        this.roomCode = code;
        this.roomId = roomId;
        this.selfPeerId = 'host';
        try {
          await this._connectWebSocket(cfg.signalingUrl, roomId, 'host');
          return { code, roomId, peerId: 'host', maxPeers: cfg.maxPeers };
        } catch (err) {
          lastErr = err;
          if (attempt < 2) continue;
        }
      }
      this._setSignalingState('error');
      throw lastErr || new Error('failed_to_create_room');
    }

    async joinRoom(rawCode) {
      const code = P.normalizeRoomCode(rawCode);
      if (!code) {
        throw new Error('invalid_room_code');
      }
      this.disconnect(false);
      this._setSignalingState('connecting');
      const cfg = await this.fetchSignalingConfig();

      const roomId = P.toSignalingRoomId(code);
      const peerId = P.generatePeerId();
      const avail = await this.checkAvailability(roomId, peerId);
      if (!avail.ok) {
        this._setSignalingState('error');
        const reason = (avail.data && avail.data.reason) || 'unavailable';
        const err = new Error(reason);
        err.code = reason;
        err.serverMessage = (avail.data && avail.data.message) || '';
        throw err;
      }

      this.role = 'guest';
      this.roomCode = code;
      this.roomId = roomId;
      this.selfPeerId = peerId;
      try {
        await this._connectWebSocket(cfg.signalingUrl, roomId, peerId);
      } catch (err) {
        if (avail.skipped) {
          const notFound = new Error('room_not_found');
          notFound.code = 'room_not_found';
          throw notFound;
        }
        throw err;
      }
      return { code, roomId, peerId, maxPeers: cfg.maxPeers };
    }

    disconnect(closeRoomIfHost) {
      if (this.wsPingTimer) {
        clearInterval(this.wsPingTimer);
        this.wsPingTimer = null;
      }
      if (this.statsTimer) {
        clearInterval(this.statsTimer);
        this.statsTimer = null;
      }

      for (const peerId of Array.from(this.peers.keys())) {
        this._removePeer(peerId);
      }

      if (this.ws) {
        try {
          if (closeRoomIfHost && this.role === 'host' && this.ws.readyState === WebSocket.OPEN) {
            this.ws.send(JSON.stringify({ type: 'close-room' }));
          }
          this.ws.onopen = null;
          this.ws.onmessage = null;
          this.ws.onerror = null;
          this.ws.onclose = null;
          this.ws.close();
        } catch (_) {}
        this.ws = null;
      }

      this.role = null;
      this.roomCode = '';
      this.roomId = '';
      this.selfPeerId = '';
      this._setSignalingState('idle');
      this._emitPeers();
    }

    _setSignalingState(state, detail) {
      this.signalingState = state;
      this.options.onSignalingState(state, detail || null);
    }

    _connectWebSocket(wsBaseUrl, roomId, peerId) {
      return new Promise((resolve, reject) => {
        const sep = wsBaseUrl.includes('?') ? '&' : '?';
        const url =
          wsBaseUrl +
          sep +
          'room=' +
          encodeURIComponent(roomId) +
          '&peer=' +
          encodeURIComponent(peerId);
        let settled = false;
        const ws = new WebSocket(url);
        this.ws = ws;

        const timeout = setTimeout(() => {
          if (!settled) {
            settled = true;
            try {
              ws.close();
            } catch (_) {}
            this._setSignalingState('error');
            reject(new Error('signaling_timeout'));
          }
        }, 12000);

        ws.onmessage = (event) => {
          let msg;
          try {
            msg = JSON.parse(event.data);
          } catch (_) {
            return;
          }
          if (msg.type === 'joined' && !settled) {
            settled = true;
            clearTimeout(timeout);
            this._setSignalingState('ready', { room: msg.room, peer: msg.peer });
            this._startTimers();
            resolve(msg);
            return;
          }
          this._handleSignalingMessage(msg);
        };

        ws.onerror = () => {
          if (!settled) {
            settled = true;
            clearTimeout(timeout);
            this._setSignalingState('error');
            reject(new Error('signaling_ws_error'));
          }
        };

        ws.onclose = (ev) => {
          clearTimeout(timeout);
          if (!settled) {
            settled = true;
            this._setSignalingState('error');
            reject(new Error('signaling_closed_' + (ev.code || 0)));
            return;
          }
          if (this.ws === ws) {
            this.ws = null;
            if (this.wsPingTimer) {
              clearInterval(this.wsPingTimer);
              this.wsPingTimer = null;
            }
            if (this.signalingState !== 'idle') {
              this._setSignalingState('closed', { code: ev.code, reason: ev.reason });
            }
          }
        };
      });
    }

    _startTimers() {
      if (this.wsPingTimer) clearInterval(this.wsPingTimer);
      this.wsPingTimer = setInterval(() => {
        if (this.ws && this.ws.readyState === WebSocket.OPEN) {
          try {
            this.ws.send(JSON.stringify({ type: 'ping' }));
          } catch (_) {}
        }
      }, WS_PING_INTERVAL_MS);

      if (this.statsTimer) clearInterval(this.statsTimer);
      this.statsTimer = setInterval(() => {
        for (const peer of this.peers.values()) {
          if (peer.pc && peer.state === 'connected') {
            this._refreshPeerStats(peer);
          }
        }
      }, STATS_INTERVAL_MS);
    }

    _sendSignal(toPeerId, payload) {
      if (!this.ws || this.ws.readyState !== WebSocket.OPEN) return;
      this.ws.send(JSON.stringify({ type: 'signal', to: toPeerId, payload }));
    }

    async _handleSignalingMessage(msg) {
      if (!msg || typeof msg !== 'object') return;
      if (msg.type === 'pong') return;

      if (msg.type === 'peer-joined') {
        const remoteId = msg.peer;
        if (!remoteId || remoteId === this.selfPeerId) return;
        const peer = this._ensurePeer(remoteId);
        // Deterministic offerer: 'host' always initiates offer; otherwise lexicographically smaller id
        const shouldOffer =
          this.selfPeerId === 'host' ||
          (remoteId !== 'host' && this.selfPeerId < remoteId);
        if (shouldOffer && !peer.offerSent) {
          peer.offerSent = true;
          await this._initiateOffer(peer);
        }
        return;
      }

      if (msg.type === 'peer-left') {
        if (msg.peer) {
          this._removePeer(msg.peer);
          this._emitPeers();
        }
        return;
      }

      if (msg.type === 'room-closed') {
        this.disconnect(false);
        this.options.onRoomClosed();
        return;
      }

      if (msg.type === 'signal' && msg.from && msg.payload) {
        await this._handleRemoteSignal(msg.from, msg.payload);
      }
    }

    _ensurePeer(peerId) {
      if (this.peers.has(peerId)) return this.peers.get(peerId);

      const iceServers =
        (this.signalingConfig && this.signalingConfig.iceServers) || [
          { urls: ['stun:stun.l.google.com:19302'] },
        ];
      const pc = new RTCPeerConnection({ iceServers });

      const peer = {
        id: peerId,
        name: peerId === 'host' ? 'Host Device' : 'Peer ' + peerId.slice(-4).toUpperCase(),
        deviceType: 'desktop',
        pc,
        dc: null,
        state: 'connecting', // connecting | connected | disconnected | failed
        iceMode: 'unknown', // lan | stun | relay | unknown
        iceCode: '',
        rttMs: null,
        encrypted: true,
        selected: true,
        offerSent: false,
        pendingCandidates: [],
      };

      pc.onicecandidate = (ev) => {
        if (ev.candidate) {
          this._sendSignal(peerId, { kind: 'ice', candidate: ev.candidate.toJSON() });
        }
      };

      pc.onconnectionstatechange = () => {
        const st = pc.connectionState;
        if (st === 'connected') {
          peer.state = peer.dc && peer.dc.readyState === 'open' ? 'connected' : 'connecting';
          this._refreshPeerStats(peer);
        } else if (st === 'failed' || st === 'disconnected' || st === 'closed') {
          peer.state = st === 'closed' ? 'disconnected' : st;
          this._abortPeerTransfers(peerId);
        }
        this._emitPeers();
      };

      pc.ondatachannel = (ev) => {
        this._attachDataChannel(peer, ev.channel);
      };

      this.peers.set(peerId, peer);
      this._emitPeers();
      return peer;
    }

    async _initiateOffer(peer) {
      try {
        const dc = peer.pc.createDataChannel('bookstark-p2p', { ordered: true });
        this._attachDataChannel(peer, dc);
        const offer = await peer.pc.createOffer();
        await peer.pc.setLocalDescription(offer);
        this._sendSignal(peer.id, { kind: 'sdp', description: peer.pc.localDescription });
      } catch (err) {
        this.options.onError(err);
      }
    }

    async _handleRemoteSignal(fromPeerId, payload) {
      const peer = this._ensurePeer(fromPeerId);
      try {
        if (payload.kind === 'sdp' && payload.description) {
          const desc = new RTCSessionDescription(payload.description);
          await peer.pc.setRemoteDescription(desc);
          // Flush queued ICE candidates
          while (peer.pendingCandidates.length) {
            const cand = peer.pendingCandidates.shift();
            try {
              await peer.pc.addIceCandidate(new RTCIceCandidate(cand));
            } catch (_) {}
          }
          if (desc.type === 'offer') {
            const answer = await peer.pc.createAnswer();
            await peer.pc.setLocalDescription(answer);
            this._sendSignal(fromPeerId, { kind: 'sdp', description: peer.pc.localDescription });
          }
        } else if (payload.kind === 'ice' && payload.candidate) {
          if (peer.pc.remoteDescription && peer.pc.remoteDescription.type) {
            await peer.pc.addIceCandidate(new RTCIceCandidate(payload.candidate));
          } else {
            peer.pendingCandidates.push(payload.candidate);
          }
        }
      } catch (err) {
        this.options.onError(err);
      }
    }

    _attachDataChannel(peer, dc) {
      peer.dc = dc;
      dc.binaryType = 'arraybuffer';
      try {
        dc.bufferedAmountLowThreshold = LOW_WATER_MARK;
      } catch (_) {}

      dc.onopen = () => {
        peer.state = 'connected';
        this._sendControl(peer, {
          type: 'hello',
          name: this.options.deviceName,
          deviceType: this.options.deviceType,
          version: 1,
        });
        this._refreshPeerStats(peer);
        this._emitPeers();
      };

      dc.onclose = () => {
        peer.state = 'disconnected';
        this._abortPeerTransfers(peer.id);
        this._emitPeers();
      };

      dc.onerror = () => {
        peer.state = 'failed';
        this._abortPeerTransfers(peer.id);
        this._emitPeers();
      };

      dc.onmessage = async (ev) => {
        try {
          if (typeof ev.data === 'string') {
            const msg = JSON.parse(ev.data);
            await this._handleControlMessage(peer, msg);
          } else {
            const ab = ev.data instanceof Blob ? await ev.data.arrayBuffer() : ev.data;
            this._handleBinaryChunk(peer, ab);
          }
        } catch (err) {
          this.options.onError(err);
        }
      };
    }

    async _refreshPeerStats(peer) {
      if (!peer.pc || typeof peer.pc.getStats !== 'function') return;
      try {
        const report = await peer.pc.getStats();
        let activePair = null;
        report.forEach((stat) => {
          if (
            stat.type === 'candidate-pair' &&
            (stat.nominated || stat.state === 'succeeded') &&
            (!activePair || stat.nominated)
          ) {
            activePair = stat;
          }
        });
        if (!activePair) return;

        const local = activePair.localCandidateId ? report.get(activePair.localCandidateId) : null;
        const remote = activePair.remoteCandidateId
          ? report.get(activePair.remoteCandidateId)
          : null;
        const candType =
          (local && local.candidateType) || (remote && remote.candidateType) || '';
        const info = P.classifyIceCandidate(candType);
        peer.iceMode = info.mode;
        peer.iceCode = info.code;
        if (typeof activePair.currentRoundTripTime === 'number') {
          peer.rttMs = Math.max(1, Math.round(activePair.currentRoundTripTime * 1000));
        }
        this._emitPeers();
      } catch (_) {}
    }

    _removePeer(peerId) {
      const peer = this.peers.get(peerId);
      if (!peer) return;
      this.peers.delete(peerId);
      this._abortPeerTransfers(peerId);
      try {
        if (peer.dc) peer.dc.close();
      } catch (_) {}
      try {
        if (peer.pc) peer.pc.close();
      } catch (_) {}
    }

    _abortPeerTransfers(peerId) {
      for (const tr of this.transfers.values()) {
        if (tr.peerId === peerId && (tr.status === 'pending' || tr.status === 'transferring' || tr.status === 'verifying')) {
          tr.status = 'failed';
          tr.error = 'peer_disconnected';
          this._emitTransfer(tr);
          const waiter = this.outgoingResolvers.get(tr.id);
          if (waiter) {
            this.outgoingResolvers.delete(tr.id);
            waiter.reject(new Error('peer_disconnected'));
          }
        }
      }
    }

    _sendControl(peer, obj) {
      if (!peer || !peer.dc || peer.dc.readyState !== 'open') return false;
      peer.dc.send(JSON.stringify(obj));
      return true;
    }

    getPeers() {
      return Array.from(this.peers.values()).map((p) => ({
        id: p.id,
        name: p.name,
        deviceType: p.deviceType,
        state: p.state,
        iceMode: p.iceMode,
        iceCode: p.iceCode,
        rttMs: p.rttMs,
        encrypted: p.encrypted,
        selected: p.selected,
      }));
    }

    togglePeerSelected(peerId, selected) {
      const peer = this.peers.get(peerId);
      if (!peer) return;
      peer.selected = selected != null ? Boolean(selected) : !peer.selected;
      this._emitPeers();
    }

    _emitPeers() {
      this.options.onPeersChanged(this.getPeers());
    }

    _emitTransfer(tr) {
      this.options.onTransferUpdate({
        id: tr.id,
        direction: tr.direction,
        peerId: tr.peerId,
        peerName: tr.peerName,
        name: tr.name,
        size: tr.size,
        mime: tr.mime,
        transferred: tr.transferred,
        progress: tr.size > 0 ? Math.min(1, tr.transferred / tr.size) : tr.status === 'done' ? 1 : 0,
        speed: tr.speed || 0,
        eta: tr.eta != null ? tr.eta : null,
        status: tr.status, // pending | awaiting_accept | transferring | verifying | done | rejected | cancelled | failed
        verified: tr.verified,
        sha256: tr.sha256 || '',
        error: tr.error || '',
        blobUrl: tr.blobUrl || '',
        createdAt: tr.createdAt,
      });
    }

    // ---- Clipboard ----
    sendClipboard(text) {
      const content = String(text || '');
      if (!content.trim()) return null;
      const connectedPeers = Array.from(this.peers.values()).filter(
        (p) => p.dc && p.dc.readyState === 'open'
      );
      if (!connectedPeers.length) {
        throw new Error('no_connected_peers');
      }
      const item = {
        id: P.generateTransferId(),
        text: content,
        ts: Date.now(),
        sender: this.options.deviceName,
        direction: 'out',
        recipients: connectedPeers.length,
      };
      for (const peer of connectedPeers) {
        this._sendControl(peer, {
          type: 'clipboard',
          id: item.id,
          text: item.text,
          ts: item.ts,
          sender: item.sender,
        });
      }
      this.options.onClipboardMessage(item);
      return item;
    }

    // ---- File Transfer ----
    async sendFiles(fileList, targetPeerIds) {
      const files = Array.from(fileList || []);
      if (!files.length) return [];

      let targets;
      if (Array.isArray(targetPeerIds) && targetPeerIds.length) {
        targets = targetPeerIds
          .map((id) => this.peers.get(id))
          .filter((p) => p && p.dc && p.dc.readyState === 'open');
      } else {
        const connected = Array.from(this.peers.values()).filter(
          (p) => p.dc && p.dc.readyState === 'open'
        );
        const selected = connected.filter((p) => p.selected);
        targets = selected.length ? selected : connected;
      }

      if (!targets.length) {
        throw new Error('no_connected_peers');
      }

      const promises = [];
      for (const file of files) {
        for (const peer of targets) {
          promises.push(this._sendFileToPeer(file, peer));
        }
      }
      return Promise.allSettled(promises);
    }

    async _sendFileToPeer(file, peer) {
      const id = P.generateTransferId();
      const chunkSize = P.DEFAULT_CHUNK_SIZE;
      const totalChunks = file.size === 0 ? 0 : Math.ceil(file.size / chunkSize);

      const tr = {
        id,
        direction: 'out',
        peerId: peer.id,
        peerName: peer.name,
        name: file.name || 'untitled',
        size: file.size || 0,
        mime: file.type || 'application/octet-stream',
        chunkSize,
        totalChunks,
        transferred: 0,
        speed: 0,
        eta: null,
        status: 'pending',
        verified: false,
        sha256: '',
        error: '',
        cancelled: false,
        createdAt: Date.now(),
      };
      this.transfers.set(id, tr);
      this._emitTransfer(tr);

      // Send offer & await acceptance
      const accepted = new Promise((resolve, reject) => {
        this.outgoingResolvers.set(id, { resolve, reject });
      });

      if (
        !this._sendControl(peer, {
          type: 'file-offer',
          id,
          name: tr.name,
          size: tr.size,
          mime: tr.mime,
          totalChunks,
          chunkSize,
        })
      ) {
        tr.status = 'failed';
        tr.error = 'channel_closed';
        this.outgoingResolvers.delete(id);
        this._emitTransfer(tr);
        return tr;
      }

      try {
        await accepted;
      } catch (err) {
        if (tr.status !== 'rejected' && tr.status !== 'cancelled') {
          tr.status = 'failed';
          tr.error = err.message || 'rejected';
          this._emitTransfer(tr);
        }
        return tr;
      }

      if (tr.cancelled) return tr;

      tr.status = 'transferring';
      this.activeSends.add(id);
      this._emitTransfer(tr);

      const startedAt = performance.now();
      let lastEmitAt = startedAt;
      let lastBytes = 0;

      try {
        // Compute SHA-256 of the source file (fast native WebCrypto)
        const shaPromise = P.sha256Hex(file);

        for (let seq = 0; seq < totalChunks; seq += 1) {
          if (tr.cancelled) {
            this._sendControl(peer, { type: 'file-cancel', id });
            tr.status = 'cancelled';
            this._emitTransfer(tr);
            return tr;
          }
          if (!peer.dc || peer.dc.readyState !== 'open') {
            throw new Error('channel_closed');
          }

          const start = seq * chunkSize;
          const end = Math.min(file.size, start + chunkSize);
          const sliceBuf = await file.slice(start, end).arrayBuffer();
          const frame = P.encodeChunkFrame(id, seq, new Uint8Array(sliceBuf));

          // Backpressure flow control
          if (peer.dc.bufferedAmount > HIGH_WATER_MARK) {
            await this._waitBufferLow(peer.dc, () => tr.cancelled);
          }
          if (tr.cancelled) {
            this._sendControl(peer, { type: 'file-cancel', id });
            tr.status = 'cancelled';
            this._emitTransfer(tr);
            return tr;
          }

          peer.dc.send(frame);
          tr.transferred = end;

          const now = performance.now();
          if (now - lastEmitAt >= 120 || seq === totalChunks - 1) {
            const elapsedSec = Math.max(0.001, (now - startedAt) / 1000);
            const deltaSec = Math.max(0.001, (now - lastEmitAt) / 1000);
            const instSpeed = (tr.transferred - lastBytes) / deltaSec;
            const avgSpeed = tr.transferred / elapsedSec;
            tr.speed = avgSpeed * 0.6 + instSpeed * 0.4;
            tr.eta = tr.speed > 0 ? Math.max(0, (tr.size - tr.transferred) / tr.speed) : null;
            lastEmitAt = now;
            lastBytes = tr.transferred;
            this._emitTransfer(tr);
          }
        }

        tr.status = 'verifying';
        this._emitTransfer(tr);

        const sha256 = await shaPromise;
        tr.sha256 = sha256;
        this._sendControl(peer, { type: 'file-complete', id, sha256 });
        this._emitTransfer(tr);
      } catch (err) {
        tr.status = 'failed';
        tr.error = err.message || 'send_failed';
        this._emitTransfer(tr);
      } finally {
        this.activeSends.delete(id);
      }
      return tr;
    }

    _waitBufferLow(dc, isCancelled) {
      return new Promise((resolve, reject) => {
        let done = false;
        const finish = (err) => {
          if (done) return;
          done = true;
          dc.removeEventListener('bufferedamountlow', onLow);
          clearInterval(poll);
          if (err) reject(err);
          else resolve();
        };
        const onLow = () => finish();
        dc.addEventListener('bufferedamountlow', onLow);
        const poll = setInterval(() => {
          if (isCancelled()) return finish(new Error('cancelled'));
          if (dc.readyState !== 'open') return finish(new Error('channel_closed'));
          if (dc.bufferedAmount <= LOW_WATER_MARK) finish();
        }, 40);
      });
    }

    acceptTransfer(transferId) {
      const tr = this.transfers.get(transferId);
      if (!tr || tr.direction !== 'in' || tr.status !== 'awaiting_accept') return;
      const peer = this.peers.get(tr.peerId);
      if (!peer || !peer.dc || peer.dc.readyState !== 'open') {
        tr.status = 'failed';
        tr.error = 'peer_disconnected';
        this._emitTransfer(tr);
        return;
      }
      tr.status = 'transferring';
      tr.startedAt = performance.now();
      tr.lastEmitAt = tr.startedAt;
      tr.lastBytes = 0;
      this._sendControl(peer, { type: 'file-accept', id: tr.id });
      this._emitTransfer(tr);
    }

    rejectTransfer(transferId) {
      const tr = this.transfers.get(transferId);
      if (!tr || tr.direction !== 'in') return;
      const peer = this.peers.get(tr.peerId);
      if (peer) {
        this._sendControl(peer, { type: 'file-reject', id: tr.id, reason: 'user_rejected' });
      }
      tr.status = 'rejected';
      tr.chunks = [];
      this._emitTransfer(tr);
    }

    cancelTransfer(transferId) {
      const tr = this.transfers.get(transferId);
      if (!tr) return;
      tr.cancelled = true;
      const peer = this.peers.get(tr.peerId);
      if (peer) {
        this._sendControl(peer, { type: 'file-cancel', id: tr.id });
      }
      const waiter = this.outgoingResolvers.get(transferId);
      if (waiter) {
        this.outgoingResolvers.delete(transferId);
        waiter.reject(new Error('cancelled'));
      }
      tr.status = 'cancelled';
      tr.chunks = [];
      this._emitTransfer(tr);
    }

    removeTransfer(transferId) {
      const tr = this.transfers.get(transferId);
      if (!tr) return;
      if (tr.blobUrl) {
        try {
          URL.revokeObjectURL(tr.blobUrl);
        } catch (_) {}
      }
      this.transfers.delete(transferId);
    }

    async _handleControlMessage(peer, msg) {
      if (!msg || typeof msg !== 'object') return;

      switch (msg.type) {
        case 'hello':
          if (msg.name) peer.name = String(msg.name).slice(0, 60);
          if (msg.deviceType) peer.deviceType = String(msg.deviceType);
          this._emitPeers();
          break;

        case 'clipboard':
          this.options.onClipboardMessage({
            id: msg.id || P.generateTransferId(),
            text: String(msg.text || ''),
            ts: Number(msg.ts) || Date.now(),
            sender: msg.sender || peer.name,
            peerId: peer.id,
            direction: 'in',
          });
          break;

        case 'file-offer': {
          const tr = {
            id: String(msg.id),
            direction: 'in',
            peerId: peer.id,
            peerName: peer.name,
            name: String(msg.name || 'file'),
            size: Math.max(0, Number(msg.size) || 0),
            mime: String(msg.mime || 'application/octet-stream'),
            totalChunks: Math.max(0, Number(msg.totalChunks) || 0),
            chunkSize: Number(msg.chunkSize) || P.DEFAULT_CHUNK_SIZE,
            chunks: [],
            receivedCount: 0,
            transferred: 0,
            speed: 0,
            eta: null,
            status: this.options.autoAccept ? 'transferring' : 'awaiting_accept',
            verified: false,
            sha256: '',
            error: '',
            blobUrl: '',
            startedAt: performance.now(),
            lastEmitAt: performance.now(),
            lastBytes: 0,
            createdAt: Date.now(),
          };
          this.transfers.set(tr.id, tr);
          this._emitTransfer(tr);
          if (this.options.autoAccept) {
            this._sendControl(peer, { type: 'file-accept', id: tr.id });
          } else {
            this.options.onTransferIncoming(tr);
          }
          break;
        }

        case 'file-accept': {
          const waiter = this.outgoingResolvers.get(msg.id);
          if (waiter) {
            this.outgoingResolvers.delete(msg.id);
            waiter.resolve();
          }
          break;
        }

        case 'file-reject': {
          const tr = this.transfers.get(msg.id);
          if (tr) {
            tr.status = 'rejected';
            this._emitTransfer(tr);
          }
          const waiter = this.outgoingResolvers.get(msg.id);
          if (waiter) {
            this.outgoingResolvers.delete(msg.id);
            waiter.reject(new Error('rejected'));
          }
          break;
        }

        case 'file-cancel': {
          const tr = this.transfers.get(msg.id);
          if (tr) {
            tr.cancelled = true;
            tr.status = 'cancelled';
            tr.chunks = [];
            this._emitTransfer(tr);
          }
          const waiter = this.outgoingResolvers.get(msg.id);
          if (waiter) {
            this.outgoingResolvers.delete(msg.id);
            waiter.reject(new Error('cancelled'));
          }
          break;
        }

        case 'file-complete': {
          const tr = this.transfers.get(msg.id);
          if (!tr || tr.direction !== 'in' || tr.cancelled) return;
          tr.status = 'verifying';
          this._emitTransfer(tr);

          try {
            const ordered = new Array(tr.totalChunks);
            for (let i = 0; i < tr.totalChunks; i += 1) {
              if (!tr.chunks[i]) {
                throw new Error('missing_chunk_' + i);
              }
              ordered[i] = tr.chunks[i];
            }
            const blob = new Blob(ordered, { type: tr.mime || 'application/octet-stream' });
            const computed = await P.sha256Hex(blob);
            const expected = String(msg.sha256 || '').toLowerCase();
            const ok = !expected || computed === expected;

            tr.sha256 = computed;
            tr.verified = ok;
            tr.chunks = []; // Free chunk references once Blob is created
            if (ok) {
              tr.blob = blob;
              tr.blobUrl = URL.createObjectURL(blob);
              tr.transferred = tr.size;
              tr.eta = 0;
              tr.status = 'done';
            } else {
              tr.status = 'failed';
              tr.error = 'sha256_mismatch';
            }
            this._sendControl(peer, {
              type: 'file-verified',
              id: tr.id,
              ok,
              sha256: computed,
            });
            this._emitTransfer(tr);
          } catch (err) {
            tr.status = 'failed';
            tr.error = err.message || 'verify_failed';
            this._sendControl(peer, {
              type: 'file-verified',
              id: tr.id,
              ok: false,
              sha256: '',
            });
            this._emitTransfer(tr);
          }
          break;
        }

        case 'file-verified': {
          const tr = this.transfers.get(msg.id);
          if (!tr || tr.direction !== 'out') return;
          if (msg.ok) {
            tr.verified = true;
            tr.status = 'done';
            tr.eta = 0;
          } else {
            tr.verified = false;
            tr.status = 'failed';
            tr.error = 'sha256_mismatch';
          }
          this._emitTransfer(tr);
          break;
        }

        default:
          break;
      }
    }

    _handleBinaryChunk(peer, arrayBuffer) {
      const frame = P.decodeChunkFrame(arrayBuffer);
      const tr = this.transfers.get(frame.id);
      if (!tr || tr.direction !== 'in' || tr.cancelled || tr.status !== 'transferring') {
        return;
      }
      if (!tr.chunks[frame.seq]) {
        tr.chunks[frame.seq] = frame.payload;
        tr.receivedCount += 1;
        tr.transferred += frame.payload.byteLength;
      }
      const now = performance.now();
      if (now - tr.lastEmitAt >= 120 || tr.receivedCount === tr.totalChunks) {
        const elapsedSec = Math.max(0.001, (now - tr.startedAt) / 1000);
        const deltaSec = Math.max(0.001, (now - tr.lastEmitAt) / 1000);
        const instSpeed = (tr.transferred - tr.lastBytes) / deltaSec;
        const avgSpeed = tr.transferred / elapsedSec;
        tr.speed = avgSpeed * 0.6 + instSpeed * 0.4;
        tr.eta = tr.speed > 0 ? Math.max(0, (tr.size - tr.transferred) / tr.speed) : null;
        tr.lastEmitAt = now;
        tr.lastBytes = tr.transferred;
        this._emitTransfer(tr);
      }
    }
  }

  root.P2PEngine = P2PEngine;
  root.P2PDetectSignalingBase = detectSignalingBase;
})(typeof globalThis !== 'undefined' ? globalThis : this);
