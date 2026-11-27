# 远程桌面（RDP + VNC）— BookStark 工具

一体化浏览器内远程桌面工作台，原生支持 **Windows / xrdp RDP（Rust IronRDP WASM）** 与 **Linux / macOS / PVE VNC（noVNC）**，直接复用 BookStark `BookStark.sockets` 裸 TCP 隧道，无需部署向日葵、Guacamole 或 `websockify`。

## 核心能力
- **双协议零网关直连**：
  - **RDP（默认 3389）**：基于 Rust `ironrdp-connector` + `ironrdp-session` + `ironrdp-graphics` + 纯 Rust TLS（`rustls` + `rustls-rustcrypto`）编译为 WASM 运行于 Web Worker，支持 TLS 1.2/1.3 与 NLA/CredSSP（NTLMv2）。
  - **VNC（默认 5900）**：内嵌 `noVNC` RFB 协议层直连 `BookStark.sockets`，支持 Tight / ZRLE / Raw 编码与画质/只读模式。
- **多主机管理与多会话标签**：可折叠侧边栏，支持按协议筛选、搜索、同时保持多个 RDP/VNC 会话并随时切换。
- **安全机制**：
  - 登录密码通过 `BookStark.secrets`（AES-256-GCM）加密托管；
  - RDP 首次连接展示服务器证书主体与 `SHA-256` 指纹（TOFU），指纹变化时弹窗告警。
- **专业虚拟键盘与手机触控板**：
  - 精简粘滞修饰键条（`Ctrl` / `Alt` / `Shift` / `Win` 点一下锁定，再按任意键自动合成组合键后释放）；
  - 完整 6 行 PC 悬浮虚拟键盘 + 本机输入法中文直传（Unicode Scancode / Keysym）；
  - 手机端虚拟触控板（单指移指针不遮挡视线、轻点左键、双指轻点右键、双指滚动 + 实体左/中/右键）。
- **RDP 音频回传 & 双向文件传输**：
  - `ironrdp-rdpsnd`（静态通道 + `AUDIO_PLAYBACK_DVC`）PCM 音频经 Web Audio `AudioWorklet` 环形队列低延迟播放，带立体声电平表与 40/80/160ms 缓冲切换；
  - `ironrdp-cliprdr` 双向剪贴板（文本 + 拖拽/Ctrl+C/V 文件延迟传输）；
  - `ironrdp-rdpdr` 虚拟共享盘（在远端 Windows 挂载 `\\tsclient\BookStark`）。

## 构建与测试
```bash
# 重新打包 noVNC 经典 IIFE 产物（仅升级 noVNC 时需要）
cd novnc-vendor && node build.mjs

# 编译 Rust IronRDP WASM 并打包 BookStark ZIP
python3 build.py

# 运行 Rust 原生单元测试（含 localhost:3389 xrdp 实时握手测试）
cd rdp-wasm && cargo test -- --nocapture

# 运行 Playwright 端到端实时测试（RDP + VNC + 移动端触控板/虚拟键盘）
node tests/e2e-localhost.mjs
```
