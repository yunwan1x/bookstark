(function () {
  'use strict';

  const P = window.P2PProtocol;
  const Engine = window.P2PEngine;
  const detectSignalingBase = window.P2PDetectSignalingBase;

  const PREFS_KEY = 'bookstark_p2p_prefs_v1';

  const I18N = {
    zh: {
      appTitle: '极速快传',
      webrtcTag: 'WebRTC 点对点',
      appSubtitle: 'DTLS 端到端加密直传 · 文件不经服务器存储 · SHA-256 完整性校验',
      sigConnecting: '正在连接信令...',
      sigReady: '信令已就绪',
      sigConnectedCount: '已直连 {n} 台设备',
      sigError: '信令连接异常',
      sigClosed: '信令已断开',
      modeCreate: '创建房间',
      modeJoin: '加入房间',
      roomCodeLabel: '6 位配对取件码',
      copy: '复制',
      newRoom: '换码',
      createRoomHint: '在另一台设备打开极速快传，输入上方 6 位码或点击二维码扫码即可直连。',
      showQrBtn: '放大配对二维码',
      copyUriBtn: '复制配对串',
      joinCodeLabel: '输入对方 6 位取件码或粘贴配对串',
      joinPlaceholder: '例如：729 405',
      joinBtn: '连接',
      joinedRoomPrefix: '已加入房间',
      leaveBtn: '断开',
      scanQrBtn: '扫码 / 识别二维码图片',
      peersTitle: '已配对设备',
      peersEmptyTitle: '等待设备配对加入',
      peersEmptyDesc: '支持同一局域网满速直连，也支持跨网 NAT 穿透传输，最多 16 台设备同时在线。',
      transferTitle: '点对点文件传输',
      noTargetPeers: '配对设备后即可发送文件',
      targetPeersReady: '将发送至 {n} 台已选设备',
      clearDone: '清理已完成',
      dropzoneTitle: '拖拽任意文件到此处，或点击选择发送',
      dropzoneSub: '原文件无损直传 · 64 KB 流控分片 · 自动 SHA-256 校验 · 不限制文件类型',
      pickFiles: '选择文件',
      clipboardTitle: '实时共享剪贴板',
      clipboardHint: '发送文字、链接或代码片段，对方秒级同步',
      clipboardPlaceholder: '输入或粘贴文本、URL、命令，按 Ctrl+Enter 发送给已配对设备...',
      pasteBtn: '从剪贴板读取',
      sendTextBtn: '发送文本',
      clipboardEmpty: '暂无剪贴板消息。配对成功后，两端发送的文本会实时显示在这里。',
      qrModalTitle: '扫码配对房间',
      qrModalDesc: '在另一台设备打开本工具的「加入房间 → 扫码」，或直接输入上方 6 位取件码。',
      copyCode: '复制 6 位码',
      scanModalTitle: '扫码加入房间',
      scanPlaceholder: '可启动摄像头扫码，或上传/粘贴二维码截图自动识别',
      startCamera: '开启摄像头扫码',
      stopCamera: '停止摄像头',
      uploadQrImg: '选择二维码图片',
      settingsTitle: '传输与信令设置',
      deviceNameLabel: '本机设备名称',
      autoAcceptLabel: '自动接收发来的文件',
      autoAcceptSub: '关闭后，收到新文件需手动点击「接收」才会开始传输',
      autoDownloadLabel: '校验通过后自动弹出下载',
      autoDownloadSub: '关闭时保留在传输列表中，随时点击「保存文件」下载',
      signalingBaseLabel: '自定义信令服务器地址（可选）',
      cancel: '取消',
      save: '保存设置',
      iceLan: '局域网直连',
      iceStun: '公网穿透',
      iceRelay: '中继转发',
      iceConnecting: '建立直连中...',
      peerDisconnected: '已断开',
      dirOut: '发送给',
      dirIn: '来自',
      statusPending: '等待对方确认...',
      statusAwaitingAccept: '等待接收确认',
      statusTransferring: '传输中',
      statusVerifying: '正在校验 SHA-256...',
      statusDone: '传输完成',
      statusRejected: '已拒绝',
      statusCancelled: '已取消',
      statusFailed: '传输失败',
      shaVerified: 'SHA-256 校验通过',
      shaMismatch: 'SHA-256 校验不匹配',
      acceptBtn: '接收',
      rejectBtn: '拒绝',
      saveFileBtn: '保存文件',
      cancelBtn: '取消',
      removeBtn: '移除',
      etaPrefix: '剩余',
      toastCopied: '已复制到剪贴板',
      toastRoomRefreshed: '已生成新的 6 位配对房间码',
      toastJoined: '已加入房间 {code}，正在建立 WebRTC 直连...',
      toastLeft: '已断开当前房间',
      toastRoomClosed: '房主已关闭房间',
      toastNoPeers: '请先与至少一台设备完成配对连接',
      toastClipSent: '已同步至 {n} 台设备',
      toastSettingsSaved: '设置已保存',
      toastQrDetected: '识别成功，正在加入房间 {code}...',
      toastQrNotFound: '未在图片中识别到有效配对二维码',
      errInvalidCode: '请输入有效的 6 位数字取件码或配对串',
      errRoomNotFound: '房间不存在或房主已离开，请核对 6 位取件码',
      errRoomFull: '该房间已达到最大连接设备数上限',
      errSignalingDisabled: '当前站点未开启 WebRTC 信令服务',
      errSignalingGeneric: '无法连接信令服务，请检查网络或设置中的信令地址',
      errCameraDenied: '无法访问摄像头，可改用「选择二维码图片」识别',
      detectedSigPrefix: '当前自动检测地址：',
      sentLabel: '我发出',
      recvLabel: '收到',
    },
    en: {
      appTitle: 'Fast P2P Drop',
      webrtcTag: 'WebRTC P2P',
      appSubtitle: 'DTLS End-to-End Encrypted · Zero Server Storage · SHA-256 Verified',
      sigConnecting: 'Connecting signaling...',
      sigReady: 'Signaling Ready',
      sigConnectedCount: '{n} Peer(s) Connected',
      sigError: 'Signaling Error',
      sigClosed: 'Signaling Closed',
      modeCreate: 'Create Room',
      modeJoin: 'Join Room',
      roomCodeLabel: '6-Digit Pairing Code',
      copy: 'Copy',
      newRoom: 'New',
      createRoomHint: 'Open Fast P2P Drop on another device and enter the 6-digit code or scan the QR.',
      showQrBtn: 'Show Pairing QR',
      copyUriBtn: 'Copy URI',
      joinCodeLabel: 'Enter 6-digit code or paste pairing URI',
      joinPlaceholder: 'e.g. 729 405',
      joinBtn: 'Connect',
      joinedRoomPrefix: 'Joined Room',
      leaveBtn: 'Leave',
      scanQrBtn: 'Scan / Read QR Image',
      peersTitle: 'Paired Devices',
      peersEmptyTitle: 'Waiting for devices to pair',
      peersEmptyDesc: 'Direct LAN speed when on the same network, or STUN NAT traversal across networks (up to 16 peers).',
      transferTitle: 'P2P File Transfer',
      noTargetPeers: 'Pair a device to send files',
      targetPeersReady: 'Sending to {n} selected device(s)',
      clearDone: 'Clear Done',
      dropzoneTitle: 'Drag & drop files here, or click to select',
      dropzoneSub: 'Lossless direct transfer · 64 KB flow-controlled chunks · SHA-256 verified',
      pickFiles: 'Choose Files',
      clipboardTitle: 'Live Shared Clipboard',
      clipboardHint: 'Send text, URLs, or snippets across paired devices instantly',
      clipboardPlaceholder: 'Type or paste text, URL, or snippet (Ctrl+Enter to send)...',
      pasteBtn: 'Paste',
      sendTextBtn: 'Send Text',
      clipboardEmpty: 'No clipboard messages yet. Sent and received text appears here live.',
      qrModalTitle: 'Scan to Pair',
      qrModalDesc: 'Open Join Room -> Scan on another device, or enter the 6-digit code above.',
      copyCode: 'Copy 6-Digit Code',
      scanModalTitle: 'Scan Pairing QR',
      scanPlaceholder: 'Use camera or pick/paste a QR screenshot to join automatically',
      startCamera: 'Start Camera',
      stopCamera: 'Stop Camera',
      uploadQrImg: 'Upload QR Image',
      settingsTitle: 'Transfer & Signaling Settings',
      deviceNameLabel: 'This Device Name',
      autoAcceptLabel: 'Auto-accept incoming files',
      autoAcceptSub: 'When off, confirm each incoming file before transfer starts',
      autoDownloadLabel: 'Auto-download after SHA-256 verification',
      autoDownloadSub: 'When off, files stay in the list for manual download',
      signalingBaseLabel: 'Custom Signaling Server (Optional)',
      cancel: 'Cancel',
      save: 'Save',
      iceLan: 'LAN Direct',
      iceStun: 'NAT Traversal',
      iceRelay: 'Relay',
      iceConnecting: 'Connecting...',
      peerDisconnected: 'Disconnected',
      dirOut: 'To',
      dirIn: 'From',
      statusPending: 'Waiting for acceptance...',
      statusAwaitingAccept: 'Awaiting your confirmation',
      statusTransferring: 'Transferring',
      statusVerifying: 'Verifying SHA-256...',
      statusDone: 'Completed',
      statusRejected: 'Rejected',
      statusCancelled: 'Cancelled',
      statusFailed: 'Failed',
      shaVerified: 'SHA-256 Verified',
      shaMismatch: 'SHA-256 Mismatch',
      acceptBtn: 'Accept',
      rejectBtn: 'Reject',
      saveFileBtn: 'Save File',
      cancelBtn: 'Cancel',
      removeBtn: 'Remove',
      etaPrefix: 'ETA',
      toastCopied: 'Copied to clipboard',
      toastRoomRefreshed: 'Generated new 6-digit room code',
      toastJoined: 'Joined room {code}, establishing P2P connection...',
      toastLeft: 'Left room',
      toastRoomClosed: 'Host closed the room',
      toastNoPeers: 'Pair at least one device first',
      toastClipSent: 'Synced to {n} device(s)',
      toastSettingsSaved: 'Settings saved',
      toastQrDetected: 'QR recognized, joining room {code}...',
      toastQrNotFound: 'No valid pairing QR found in image',
      errInvalidCode: 'Please enter a valid 6-digit code or pairing URI',
      errRoomNotFound: 'Room not found or host left. Check the 6-digit code.',
      errRoomFull: 'Room is full',
      errSignalingDisabled: 'WebRTC signaling is disabled on this server',
      errSignalingGeneric: 'Unable to reach signaling server. Check network or settings.',
      errCameraDenied: 'Camera unavailable. Try uploading a QR image instead.',
      detectedSigPrefix: 'Auto-detected server: ',
      sentLabel: 'Sent',
      recvLabel: 'Received',
    },
  };

  function loadPrefs() {
    const defaults = {
      lang: (navigator.language || '').toLowerCase().startsWith('zh') ? 'zh' : 'en',
      deviceName: P.defaultDeviceName(),
      autoAccept: true,
      autoDownload: false,
      signalingBase: '',
    };
    try {
      const raw = localStorage.getItem(PREFS_KEY);
      if (raw) {
        return Object.assign(defaults, JSON.parse(raw));
      }
    } catch (_) {}
    return defaults;
  }

  function savePrefs(prefs) {
    try {
      localStorage.setItem(PREFS_KEY, JSON.stringify(prefs));
    } catch (_) {}
  }

  const prefs = loadPrefs();
  let mode = 'create'; // 'create' | 'join'
  let peers = [];
  let transfers = new Map();
  let clipboardItems = [];
  let maxPeers = 16;
  let toastTimer = null;
  let scanStream = null;
  let scanRaf = null;

  const $ = (id) => document.getElementById(id);

  function t(key, vars) {
    const dict = I18N[prefs.lang] || I18N.zh;
    let str = dict[key] || I18N.zh[key] || key;
    if (vars) {
      for (const [k, v] of Object.entries(vars)) {
        str = str.replace(new RegExp('\\{' + k + '\\}', 'g'), String(v));
      }
    }
    return str;
  }

  function esc(str) {
    return String(str == null ? '' : str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function showToast(msg, kind) {
    const el = $('toast');
    el.textContent = msg;
    el.className = 'p2p-toast' + (kind === 'error' ? ' is-error' : kind === 'success' ? ' is-success' : '');
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      el.hidden = true;
    }, 2800);
  }

  async function copyText(text) {
    if (!text) return false;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(text);
        return true;
      }
    } catch (_) {}
    try {
      const ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand('copy');
      ta.remove();
      return ok;
    } catch (_) {
      return false;
    }
  }

  function renderQrSvg(text) {
    if (typeof window.qrcode !== 'function' || !text) return '';
    const qr = window.qrcode(0, 'M');
    qr.addData(text);
    qr.make();
    return qr.createSvgTag({ scalable: true, margin: 2 });
  }

  function applyI18n() {
    document.documentElement.lang = prefs.lang === 'zh' ? 'zh-CN' : 'en';
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      if (key) el.textContent = t(key);
    });
    $('langBtn').textContent = prefs.lang === 'zh' ? 'EN' : '中文';
    $('joinCodeInput').placeholder = t('joinPlaceholder');
    $('clipboardInput').placeholder = t('clipboardPlaceholder');
    updateSignalingPill();
    renderPeers();
    renderTransfers();
    renderClipboard();
  }

  function updateSelfDeviceUI() {
    $('selfDeviceNameLabel').textContent = prefs.deviceName;
    const dtype = P.detectDeviceType();
    $('selfDeviceIcon').className =
      dtype === 'mobile'
        ? 'fa-solid fa-mobile-screen'
        : dtype === 'tablet'
          ? 'fa-solid fa-tablet-screen-button'
          : 'fa-solid fa-laptop';
  }

  const engine = new Engine({
    deviceName: prefs.deviceName,
    deviceType: P.detectDeviceType(),
    autoAccept: prefs.autoAccept,
    signalingBase: prefs.signalingBase,
    onSignalingState: () => {
      updateSignalingPill();
    },
    onPeersChanged: (nextPeers) => {
      peers = nextPeers;
      updateSignalingPill();
      renderPeers();
    },
    onTransferUpdate: (tr) => {
      const prev = transfers.get(tr.id);
      transfers.set(tr.id, tr);
      renderTransfers();
      if (
        tr.direction === 'in' &&
        tr.status === 'done' &&
        tr.verified &&
        tr.blobUrl &&
        (!prev || prev.status !== 'done') &&
        prefs.autoDownload
      ) {
        triggerDownload(tr.blobUrl, tr.name);
      }
    },
    onTransferIncoming: (tr) => {
      showToast((prefs.lang === 'zh' ? '收到文件请求：' : 'Incoming file: ') + tr.name);
    },
    onClipboardMessage: (item) => {
      clipboardItems.unshift(item);
      if (clipboardItems.length > 50) clipboardItems.length = 50;
      renderClipboard();
      if (item.direction === 'in') {
        showToast((prefs.lang === 'zh' ? '收到剪贴板：' : 'Clipboard from ') + item.sender);
      }
    },
    onRoomClosed: () => {
      showToast(t('toastRoomClosed'), 'error');
      $('joinedBanner').hidden = true;
      updateSignalingPill();
      renderPeers();
    },
    onError: (err) => {
      console.error('[p2p]', err);
    },
  });

  function updateSignalingPill() {
    const pill = $('signalingPill');
    const text = $('signalingPillText');
    const connectedCount = peers.filter((p) => p.state === 'connected').length;

    pill.className = 'status-pill';
    if (connectedCount > 0) {
      pill.classList.add('status-ready');
      text.textContent = t('sigConnectedCount', { n: connectedCount });
      return;
    }

    switch (engine.signalingState) {
      case 'ready':
        pill.classList.add('status-ready');
        text.textContent = t('sigReady');
        break;
      case 'connecting':
        pill.classList.add('status-connecting');
        text.textContent = t('sigConnecting');
        break;
      case 'error':
        pill.classList.add('status-error');
        text.textContent = t('sigError');
        break;
      case 'closed':
        pill.classList.add('status-error');
        text.textContent = t('sigClosed');
        break;
      default:
        text.textContent = t('sigConnecting');
        break;
    }
  }

  function updateRoomDisplay() {
    const code = engine.roomCode;
    const formatted = code ? P.formatRoomCode(code) : '--- ---';
    $('roomCodeValue').textContent = formatted;
    $('qrModalCode').textContent = formatted;
    if (code) {
      const payload = P.buildPairingPayload(code, prefs.signalingBase);
      const svg = renderQrSvg(payload);
      $('miniQrWrap').innerHTML = svg;
      $('qrModalSvgWrap').innerHTML = svg;
    } else {
      $('miniQrWrap').innerHTML = '';
      $('qrModalSvgWrap').innerHTML = '';
    }
  }

  function mapSignalingError(err) {
    const code = (err && (err.code || err.message)) || '';
    if (code === 'invalid_room_code') return t('errInvalidCode');
    if (code === 'room_not_found') return t('errRoomNotFound');
    if (code === 'room_full') return t('errRoomFull');
    if (code === 'signaling_disabled') return t('errSignalingDisabled');
    return t('errSignalingGeneric');
  }

  async function startCreateRoom() {
    mode = 'create';
    $('tabCreateBtn').classList.add('is-active');
    $('tabCreateBtn').setAttribute('aria-selected', 'true');
    $('tabJoinBtn').classList.remove('is-active');
    $('tabJoinBtn').setAttribute('aria-selected', 'false');
    $('createPane').hidden = false;
    $('joinPane').hidden = true;
    $('joinedBanner').hidden = true;
    $('joinError').hidden = true;

    try {
      const res = await engine.createRoom();
      maxPeers = res.maxPeers || 16;
      updateRoomDisplay();
      renderPeers();
    } catch (err) {
      updateRoomDisplay();
      showToast(mapSignalingError(err), 'error');
    }
  }

  function switchToJoinMode() {
    mode = 'join';
    $('tabJoinBtn').classList.add('is-active');
    $('tabJoinBtn').setAttribute('aria-selected', 'true');
    $('tabCreateBtn').classList.remove('is-active');
    $('tabCreateBtn').setAttribute('aria-selected', 'false');
    $('createPane').hidden = true;
    $('joinPane').hidden = false;
    $('joinError').hidden = true;
    if (engine.role === 'host') {
      engine.disconnect(true);
      updateRoomDisplay();
    }
    setTimeout(() => $('joinCodeInput').focus(), 40);
  }

  async function performJoin(rawInput) {
    const parsed = P.parsePairingPayload(rawInput);
    const code = parsed.code || P.normalizeRoomCode(rawInput);
    if (!code) {
      $('joinError').textContent = t('errInvalidCode');
      $('joinError').hidden = false;
      return;
    }
    $('joinError').hidden = true;

    if (parsed.signalingBase && parsed.signalingBase !== prefs.signalingBase) {
      engine.setSignalingBase(parsed.signalingBase);
    }

    $('joinSubmitBtn').disabled = true;
    try {
      const res = await engine.joinRoom(code);
      maxPeers = res.maxPeers || 16;
      $('joinCodeInput').value = P.formatRoomCode(code);
      $('joinedRoomCodeText').textContent = P.formatRoomCode(code);
      $('joinedBanner').hidden = false;
      showToast(t('toastJoined', { code: P.formatRoomCode(code) }), 'success');
      renderPeers();
    } catch (err) {
      $('joinedBanner').hidden = true;
      $('joinError').textContent = mapSignalingError(err);
      $('joinError').hidden = false;
    } finally {
      $('joinSubmitBtn').disabled = false;
    }
  }

  function renderPeers() {
    const connected = peers.filter((p) => p.state === 'connected');
    const selectedConnected = connected.filter((p) => p.selected);
    const targetCount = selectedConnected.length || connected.length;

    $('peerCountBadge').textContent = connected.length + ' / ' + maxPeers;
    $('targetPeersHint').textContent =
      targetCount > 0 ? t('targetPeersReady', { n: targetCount }) : t('noTargetPeers');

    if (!peers.length) {
      $('peersEmpty').hidden = false;
      $('peersList').hidden = true;
      $('peersList').innerHTML = '';
      return;
    }

    $('peersEmpty').hidden = true;
    $('peersList').hidden = false;

    const html = peers
      .map((peer) => {
        const devIcon =
          peer.deviceType === 'mobile'
            ? 'fa-mobile-screen'
            : peer.deviceType === 'tablet'
              ? 'fa-tablet-screen-button'
              : 'fa-laptop';

        let iceBadge = '';
        if (peer.state === 'connected') {
          if (peer.iceMode === 'lan') {
            iceBadge =
              '<span class="ice-badge ice-lan"><i class="fa-solid fa-bolt"></i> ' +
              esc(t('iceLan')) +
              '</span>';
          } else if (peer.iceMode === 'stun') {
            iceBadge =
              '<span class="ice-badge ice-stun"><i class="fa-solid fa-globe"></i> ' +
              esc(t('iceStun')) +
              '</span>';
          } else if (peer.iceMode === 'relay') {
            iceBadge =
              '<span class="ice-badge ice-relay"><i class="fa-solid fa-route"></i> ' +
              esc(t('iceRelay')) +
              '</span>';
          } else {
            iceBadge =
              '<span class="ice-badge ice-lan"><i class="fa-solid fa-link"></i> P2P</span>';
          }
        } else if (peer.state === 'connecting') {
          iceBadge = '<span class="ice-badge ice-connecting">' + esc(t('iceConnecting')) + '</span>';
        } else {
          iceBadge = '<span class="ice-badge ice-connecting">' + esc(t('peerDisconnected')) + '</span>';
        }

        const rttHtml = peer.rttMs != null ? '<span>' + esc(peer.rttMs) + ' ms</span>' : '';

        return (
          '<li class="peer-item ' +
          (peer.selected ? 'is-selected' : '') +
          '" data-peer-id="' +
          esc(peer.id) +
          '">' +
          '<input type="checkbox" class="peer-check" data-toggle-peer="' +
          esc(peer.id) +
          '" ' +
          (peer.selected ? 'checked' : '') +
          ' aria-label="' +
          esc(peer.name) +
          '" />' +
          '<span class="peer-avatar"><i class="fa-solid ' +
          devIcon +
          '"></i></span>' +
          '<div class="peer-info">' +
          '<div class="peer-name">' +
          esc(peer.name) +
          '</div>' +
          '<div class="peer-meta">' +
          iceBadge +
          rttHtml +
          '<span><i class="fa-solid fa-lock"></i> DTLS</span>' +
          '</div>' +
          '</div>' +
          '</li>'
        );
      })
      .join('');

    $('peersList').innerHTML = html;
  }

  function triggerDownload(blobUrl, filename) {
    const a = document.createElement('a');
    a.href = blobUrl;
    a.download = filename || 'download';
    document.body.appendChild(a);
    a.click();
    a.remove();
  }

  function renderTransfers() {
    const items = Array.from(transfers.values()).sort((a, b) => b.createdAt - a.createdAt);
    const hasDone = items.some((x) =>
      ['done', 'rejected', 'cancelled', 'failed'].includes(x.status)
    );
    $('clearDoneBtn').hidden = !hasDone;

    if (!items.length) {
      $('transfersWrap').hidden = true;
      $('transfersList').innerHTML = '';
      return;
    }

    $('transfersWrap').hidden = false;

    const html = items
      .map((tr) => {
        const pct = Math.round((tr.progress || 0) * 100);
        const isDone = tr.status === 'done';
        const isErr = ['failed', 'rejected', 'cancelled'].includes(tr.status);
        const dirClass = tr.direction === 'out' ? 'transfer-dir-out' : 'transfer-dir-in';
        const dirIcon = tr.direction === 'out' ? 'fa-arrow-up' : 'fa-arrow-down';
        const dirText =
          (tr.direction === 'out' ? t('dirOut') : t('dirIn')) + ' ' + (tr.peerName || tr.peerId);

        let statusText = t('statusTransferring');
        if (tr.status === 'pending') statusText = t('statusPending');
        else if (tr.status === 'awaiting_accept') statusText = t('statusAwaitingAccept');
        else if (tr.status === 'verifying') statusText = t('statusVerifying');
        else if (tr.status === 'done') statusText = t('statusDone');
        else if (tr.status === 'rejected') statusText = t('statusRejected');
        else if (tr.status === 'cancelled') statusText = t('statusCancelled');
        else if (tr.status === 'failed') statusText = t('statusFailed');

        let actionsHtml = '';
        if (tr.status === 'awaiting_accept' && tr.direction === 'in') {
          actionsHtml =
            '<button type="button" class="mini-btn mini-btn-primary" data-accept-tr="' +
            esc(tr.id) +
            '"><i class="fa-solid fa-check"></i> ' +
            esc(t('acceptBtn')) +
            '</button>' +
            '<button type="button" class="mini-btn mini-btn-danger" data-reject-tr="' +
            esc(tr.id) +
            '"><i class="fa-solid fa-xmark"></i> ' +
            esc(t('rejectBtn')) +
            '</button>';
        } else if (tr.status === 'pending' || tr.status === 'transferring') {
          actionsHtml =
            '<button type="button" class="mini-btn mini-btn-danger" data-cancel-tr="' +
            esc(tr.id) +
            '"><i class="fa-solid fa-xmark"></i> ' +
            esc(t('cancelBtn')) +
            '</button>';
        } else if (tr.status === 'done' && tr.direction === 'in' && tr.blobUrl) {
          actionsHtml =
            '<button type="button" class="mini-btn mini-btn-primary" data-download-tr="' +
            esc(tr.id) +
            '"><i class="fa-solid fa-download"></i> ' +
            esc(t('saveFileBtn')) +
            '</button>' +
            '<button type="button" class="mini-btn" data-remove-tr="' +
            esc(tr.id) +
            '" title="' +
            esc(t('removeBtn')) +
            '"><i class="fa-solid fa-trash"></i></button>';
        } else if (isDone || isErr) {
          actionsHtml =
            '<button type="button" class="mini-btn" data-remove-tr="' +
            esc(tr.id) +
            '" title="' +
            esc(t('removeBtn')) +
            '"><i class="fa-solid fa-trash"></i></button>';
        }

        let badgeHtml = '';
        if (tr.status === 'done' && tr.verified) {
          badgeHtml =
            '<span class="verified-badge" title="SHA-256: ' +
            esc(tr.sha256) +
            '"><i class="fa-solid fa-shield-halved"></i> ' +
            esc(t('shaVerified')) +
            '</span>';
        } else if (tr.error === 'sha256_mismatch') {
          badgeHtml =
            '<span class="error-badge"><i class="fa-solid fa-triangle-exclamation"></i> ' +
            esc(t('shaMismatch')) +
            '</span>';
        } else {
          badgeHtml = '<span>' + esc(statusText) + '</span>';
        }

        const speedStr =
          tr.status === 'transferring' && tr.speed > 0 ? P.formatSpeed(tr.speed) : '';
        const etaStr =
          tr.status === 'transferring' && tr.eta != null
            ? t('etaPrefix') + ' ' + P.formatEta(tr.eta)
            : '';

        return (
          '<li class="transfer-item" data-transfer-id="' +
          esc(tr.id) +
          '" data-status="' +
          esc(tr.status) +
          '">' +
          '<div class="transfer-top">' +
          '<div class="transfer-file-info">' +
          '<span class="transfer-dir-icon ' +
          dirClass +
          '"><i class="fa-solid ' +
          dirIcon +
          '"></i></span>' +
          '<div class="transfer-name-wrap">' +
          '<div class="transfer-name" title="' +
          esc(tr.name) +
          '">' +
          esc(tr.name) +
          '</div>' +
          '<div class="transfer-sub">' +
          '<span>' +
          esc(dirText) +
          '</span>' +
          '<span>' +
          esc(P.formatBytes(tr.transferred)) +
          ' / ' +
          esc(P.formatBytes(tr.size)) +
          '</span>' +
          '</div>' +
          '</div>' +
          '</div>' +
          '<div class="transfer-actions">' +
          actionsHtml +
          '</div>' +
          '</div>' +
          '<div class="progress-track">' +
          '<div class="progress-fill ' +
          (isDone ? 'is-done' : isErr ? 'is-error' : '') +
          '" style="width:' +
          pct +
          '%"></div>' +
          '</div>' +
          '<div class="transfer-bottom">' +
          '<div>' +
          badgeHtml +
          '</div>' +
          '<div class="transfer-metrics">' +
          '<span>' +
          pct +
          '%</span>' +
          (speedStr ? '<span>' + esc(speedStr) + '</span>' : '') +
          (etaStr ? '<span>' + esc(etaStr) + '</span>' : '') +
          '</div>' +
          '</div>' +
          '</li>'
        );
      })
      .join('');

    $('transfersList').innerHTML = html;
  }

  function linkifySafe(text) {
    const parts = String(text || '').split(/(https?:\/\/[^\s<>"']+)/g);
    return parts
      .map((part) => {
        if (/^https?:\/\//.test(part)) {
          const safe = esc(part);
          return '<a href="' + safe + '" target="_blank" rel="noopener noreferrer">' + safe + '</a>';
        }
        return esc(part);
      })
      .join('');
  }

  function formatTime(ts) {
    try {
      const d = new Date(ts);
      return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
    } catch (_) {
      return '';
    }
  }

  function renderClipboard() {
    if (!clipboardItems.length) {
      $('clipboardEmpty').hidden = false;
      $('clipboardList').hidden = true;
      $('clipboardList').innerHTML = '';
      return;
    }

    $('clipboardEmpty').hidden = true;
    $('clipboardList').hidden = false;

    const html = clipboardItems
      .map(
        (item) =>
          '<li class="clip-item" data-clip-id="' +
          esc(item.id) +
          '">' +
          '<div class="clip-head">' +
          '<span><span class="clip-sender">' +
          esc(item.direction === 'out' ? t('sentLabel') : item.sender) +
          '</span> · ' +
          esc(formatTime(item.ts)) +
          '</span>' +
          '<button type="button" class="mini-btn" data-copy-clip="' +
          esc(item.id) +
          '"><i class="fa-solid fa-copy"></i> ' +
          esc(t('copy')) +
          '</button>' +
          '</div>' +
          '<p class="clip-text">' +
          linkifySafe(item.text) +
          '</p>' +
          '</li>'
      )
      .join('');

    $('clipboardList').innerHTML = html;
  }

  async function handleFilesSelected(fileList) {
    if (!fileList || !fileList.length) return;
    try {
      await engine.sendFiles(fileList);
    } catch (err) {
      if (err && err.message === 'no_connected_peers') {
        showToast(t('toastNoPeers'), 'error');
      } else {
        showToast(String(err && err.message ? err.message : err), 'error');
      }
    }
  }

  // ---- QR Scanner ----
  function stopCameraScan() {
    if (scanRaf) {
      cancelAnimationFrame(scanRaf);
      scanRaf = null;
    }
    if (scanStream) {
      scanStream.getTracks().forEach((tr) => tr.stop());
      scanStream = null;
    }
    const video = $('scanVideo');
    video.srcObject = null;
    video.hidden = true;
    $('scanPlaceholder').hidden = false;
    $('startCameraBtn').querySelector('span').textContent = t('startCamera');
  }

  async function toggleCameraScan() {
    if (scanStream) {
      stopCameraScan();
      return;
    }
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      $('scanStatus').textContent = t('errCameraDenied');
      $('scanStatus').hidden = false;
      return;
    }
    try {
      scanStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
        audio: false,
      });
      const video = $('scanVideo');
      video.srcObject = scanStream;
      await video.play();
      video.hidden = false;
      $('scanPlaceholder').hidden = true;
      $('scanStatus').hidden = true;
      $('startCameraBtn').querySelector('span').textContent = t('stopCamera');

      const canvas = $('scanCanvas');
      const ctx = canvas.getContext('2d', { willReadFrequently: true });

      const tick = () => {
        if (!scanStream) return;
        if (video.readyState >= 2 && video.videoWidth > 0 && typeof window.jsQR === 'function') {
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const img = ctx.getImageData(0, 0, canvas.width, canvas.height);
          const hit = window.jsQR(img.data, img.width, img.height);
          if (hit && hit.data) {
            const parsed = P.parsePairingPayload(hit.data);
            if (parsed.code) {
              stopCameraScan();
              closeModal('scanModal');
              showToast(t('toastQrDetected', { code: P.formatRoomCode(parsed.code) }), 'success');
              performJoin(hit.data);
              return;
            }
          }
        }
        scanRaf = requestAnimationFrame(tick);
      };
      scanRaf = requestAnimationFrame(tick);
    } catch (_) {
      $('scanStatus').textContent = t('errCameraDenied');
      $('scanStatus').hidden = false;
    }
  }

  function decodeQrImageFile(file) {
    if (!file || typeof window.jsQR !== 'function') return;
    const reader = new FileReader();
    reader.onload = () => {
      const img = new Image();
      img.onload = () => {
        const canvas = $('scanCanvas');
        canvas.width = img.naturalWidth || img.width;
        canvas.height = img.naturalHeight || img.height;
        const ctx = canvas.getContext('2d', { willReadFrequently: true });
        ctx.drawImage(img, 0, 0);
        const data = ctx.getImageData(0, 0, canvas.width, canvas.height);
        const hit = window.jsQR(data.data, data.width, data.height);
        if (hit && hit.data) {
          const parsed = P.parsePairingPayload(hit.data);
          if (parsed.code) {
            stopCameraScan();
            closeModal('scanModal');
            showToast(t('toastQrDetected', { code: P.formatRoomCode(parsed.code) }), 'success');
            performJoin(hit.data);
            return;
          }
        }
        $('scanStatus').textContent = t('toastQrNotFound');
        $('scanStatus').hidden = false;
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  }

  function openModal(id) {
    $(id).hidden = false;
  }

  function closeModal(id) {
    if (id === 'scanModal') stopCameraScan();
    $(id).hidden = true;
  }

  // ---- Event Wiring ----
  function bindEvents() {
    $('tabCreateBtn').addEventListener('click', () => {
      if (mode !== 'create') startCreateRoom();
    });
    $('tabJoinBtn').addEventListener('click', () => {
      if (mode !== 'join') switchToJoinMode();
    });

    $('copyCodeBtn').addEventListener('click', async () => {
      if (engine.roomCode && (await copyText(engine.roomCode))) {
        showToast(t('toastCopied'), 'success');
      }
    });
    $('qrModalCopyCodeBtn').addEventListener('click', async () => {
      if (engine.roomCode && (await copyText(engine.roomCode))) {
        showToast(t('toastCopied'), 'success');
      }
    });

    const copyUriHandler = async () => {
      if (!engine.roomCode) return;
      const uri = P.buildPairingPayload(engine.roomCode, prefs.signalingBase);
      if (await copyText(uri)) {
        showToast(t('toastCopied'), 'success');
      }
    };
    $('copyUriBtn').addEventListener('click', copyUriHandler);
    $('qrModalCopyUriBtn').addEventListener('click', copyUriHandler);

    $('refreshRoomBtn').addEventListener('click', async () => {
      await startCreateRoom();
      if (engine.roomCode) showToast(t('toastRoomRefreshed'));
    });

    $('openQrModalBtn').addEventListener('click', () => openModal('qrModal'));
    $('miniQrTrigger').addEventListener('click', () => openModal('qrModal'));

    $('joinForm').addEventListener('submit', (e) => {
      e.preventDefault();
      performJoin($('joinCodeInput').value);
    });

    $('leaveRoomBtn').addEventListener('click', () => {
      engine.disconnect(false);
      $('joinedBanner').hidden = true;
      showToast(t('toastLeft'));
    });

    $('openScanModalBtn').addEventListener('click', () => {
      $('scanStatus').hidden = true;
      openModal('scanModal');
    });
    $('startCameraBtn').addEventListener('click', toggleCameraScan);
    $('uploadQrImgBtn').addEventListener('click', () => $('qrImgFileInput').click());
    $('qrImgFileInput').addEventListener('change', (e) => {
      const f = e.target.files && e.target.files[0];
      if (f) decodeQrImageFile(f);
      e.target.value = '';
    });

    // Support pasting QR screenshot while scan modal is open
    window.addEventListener('paste', (e) => {
      if ($('scanModal').hidden) return;
      const items = (e.clipboardData && e.clipboardData.items) || [];
      for (const item of items) {
        if (item.type && item.type.startsWith('image/')) {
          const f = item.getAsFile();
          if (f) decodeQrImageFile(f);
          break;
        }
      }
    });

    // Peers checkbox toggle
    $('peersList').addEventListener('change', (e) => {
      const id = e.target && e.target.getAttribute('data-toggle-peer');
      if (id) engine.togglePeerSelected(id, e.target.checked);
    });

    // Dropzone & file picker
    const dropzone = $('dropzone');
    const fileInput = $('fileInput');
    $('pickFilesBtn').addEventListener('click', (e) => {
      e.stopPropagation();
      fileInput.click();
    });
    dropzone.addEventListener('click', () => fileInput.click());
    dropzone.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' || e.key === ' ') {
        e.preventDefault();
        fileInput.click();
      }
    });
    fileInput.addEventListener('change', (e) => {
      handleFilesSelected(e.target.files);
      e.target.value = '';
    });

    ['dragenter', 'dragover'].forEach((evName) => {
      dropzone.addEventListener(evName, (e) => {
        e.preventDefault();
        dropzone.classList.add('is-dragover');
      });
    });
    ['dragleave', 'drop'].forEach((evName) => {
      dropzone.addEventListener(evName, (e) => {
        e.preventDefault();
        dropzone.classList.remove('is-dragover');
      });
    });
    dropzone.addEventListener('drop', (e) => {
      const files = e.dataTransfer && e.dataTransfer.files;
      if (files && files.length) handleFilesSelected(files);
    });

    // Transfer item actions
    $('transfersList').addEventListener('click', (e) => {
      const btn = e.target.closest('button');
      if (!btn) return;
      const acceptId = btn.getAttribute('data-accept-tr');
      const rejectId = btn.getAttribute('data-reject-tr');
      const cancelId = btn.getAttribute('data-cancel-tr');
      const downloadId = btn.getAttribute('data-download-tr');
      const removeId = btn.getAttribute('data-remove-tr');

      if (acceptId) engine.acceptTransfer(acceptId);
      else if (rejectId) engine.rejectTransfer(rejectId);
      else if (cancelId) engine.cancelTransfer(cancelId);
      else if (downloadId) {
        const tr = transfers.get(downloadId);
        if (tr && tr.blobUrl) triggerDownload(tr.blobUrl, tr.name);
      } else if (removeId) {
        engine.removeTransfer(removeId);
        transfers.delete(removeId);
        renderTransfers();
      }
    });

    $('clearDoneBtn').addEventListener('click', () => {
      for (const [id, tr] of Array.from(transfers.entries())) {
        if (['done', 'rejected', 'cancelled', 'failed'].includes(tr.status)) {
          engine.removeTransfer(id);
          transfers.delete(id);
        }
      }
      renderTransfers();
    });

    // Shared Clipboard
    const sendClip = () => {
      const text = $('clipboardInput').value;
      if (!text.trim()) return;
      try {
        const item = engine.sendClipboard(text);
        if (item) {
          $('clipboardInput').value = '';
          showToast(t('toastClipSent', { n: item.recipients }), 'success');
        }
      } catch (err) {
        if (err && err.message === 'no_connected_peers') {
          showToast(t('toastNoPeers'), 'error');
        }
      }
    };

    $('clipboardForm').addEventListener('submit', (e) => {
      e.preventDefault();
      sendClip();
    });
    $('clipboardInput').addEventListener('keydown', (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault();
        sendClip();
      }
    });
    $('pasteClipboardBtn').addEventListener('click', async () => {
      try {
        if (navigator.clipboard && navigator.clipboard.readText) {
          const txt = await navigator.clipboard.readText();
          if (txt) $('clipboardInput').value = txt;
        }
      } catch (_) {}
    });
    $('clipboardList').addEventListener('click', async (e) => {
      const btn = e.target.closest('[data-copy-clip]');
      if (!btn) return;
      const id = btn.getAttribute('data-copy-clip');
      const item = clipboardItems.find((x) => x.id === id);
      if (item && (await copyText(item.text))) {
        showToast(t('toastCopied'), 'success');
      }
    });

    // Settings Modal
    const openSettings = () => {
      $('settingDeviceName').value = prefs.deviceName;
      $('settingAutoAccept').checked = Boolean(prefs.autoAccept);
      $('settingAutoDownload').checked = Boolean(prefs.autoDownload);
      $('settingSignalingBase').value = prefs.signalingBase || '';
      $('detectedSignalingHint').textContent = t('detectedSigPrefix') + detectSignalingBase('');
      openModal('settingsModal');
    };
    $('openSettingsBtn').addEventListener('click', openSettings);
    $('editDeviceBtn').addEventListener('click', openSettings);

    $('settingsForm').addEventListener('submit', async (e) => {
      e.preventDefault();
      const prevSig = prefs.signalingBase;
      prefs.deviceName = $('settingDeviceName').value.trim() || P.defaultDeviceName();
      prefs.autoAccept = $('settingAutoAccept').checked;
      prefs.autoDownload = $('settingAutoDownload').checked;
      prefs.signalingBase = $('settingSignalingBase').value.trim().replace(/\/+$/, '');
      savePrefs(prefs);

      engine.setDeviceName(prefs.deviceName);
      engine.setAutoAccept(prefs.autoAccept);
      engine.setSignalingBase(prefs.signalingBase);
      updateSelfDeviceUI();
      closeModal('settingsModal');
      showToast(t('toastSettingsSaved'), 'success');

      if (prevSig !== prefs.signalingBase && mode === 'create') {
        await startCreateRoom();
      }
    });

    // Modal closing
    document.querySelectorAll('[data-close-modal]').forEach((btn) => {
      btn.addEventListener('click', () => closeModal(btn.getAttribute('data-close-modal')));
    });
    document.querySelectorAll('.modal-backdrop').forEach((bg) => {
      bg.addEventListener('click', (e) => {
        if (e.target === bg) closeModal(bg.id);
      });
    });
    window.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        ['qrModal', 'scanModal', 'settingsModal'].forEach((id) => {
          if (!$(id).hidden) closeModal(id);
        });
      }
    });

    // Language toggle
    $('langBtn').addEventListener('click', () => {
      prefs.lang = prefs.lang === 'zh' ? 'en' : 'zh';
      savePrefs(prefs);
      applyI18n();
    });

    // Clean close on page unload
    window.addEventListener('beforeunload', () => {
      engine.disconnect(engine.role === 'host');
    });
  }

  // ---- Init ----
  updateSelfDeviceUI();
  bindEvents();
  applyI18n();
  startCreateRoom();
})();
