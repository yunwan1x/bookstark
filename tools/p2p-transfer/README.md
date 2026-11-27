# 极速快传 · WebRTC 点对点 (`p2p-transfer`)

基于 WebRTC `RTCDataChannel` 的 BookStark 独立工具包，用于跨设备点对点传输文件与实时共享剪贴板。

## 核心能力

- **零服务端文件落盘**：服务端仅通过 BookStark 内置 `/api/webrtc-signaling/ws` 交换 SDP 与 ICE 信令，文件内容全程走端到端 DTLS 加密的 WebRTC DataChannel 直传。
- **6 位取件码 + 离线二维码配对**：自动生成 6 位数字配对房间码与离线 SVG 二维码，支持另一端输入取件码、粘贴配对串、摄像头扫码或上传二维码图片快速配对。
- **实时网络路径与延迟监测**：通过 `RTCPeerConnection.getStats()` 实时识别 `局域网直连 (host)`、`公网穿透 (srflx/prflx)` 与 `中继转发 (relay)`，展示 RTT 延迟。
- **大文件背压流控与 SHA-256 校验**：64 KiB 二进制分片（`BSP2` 帧头，支持多文件并发交错传输）+ `bufferedAmount` 背压流控，接收端自动计算 SHA-256 并回传校验结果。
- **跨设备实时共享剪贴板**：文本、链接、代码片段毫秒级同步至所有已配对设备，支持一键复制。

## 构建与测试

```bash
# 1. 运行协议单元测试
node --test tools/p2p-transfer/tests/p2p_protocol_test.cjs

# 2. 构建独立工具包 ZIP
python3 tools/p2p-transfer/build.py --output ../artifacts/p2p-transfer

# 3. 运行双浏览器 WebRTC 真实点对点端到端测试
node tools/p2p-transfer/tests/browser_e2e_test.cjs
```
