import {
  Adb,
  AdbDaemonTransport,
  AdbPacket,
  AdbPacketSerializeStream,
} from "@yume-chan/adb";
import { AdbScrcpyClient, AdbScrcpyOptions3_3_3 } from "@yume-chan/adb-scrcpy";
import {
  AndroidKeyCode,
  AndroidKeyEventAction,
  AndroidKeyEventMeta,
  AndroidMotionEventAction,
  AndroidMotionEventButton,
  AndroidScreenPowerMode,
  ScrcpyPointerId,
} from "@yume-chan/scrcpy";
import {
  BitmapVideoFrameRenderer,
  WebCodecsVideoDecoder,
} from "@yume-chan/scrcpy-decoder-webcodecs";
import {
  Consumable,
  ReadableStream,
  StructDeserializeStream,
  WritableStream,
} from "@yume-chan/stream-extra";

const ADB_RSA_SECRET_NAME = "bookstark_adb_rsa_pkcs8_b64";

function bytesToBase64(bytes) {
  let bin = "";
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function base64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

class BookStarkAdbCredentialStore {
  constructor(secretGet, secretSet) {
    this.secretGet = secretGet;
    this.secretSet = secretSet;
    this.name = "BookStark@RemoteDesktop";
  }

  async generateKey() {
    const keyPair = await crypto.subtle.generateKey(
      {
        name: "RSASSA-PKCS1-v1_5",
        modulusLength: 2048,
        publicExponent: new Uint8Array([1, 0, 1]),
        hash: "SHA-1",
      },
      true,
      ["sign", "verify"]
    );
    const pkcs8 = new Uint8Array(await crypto.subtle.exportKey("pkcs8", keyPair.privateKey));
    const b64 = bytesToBase64(pkcs8);
    try {
      await this.secretSet(ADB_RSA_SECRET_NAME, b64);
    } catch (_) {
      try { localStorage.setItem(ADB_RSA_SECRET_NAME, b64); } catch (__) {}
    }
    return { buffer: pkcs8, name: this.name };
  }

  async *iterateKeys() {
    let b64 = "";
    try {
      b64 = (await this.secretGet(ADB_RSA_SECRET_NAME)) || "";
    } catch (_) {}
    if (!b64) {
      try { b64 = localStorage.getItem(ADB_RSA_SECRET_NAME) || ""; } catch (_) {}
    }
    if (b64) {
      try {
        yield { buffer: base64ToBytes(b64), name: this.name };
      } catch (_) {}
    }
  }
}

function createTcpAdbConnection(toolSocket) {
  let closed = false;
  const rawReadable = new ReadableStream({
    start(controller) {
      toolSocket.binaryType = "arraybuffer";
      toolSocket.onmessage = (ev) => {
        if (closed) return;
        if (ev.data instanceof ArrayBuffer) {
          controller.enqueue(new Uint8Array(ev.data));
        } else if (ArrayBuffer.isView(ev.data)) {
          controller.enqueue(new Uint8Array(ev.data.buffer, ev.data.byteOffset, ev.data.byteLength));
        }
      };
      toolSocket.onclose = () => {
        if (closed) return;
        closed = true;
        try { controller.close(); } catch (_) {}
      };
      toolSocket.onerror = () => {
        if (closed) return;
        closed = true;
        try { controller.error(new Error("ADB TCP socket error")); } catch (_) {}
      };
    },
    cancel() {
      closed = true;
      try { toolSocket.close(); } catch (_) {}
    },
  });

  const readable = rawReadable.pipeThrough(new StructDeserializeStream(AdbPacket));

  const serializer = new AdbPacketSerializeStream();
  serializer.readable
    .pipeTo(
      new WritableStream({
        async write(chunk) {
          const data = chunk instanceof Consumable ? chunk.value : chunk;
          try {
            if (toolSocket.readyState !== 1) throw new Error("ADB socket closed");
            await toolSocket.send(data);
          } finally {
            if (chunk instanceof Consumable) chunk.consume();
          }
        },
        close() {
          try { toolSocket.close(); } catch (_) {}
        },
        abort() {
          try { toolSocket.close(); } catch (_) {}
        },
      })
    )
    .catch(() => {});

  return {
    readable,
    writable: serializer.writable,
  };
}

let cachedServerBytes = null;
async function loadScrcpyServerBytes() {
  if (cachedServerBytes) return cachedServerBytes;
  const resp = await fetch("scrcpy-server.bin");
  if (!resp.ok) throw new Error("无法加载内置 scrcpy-server.bin (" + resp.status + ")");
  cachedServerBytes = new Uint8Array(await resp.arrayBuffer());
  return cachedServerBytes;
}

async function connectAndroid(cfg) {
  const {
    toolSocket,
    serial,
    secretGet,
    secretSet,
    canvas,
    maxSize = 1280,
    bitRate = 4_000_000,
    maxFps = 60,
    enableAudio = true,
    onStatus = () => {},
    onSize = () => {},
    onClipboard = () => {},
    onAudioPcm = () => {},
    onAudioState = () => {},
    onDisconnected = () => {},
  } = cfg;

  if (!WebCodecsVideoDecoder.isSupported) {
    throw new Error("当前浏览器不支持 WebCodecs H.264 硬件解码，请使用新版 Chrome / Edge。");
  }

  onStatus("正在进行 ADB RSA 密钥握手（首次连接请在手机上点允许调试）…");
  const connection = createTcpAdbConnection(toolSocket);
  const credentialStore = new BookStarkAdbCredentialStore(secretGet, secretSet);
  const transport = await AdbDaemonTransport.authenticate({
    serial,
    connection,
    credentialStore,
  });
  const adb = new Adb(transport);

  transport.disconnected.then(() => {
    onDisconnected("ADB 连接已断开");
  });

  onStatus("ADB 认证成功，正在推送 scrcpy-server v3.3.3…");
  const serverBytes = await loadScrcpyServerBytes();
  const remoteServerPath = "/data/local/tmp/scrcpy-server.jar";
  await AdbScrcpyClient.pushServer(
    adb,
    new ReadableStream({
      start(controller) {
        controller.enqueue(serverBytes);
        controller.close();
      },
    }),
    remoteServerPath
  );

  onStatus("正在启动手机端 Scrcpy 投屏与控制服务…");
  const options = new AdbScrcpyOptions3_3_3({
    tunnelForward: true,
    video: true,
    videoCodec: "h264",
    maxSize: Number(maxSize) || 1280,
    videoBitRate: Number(bitRate) || 4_000_000,
    maxFps: Number(maxFps) || 60,
    audio: !!enableAudio,
    audioCodec: "raw",
    control: true,
    stayAwake: true,
    cleanup: true,
    sendDeviceMeta: true,
    sendCodecMeta: true,
  });

  const scrcpy = await AdbScrcpyClient.start(adb, remoteServerPath, options);

  // Consume server stdout so the process never stalls
  scrcpy.output
    .pipeTo(new WritableStream({ write() {} }))
    .catch(() => {});

  // Video stream -> WebCodecs hardware H.264 decoder -> Canvas
  const videoStream = await scrcpy.videoStream;
  if (!videoStream) {
    throw new Error("未能建立 Android 视频流");
  }
  const renderer = new BitmapVideoFrameRenderer(canvas);
  const decoder = new WebCodecsVideoDecoder({
    codec: videoStream.metadata.codec,
    renderer,
  });

  let videoWidth = videoStream.metadata.width || 0;
  let videoHeight = videoStream.metadata.height || 0;
  if (videoWidth && videoHeight) onSize(videoWidth, videoHeight);

  decoder.sizeChanged(({ width, height }) => {
    videoWidth = width;
    videoHeight = height;
    onSize(width, height);
  });

  videoStream.stream.pipeTo(decoder.writable).catch(() => {});

  // Audio stream (optional raw 48kHz 16-bit stereo PCM)
  if (enableAudio && scrcpy.audioStream) {
    scrcpy.audioStream
      .then((audioMeta) => {
        if (!audioMeta || audioMeta.type !== "success") {
          onAudioState(false, "设备不支持音频捕获（需 Android 11+）");
          return;
        }
        onAudioState(true, "Scrcpy RAW PCM 48kHz · 16-bit Stereo");
        audioMeta.stream
          .pipeTo(
            new WritableStream({
              write(packet) {
                if (packet.type === "data" && packet.data && packet.data.byteLength > 0) {
                  const buf = packet.data.buffer.slice(
                    packet.data.byteOffset,
                    packet.data.byteOffset + packet.data.byteLength
                  );
                  onAudioPcm(buf, 48000, 2, 16);
                }
              },
            })
          )
          .catch(() => {});
      })
      .catch(() => {
        onAudioState(false, "音频流不可用");
      });
  } else {
    onAudioState(false, "音频已关闭");
  }

  // Device clipboard stream
  if (scrcpy.clipboard) {
    scrcpy.clipboard
      .pipeTo(
        new WritableStream({
          write(text) {
            onClipboard(text);
          },
        })
      )
      .catch(() => {});
  }

  scrcpy.exited.then(() => {
    onDisconnected("Scrcpy 服务已退出");
  });

  const controller = scrcpy.controller;
  const deviceName = videoStream.metadata.deviceName || transport.banner.model || serial;

  return {
    deviceName,
    get width() {
      return videoWidth || canvas.width || 720;
    },
    get height() {
      return videoHeight || canvas.height || 1280;
    },
    async injectTouch(actionName, x, y, buttons = 0) {
      if (!controller) return;
      const actionMap = {
        down: AndroidMotionEventAction.Down,
        move: AndroidMotionEventAction.Move,
        up: AndroidMotionEventAction.Up,
        cancel: AndroidMotionEventAction.Cancel,
      };
      const action = actionMap[actionName] ?? AndroidMotionEventAction.Move;
      const w = videoWidth || canvas.width || 720;
      const h = videoHeight || canvas.height || 1280;
      await controller.injectTouch({
        action,
        pointerId: ScrcpyPointerId.Finger,
        pointerX: Math.max(0, Math.min(w - 1, Math.round(x))),
        pointerY: Math.max(0, Math.min(h - 1, Math.round(y))),
        videoWidth: w,
        videoHeight: h,
        pressure: action === AndroidMotionEventAction.Up ? 0 : 1,
        actionButton: buttons ? AndroidMotionEventButton.Primary : AndroidMotionEventButton.None,
        buttons: buttons ? AndroidMotionEventButton.Primary : AndroidMotionEventButton.None,
      });
    },
    async injectScroll(x, y, scrollX, scrollY) {
      if (!controller) return;
      const w = videoWidth || canvas.width || 720;
      const h = videoHeight || canvas.height || 1280;
      await controller.injectScroll({
        pointerX: Math.max(0, Math.min(w - 1, Math.round(x))),
        pointerY: Math.max(0, Math.min(h - 1, Math.round(y))),
        videoWidth: w,
        videoHeight: h,
        scrollX: Math.max(-1, Math.min(1, scrollX)),
        scrollY: Math.max(-1, Math.min(1, scrollY)),
        buttons: 0,
      });
    },
    async injectKeyCode(domCode, pressed, metaState = 0) {
      if (!controller) return;
      const code =
        typeof domCode === "number"
          ? domCode
          : AndroidKeyCode[domCode];
      if (code === undefined) return;
      await controller.injectKeyCode({
        action: pressed ? AndroidKeyEventAction.Down : AndroidKeyEventAction.Up,
        keyCode: code,
        repeat: 0,
        metaState: metaState || AndroidKeyEventMeta.None,
      });
    },
    async setClipboard(text, paste = false) {
      if (!controller) return;
      await controller.setClipboard({
        sequence: 0n,
        paste: !!paste,
        content: String(text || ""),
      });
    },
    async sendAndroidAction(action) {
      if (!controller) return;
      const tapKey = async (kc) => {
        await controller.injectKeyCode({
          action: AndroidKeyEventAction.Down,
          keyCode: kc,
          repeat: 0,
          metaState: AndroidKeyEventMeta.None,
        });
        await controller.injectKeyCode({
          action: AndroidKeyEventAction.Up,
          keyCode: kc,
          repeat: 0,
          metaState: AndroidKeyEventMeta.None,
        });
      };
      switch (action) {
        case "back":
          await controller.backOrScreenOn(AndroidKeyEventAction.Down);
          await controller.backOrScreenOn(AndroidKeyEventAction.Up);
          break;
        case "home":
          await tapKey(AndroidKeyCode.AndroidHome);
          break;
        case "recents":
          await tapKey(AndroidKeyCode.AndroidAppSwitch);
          break;
        case "power":
          await tapKey(AndroidKeyCode.Power);
          break;
        case "vol_up":
          await tapKey(AndroidKeyCode.VolumeUp);
          break;
        case "vol_down":
          await tapKey(AndroidKeyCode.VolumeDown);
          break;
        case "rotate":
          await controller.rotateDevice();
          break;
        case "notif":
          await controller.expandNotificationPanel();
          break;
        case "screen_off":
          await controller.setScreenPowerMode(AndroidScreenPowerMode.Off);
          break;
        case "screen_on":
          await controller.setScreenPowerMode(AndroidScreenPowerMode.Normal);
          break;
      }
    },
    async listDir(dirPath = "/sdcard/Download") {
      const sync = await adb.sync();
      try {
        const entries = await sync.readdir(dirPath);
        return entries
          .filter((e) => e.name !== "." && e.name !== "..")
          .map((e) => ({
            name: e.name,
            size: Number(e.size || 0),
            isDir: e.type === 4, // LinuxFileType.Directory
            mtime: Number(e.mtime || 0) * 1000,
          }))
          .sort((a, b) => Number(b.isDir) - Number(a.isDir) || a.name.localeCompare(b.name));
      } finally {
        await sync.dispose();
      }
    },
    async pushFile(remotePath, bytes) {
      const sync = await adb.sync();
      try {
        await sync.write({
          filename: remotePath,
          file: new ReadableStream({
            start(c) {
              c.enqueue(bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes));
              c.close();
            },
          }),
        });
      } finally {
        await sync.dispose();
      }
    },
    async pullFile(remotePath) {
      const sync = await adb.sync();
      try {
        const chunks = [];
        let total = 0;
        const stream = sync.read(remotePath);
        await stream.pipeTo(
          new WritableStream({
            write(chunk) {
              chunks.push(chunk);
              total += chunk.byteLength;
            },
          })
        );
        const out = new Uint8Array(total);
        let off = 0;
        for (const c of chunks) {
          out.set(c, off);
          off += c.byteLength;
        }
        return out;
      } finally {
        await sync.dispose();
      }
    },
    async installApk(fileName, bytes) {
      const safeName = String(fileName || "app.apk").replace(/[^a-zA-Z0-9._-]/g, "_");
      const tmpPath = "/data/local/tmp/" + safeName;
      await this.pushFile(tmpPath, bytes);
      const proc = await adb.subprocess.noneProtocol.spawnWaitText(
        ["pm", "install", "-r", tmpPath]
      );
      await adb.subprocess.noneProtocol.spawnWaitText(["rm", "-f", tmpPath]).catch(() => {});
      return proc;
    },
    async close() {
      try { await scrcpy.close(); } catch (_) {}
      try { decoder.dispose(); } catch (_) {}
      try { await adb.close(); } catch (_) {}
    },
  };
}

window.BookStarkAndroid = {
  connect: connectAndroid,
  AndroidKeyCode,
  isWebCodecsSupported: () => WebCodecsVideoDecoder.isSupported,
};
