(function () {
  'use strict';

  const VAULT_SECRET_NAME = 'vault-v1';
  const PREVIEW_STORAGE_KEY = 'bs_vault_preview_envelope_v1';
  const PREF_LANG_KEY = 'bs_vault_lang';
  const PREF_AUTOLOCK_KEY = 'bs_vault_autolock_min';
  const PREF_CLIPCLEAR_KEY = 'bs_vault_clipclear_sec';
  const RING_CIRCUMFERENCE = 2 * Math.PI * 24;

  const I18N = {
    zh: {
      appTitle: '密码箱 & 2FA',
      e2eeBadge: '前端零知识加密',
      setupTitle: '设置前端主密码',
      setupSubtitle:
        '密码箱在浏览器本地使用 PBKDF2-SHA256 与 AES-256-GCM 加密后同步至当前工作区，服务端不保存明文与主密码。',
      unlockTitle: '输入主密码解锁',
      unlockSubtitle: '数据已使用你的前端主密码加密。请输入主密码在本地内存中解密。',
      masterPasswordLabel: '主密码',
      confirmMasterLabel: '确认主密码',
      masterWarning:
        '主密码仅保留在当前浏览器内存中，无法通过服务端找回；忘记主密码将无法解密已有数据。',
      createVaultBtn: '创建并解锁密码箱',
      unlockBtn: '解锁密码箱',
      unlockingBtn: '正在派生密钥并解密…',
      creatingBtn: '正在加密初始化…',
      restoreFromFile: '从 .bsvault.json 加密备份恢复',
      newEntry: '新建条目',
      editEntry: '编辑条目',
      catAll: '全部条目',
      catHasTotp: '2FA 动态码',
      catFavorite: '收藏',
      catAudit: '安全体检',
      catWeb: '网站账号',
      catServer: '服务器 / 云',
      catToken: 'API Token',
      catTotpOnly: '仅 2FA',
      catNote: '安全笔记',
      catOther: '其他',
      pickCategoryLabel: '选择条目类型（表单字段自动切换）',
      fieldHost: '主机 IP / 域名',
      fieldPort: 'SSH 端口',
      fieldSshKey: 'SSH 私钥（可选，密文存储）',
      fieldKeyId: 'Key ID / AccessKey（可选）',
      fieldExpiresAt: '过期日期（可选，提前 14 天提醒）',
      fieldScope: '权限范围 / Scope（可选）',
      liveTotpPreview: '实时验证码预览',
      totpAdvParams: '高级参数（默认 SHA-1 / 6 位 / 30 秒）',
      customFieldsTitle: '自定义字段（支持密文遮罩）',
      addCustomField: '添加字段',
      clearNow: '立即清空',
      clipClearLabel: '复制敏感内容后自动清空剪贴板',
      clipClearText: '剪贴板将在 {s}s 后自动清空',
      clipCleared: '已清空剪贴板',
      issueWeak: '弱密码',
      issueReused: '重复密码',
      issueExpired: '已过期',
      issueExpiring: '剩 {d} 天过期',
      sshCmdLabel: 'SSH 快捷命令',
      noteBodyLabel: '加密正文',
      cfPlain: '明文',
      cfSecret: '密文',
      cfLabelPh: '字段名（如：恢复邮箱）',
      cfValPh: '字段值',
      quickCopyUser: '账号',
      quickCopyPwd: '密码',
      quickCopySsh: 'SSH',
      quickCopyToken: 'Token',
      totpValid: '✓ 密钥有效',
      totpInvalid: '密钥格式无效',
      optionalTotpTitle: '附加 2FA 动态验证码（可选）',
      serverNameLabel: '服务器名称 *',
      serverUserLabel: '登录用户名',
      serverPwdLabel: '登录密码 / 密钥口令',
      serverUrlLabel: '云控制台网址（可选）',
      tokenNameLabel: 'Token 名称 *',
      tokenIssuerLabel: '服务商',
      tokenUrlLabel: 'Endpoint / 控制台',
      tokenPwdLabel: 'Secret / Bearer Token',
      totpNameLabel: '服务名 / 名称 *',
      totpUserLabel: '账号标识（可选）',
      noteNameLabel: '笔记标题 *',
      noteTagLabel: '标签 / 说明（可选）',
      openSite: '打开',
      revealNote: '点击显示加密正文',
      hideNote: '隐藏正文',
      expiresValid: '有效期至 {date}',
      importTitle: '导入（二维码 / CSV）',
      importBtnShort: '扫码 / CSV 导入',
      securitySettings: '安全与备份',
      lockNow: '立即锁定',
      syncWorkspace: '工作区加密同步',
      syncPreview: '本机预览模式',
      searchPlaceholder: '搜索名称、账号、网址、备注…',
      emptyDetailTitle: '选择条目查看详情',
      emptyDetailDesc: '点击左侧条目查看实时 2FA 验证码与密码，或快速新建、导入已有数据。',
      emptyList: '当前分类暂无条目',
      cancel: '取消',
      save: '保存',
      edit: '编辑',
      delete: '删除',
      close: '关闭',
      copy: '复制',
      copied: '已复制到剪贴板',
      copyCode: '复制验证码',
      showQr: '显示二维码',
      fieldTitle: '名称 *',
      fieldCategory: '分类',
      fieldIssuer: '签发方 / 服务名',
      fieldUsername: '账号 / 邮箱',
      fieldPassword: '密码 / Token',
      genPassword: '生成强密码',
      genLength: '长度',
      applyGenerated: '生成并填入',
      fieldUrl: '网址',
      totpSection: '2FA 动态验证码（TOTP）',
      scanOrUploadQr: '识别二维码',
      fieldTotpSecret: '密钥（Base32 或直接粘贴 otpauth:// 链接）',
      fieldAlgo: '算法',
      fieldDigits: '位数',
      fieldPeriod: '周期 (秒)',
      fieldNotes: '备注 / 恢复码',
      markFavorite: '加入收藏置顶',
      tabQr: '二维码 / 2FA 链接',
      tabCsv: 'CSV 密码导入',
      tabBackup: '加密备份恢复',
      qrDropHint: '直接按 Ctrl+V 粘贴二维码截图、拖拽图片到这里，或点击下方按钮',
      pickQrImage: '选择二维码图片',
      startCamera: '摄像头扫码',
      stopCamera: '关闭摄像头',
      cameraScanning: '将二维码对准取景框，识别后自动停止…',
      qrSupportHint:
        '支持单个网站 otpauth:// 二维码，以及 Google Authenticator「导出账号」生成的批量迁移二维码。',
      otpTextLabel: '或直接粘贴 otpauth:// / otpauth-migration:// / Base32 密钥（支持多行）',
      parseText: '解析文本',
      csvDropHint: '选择从 Chrome / Edge / Bitwarden / 1Password / KeePass / iCloud 导出的 CSV 文件',
      pickCsvFile: '选择 CSV 文件',
      csvPasteLabel: '或粘贴 CSV 文本',
      parseCsv: '解析 CSV',
      backupSelectLabel: '选择 .bsvault.json 加密备份文件',
      backupPwdLabel: '该备份文件对应的主密码',
      decryptBackup: '解密并预览条目',
      skipDuplicates: '自动跳过完全重复项',
      confirmImport: '确认导入',
      exportQrTitle: '2FA 迁移二维码',
      exportQrHint: '使用手机任意 Authenticator（Google / 微软 / 1Password 等）扫码即可同步备份此 2FA。',
      copyOtpUri: '复制 otpauth 链接',
      autoLockSection: '无操作自动锁定',
      autoLockLabel: '空闲超过以下时长自动清空内存并锁定',
      changeMasterSection: '修改前端主密码',
      oldMasterLabel: '当前主密码',
      newMasterLabel: '新主密码（至少 6 位）',
      confirmNewMasterLabel: '确认新主密码',
      updateMasterBtn: '重新加密并更换主密码',
      backupSection: '加密备份（保持前端主密码加密，绝不明文落盘）',
      downloadEncBackup: '下载 .bsvault.json',
      saveWorkspaceBackup: '保存加密快照到工作区',
      strengthWeak: '较弱',
      strengthFair: '一般',
      strengthGood: '良好',
      strengthStrong: '很强',
      errPwdTooShort: '主密码至少需要 6 位字符。',
      errPwdMismatch: '两次输入的主密码不一致。',
      errWrongPwd: '主密码不正确，请重新输入。',
      errInvalidEnvelope: '加密数据格式损坏或不受支持。',
      errSaveFailed: '保存失败，请检查工作区权限或网络。',
      errInvalidSecret: '2FA 密钥格式无效（需为 Base32 或 otpauth:// 链接）。',
      errNoQrFound: '未在图片中识别到二维码，请确保截图清晰完整。',
      errCameraDenied: '无法打开摄像头，请检查浏览器授权或改用截图粘贴。',
      errNoEntriesParsed: '未解析到可导入的有效条目，请检查内容格式。',
      errSelectBackup: '请先选择 .bsvault.json 加密备份文件并输入其主密码。',
      msgSaved: '已加密保存',
      msgDeleted: '已删除条目',
      msgLocked: '密码箱已锁定',
      msgAutoLocked: '长时间无操作，已自动锁定密码箱',
      msgMasterChanged: '主密码已更新，数据已重新加密保存',
      msgSnapshotSaved: '加密快照已保存到工作区',
      msgBackupRestored: '已导入加密备份，请用备份的主密码解锁',
      msgImported: '成功导入 {n} 条记录',
      msgImportedSkipped: '成功导入 {n} 条，跳过 {s} 条重复项',
      confirmDelete: '确定删除「{title}」吗？删除后无法恢复（除非有备份）。',
      totpLiveLabel: 'TOTP 动态验证码（每 {p} 秒刷新）',
      securityFooter: '前端 AES-256-GCM + 工作区加密存储',
      updatedAt: '更新于',
      noSnapshots: '暂无工作区快照',
      previewSummary: '已解析 {n} 条记录（可立即导入）',
      previewHotpSkipped: '已解析 {n} 条 TOTP（跳过 {h} 条旧式计数器 HOTP）',
      backupSnapshotsUnavailable: '当前不在 BookStark 工作区文件权限内，仅支持本地下载备份。',
    },
    en: {
      appTitle: 'Vault & 2FA',
      e2eeBadge: 'Zero-Knowledge E2EE',
      setupTitle: 'Set Master Password',
      setupSubtitle:
        'Your vault is encrypted locally with PBKDF2-SHA256 & AES-256-GCM before syncing to your workspace. The server never sees plaintext or your master password.',
      unlockTitle: 'Unlock Vault',
      unlockSubtitle: 'Your vault is encrypted with your master password. Enter it to decrypt in memory.',
      masterPasswordLabel: 'Master password',
      confirmMasterLabel: 'Confirm master password',
      masterWarning:
        'Your master password lives only in memory and cannot be recovered by the server. If forgotten, existing encrypted data cannot be decrypted.',
      createVaultBtn: 'Create & Unlock Vault',
      unlockBtn: 'Unlock Vault',
      unlockingBtn: 'Deriving key & decrypting…',
      creatingBtn: 'Encrypting vault…',
      restoreFromFile: 'Restore from .bsvault.json encrypted backup',
      newEntry: 'New entry',
      editEntry: 'Edit entry',
      catAll: 'All items',
      catHasTotp: '2FA Codes',
      catFavorite: 'Favorites',
      catAudit: 'Security Audit',
      catWeb: 'Websites',
      catServer: 'Servers / Cloud',
      catToken: 'API Tokens',
      catTotpOnly: '2FA Only',
      catNote: 'Secure Notes',
      catOther: 'Other',
      pickCategoryLabel: 'Entry type (form adapts automatically)',
      fieldHost: 'Host IP / Domain',
      fieldPort: 'SSH Port',
      fieldSshKey: 'SSH Private Key (optional, encrypted)',
      fieldKeyId: 'Key ID / AccessKey (optional)',
      fieldExpiresAt: 'Expiration Date (warns 14d ahead)',
      fieldScope: 'Permissions / Scope (optional)',
      liveTotpPreview: 'Live Code Preview',
      totpAdvParams: 'Advanced (default SHA-1 / 6 digits / 30s)',
      customFieldsTitle: 'Custom Fields (supports secret masking)',
      addCustomField: 'Add field',
      clearNow: 'Clear now',
      clipClearLabel: 'Auto-clear clipboard after copying secrets',
      clipClearText: 'Clipboard clears in {s}s',
      clipCleared: 'Clipboard cleared',
      issueWeak: 'Weak password',
      issueReused: 'Reused password',
      issueExpired: 'Expired',
      issueExpiring: 'Expires in {d}d',
      sshCmdLabel: 'SSH Quick Command',
      noteBodyLabel: 'Encrypted Note Body',
      cfPlain: 'Plain',
      cfSecret: 'Secret',
      cfLabelPh: 'Field label',
      cfValPh: 'Value',
      quickCopyUser: 'User',
      quickCopyPwd: 'Pwd',
      quickCopySsh: 'SSH',
      quickCopyToken: 'Token',
      totpValid: '✓ Valid secret',
      totpInvalid: 'Invalid Base32',
      optionalTotpTitle: 'Attach 2FA Code (Optional)',
      serverNameLabel: 'Server Name *',
      serverUserLabel: 'Login Username',
      serverPwdLabel: 'Password / Passphrase',
      serverUrlLabel: 'Console URL (optional)',
      tokenNameLabel: 'Token Name *',
      tokenIssuerLabel: 'Provider',
      tokenUrlLabel: 'Endpoint / Console',
      tokenPwdLabel: 'Secret / Bearer Token',
      totpNameLabel: 'Service / Title *',
      totpUserLabel: 'Account Label (optional)',
      noteNameLabel: 'Note Title *',
      noteTagLabel: 'Tag / Subtitle (optional)',
      openSite: 'Open',
      revealNote: 'Click to reveal encrypted note',
      hideNote: 'Hide',
      expiresValid: 'Valid until {date}',
      importTitle: 'Import (QR / CSV)',
      importBtnShort: 'QR / CSV Import',
      securitySettings: 'Security & Backup',
      lockNow: 'Lock now',
      syncWorkspace: 'Workspace Encrypted Sync',
      syncPreview: 'Local Preview Mode',
      searchPlaceholder: 'Search title, account, URL, notes…',
      emptyDetailTitle: 'Select an item',
      emptyDetailDesc: 'Choose an item to view live 2FA codes and credentials, or create/import entries.',
      emptyList: 'No items in this view',
      cancel: 'Cancel',
      save: 'Save',
      edit: 'Edit',
      delete: 'Delete',
      close: 'Close',
      copy: 'Copy',
      copied: 'Copied to clipboard',
      copyCode: 'Copy code',
      showQr: 'Show QR',
      fieldTitle: 'Title *',
      fieldCategory: 'Category',
      fieldIssuer: 'Issuer / Service',
      fieldUsername: 'Account / Email',
      fieldPassword: 'Password / Token',
      genPassword: 'Generate strong',
      genLength: 'Length',
      applyGenerated: 'Generate & fill',
      fieldUrl: 'Website URL',
      totpSection: '2FA Verification Code (TOTP)',
      scanOrUploadQr: 'Scan / Upload QR',
      fieldTotpSecret: 'Secret (Base32 or paste otpauth:// URI)',
      fieldAlgo: 'Algorithm',
      fieldDigits: 'Digits',
      fieldPeriod: 'Period (s)',
      fieldNotes: 'Notes / Recovery codes',
      markFavorite: 'Pin to Favorites',
      tabQr: 'QR / 2FA URI',
      tabCsv: 'CSV Passwords',
      tabBackup: 'Encrypted Backup',
      qrDropHint: 'Press Ctrl+V to paste a QR screenshot, drop an image here, or choose below',
      pickQrImage: 'Choose QR Image',
      startCamera: 'Scan with Camera',
      stopCamera: 'Stop Camera',
      cameraScanning: 'Point camera at QR code. Scanning stops automatically…',
      qrSupportHint:
        'Supports standard otpauth:// QR codes and Google Authenticator batch export QR codes.',
      otpTextLabel: 'Or paste otpauth:// / otpauth-migration:// / Base32 secret (multi-line supported)',
      parseText: 'Parse text',
      csvDropHint: 'Select a CSV exported from Chrome / Edge / Bitwarden / 1Password / KeePass / iCloud',
      pickCsvFile: 'Choose CSV File',
      csvPasteLabel: 'Or paste CSV text',
      parseCsv: 'Parse CSV',
      backupSelectLabel: 'Choose .bsvault.json encrypted backup file',
      backupPwdLabel: 'Master password for this backup',
      decryptBackup: 'Decrypt & preview',
      skipDuplicates: 'Skip exact duplicates',
      confirmImport: 'Confirm Import',
      exportQrTitle: '2FA Migration QR Code',
      exportQrHint: 'Scan with any mobile Authenticator app to sync a backup of this 2FA.',
      copyOtpUri: 'Copy otpauth URI',
      autoLockSection: 'Auto-Lock Timer',
      autoLockLabel: 'Clear memory and lock automatically after inactivity',
      changeMasterSection: 'Change Master Password',
      oldMasterLabel: 'Current master password',
      newMasterLabel: 'New master password (min 6 chars)',
      confirmNewMasterLabel: 'Confirm new master password',
      updateMasterBtn: 'Re-encrypt with new password',
      backupSection: 'Encrypted Backups (always encrypted with your master password)',
      downloadEncBackup: 'Download .bsvault.json',
      saveWorkspaceBackup: 'Save snapshot to workspace',
      strengthWeak: 'Weak',
      strengthFair: 'Fair',
      strengthGood: 'Good',
      strengthStrong: 'Strong',
      errPwdTooShort: 'Master password must be at least 6 characters.',
      errPwdMismatch: 'Master passwords do not match.',
      errWrongPwd: 'Incorrect master password.',
      errInvalidEnvelope: 'Encrypted vault data is invalid or corrupted.',
      errSaveFailed: 'Failed to save vault. Check workspace permissions or connection.',
      errInvalidSecret: 'Invalid 2FA secret (expected Base32 or otpauth:// URI).',
      errNoQrFound: 'No QR code detected in the image. Try a clearer crop.',
      errCameraDenied: 'Could not access camera. Check permissions or paste a screenshot instead.',
      errNoEntriesParsed: 'No valid entries found in the input.',
      errSelectBackup: 'Select a .bsvault.json file and enter its master password.',
      msgSaved: 'Encrypted & saved',
      msgDeleted: 'Item deleted',
      msgLocked: 'Vault locked',
      msgAutoLocked: 'Vault locked automatically due to inactivity',
      msgMasterChanged: 'Master password updated and vault re-encrypted',
      msgSnapshotSaved: 'Encrypted snapshot saved to workspace',
      msgBackupRestored: 'Encrypted backup loaded. Enter its master password to unlock.',
      msgImported: 'Imported {n} item(s)',
      msgImportedSkipped: 'Imported {n} item(s), skipped {s} duplicate(s)',
      confirmDelete: 'Delete "{title}"? This cannot be undone without a backup.',
      totpLiveLabel: 'Live TOTP Code (refreshes every {p}s)',
      securityFooter: 'Frontend AES-256-GCM + Workspace Encrypted Storage',
      updatedAt: 'Updated',
      noSnapshots: 'No workspace snapshots yet',
      previewSummary: 'Parsed {n} item(s) ready to import',
      previewHotpSkipped: 'Parsed {n} TOTP item(s) ({h} legacy HOTP skipped)',
      backupSnapshotsUnavailable: 'Workspace file bridge unavailable; local encrypted download is still active.',
    },
  };

  let lang = 'zh';
  try {
    const saved = localStorage.getItem(PREF_LANG_KEY);
    if (saved === 'en' || saved === 'zh') lang = saved;
    else if (navigator.language && !navigator.language.toLowerCase().startsWith('zh')) lang = 'en';
  } catch (_) {}

  function t(key, vars) {
    let str = (I18N[lang] && I18N[lang][key]) || I18N.zh[key] || key;
    if (vars) {
      Object.keys(vars).forEach(function (k) {
        str = str.replace('{' + k + '}', String(vars[k]));
      });
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

  function safeHref(raw) {
    const s = String(raw || '').trim();
    if (!s) return '';
    try {
      const u = new URL(s.includes('://') ? s : 'https://' + s);
      if (u.protocol === 'https:' || u.protocol === 'http:') return u.href;
    } catch (_) {}
    return '';
  }

  function genId() {
    if (crypto.randomUUID) return crypto.randomUUID();
    const b = crypto.getRandomValues(new Uint8Array(12));
    return Array.from(b, function (x) { return x.toString(16).padStart(2, '0'); }).join('');
  }

  // Storage bridge (BookStark.secrets in installed runtime; localStorage fallback in standalone preview)
  function hasWorkspaceSecrets() {
    return !!(window.BookStark && window.BookStark.secrets && typeof window.BookStark.secrets.get === 'function');
  }
  function hasWorkspaceFiles() {
    return !!(window.BookStark && window.BookStark.files && typeof window.BookStark.files.write === 'function');
  }

  async function loadEncryptedEnvelope() {
    if (hasWorkspaceSecrets()) {
      const raw = await window.BookStark.secrets.get(VAULT_SECRET_NAME);
      return raw || null;
    }
    try {
      return localStorage.getItem(PREVIEW_STORAGE_KEY);
    } catch (_) {
      return null;
    }
  }

  async function saveEncryptedEnvelope(envelopeObj) {
    const raw = JSON.stringify(envelopeObj);
    if (hasWorkspaceSecrets()) {
      await window.BookStark.secrets.set(VAULT_SECRET_NAME, raw);
    } else {
      localStorage.setItem(PREVIEW_STORAGE_KEY, raw);
    }
    state.rawEnvelope = raw;
  }

  // In-memory sensitive state (wiped on lock)
  const state = {
    mode: 'loading', // 'setup' | 'unlock' | 'unlocked'
    rawEnvelope: null,
    derivedKey: null,
    cryptoMeta: null,
    vault: null, // { v: 1, entries: [...] }
    activeCategory: 'all',
    search: '',
    selectedId: null,
    editing: false,
    showDetailPassword: false,
    showDetailSshKey: false,
    showDetailNote: false,
    revealedCustomFields: Object.create(null),
    autoLockMinutes: 5,
    clipClearSeconds: 30,
    clipClearDeadline: 0,
    idleDeadline: 0,
    totpCache: Object.create(null), // entryId -> { slot, code }
    auditResult: { flaggedCount: 0, byId: Object.create(null) },
    formTotpOpen: false,
    formTotpAdvOpen: false,
    pendingImport: [],
    currentExportUri: '',
    cameraStream: null,
    cameraRaf: 0,
  };

  try {
    const m = localStorage.getItem(PREF_AUTOLOCK_KEY);
    if (m !== null && ['0', '1', '5', '15', '30'].includes(m)) {
      state.autoLockMinutes = Number(m);
    }
    const c = localStorage.getItem(PREF_CLIPCLEAR_KEY);
    if (c !== null && ['0', '30', '60'].includes(c)) {
      state.clipClearSeconds = Number(c);
    }
  } catch (_) {}

  const $ = function (id) { return document.getElementById(id); };
  let toastTimer = 0;

  function showToast(msg, isError) {
    const el = $('toast');
    el.textContent = msg;
    el.className = 'vault-toast' + (isError ? ' error' : '');
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.hidden = true; }, 2600);
  }

  function updateClipClearBanner() {
    const banner = $('clipClearBanner');
    if (!banner) return;
    if (!state.clipClearDeadline) {
      banner.hidden = true;
      return;
    }
    const rem = Math.max(0, Math.ceil((state.clipClearDeadline - Date.now()) / 1000));
    if (rem <= 0) {
      clearClipboardNow(false);
      return;
    }
    $('clipClearText').textContent = t('clipClearText', { s: rem });
    banner.hidden = false;
  }

  async function clearClipboardNow(notify) {
    state.clipClearDeadline = 0;
    const banner = $('clipClearBanner');
    if (banner) banner.hidden = true;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText('');
      }
    } catch (_) {}
    if (notify) showToast(t('clipCleared'));
  }

  async function copyText(text, isSensitive) {
    const val = String(text || '');
    if (!val) return;
    let ok = false;
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(val);
        ok = true;
      }
    } catch (_) {}
    if (!ok) {
      const ta = document.createElement('textarea');
      ta.value = val;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try {
        document.execCommand('copy');
        ok = true;
      } catch (_) {}
      ta.remove();
    }
    if (!ok) {
      showToast(t('errSaveFailed'), true);
      return;
    }
    showToast(t('copied'));
    if (isSensitive && state.clipClearSeconds > 0) {
      state.clipClearDeadline = Date.now() + state.clipClearSeconds * 1000;
      updateClipClearBanner();
    }
  }

  function applyI18n() {
    document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
    document.title = t('appTitle');
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      const key = el.getAttribute('data-i18n');
      if (key) el.textContent = t(key);
    });
    $('searchInput').placeholder = t('searchPlaceholder');
    $('langToggleBtn').textContent = lang === 'zh' ? 'EN' : '中文';
    $('lockLangBtn').textContent = lang === 'zh' ? 'EN' : '中文';
    $('syncStatusText').textContent = hasWorkspaceSecrets() ? t('syncWorkspace') : t('syncPreview');
    renderLockModeUI();
    if (state.mode === 'unlocked') {
      renderEntries();
      if (!state.editing && state.selectedId) renderDetailView();
    }
  }

  function toggleLang() {
    lang = lang === 'zh' ? 'en' : 'zh';
    try { localStorage.setItem(PREF_LANG_KEY, lang); } catch (_) {}
    applyI18n();
  }

  function renderLockModeUI() {
    const isSetup = state.mode === 'setup';
    $('lockTitle').textContent = isSetup ? t('setupTitle') : t('unlockTitle');
    $('lockSubtitle').textContent = isSetup ? t('setupSubtitle') : t('unlockSubtitle');
    $('confirmPasswordField').hidden = !isSetup;
    $('setupWarning').hidden = !isSetup;
    $('setupStrengthWrap').hidden = !isSetup;
    $('confirmMasterPassword').required = isSetup;
    $('lockSubmitText').textContent = isSetup ? t('createVaultBtn') : t('unlockBtn');
  }

  function updateStrengthMeter() {
    if (state.mode !== 'setup') return;
    const pwd = $('masterPassword').value;
    const info = VaultCrypto.passwordStrength(pwd);
    const fill = $('setupStrengthFill');
    const lbl = $('setupStrengthLabel');
    const widths = ['0%', '25%', '50%', '75%', '100%'];
    const colors = ['transparent', '#dc2626', '#d97706', '#2563eb', '#059669'];
    const labels = {
      empty: '',
      weak: t('strengthWeak'),
      fair: t('strengthFair'),
      good: t('strengthGood'),
      strong: t('strengthStrong'),
    };
    fill.style.width = widths[info.score];
    fill.style.background = colors[info.score];
    lbl.textContent = labels[info.key] || '';
    lbl.style.color = colors[info.score] || 'inherit';
  }

  function resetIdleTimer() {
    if (state.mode !== 'unlocked' || !state.autoLockMinutes) {
      state.idleDeadline = 0;
      return;
    }
    state.idleDeadline = Date.now() + state.autoLockMinutes * 60 * 1000;
  }

  function lockVault(reasonKey) {
    stopCamera();
    closeAllModals();
    clearClipboardNow(false);
    state.derivedKey = null;
    state.cryptoMeta = null;
    state.vault = null;
    state.selectedId = null;
    state.editing = false;
    state.showDetailPassword = false;
    state.showDetailSshKey = false;
    state.showDetailNote = false;
    state.revealedCustomFields = Object.create(null);
    state.totpCache = Object.create(null);
    state.auditResult = { flaggedCount: 0, byId: Object.create(null) };
    state.pendingImport = [];
    state.idleDeadline = 0;
    state.mode = state.rawEnvelope ? 'unlock' : 'setup';

    $('entryList').innerHTML = '';
    $('detailView').innerHTML = '';
    $('detailView').hidden = true;
    $('entryForm').hidden = true;
    $('detailEmpty').hidden = false;
    $('workspace').hidden = true;
    $('workspace').classList.remove('show-detail');
    $('lockScreen').hidden = false;
    $('masterPassword').value = '';
    $('confirmMasterPassword').value = '';
    $('lockError').hidden = true;
    renderLockModeUI();
    $('masterPassword').focus();
    if (reasonKey) showToast(t(reasonKey));
  }

  async function persistVault() {
    if (!state.derivedKey || !state.cryptoMeta || !state.vault) {
      throw new Error('vault_locked');
    }
    const envelope = await VaultCrypto.encryptVaultWithKey(
      state.vault,
      state.derivedKey,
      state.cryptoMeta
    );
    await saveEncryptedEnvelope(envelope);
  }

  const KNOWN_CATEGORIES = ['web', 'server', 'token', 'totp', 'note', 'other'];

  function categoryLabel(cat) {
    const map = {
      web: t('catWeb'),
      server: t('catServer'),
      token: t('catToken'),
      totp: t('catTotpOnly'),
      note: t('catNote'),
      other: t('catOther'),
    };
    return map[cat] || t('catOther');
  }

  function categoryMeta(cat) {
    const map = {
      web: { icon: 'fa-globe', cls: 'cat-web' },
      server: { icon: 'fa-server', cls: 'cat-server' },
      token: { icon: 'fa-key', cls: 'cat-token' },
      totp: { icon: 'fa-qrcode', cls: 'cat-totp' },
      note: { icon: 'fa-file-lines', cls: 'cat-note' },
      other: { icon: 'fa-folder', cls: 'cat-other' },
    };
    return map[cat] || map.other;
  }

  function formatIssueBadge(issue) {
    if (!issue) return '';
    if (issue.type === 'weak_password') {
      return '<span class="issue-pill danger"><i class="fa-solid fa-triangle-exclamation"></i> ' + esc(t('issueWeak')) + '</span>';
    }
    if (issue.type === 'reused_password') {
      return '<span class="issue-pill warn"><i class="fa-solid fa-copy"></i> ' + esc(t('issueReused')) + '</span>';
    }
    if (issue.type === 'expired_token') {
      return '<span class="issue-pill danger"><i class="fa-solid fa-calendar-xmark"></i> ' + esc(t('issueExpired')) + '</span>';
    }
    if (issue.type === 'expiring_token') {
      return '<span class="issue-pill warn"><i class="fa-solid fa-hourglass-half"></i> ' + esc(t('issueExpiring', { d: issue.days })) + '</span>';
    }
    return '';
  }

  function filteredEntries() {
    if (!state.vault || !Array.isArray(state.vault.entries)) return [];
    const q = state.search.trim().toLowerCase();
    return state.vault.entries
      .filter(function (e) {
        if (state.activeCategory === 'has_totp' && !(e.totp && e.totp.secret)) return false;
        if (state.activeCategory === 'favorite' && !e.favorite) return false;
        if (state.activeCategory === 'audit' && !(state.auditResult.byId && state.auditResult.byId[e.id])) return false;
        if (
          KNOWN_CATEGORIES.includes(state.activeCategory) &&
          (e.category || 'other') !== state.activeCategory
        ) {
          return false;
        }
        if (q) {
          const cfText = Array.isArray(e.customFields)
            ? e.customFields.map(function (c) { return (c.label || '') + ' ' + (c.secret ? '' : c.value || ''); }).join(' ')
            : '';
          const hay = [e.title, e.issuer, e.username, e.host, e.keyId, e.scope, e.url, e.notes, cfText].join(' ').toLowerCase();
          if (!hay.includes(q)) return false;
        }
        return true;
      })
      .sort(function (a, b) {
        if (!!a.favorite !== !!b.favorite) return a.favorite ? -1 : 1;
        return (b.updatedAt || 0) - (a.updatedAt || 0);
      });
  }

  function updateCategoryCounts() {
    const entries = (state.vault && state.vault.entries) || [];
    state.auditResult = VaultCrypto.auditVaultEntries(entries);
    const counts = {
      all: entries.length,
      has_totp: 0,
      favorite: 0,
      audit: state.auditResult.flaggedCount,
      web: 0,
      server: 0,
      token: 0,
      totp: 0,
      note: 0,
      other: 0,
    };
    entries.forEach(function (e) {
      if (e.totp && e.totp.secret) counts.has_totp++;
      if (e.favorite) counts.favorite++;
      const c = KNOWN_CATEGORIES.includes(e.category) ? e.category : 'other';
      counts[c]++;
    });
    Object.keys(counts).forEach(function (k) {
      const node = document.querySelector('[data-count="' + k + '"]');
      if (node) node.textContent = String(counts[k]);
    });
    const auditBtn = $('catAuditBtn');
    if (auditBtn) {
      auditBtn.classList.toggle('has-issues', counts.audit > 0);
    }
  }

  function renderEntries() {
    updateCategoryCounts();
    const list = filteredEntries();
    const host = $('entryList');
    if (!list.length) {
      host.innerHTML = '<div class="list-empty">' + esc(t('emptyList')) + '</div>';
      return;
    }
    host.innerHTML = list
      .map(function (entry) {
        const active = entry.id === state.selectedId ? ' active' : '';
        const hasTotp = !!(entry.totp && entry.totp.secret);
        const cat = KNOWN_CATEGORIES.includes(entry.category) ? entry.category : 'other';
        const meta = categoryMeta(cat);
        const sshCmd = cat === 'server' ? VaultCrypto.buildSshCommand(entry) : '';
        const sub =
          cat === 'server' && entry.host
            ? (entry.username || 'root') + '@' + entry.host + (entry.port && String(entry.port) !== '22' ? ':' + entry.port : '')
            : cat === 'token'
            ? entry.scope || entry.keyId || entry.issuer || categoryLabel(cat)
            : entry.username || entry.issuer || entry.url || categoryLabel(cat);

        const cached = state.totpCache[entry.id];
        const codeStr = cached ? VaultCrypto.formatTOTP(cached.code) : '••• •••';
        const period = hasTotp ? entry.totp.period || 30 : 30;
        const rem = hasTotp ? VaultCrypto.remainingSeconds(period) : 0;
        const urgent = rem <= 5 ? ' urgent' : '';

        const issues = (state.auditResult.byId && state.auditResult.byId[entry.id]) || [];
        const firstIssueHtml = issues.length ? formatIssueBadge(issues[0]) : '';

        // Quick copy chips
        const quickBtns = [];
        if (sshCmd) {
          quickBtns.push(
            '<button type="button" class="quick-copy-chip" data-quick-copy="ssh" data-entry-id="' + esc(entry.id) + '">' +
            '<i class="fa-solid fa-terminal"></i> ' + esc(t('quickCopySsh')) + '</button>'
          );
        }
        if (cat !== 'token' && entry.username) {
          quickBtns.push(
            '<button type="button" class="quick-copy-chip" data-quick-copy="username" data-entry-id="' + esc(entry.id) + '">' +
            esc(t('quickCopyUser')) + '</button>'
          );
        }
        if (entry.password) {
          quickBtns.push(
            '<button type="button" class="quick-copy-chip" data-quick-copy="password" data-entry-id="' + esc(entry.id) + '">' +
            esc(cat === 'token' ? t('quickCopyToken') : t('quickCopyPwd')) + '</button>'
          );
        }

        const hasFoot = hasTotp || firstIssueHtml || quickBtns.length > 0;

        return (
          '<div class="entry-card' + active + '" role="option" tabindex="0" data-entry-id="' + esc(entry.id) + '">' +
          '<div class="entry-card-top">' +
          '<div class="entry-avatar ' + meta.cls + '"><i class="fa-solid ' + meta.icon + '" aria-hidden="true"></i></div>' +
          '<div class="entry-meta">' +
          '<div class="entry-title-row">' +
          '<span class="entry-title">' + esc(entry.title) + '</span>' +
          (entry.favorite ? '<i class="fa-solid fa-star star-mark" aria-hidden="true"></i>' : '') +
          '</div>' +
          '<div class="entry-sub">' + esc(sub) + '</div>' +
          '</div>' +
          '</div>' +
          (hasFoot
            ? '<div class="entry-card-foot">' +
              (hasTotp
                ? '<div class="entry-totp-pill" data-copy-totp="' + esc(entry.id) + '" title="' + esc(t('copyCode')) + '">' +
                  '<span data-list-code="' + esc(entry.id) + '">' + esc(codeStr) + '</span>' +
                  '<span class="entry-totp-rem' + urgent + '" data-list-rem="' + esc(entry.id) + '">' + rem + 's</span>' +
                  '</div>'
                : '') +
              firstIssueHtml +
              (quickBtns.length ? '<div class="entry-quick-actions">' + quickBtns.join('') + '</div>' : '') +
              '</div>'
            : '') +
          '</div>'
        );
      })
      .join('');
    refreshAllTotpDisplay();
  }

  function getSelectedEntry() {
    if (!state.vault || !state.selectedId) return null;
    return state.vault.entries.find(function (e) { return e.id === state.selectedId; }) || null;
  }

  function renderDetailView() {
    const entry = getSelectedEntry();
    if (!entry) {
      $('detailView').hidden = true;
      $('entryForm').hidden = true;
      $('detailEmpty').hidden = false;
      $('workspace').classList.remove('show-detail');
      return;
    }
    state.editing = false;
    $('detailEmpty').hidden = true;
    $('entryForm').hidden = true;
    $('detailView').hidden = false;
    $('workspace').classList.add('show-detail');

    const hasTotp = !!(entry.totp && entry.totp.secret);
    const period = hasTotp ? entry.totp.period || 30 : 30;
    const rem = hasTotp ? VaultCrypto.remainingSeconds(period) : 0;
    const dashOffset = RING_CIRCUMFERENCE * (1 - rem / period);
    const cached = state.totpCache[entry.id];
    const formattedCode = cached ? VaultCrypto.formatTOTP(cached.code) : '••• •••';
    const href = safeHref(entry.url);
    const cat = KNOWN_CATEGORIES.includes(entry.category) ? entry.category : 'other';
    const sshCmd = cat === 'server' ? VaultCrypto.buildSshCommand(entry) : '';
    const pwdDisplay = entry.password
      ? state.showDetailPassword
        ? entry.password
        : '•'.repeat(Math.min(24, Math.max(8, entry.password.length)))
      : '';
    const updatedStr = entry.updatedAt ? new Date(entry.updatedAt).toLocaleString() : '';
    const issues = (state.auditResult.byId && state.auditResult.byId[entry.id]) || [];

    let html =
      '<div class="detail-bar">' +
      '<div class="detail-bar-left">' +
      '<button type="button" class="icon-btn mobile-only" id="detailBackBtn" aria-label="返回列表"><i class="fa-solid fa-arrow-left" aria-hidden="true"></i></button>' +
      '<h2>' + esc(entry.title) + '</h2>' +
      '</div>' +
      '<div class="detail-bar-right">' +
      '<button type="button" class="icon-btn" id="detailFavBtn" title="' + esc(t('catFavorite')) + '">' +
      '<i class="fa-solid fa-star" style="color:' + (entry.favorite ? 'var(--color-warning)' : 'var(--color-border-strong)') + '"></i>' +
      '</button>' +
      '<button type="button" class="btn-secondary btn-sm" id="detailEditBtn"><i class="fa-solid fa-pen" aria-hidden="true"></i> ' + esc(t('edit')) + '</button>' +
      '<button type="button" class="btn-danger-outline btn-sm" id="detailDelBtn"><i class="fa-solid fa-trash" aria-hidden="true"></i></button>' +
      '</div>' +
      '</div>' +
      '<div class="detail-scroll">';

    if (issues.length) {
      html +=
        '<div class="detail-audit-banner">' +
        '<i class="fa-solid fa-shield-halved" aria-hidden="true"></i>' +
        '<span>' + esc(t('catAudit')) + '：</span>' +
        issues.map(formatIssueBadge).join(' ') +
        '</div>';
    }

    if (hasTotp) {
      const ringClass = rem <= 5 ? ' urgent' : rem <= 10 ? ' warn' : '';
      html +=
        '<div class="totp-hero">' +
        '<div>' +
        '<div class="totp-hero-label">' + esc(t('totpLiveLabel', { p: period })) + '</div>' +
        '<div class="totp-hero-code' + (rem <= 5 ? ' urgent' : '') + '" id="detailTotpCode" title="' + esc(t('copyCode')) + '">' + esc(formattedCode) + '</div>' +
        '<div class="totp-hero-actions">' +
        '<button type="button" class="btn-primary btn-xs" id="detailCopyTotpBtn"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' + esc(t('copyCode')) + '</button>' +
        '<button type="button" class="btn-secondary btn-xs" id="detailShowQrBtn"><i class="fa-solid fa-qrcode" aria-hidden="true"></i> ' + esc(t('showQr')) + '</button>' +
        '</div>' +
        '</div>' +
        '<div class="totp-ring-wrap" aria-label="' + rem + 's">' +
        '<svg width="56" height="56" viewBox="0 0 56 56">' +
        '<circle class="totp-ring-bg" cx="28" cy="28" r="24"></circle>' +
        '<circle class="totp-ring-fg' + ringClass + '" id="detailTotpRing" cx="28" cy="28" r="24" stroke-dasharray="' + RING_CIRCUMFERENCE.toFixed(2) + '" stroke-dashoffset="' + dashOffset.toFixed(2) + '"></circle>' +
        '</svg>' +
        '<span class="totp-ring-sec" id="detailTotpRem">' + rem + 's</span>' +
        '</div>' +
        '</div>';
    }

    if (sshCmd) {
      html +=
        '<div class="ssh-cmd-bar">' +
        '<code>' + esc(sshCmd) + '</code>' +
        '<button type="button" class="btn-primary btn-xs" id="detailCopySshBtn"><i class="fa-solid fa-terminal" aria-hidden="true"></i> ' + esc(t('copy')) + '</button>' +
        '</div>';
    }

    html += '<div class="info-group">';
    html +=
      '<div class="info-row"><div class="info-body"><div class="info-label">' +
      esc(t('fieldCategory')) +
      '</div><div class="info-val">' +
      esc(categoryLabel(cat)) +
      (entry.issuer && entry.issuer !== entry.title ? ' · ' + esc(entry.issuer) : '') +
      '</div></div></div>';

    if (entry.host) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(t('fieldHost')) + (entry.port ? ' : ' + esc(t('fieldPort')) : '') +
        '</div><div class="info-val mono">' +
        esc(entry.host) + (entry.port ? ':' + esc(entry.port) : '') +
        '</div></div><div class="info-btns"><button type="button" class="btn-secondary btn-xs" data-copy-field="host"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
        esc(t('copy')) +
        '</button></div></div>';
    }

    if (entry.keyId) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">Key ID / AccessKey</div><div class="info-val mono">' +
        esc(entry.keyId) +
        '</div></div><div class="info-btns"><button type="button" class="btn-secondary btn-xs" data-copy-field="keyId"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
        esc(t('copy')) +
        '</button></div></div>';
    }

    if (entry.username) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(cat === 'server' ? t('serverUserLabel') : t('fieldUsername')) +
        '</div><div class="info-val mono">' +
        esc(entry.username) +
        '</div></div><div class="info-btns"><button type="button" class="btn-secondary btn-xs" data-copy-field="username"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
        esc(t('copy')) +
        '</button></div></div>';
    }

    if (entry.password) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(cat === 'token' ? t('tokenPwdLabel') : cat === 'server' ? t('serverPwdLabel') : t('fieldPassword')) +
        '</div><div class="info-val mono">' +
        esc(pwdDisplay) +
        '</div></div><div class="info-btns">' +
        '<button type="button" class="icon-btn" id="detailTogglePwdBtn" aria-label="显示或隐藏密码"><i class="fa-solid ' +
        (state.showDetailPassword ? 'fa-eye-slash' : 'fa-eye') +
        '"></i></button>' +
        '<button type="button" class="btn-secondary btn-xs" data-copy-field="password" data-sensitive="1"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
        esc(t('copy')) +
        '</button></div></div>';
    }

    if (entry.sshKey) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(t('fieldSshKey')) +
        '</div>' +
        (state.showDetailSshKey
          ? '<pre class="secret-pre">' + esc(entry.sshKey) + '</pre>'
          : '<div class="info-val mono">••••••••••••••••••••••••••••</div>') +
        '</div><div class="info-btns">' +
        '<button type="button" class="icon-btn" id="detailToggleSshKeyBtn" aria-label="显示或隐藏私钥"><i class="fa-solid ' +
        (state.showDetailSshKey ? 'fa-eye-slash' : 'fa-eye') +
        '"></i></button>' +
        '<button type="button" class="btn-secondary btn-xs" data-copy-field="sshKey" data-sensitive="1"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
        esc(t('copy')) +
        '</button></div></div>';
    }

    if (entry.scope) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(t('fieldScope')) +
        '</div><div class="info-val mono">' +
        esc(entry.scope) +
        '</div></div></div>';
    }

    if (entry.expiresAt) {
      const days = VaultCrypto.daysUntilExpiry(entry.expiresAt);
      let expPill = '<span class="issue-pill ok">' + esc(t('expiresValid', { date: entry.expiresAt })) + '</span>';
      if (days !== null && days < 0) {
        expPill = '<span class="issue-pill danger">' + esc(entry.expiresAt + ' · ' + t('issueExpired')) + '</span>';
      } else if (days !== null && days <= 14) {
        expPill = '<span class="issue-pill warn">' + esc(entry.expiresAt + ' · ' + t('issueExpiring', { d: days })) + '</span>';
      }
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(t('fieldExpiresAt')) +
        '</div><div class="info-val">' + expPill + '</div></div></div>';
    }

    if (entry.url) {
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(cat === 'token' ? t('tokenUrlLabel') : cat === 'server' ? t('serverUrlLabel') : t('fieldUrl')) +
        '</div><div class="info-val">' +
        (href
          ? '<a href="' + esc(href) + '" target="_blank" rel="noopener noreferrer">' + esc(entry.url) + '</a>'
          : esc(entry.url)) +
        '</div></div><div class="info-btns">' +
        (href
          ? '<a class="btn-secondary btn-xs" href="' + esc(href) + '" target="_blank" rel="noopener noreferrer"><i class="fa-solid fa-arrow-up-right-from-square" aria-hidden="true"></i> ' + esc(t('openSite')) + '</a>'
          : '') +
        '<button type="button" class="btn-secondary btn-xs" data-copy-field="url"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
        esc(t('copy')) +
        '</button></div></div>';
    }

    if (Array.isArray(entry.customFields) && entry.customFields.length) {
      entry.customFields.forEach(function (cf, idx) {
        if (!cf || (!cf.label && !cf.value)) return;
        const revealed = !cf.secret || !!state.revealedCustomFields[idx];
        html +=
          '<div class="info-row"><div class="info-body"><div class="info-label">' +
          esc(cf.label || ('Field ' + (idx + 1))) +
          '</div><div class="info-val mono">' +
          esc(revealed ? cf.value || '' : '•'.repeat(Math.min(20, Math.max(8, (cf.value || '').length)))) +
          '</div></div><div class="info-btns">' +
          (cf.secret
            ? '<button type="button" class="icon-btn" data-toggle-cf="' + idx + '" aria-label="显示或隐藏"><i class="fa-solid ' + (revealed ? 'fa-eye-slash' : 'fa-eye') + '"></i></button>'
            : '') +
          '<button type="button" class="btn-secondary btn-xs" data-copy-cf="' + idx + '" data-sensitive="' + (cf.secret ? '1' : '0') + '"><i class="fa-solid fa-copy" aria-hidden="true"></i> ' +
          esc(t('copy')) +
          '</button></div></div>';
      });
    }

    if (entry.notes) {
      const maskNote = cat === 'note' && !state.showDetailNote;
      html +=
        '<div class="info-row"><div class="info-body"><div class="info-label">' +
        esc(cat === 'note' ? t('noteBodyLabel') : t('fieldNotes')) +
        '</div>' +
        (maskNote
          ? '<button type="button" class="btn-secondary btn-xs" id="detailRevealNoteBtn"><i class="fa-solid fa-eye" aria-hidden="true"></i> ' + esc(t('revealNote')) + '</button>'
          : '<pre class="notes-pre">' + esc(entry.notes) + '</pre>') +
        '</div><div class="info-btns">' +
        (cat === 'note' && !maskNote
          ? '<button type="button" class="icon-btn" id="detailHideNoteBtn" title="' + esc(t('hideNote')) + '"><i class="fa-solid fa-eye-slash"></i></button>'
          : '') +
        '<button type="button" class="btn-secondary btn-xs" data-copy-field="notes" data-sensitive="' + (cat === 'note' ? '1' : '0') + '"><i class="fa-solid fa-copy" aria-hidden="true"></i></button></div></div>';
    }

    html += '</div>';
    html +=
      '<div class="detail-security-note">' +
      '<span><i class="fa-solid fa-lock" aria-hidden="true"></i> ' + esc(t('securityFooter')) + '</span>' +
      (updatedStr ? '<span>' + esc(t('updatedAt')) + ' ' + esc(updatedStr) + '</span>' : '') +
      '</div></div>';

    $('detailView').innerHTML = html;

    // Bind detail events
    const backBtn = $('detailBackBtn');
    if (backBtn) {
      backBtn.onclick = function () {
        $('workspace').classList.remove('show-detail');
      };
    }
    $('detailFavBtn').onclick = async function () {
      entry.favorite = !entry.favorite;
      entry.updatedAt = Date.now();
      try {
        await persistVault();
        renderEntries();
        renderDetailView();
      } catch (_) {
        showToast(t('errSaveFailed'), true);
      }
    };
    $('detailEditBtn').onclick = function () { openEntryForm(entry); };
    $('detailDelBtn').onclick = async function () {
      if (!window.confirm(t('confirmDelete', { title: entry.title }))) return;
      state.vault.entries = state.vault.entries.filter(function (x) { return x.id !== entry.id; });
      delete state.totpCache[entry.id];
      state.selectedId = null;
      try {
        await persistVault();
        showToast(t('msgDeleted'));
        renderEntries();
        renderDetailView();
      } catch (_) {
        showToast(t('errSaveFailed'), true);
      }
    };

    const copySshBtn = $('detailCopySshBtn');
    if (copySshBtn) {
      copySshBtn.onclick = function () { copyText(sshCmd, false); };
    }
    const togglePwd = $('detailTogglePwdBtn');
    if (togglePwd) {
      togglePwd.onclick = function () {
        state.showDetailPassword = !state.showDetailPassword;
        renderDetailView();
      };
    }
    const toggleSshKey = $('detailToggleSshKeyBtn');
    if (toggleSshKey) {
      toggleSshKey.onclick = function () {
        state.showDetailSshKey = !state.showDetailSshKey;
        renderDetailView();
      };
    }
    const revealNoteBtn = $('detailRevealNoteBtn');
    if (revealNoteBtn) {
      revealNoteBtn.onclick = function () {
        state.showDetailNote = true;
        renderDetailView();
      };
    }
    const hideNoteBtn = $('detailHideNoteBtn');
    if (hideNoteBtn) {
      hideNoteBtn.onclick = function () {
        state.showDetailNote = false;
        renderDetailView();
      };
    }
    $('detailView').querySelectorAll('[data-toggle-cf]').forEach(function (btn) {
      btn.onclick = function () {
        const idx = btn.getAttribute('data-toggle-cf');
        state.revealedCustomFields[idx] = !state.revealedCustomFields[idx];
        renderDetailView();
      };
    });
    $('detailView').querySelectorAll('[data-copy-cf]').forEach(function (btn) {
      btn.onclick = function () {
        const idx = Number(btn.getAttribute('data-copy-cf'));
        const cf = entry.customFields && entry.customFields[idx];
        if (cf) copyText(cf.value || '', btn.getAttribute('data-sensitive') === '1');
      };
    });
    $('detailView').querySelectorAll('[data-copy-field]').forEach(function (btn) {
      btn.onclick = function () {
        const f = btn.getAttribute('data-copy-field');
        copyText(entry[f] || '', btn.getAttribute('data-sensitive') === '1');
      };
    });
    const copyTotp = $('detailCopyTotpBtn');
    if (copyTotp) {
      copyTotp.onclick = function () { copyEntryTotp(entry.id); };
    }
    const heroCode = $('detailTotpCode');
    if (heroCode) {
      heroCode.onclick = function () { copyEntryTotp(entry.id); };
    }
    const showQrBtn = $('detailShowQrBtn');
    if (showQrBtn) {
      showQrBtn.onclick = function () { openQrExportModal(entry); };
    }
    refreshAllTotpDisplay();
  }

  async function computeEntryTotp(entry) {
    if (!entry || !entry.totp || !entry.totp.secret) return '';
    const period = entry.totp.period || 30;
    const slot = Math.floor(Date.now() / 1000 / period);
    const cached = state.totpCache[entry.id];
    if (cached && cached.slot === slot && cached.secret === entry.totp.secret) {
      return cached.code;
    }
    const code = await VaultCrypto.generateTOTP(entry.totp.secret, entry.totp);
    state.totpCache[entry.id] = { slot: slot, code: code, secret: entry.totp.secret };
    return code;
  }

  async function copyEntryTotp(entryId) {
    if (!state.vault) return;
    const entry = state.vault.entries.find(function (e) { return e.id === entryId; });
    if (!entry || !entry.totp || !entry.totp.secret) return;
    try {
      const code = await computeEntryTotp(entry);
      await copyText(code, true);
    } catch (_) {
      showToast(t('errInvalidSecret'), true);
    }
  }

  async function refreshAllTotpDisplay() {
    if (state.mode !== 'unlocked' || !state.vault) return;
    const entries = state.vault.entries.filter(function (e) { return e.totp && e.totp.secret; });
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      try {
        const code = await computeEntryTotp(entry);
        const formatted = VaultCrypto.formatTOTP(code);
        const period = entry.totp.period || 30;
        const rem = VaultCrypto.remainingSeconds(period);

        const listCode = document.querySelector('[data-list-code="' + entry.id + '"]');
        if (listCode && listCode.textContent !== formatted) listCode.textContent = formatted;
        const listRem = document.querySelector('[data-list-rem="' + entry.id + '"]');
        if (listRem) {
          listRem.textContent = rem + 's';
          listRem.className = 'entry-totp-rem' + (rem <= 5 ? ' urgent' : '');
        }

        if (!state.editing && state.selectedId === entry.id) {
          const hero = $('detailTotpCode');
          const remEl = $('detailTotpRem');
          const ring = $('detailTotpRing');
          if (hero) {
            hero.textContent = formatted;
            hero.className = 'totp-hero-code' + (rem <= 5 ? ' urgent' : '');
          }
          if (remEl) remEl.textContent = rem + 's';
          if (ring) {
            const offset = RING_CIRCUMFERENCE * (1 - rem / period);
            ring.setAttribute('stroke-dashoffset', offset.toFixed(2));
            ring.setAttribute('class', 'totp-ring-fg' + (rem <= 5 ? ' urgent' : rem <= 10 ? ' warn' : ''));
          }
        }
      } catch (_) {}
    }
  }

  function updateFormSshPreview() {
    const cat = $('fCategory').value;
    const bar = $('formSshPreview');
    if (cat !== 'server') {
      bar.hidden = true;
      return;
    }
    const cmd = VaultCrypto.buildSshCommand({
      host: $('fHost').value,
      username: $('fUsername').value,
      port: $('fPort').value,
    });
    if (!cmd) {
      bar.hidden = true;
      return;
    }
    $('formSshPreviewCode').textContent = cmd;
    bar.hidden = false;
  }

  function updateEntryPasswordStrength() {
    const cat = $('fCategory').value;
    const wrap = $('entryPwdStrengthWrap');
    const pwd = $('fPassword').value;
    if (!pwd || cat === 'totp' || cat === 'note' || cat === 'token') {
      wrap.hidden = true;
      return;
    }
    wrap.hidden = false;
    const info = VaultCrypto.passwordStrength(pwd);
    const widths = ['0%', '25%', '50%', '75%', '100%'];
    const colors = ['transparent', '#dc2626', '#d97706', '#2563eb', '#059669'];
    const labels = {
      empty: '',
      weak: t('strengthWeak'),
      fair: t('strengthFair'),
      good: t('strengthGood'),
      strong: t('strengthStrong'),
    };
    $('entryPwdStrengthFill').style.width = widths[info.score];
    $('entryPwdStrengthFill').style.background = colors[info.score];
    $('entryPwdStrengthLabel').textContent = labels[info.key] || '';
    $('entryPwdStrengthLabel').style.color = colors[info.score] || 'inherit';
  }

  async function updateFormTotpPreview() {
    if (!state.editing) return;
    const box = $('formTotpPreview');
    const raw = $('fTotpSecret').value.trim();
    if (!raw) {
      box.hidden = true;
      return;
    }
    box.hidden = false;
    try {
      let secret = '';
      let algo = VaultCrypto.normalizeAlgorithm($('fTotpAlgo').value);
      let digits = Number($('fTotpDigits').value) === 8 ? 8 : 6;
      let period = Math.max(10, Math.min(120, Number($('fTotpPeriod').value) || 30));
      if (raw.startsWith('otpauth://')) {
        const parsed = VaultImport.parseOtpAuthURI(raw);
        secret = parsed.totp.secret;
        algo = parsed.totp.algorithm;
        digits = parsed.totp.digits;
        period = parsed.totp.period;
      } else {
        secret = VaultCrypto.normalizeBase32(raw);
        if (!VaultCrypto.isValidBase32(secret)) throw new Error('invalid');
      }
      const code = await VaultCrypto.generateTOTP(secret, { algorithm: algo, digits: digits, period: period });
      const rem = VaultCrypto.remainingSeconds(period);
      box.classList.remove('invalid');
      $('formTotpPreviewCode').textContent = VaultCrypto.formatTOTP(code);
      $('formTotpPreviewBadge').textContent = t('totpValid');
      $('formTotpPreviewRem').textContent = rem + 's';
    } catch (_) {
      box.classList.add('invalid');
      $('formTotpPreviewCode').textContent = t('errInvalidSecret');
      $('formTotpPreviewBadge').textContent = t('totpInvalid');
      $('formTotpPreviewRem').textContent = '';
    }
  }

  function syncTotpCollapseUI() {
    const cat = $('fCategory').value;
    const forcedOpen = cat === 'totp';
    const isOpen = forcedOpen || state.formTotpOpen;
    $('totpBodyWrap').hidden = !isOpen;
    $('toggleTotpSectionBtn').setAttribute('aria-expanded', String(isOpen));
    $('totpSectionCaret').hidden = forcedOpen;
    $('totpSectionTitle').textContent = forcedOpen ? t('totpSection') : t('optionalTotpTitle');
    $('totpAdvRow').hidden = !state.formTotpAdvOpen;
  }

  function applyFormCategory(cat, opts) {
    const c = KNOWN_CATEGORIES.includes(cat) ? cat : 'web';
    $('fCategory').value = c;
    document.querySelectorAll('#catPicker .cat-card').forEach(function (btn) {
      btn.classList.toggle('active', btn.getAttribute('data-pick-cat') === c);
    });
    $('formDynamicStack').classList.toggle('mode-totp', c === 'totp');

    const isWeb = c === 'web' || c === 'other';
    const isServer = c === 'server';
    const isToken = c === 'token';
    const isTotp = c === 'totp';
    const isNote = c === 'note';

    $('secServer').hidden = !isServer;
    $('secSshKey').hidden = !isServer;
    $('secTokenMeta').hidden = !isToken;
    $('secAccountUrlRow').hidden = isNote;
    $('secUsernameField').hidden = isToken || isNote;
    $('secUrlField').hidden = isTotp || isNote;
    $('secPassword').hidden = isTotp || isNote;
    $('secTotp').hidden = isNote;

    // Context-specific labels & placeholders
    if (isServer) {
      $('fTitleLabel').textContent = t('serverNameLabel');
      $('fTitle').placeholder = lang === 'zh' ? '例如：生产云主机 · 香港节点' : 'e.g. Prod Server · HK';
      $('fIssuerLabel').textContent = t('fieldIssuer');
      $('fUsernameLabel').textContent = t('serverUserLabel');
      $('fUsername').placeholder = 'root';
      $('fPasswordLabel').textContent = t('serverPwdLabel');
      $('fPassword').placeholder = lang === 'zh' ? 'SSH 登录密码或私钥口令' : 'SSH password or passphrase';
      $('fUrlLabel').textContent = t('serverUrlLabel');
      $('fUrl').placeholder = 'https://console.cloud.example.com';
    } else if (isToken) {
      $('fTitleLabel').textContent = t('tokenNameLabel');
      $('fTitle').placeholder = lang === 'zh' ? '例如：Cloudflare DNS Token' : 'e.g. Cloudflare DNS Token';
      $('fIssuerLabel').textContent = t('tokenIssuerLabel');
      $('fUrlLabel').textContent = t('tokenUrlLabel');
      $('fUrl').placeholder = 'https://api.example.com/v1';
      $('fPasswordLabel').textContent = t('tokenPwdLabel');
      $('fPassword').placeholder = lang === 'zh' ? '粘贴 API Secret / Bearer Token' : 'Paste API Secret / Bearer Token';
    } else if (isTotp) {
      $('fTitleLabel').textContent = t('totpNameLabel');
      $('fTitle').placeholder = lang === 'zh' ? '例如：AWS Root / GitHub' : 'e.g. AWS Root / GitHub';
      $('fIssuerLabel').textContent = t('fieldIssuer');
      $('fUsernameLabel').textContent = t('totpUserLabel');
      $('fUsername').placeholder = 'user@example.com';
    } else if (isNote) {
      $('fTitleLabel').textContent = t('noteNameLabel');
      $('fTitle').placeholder = lang === 'zh' ? '例如：GitHub 恢复码 / 重要证件' : 'e.g. Recovery Codes / License Key';
      $('fIssuerLabel').textContent = t('noteTagLabel');
    } else {
      $('fTitleLabel').textContent = t('fieldTitle');
      $('fTitle').placeholder = lang === 'zh' ? '例如：GitHub / Cloudflare' : 'e.g. GitHub / Cloudflare';
      $('fIssuerLabel').textContent = t('fieldIssuer');
      $('fUsernameLabel').textContent = t('fieldUsername');
      $('fUsername').placeholder = 'user@example.com';
      $('fPasswordLabel').textContent = t('fieldPassword');
      $('fPassword').placeholder = lang === 'zh' ? '可选，留空表示仅保存 2FA' : 'Optional';
      $('fUrlLabel').textContent = t('fieldUrl');
      $('fUrl').placeholder = 'https://example.com';
    }

    $('fNotesLabel').textContent = isNote ? t('noteBodyLabel') : t('fieldNotes');
    $('fNotes').rows = isNote ? 7 : 3;

    if (opts && typeof opts.openTotp === 'boolean') {
      state.formTotpOpen = opts.openTotp;
    } else if (isTotp) {
      state.formTotpOpen = true;
    } else if (!$('fTotpSecret').value.trim()) {
      state.formTotpOpen = false;
    }

    syncTotpCollapseUI();
    updateFormSshPreview();
    updateEntryPasswordStrength();
    updateFormTotpPreview();
  }

  function addCustomFieldRow(cf) {
    const item = cf || { label: '', value: '', secret: false };
    const row = document.createElement('div');
    row.className = 'cf-edit-row';

    const labelInp = document.createElement('input');
    labelInp.type = 'text';
    labelInp.className = 'cf-label-inp';
    labelInp.maxLength = 80;
    labelInp.placeholder = t('cfLabelPh');
    labelInp.value = item.label || '';

    const valInp = document.createElement('input');
    valInp.type = item.secret ? 'password' : 'text';
    valInp.className = 'cf-val-inp';
    valInp.maxLength = 2000;
    valInp.placeholder = t('cfValPh');
    valInp.value = item.value || '';

    const secBtn = document.createElement('button');
    secBtn.type = 'button';
    secBtn.className = 'cf-secret-btn' + (item.secret ? ' is-secret' : '');
    secBtn.dataset.secret = item.secret ? '1' : '0';
    secBtn.innerHTML = item.secret
      ? '<i class="fa-solid fa-lock" aria-hidden="true"></i> ' + esc(t('cfSecret'))
      : esc(t('cfPlain'));
    secBtn.onclick = function () {
      const next = secBtn.dataset.secret !== '1';
      secBtn.dataset.secret = next ? '1' : '0';
      secBtn.classList.toggle('is-secret', next);
      valInp.type = next ? 'password' : 'text';
      secBtn.innerHTML = next
        ? '<i class="fa-solid fa-lock" aria-hidden="true"></i> ' + esc(t('cfSecret'))
        : esc(t('cfPlain'));
    };

    const delBtn = document.createElement('button');
    delBtn.type = 'button';
    delBtn.className = 'icon-btn';
    delBtn.setAttribute('aria-label', t('delete'));
    delBtn.innerHTML = '<i class="fa-solid fa-xmark" aria-hidden="true"></i>';
    delBtn.onclick = function () { row.remove(); };

    row.appendChild(labelInp);
    row.appendChild(valInp);
    row.appendChild(secBtn);
    row.appendChild(delBtn);
    $('customFieldsList').appendChild(row);
  }

  function renderCustomFieldRows(list) {
    $('customFieldsList').innerHTML = '';
    if (Array.isArray(list)) {
      list.forEach(addCustomFieldRow);
    }
  }

  function readCustomFieldsFromForm() {
    const rows = $('customFieldsList').querySelectorAll('.cf-edit-row');
    const out = [];
    rows.forEach(function (row) {
      const label = (row.querySelector('.cf-label-inp').value || '').trim();
      const value = row.querySelector('.cf-val-inp').value || '';
      const secret = row.querySelector('.cf-secret-btn').dataset.secret === '1';
      if (label || value) {
        out.push({ label: label, value: value, secret: secret });
      }
    });
    return out;
  }

  function openEntryForm(entry) {
    state.editing = true;
    closeMobileSidebar();
    $('detailEmpty').hidden = true;
    $('detailView').hidden = true;
    $('entryForm').hidden = false;
    $('workspace').classList.add('show-detail');
    $('genPanel').hidden = true;

    const isEdit = !!entry;
    $('entryFormTitle').textContent = isEdit ? t('editEntry') : t('newEntry');
    $('entryId').value = isEdit ? entry.id : '';
    $('fTitle').value = isEdit ? entry.title || '' : '';

    const initialCat = isEdit
      ? entry.category || 'web'
      : KNOWN_CATEGORIES.includes(state.activeCategory)
      ? state.activeCategory
      : state.activeCategory === 'has_totp'
      ? 'totp'
      : 'web';

    $('fIssuer').value = isEdit ? entry.issuer || '' : '';
    $('fUsername').value = isEdit ? entry.username || '' : '';
    $('fPassword').value = isEdit ? entry.password || '' : '';
    $('fPassword').type = 'password';
    $('fUrl').value = isEdit ? entry.url || '' : '';
    $('fHost').value = isEdit ? entry.host || '' : '';
    $('fPort').value = isEdit ? (entry.port || '22') : '22';
    $('fSshKey').value = isEdit ? entry.sshKey || '' : '';
    $('fKeyId').value = isEdit ? entry.keyId || '' : '';
    $('fExpiresAt').value = isEdit ? entry.expiresAt || '' : '';
    $('fScope').value = isEdit ? entry.scope || '' : '';
    $('fNotes').value = isEdit ? entry.notes || '' : '';
    $('fFavorite').checked = !!(isEdit && entry.favorite);

    const hasTotp = !!(isEdit && entry.totp && entry.totp.secret);
    if (hasTotp) {
      $('fTotpSecret').value = entry.totp.secret;
      $('fTotpAlgo').value = VaultCrypto.normalizeAlgorithm(entry.totp.algorithm);
      $('fTotpDigits').value = String(entry.totp.digits === 8 ? 8 : 6);
      $('fTotpPeriod').value = String(entry.totp.period || 30);
      state.formTotpAdvOpen =
        $('fTotpAlgo').value !== 'SHA-1' ||
        $('fTotpDigits').value !== '6' ||
        $('fTotpPeriod').value !== '30';
    } else {
      $('fTotpSecret').value = '';
      $('fTotpAlgo').value = 'SHA-1';
      $('fTotpDigits').value = '6';
      $('fTotpPeriod').value = '30';
      state.formTotpAdvOpen = false;
    }

    renderCustomFieldRows(isEdit ? entry.customFields : []);
    applyFormCategory(initialCat, { openTotp: initialCat === 'totp' || hasTotp });
    $('fTitle').focus();
  }

  function fillFormFromOtpText(raw) {
    try {
      const parsed = VaultImport.parseOtpAuthURI(raw);
      if (!$('fTitle').value.trim()) $('fTitle').value = parsed.title;
      if (!$('fIssuer').value.trim() && parsed.issuer) $('fIssuer').value = parsed.issuer;
      if (!$('fUsername').value.trim() && parsed.username) $('fUsername').value = parsed.username;
      $('fTotpSecret').value = parsed.totp.secret;
      $('fTotpAlgo').value = parsed.totp.algorithm;
      $('fTotpDigits').value = String(parsed.totp.digits);
      $('fTotpPeriod').value = String(parsed.totp.period);
      state.formTotpOpen = true;
      syncTotpCollapseUI();
      updateFormTotpPreview();
      showToast('已自动解析 otpauth 链接');
      return true;
    } catch (_) {
      return false;
    }
  }

  async function saveEntryForm(event) {
    event.preventDefault();
    const title = $('fTitle').value.trim();
    if (!title) return;

    const category = $('fCategory').value || 'web';
    let rawSecret = category === 'note' ? '' : $('fTotpSecret').value.trim();
    let totp = null;
    if (rawSecret) {
      if (rawSecret.startsWith('otpauth://')) {
        try {
          const parsed = VaultImport.parseOtpAuthURI(rawSecret);
          totp = parsed.totp;
        } catch (_) {
          showToast(t('errInvalidSecret'), true);
          return;
        }
      } else {
        const clean = VaultCrypto.normalizeBase32(rawSecret);
        if (!VaultCrypto.isValidBase32(clean)) {
          showToast(t('errInvalidSecret'), true);
          return;
        }
        totp = {
          secret: clean,
          algorithm: VaultCrypto.normalizeAlgorithm($('fTotpAlgo').value),
          digits: Number($('fTotpDigits').value) === 8 ? 8 : 6,
          period: Math.max(10, Math.min(120, Number($('fTotpPeriod').value) || 30)),
        };
      }
    }

    const id = $('entryId').value || genId();
    const existingIndex = state.vault.entries.findIndex(function (e) { return e.id === id; });
    const customFields = readCustomFieldsFromForm();
    const record = {
      id: id,
      title: title,
      category: category,
      issuer: $('fIssuer').value.trim(),
      username: category === 'token' || category === 'note' ? '' : $('fUsername').value.trim(),
      password: category === 'totp' || category === 'note' ? '' : $('fPassword').value,
      url: category === 'totp' || category === 'note' ? '' : $('fUrl').value.trim(),
      host: category === 'server' ? $('fHost').value.trim() : '',
      port: category === 'server' ? ($('fPort').value.trim() || '22') : '',
      sshKey: category === 'server' ? $('fSshKey').value.trim() : '',
      keyId: category === 'token' ? $('fKeyId').value.trim() : '',
      expiresAt: category === 'token' ? $('fExpiresAt').value.trim() : '',
      scope: category === 'token' ? $('fScope').value.trim() : '',
      customFields: customFields.length ? customFields : undefined,
      notes: $('fNotes').value,
      favorite: $('fFavorite').checked,
      totp: totp,
      createdAt: existingIndex >= 0 ? state.vault.entries[existingIndex].createdAt || Date.now() : Date.now(),
      updatedAt: Date.now(),
    };

    if (existingIndex >= 0) {
      state.vault.entries[existingIndex] = record;
    } else {
      state.vault.entries.unshift(record);
    }
    delete state.totpCache[id];
    state.selectedId = id;
    state.showDetailPassword = false;
    state.showDetailSshKey = false;
    state.showDetailNote = false;
    state.revealedCustomFields = Object.create(null);

    try {
      await persistVault();
      showToast(t('msgSaved'));
      renderEntries();
      renderDetailView();
    } catch (_) {
      showToast(t('errSaveFailed'), true);
    }
  }

  // QR Image Decoding (jsQR offline)
  function decodeQRFromBlob(blob) {
    return new Promise(function (resolve, reject) {
      const url = URL.createObjectURL(blob);
      const img = new Image();
      img.onload = function () {
        URL.revokeObjectURL(url);
        try {
          const maxDim = 1600;
          let w = img.naturalWidth || img.width;
          let h = img.naturalHeight || img.height;
          if (w > maxDim || h > maxDim) {
            const scale = maxDim / Math.max(w, h);
            w = Math.round(w * scale);
            h = Math.round(h * scale);
          }
          const canvas = document.createElement('canvas');
          canvas.width = w;
          canvas.height = h;
          const ctx = canvas.getContext('2d', { willReadFrequently: true });
          ctx.fillStyle = '#ffffff';
          ctx.fillRect(0, 0, w, h);
          ctx.drawImage(img, 0, 0, w, h);
          const imageData = ctx.getImageData(0, 0, w, h);
          if (typeof window.jsQR !== 'function') {
            return reject(new Error('jsqr_missing'));
          }
          const result = window.jsQR(imageData.data, w, h, { inversionAttempts: 'attemptBoth' });
          if (result && result.data) return resolve(result.data);
          reject(new Error('no_qr'));
        } catch (err) {
          reject(err);
        }
      };
      img.onerror = function () {
        URL.revokeObjectURL(url);
        reject(new Error('invalid_image'));
      };
      img.src = url;
    });
  }

  async function startCameraScan() {
    $('importError').hidden = true;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      $('importError').textContent = t('errCameraDenied');
      $('importError').hidden = false;
      return;
    }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'environment' } },
        audio: false,
      });
      state.cameraStream = stream;
      const video = $('cameraVideo');
      video.srcObject = stream;
      await video.play();
      $('cameraBox').hidden = false;

      const canvas = document.createElement('canvas');
      const ctx = canvas.getContext('2d', { willReadFrequently: true });
      let lastTick = 0;

      const scanFrame = function (ts) {
        if (!state.cameraStream) return;
        if (ts - lastTick >= 180 && video.readyState >= 2 && video.videoWidth > 0) {
          lastTick = ts;
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
          const imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
          if (typeof window.jsQR === 'function') {
            const hit = window.jsQR(imgData.data, canvas.width, canvas.height, { inversionAttempts: 'dontInvert' });
            if (hit && hit.data) {
              stopCamera();
              handleDecodedOtpPayload(hit.data);
              return;
            }
          }
        }
        state.cameraRaf = requestAnimationFrame(scanFrame);
      };
      state.cameraRaf = requestAnimationFrame(scanFrame);
    } catch (_) {
      $('importError').textContent = t('errCameraDenied');
      $('importError').hidden = false;
    }
  }

  function stopCamera() {
    if (state.cameraRaf) {
      cancelAnimationFrame(state.cameraRaf);
      state.cameraRaf = 0;
    }
    if (state.cameraStream) {
      state.cameraStream.getTracks().forEach(function (track) { track.stop(); });
      state.cameraStream = null;
    }
    const video = $('cameraVideo');
    if (video) video.srcObject = null;
    if ($('cameraBox')) $('cameraBox').hidden = true;
  }

  function setImportPreview(entries, skippedHotp) {
    state.pendingImport = entries || [];
    $('importError').hidden = true;
    if (!state.pendingImport.length) {
      $('importPreviewBox').hidden = true;
      $('confirmImportBtn').disabled = true;
      $('importError').textContent = t('errNoEntriesParsed');
      $('importError').hidden = false;
      return;
    }
    $('importPreviewBox').hidden = false;
    $('confirmImportBtn').disabled = false;
    $('importPreviewSummary').textContent =
      skippedHotp > 0
        ? t('previewHotpSkipped', { n: state.pendingImport.length, h: skippedHotp })
        : t('previewSummary', { n: state.pendingImport.length });
    $('importPreviewList').innerHTML = state.pendingImport
      .slice(0, 60)
      .map(function (item) {
        const sub = item.username || item.url || item.issuer || '';
        const badges = [];
        if (item.password) badges.push('PWD');
        if (item.totp && item.totp.secret) badges.push('2FA');
        return (
          '<div class="import-preview-row">' +
          '<div><strong>' + esc(item.title) + '</strong>' + (sub ? ' <small>' + esc(sub) + '</small>' : '') + '</div>' +
          '<div>' + badges.map(function (b) { return '<span class="mini-tag">' + b + '</span>'; }).join(' ') + '</div>' +
          '</div>'
        );
      })
      .join('');
  }

  function handleDecodedOtpPayload(text) {
    try {
      const res = VaultImport.parseAnyOtpText(text);
      setImportPreview(res.entries, res.skippedHotp);
    } catch (_) {
      $('importPreviewBox').hidden = true;
      $('confirmImportBtn').disabled = true;
      $('importError').textContent = t('errNoEntriesParsed');
      $('importError').hidden = false;
    }
  }

  function entryFingerprint(e) {
    return [
      (e.title || '').toLowerCase(),
      (e.username || '').toLowerCase(),
      e.password || '',
      (e.totp && e.totp.secret) || '',
    ].join('\u0000');
  }

  async function commitPendingImport() {
    if (!state.pendingImport.length || !state.vault) return;
    const skipDup = $('skipDuplicateCheck').checked;
    const existingSet = new Set(state.vault.entries.map(entryFingerprint));
    let added = 0;
    let skipped = 0;
    const now = Date.now();

    for (let i = 0; i < state.pendingImport.length; i++) {
      const item = state.pendingImport[i];
      const fp = entryFingerprint(item);
      if (skipDup && existingSet.has(fp)) {
        skipped++;
        continue;
      }
      existingSet.add(fp);
      state.vault.entries.unshift({
        id: genId(),
        title: item.title || 'Untitled',
        category: item.category || (item.totp && !item.password ? 'totp' : 'web'),
        issuer: item.issuer || '',
        username: item.username || '',
        password: item.password || '',
        url: item.url || '',
        notes: item.notes || '',
        favorite: !!item.favorite,
        totp: item.totp || null,
        createdAt: now,
        updatedAt: now,
      });
      added++;
    }

    try {
      await persistVault();
      closeModal('importModal');
      showToast(
        skipped > 0
          ? t('msgImportedSkipped', { n: added, s: skipped })
          : t('msgImported', { n: added })
      );
      if (added > 0 && state.vault.entries.length) {
        state.selectedId = state.vault.entries[0].id;
      }
      renderEntries();
      if (state.selectedId) renderDetailView();
    } catch (_) {
      showToast(t('errSaveFailed'), true);
    }
  }

  // QR Export Modal
  function openQrExportModal(entry) {
    const uri = VaultImport.buildOtpAuthURI(entry);
    if (!uri || typeof window.qrcode !== 'function') return;
    state.currentExportUri = uri;
    const qr = window.qrcode(0, 'M');
    qr.addData(uri);
    qr.make();
    $('qrSvgWrap').innerHTML = qr.createSvgTag({ cellSize: 5, margin: 0, scalable: true });
    $('qrEntryName').textContent = entry.title || '';
    $('qrEntrySub').textContent = [entry.issuer, entry.username].filter(Boolean).join(' · ');
    openModal('qrModal');
  }

  // Encrypted Backup Download & Workspace Snapshots
  function downloadEncryptedBackup() {
    if (!state.rawEnvelope) return;
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const blob = new Blob([state.rawEnvelope], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'bookstark-vault-' + ts + '.bsvault.json';
    a.click();
    setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
  }

  async function refreshSnapshotList() {
    const host = $('snapshotList');
    if (!hasWorkspaceFiles()) {
      host.innerHTML = '<p class="muted-text" style="font-size:12px;">' + esc(t('backupSnapshotsUnavailable')) + '</p>';
      $('saveWorkspaceSnapshotBtn').disabled = true;
      return;
    }
    $('saveWorkspaceSnapshotBtn').disabled = false;
    try {
      const exists = await window.BookStark.files.exists('backups');
      if (!exists) {
        host.innerHTML = '<p class="muted-text" style="font-size:12px;">' + esc(t('noSnapshots')) + '</p>';
        return;
      }
      const items = await window.BookStark.files.list('backups');
      const files = (items || [])
        .filter(function (x) { return !x.is_directory && x.name.endsWith('.bsvault.json'); })
        .sort(function (a, b) { return String(b.name).localeCompare(String(a.name)); });
      if (!files.length) {
        host.innerHTML = '<p class="muted-text" style="font-size:12px;">' + esc(t('noSnapshots')) + '</p>';
        return;
      }
      host.innerHTML = files
        .slice(0, 8)
        .map(function (f) {
          return (
            '<div class="snapshot-row">' +
            '<code>' + esc(f.name) + '</code>' +
            '<div style="display:flex;gap:4px;">' +
            '<button type="button" class="btn-secondary btn-xs" data-dl-snap="' + esc(f.path) + '">' + esc(t('downloadEncBackup').split(' ')[0]) + '</button>' +
            '<button type="button" class="btn-danger-outline btn-xs" data-del-snap="' + esc(f.path) + '"><i class="fa-solid fa-trash"></i></button>' +
            '</div></div>'
          );
        })
        .join('');
      host.querySelectorAll('[data-dl-snap]').forEach(function (btn) {
        btn.onclick = async function () {
          try {
            const bytes = await window.BookStark.files.read(btn.getAttribute('data-dl-snap'));
            const blob = new Blob([bytes], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = btn.getAttribute('data-dl-snap').split('/').pop();
            a.click();
            setTimeout(function () { URL.revokeObjectURL(url); }, 10000);
          } catch (_) {
            showToast(t('errSaveFailed'), true);
          }
        };
      });
      host.querySelectorAll('[data-del-snap]').forEach(function (btn) {
        btn.onclick = async function () {
          try {
            await window.BookStark.files.remove(btn.getAttribute('data-del-snap'));
            refreshSnapshotList();
          } catch (_) {
            showToast(t('errSaveFailed'), true);
          }
        };
      });
    } catch (_) {
      host.innerHTML = '<p class="muted-text" style="font-size:12px;">' + esc(t('noSnapshots')) + '</p>';
    }
  }

  async function saveWorkspaceSnapshot() {
    if (!hasWorkspaceFiles() || !state.rawEnvelope) return;
    const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
    const path = 'backups/vault-' + ts + '.bsvault.json';
    try {
      await window.BookStark.files.write(path, state.rawEnvelope);
      showToast(t('msgSnapshotSaved'));
      refreshSnapshotList();
    } catch (_) {
      showToast(t('errSaveFailed'), true);
    }
  }

  // Modal helpers
  function openModal(id) {
    $(id).hidden = false;
  }
  function closeModal(id) {
    if (id === 'importModal') stopCamera();
    $(id).hidden = true;
  }
  function closeAllModals() {
    ['importModal', 'qrModal', 'settingsModal'].forEach(closeModal);
  }
  function closeMobileSidebar() {
    $('catSidebar').classList.remove('open');
    $('sidebarShade').hidden = true;
  }

  // Unlock / Setup submit
  async function handleLockSubmit(event) {
    event.preventDefault();
    const pwd = $('masterPassword').value;
    const errEl = $('lockError');
    errEl.hidden = true;

    if (pwd.length < 6) {
      errEl.textContent = t('errPwdTooShort');
      errEl.hidden = false;
      return;
    }

    const submitBtn = $('lockSubmitBtn');
    submitBtn.disabled = true;

    try {
      if (state.mode === 'setup') {
        const confirmPwd = $('confirmMasterPassword').value;
        if (pwd !== confirmPwd) {
          errEl.textContent = t('errPwdMismatch');
          errEl.hidden = false;
          return;
        }
        $('lockSubmitText').textContent = t('creatingBtn');
        const initialVault = { v: 1, entries: [] };
        const res = await VaultCrypto.encryptVault(initialVault, pwd);
        await saveEncryptedEnvelope(res.envelope);
        state.derivedKey = res.key;
        state.cryptoMeta = res.meta;
        state.vault = initialVault;
      } else {
        $('lockSubmitText').textContent = t('unlockingBtn');
        const res = await VaultCrypto.decryptVault(state.rawEnvelope, pwd);
        state.derivedKey = res.key;
        state.cryptoMeta = res.meta;
        state.vault = res.data && Array.isArray(res.data.entries) ? res.data : { v: 1, entries: [] };
      }

      state.mode = 'unlocked';
      $('masterPassword').value = '';
      $('confirmMasterPassword').value = '';
      $('lockScreen').hidden = true;
      $('workspace').hidden = false;
      resetIdleTimer();
      renderEntries();
      if (state.vault.entries.length) {
        state.selectedId = state.vault.entries[0].id;
        renderEntries();
        renderDetailView();
      } else {
        renderDetailView();
      }
    } catch (err) {
      errEl.textContent =
        err && err.message === 'wrong_password'
          ? t('errWrongPwd')
          : err && err.message === 'invalid_envelope'
          ? t('errInvalidEnvelope')
          : t('errSaveFailed');
      errEl.hidden = false;
    } finally {
      submitBtn.disabled = false;
      if (state.mode !== 'unlocked') renderLockModeUI();
    }
  }

  // Change Master Password
  async function handleChangeMaster(event) {
    event.preventDefault();
    const oldPwd = $('oldMasterInput').value;
    const newPwd = $('newMasterInput').value;
    const confirmPwd = $('newMasterConfirm').value;
    const errEl = $('changeMasterError');
    errEl.hidden = true;

    if (newPwd.length < 6) {
      errEl.textContent = t('errPwdTooShort');
      errEl.hidden = false;
      return;
    }
    if (newPwd !== confirmPwd) {
      errEl.textContent = t('errPwdMismatch');
      errEl.hidden = false;
      return;
    }

    const btn = $('changeMasterSubmitBtn');
    btn.disabled = true;
    try {
      await VaultCrypto.decryptVault(state.rawEnvelope, oldPwd);
      const next = await VaultCrypto.encryptVault(state.vault, newPwd);
      await saveEncryptedEnvelope(next.envelope);
      state.derivedKey = next.key;
      state.cryptoMeta = next.meta;
      $('oldMasterInput').value = '';
      $('newMasterInput').value = '';
      $('newMasterConfirm').value = '';
      showToast(t('msgMasterChanged'));
    } catch (err) {
      errEl.textContent = err && err.message === 'wrong_password' ? t('errWrongPwd') : t('errSaveFailed');
      errEl.hidden = false;
    } finally {
      btn.disabled = false;
    }
  }

  function bindEvents() {
    $('lockForm').addEventListener('submit', handleLockSubmit);
    $('masterPassword').addEventListener('input', updateStrengthMeter);
    $('toggleMasterVis').onclick = function () {
      const inp = $('masterPassword');
      const showing = inp.type === 'text';
      inp.type = showing ? 'password' : 'text';
      this.innerHTML = '<i class="fa-solid ' + (showing ? 'fa-eye' : 'fa-eye-slash') + '" aria-hidden="true"></i>';
    };

    $('lockLangBtn').onclick = toggleLang;
    $('langToggleBtn').onclick = toggleLang;

    // Restore encrypted backup directly from lock screen
    $('restoreBackupFromLock').onclick = function () { $('lockBackupFileInput').click(); };
    $('lockBackupFileInput').onchange = async function () {
      const file = this.files && this.files[0];
      this.value = '';
      if (!file) return;
      try {
        const text = await file.text();
        const parsed = JSON.parse(text);
        if (!parsed || parsed.v !== 1 || parsed.cipher !== 'AES-256-GCM') {
          throw new Error('invalid_envelope');
        }
        await saveEncryptedEnvelope(parsed);
        state.mode = 'unlock';
        renderLockModeUI();
        $('lockError').hidden = true;
        showToast(t('msgBackupRestored'));
        $('masterPassword').focus();
      } catch (_) {
        $('lockError').textContent = t('errInvalidEnvelope');
        $('lockError').hidden = false;
      }
    };

    // Category sidebar & mobile drawer
    $('catNav').addEventListener('click', function (e) {
      const btn = e.target.closest('.cat-item');
      if (!btn) return;
      state.activeCategory = btn.getAttribute('data-cat');
      $('catNav').querySelectorAll('.cat-item').forEach(function (x) {
        x.classList.toggle('active', x === btn);
      });
      closeMobileSidebar();
      renderEntries();
    });

    $('openSidebarBtn').onclick = function () {
      $('catSidebar').classList.add('open');
      $('sidebarShade').hidden = false;
    };
    $('closeSidebarBtn').onclick = closeMobileSidebar;
    $('sidebarShade').onclick = closeMobileSidebar;

    $('searchInput').addEventListener('input', function () {
      state.search = this.value;
      renderEntries();
    });

    // Entry list click, quick TOTP copy & quick field copy
    $('entryList').addEventListener('click', function (e) {
      const quickBtn = e.target.closest('[data-quick-copy]');
      if (quickBtn) {
        e.stopPropagation();
        const id = quickBtn.getAttribute('data-entry-id');
        const kind = quickBtn.getAttribute('data-quick-copy');
        const entry = state.vault && state.vault.entries.find(function (x) { return x.id === id; });
        if (!entry) return;
        if (kind === 'ssh') copyText(VaultCrypto.buildSshCommand(entry), false);
        else if (kind === 'username') copyText(entry.username || '', false);
        else if (kind === 'password') copyText(entry.password || '', true);
        return;
      }
      const copyBtn = e.target.closest('[data-copy-totp]');
      if (copyBtn) {
        e.stopPropagation();
        copyEntryTotp(copyBtn.getAttribute('data-copy-totp'));
        return;
      }
      const card = e.target.closest('[data-entry-id]');
      if (!card) return;
      state.selectedId = card.getAttribute('data-entry-id');
      state.showDetailPassword = false;
      state.showDetailSshKey = false;
      state.showDetailNote = false;
      state.revealedCustomFields = Object.create(null);
      renderEntries();
      renderDetailView();
    });

    $('clipClearNowBtn').onclick = function () { clearClipboardNow(true); };

    // Category picker & dynamic form interactions
    $('catPicker').addEventListener('click', function (e) {
      const btn = e.target.closest('[data-pick-cat]');
      if (!btn) return;
      applyFormCategory(btn.getAttribute('data-pick-cat'));
    });
    $('fCategory').addEventListener('change', function () {
      applyFormCategory(this.value);
    });
    $('toggleTotpSectionBtn').onclick = function () {
      if ($('fCategory').value === 'totp') return;
      state.formTotpOpen = !state.formTotpOpen;
      syncTotpCollapseUI();
    };
    $('toggleTotpAdvBtn').onclick = function () {
      state.formTotpAdvOpen = !state.formTotpAdvOpen;
      syncTotpCollapseUI();
    };
    $('addCustomFieldBtn').onclick = function () {
      addCustomFieldRow({ label: '', value: '', secret: false });
    };
    ['fHost', 'fPort', 'fUsername'].forEach(function (id) {
      $(id).addEventListener('input', updateFormSshPreview);
    });
    $('copyFormSshBtn').onclick = function () {
      copyText($('formSshPreviewCode').textContent || '', false);
    };
    $('fPassword').addEventListener('input', updateEntryPasswordStrength);
    ['fTotpSecret', 'fTotpAlgo', 'fTotpDigits', 'fTotpPeriod'].forEach(function (id) {
      $(id).addEventListener('input', updateFormTotpPreview);
      $(id).addEventListener('change', updateFormTotpPreview);
    });

    // Create / edit form
    $('newEntryBtn').onclick = function () { openEntryForm(null); };
    $('mobileAddBtn').onclick = function () { openEntryForm(null); };
    $('emptyNewBtn').onclick = function () { openEntryForm(null); };
    $('cancelEntryBtn').onclick = function () {
      state.editing = false;
      renderDetailView();
    };
    $('formBackBtn').onclick = function () {
      state.editing = false;
      $('workspace').classList.remove('show-detail');
      renderDetailView();
    };
    $('entryForm').addEventListener('submit', saveEntryForm);

    $('toggleEntryPwdVis').onclick = function () {
      const inp = $('fPassword');
      const showing = inp.type === 'text';
      inp.type = showing ? 'password' : 'text';
      this.innerHTML = '<i class="fa-solid ' + (showing ? 'fa-eye' : 'fa-eye-slash') + '" aria-hidden="true"></i>';
    };

    $('toggleGenBtn').onclick = function () {
      $('genPanel').hidden = !$('genPanel').hidden;
    };
    $('genLen').oninput = function () {
      $('genLenVal').textContent = this.value;
    };
    $('runGenBtn').onclick = function () {
      const pwd = VaultCrypto.generatePassword({
        length: Number($('genLen').value),
        upper: $('genUpper').checked,
        lower: $('genLower').checked,
        digits: $('genDigits').checked,
        symbols: $('genSymbols').checked,
      });
      $('fPassword').value = pwd;
      $('fPassword').type = 'text';
      updateEntryPasswordStrength();
    };

    $('fTotpSecret').addEventListener('paste', function (e) {
      const text = (e.clipboardData && e.clipboardData.getData('text')) || '';
      if (text.trim().startsWith('otpauth://')) {
        e.preventDefault();
        fillFormFromOtpText(text.trim());
      }
    });

    $('quickScanQrBtn').onclick = function () { $('quickQrFileInput').click(); };
    $('quickQrFileInput').onchange = async function () {
      const file = this.files && this.files[0];
      this.value = '';
      if (!file) return;
      try {
        const decoded = await decodeQRFromBlob(file);
        if (!fillFormFromOtpText(decoded)) {
          showToast(t('errInvalidSecret'), true);
        }
      } catch (_) {
        showToast(t('errNoQrFound'), true);
      }
    };

    // Lock triggers
    $('lockNowBtn').onclick = function () { lockVault('msgLocked'); };
    $('mobileLockBtn').onclick = function () { lockVault('msgLocked'); };

    // Import Modal
    const openImport = function () {
      closeMobileSidebar();
      state.pendingImport = [];
      $('importPreviewBox').hidden = true;
      $('importError').hidden = true;
      $('confirmImportBtn').disabled = true;
      $('otpTextInput').value = '';
      $('csvTextInput').value = '';
      $('backupPasswordInput').value = '';
      openModal('importModal');
    };
    $('openImportBtn').onclick = openImport;
    $('emptyImportBtn').onclick = openImport;

    document.querySelectorAll('[data-import-tab]').forEach(function (tab) {
      tab.onclick = function () {
        stopCamera();
        const name = tab.getAttribute('data-import-tab');
        document.querySelectorAll('[data-import-tab]').forEach(function (x) {
          x.classList.toggle('active', x === tab);
        });
        $('importTabQr').hidden = name !== 'qr';
        $('importTabCsv').hidden = name !== 'csv';
        $('importTabBackup').hidden = name !== 'backup';
        $('importError').hidden = true;
      };
    });

    $('pickQrImgBtn').onclick = function () { $('importQrFileInput').click(); };
    $('importQrFileInput').onchange = async function () {
      const file = this.files && this.files[0];
      this.value = '';
      if (!file) return;
      try {
        const decoded = await decodeQRFromBlob(file);
        handleDecodedOtpPayload(decoded);
      } catch (_) {
        $('importError').textContent = t('errNoQrFound');
        $('importError').hidden = false;
      }
    };

    const dz = $('qrDropzone');
    dz.addEventListener('dragover', function (e) {
      e.preventDefault();
      dz.classList.add('dragover');
    });
    dz.addEventListener('dragleave', function () { dz.classList.remove('dragover'); });
    dz.addEventListener('drop', async function (e) {
      e.preventDefault();
      dz.classList.remove('dragover');
      const file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
      if (!file) return;
      try {
        const decoded = await decodeQRFromBlob(file);
        handleDecodedOtpPayload(decoded);
      } catch (_) {
        $('importError').textContent = t('errNoQrFound');
        $('importError').hidden = false;
      }
    });

    // Global paste screenshot handler (works in Import modal AND directly in Entry Form)
    document.addEventListener('paste', async function (e) {
      const inImportQr = !$('importModal').hidden && !$('importTabQr').hidden;
      const inForm = state.editing && $('importModal').hidden;
      if (!inImportQr && !inForm) return;
      const items = e.clipboardData && e.clipboardData.items;
      if (!items) return;
      for (let i = 0; i < items.length; i++) {
        if (items[i].type && items[i].type.startsWith('image/')) {
          const blob = items[i].getAsFile();
          if (blob) {
            e.preventDefault();
            try {
              const decoded = await decodeQRFromBlob(blob);
              if (inImportQr) {
                handleDecodedOtpPayload(decoded);
              } else if (!fillFormFromOtpText(decoded)) {
                showToast(t('errInvalidSecret'), true);
              }
            } catch (_) {
              if (inImportQr) {
                $('importError').textContent = t('errNoQrFound');
                $('importError').hidden = false;
              } else {
                showToast(t('errNoQrFound'), true);
              }
            }
            return;
          }
        }
      }
    });

    $('startCameraBtn').onclick = startCameraScan;
    $('stopCameraBtn').onclick = stopCamera;
    $('parseOtpTextBtn').onclick = function () {
      handleDecodedOtpPayload($('otpTextInput').value);
    };

    $('pickCsvFileBtn').onclick = function () { $('importCsvFileInput').click(); };
    $('importCsvFileInput').onchange = async function () {
      const file = this.files && this.files[0];
      this.value = '';
      if (!file) return;
      const text = await file.text();
      $('csvTextInput').value = text;
      try {
        const entries = VaultImport.parsePasswordCSV(text);
        setImportPreview(entries, 0);
      } catch (_) {
        $('importError').textContent = t('errNoEntriesParsed');
        $('importError').hidden = false;
      }
    };
    $('parseCsvTextBtn').onclick = function () {
      try {
        const entries = VaultImport.parsePasswordCSV($('csvTextInput').value);
        setImportPreview(entries, 0);
      } catch (_) {
        $('importError').textContent = t('errNoEntriesParsed');
        $('importError').hidden = false;
      }
    };

    $('decryptBackupBtn').onclick = async function () {
      const file = $('backupFileInput').files && $('backupFileInput').files[0];
      const pwd = $('backupPasswordInput').value;
      if (!file || !pwd) {
        $('importError').textContent = t('errSelectBackup');
        $('importError').hidden = false;
        return;
      }
      try {
        const text = await file.text();
        const res = await VaultCrypto.decryptVault(text, pwd);
        const entries = (res.data && Array.isArray(res.data.entries)) ? res.data.entries : [];
        setImportPreview(entries, 0);
      } catch (err) {
        $('importError').textContent =
          err && err.message === 'wrong_password' ? t('errWrongPwd') : t('errInvalidEnvelope');
        $('importError').hidden = false;
      }
    };

    $('confirmImportBtn').onclick = commitPendingImport;

    // QR Export Modal
    $('copyOtpUriBtn').onclick = function () { copyText(state.currentExportUri); };

    // Security & Settings Modal
    $('openSettingsBtn').onclick = function () {
      closeMobileSidebar();
      $('autoLockSelect').value = String(state.autoLockMinutes);
      $('clipClearSelect').value = String(state.clipClearSeconds);
      $('changeMasterError').hidden = true;
      $('oldMasterInput').value = '';
      $('newMasterInput').value = '';
      $('newMasterConfirm').value = '';
      openModal('settingsModal');
      refreshSnapshotList();
    };
    $('autoLockSelect').onchange = function () {
      state.autoLockMinutes = Number(this.value);
      try { localStorage.setItem(PREF_AUTOLOCK_KEY, String(state.autoLockMinutes)); } catch (_) {}
      resetIdleTimer();
      showToast(t('msgSaved'));
    };
    $('clipClearSelect').onchange = function () {
      state.clipClearSeconds = Number(this.value);
      try { localStorage.setItem(PREF_CLIPCLEAR_KEY, String(state.clipClearSeconds)); } catch (_) {}
      if (!state.clipClearSeconds) {
        state.clipClearDeadline = 0;
        updateClipClearBanner();
      }
      showToast(t('msgSaved'));
    };
    $('changeMasterForm').addEventListener('submit', handleChangeMaster);
    $('downloadBackupBtn').onclick = downloadEncryptedBackup;
    $('saveWorkspaceSnapshotBtn').onclick = saveWorkspaceSnapshot;

    // Modal close buttons & Esc
    document.querySelectorAll('[data-close-modal]').forEach(function (btn) {
      btn.onclick = function () { closeModal(btn.getAttribute('data-close-modal')); };
    });
    document.querySelectorAll('.modal-backdrop').forEach(function (backdrop) {
      backdrop.addEventListener('click', function (e) {
        if (e.target === backdrop) closeModal(backdrop.id);
      });
    });

    // Global activity & keyboard shortcuts
    ['pointerdown', 'keydown', 'touchstart', 'wheel'].forEach(function (evt) {
      document.addEventListener(evt, resetIdleTimer, { passive: true });
    });
    document.addEventListener('keydown', function (e) {
      if ((e.ctrlKey || e.metaKey) && e.shiftKey && e.key.toLowerCase() === 'l') {
        if (state.mode === 'unlocked') {
          e.preventDefault();
          lockVault('msgLocked');
        }
      } else if (e.key === 'Escape') {
        const openModalEl = document.querySelector('.modal-backdrop:not([hidden])');
        if (openModalEl) {
          e.preventDefault();
          closeModal(openModalEl.id);
        }
      }
    });
  }

  async function init() {
    bindEvents();
    applyI18n();

    try {
      state.rawEnvelope = await loadEncryptedEnvelope();
    } catch (_) {
      state.rawEnvelope = null;
    }

    state.mode = state.rawEnvelope ? 'unlock' : 'setup';
    renderLockModeUI();
    $('lockScreen').hidden = false;
    $('workspace').hidden = true;
    $('masterPassword').focus();

    // 1-second loop for live TOTP ticks, form preview, clipboard countdown & auto-lock
    setInterval(function () {
      if (state.mode !== 'unlocked') return;
      if (state.idleDeadline && Date.now() >= state.idleDeadline) {
        lockVault('msgAutoLocked');
        return;
      }
      refreshAllTotpDisplay();
      if (state.editing) updateFormTotpPreview();
      if (state.clipClearDeadline) updateClipClearBanner();
    }, 1000);
  }

  init();
})();
