# GUI 客户端修复与验证

日期：2026-11-23。验证环境：redroid Android 12 x86_64，Android System WebView 125。

## 已完成修复

- 普通链接、Ctrl/中键、直接 window.open 和先开空白窗口再设置地址：站内在客户端打开，外部网站使用系统浏览器。
- Android 宿主接入网站音视频许可及运行时授权；macOS 添加摄像头/麦克风用途声明。
- 系统文件保存、分块导出、带 Cookie 的 HTTP 下载、文件名保留、取消回执，以及编辑器/iframe 的系统打印与 PDF 保存。
- 原生复制成功回执、局域网 HTTP 复制回退，修复分享页和 WebDAV 的失败处理/误报成功。
- 返回、前进、切换工作区、关闭前等待保存；保存失败可取消离开；保留真正卸载时的清理回调。
- 旧客户端先协商能力，缺少新接口时回退浏览器能力；Android 通用 Wails 桥继续关闭，仅暴露受限能力。

## redroid 最终安装包验证

使用独立包 com.bookstark.wails.qa。已校验安装包内适配脚本和完整资源版本清单与最终源码一致。17 项实测通过：

- Actual APK loads shared native adapter
- Native Back waits for IndexedDB save
- Native Forward restores draft
- Native clipboard write + real Android paste
- Native SAF export preserves all chunked UTF-8 bytes
- LAN HTTP clipboard fallback on real Android WebView
- External link opens system browser and retains client page
- Blank-window deferred external link opens the system browser
- Iframe print produces a PDF with the expected content
- Native Save cancellation returns false
- Authenticated HTTP download keeps cookie and server filename
- Native file chooser returns readable file bytes
- Website microphone denial is respected
- Website + Android microphone permission granted; capture reaches device
- Failed save blocks native navigation; cancel retains draft and retry saves
- Android Back at history root closes the Activity after save
- Draft survives Activity close and process restart

证据：artifacts/native-gui-redroid/results.json、原生保存/打印/未保存保护截图、288022 字节导出文件、含预期文字的 PDF。

## 实机覆盖限制

- 摄像头：redroid 摄像头设备数为 0，未验证真实图像采集。
- 麦克风：拒绝被正确执行；允许后 Android RECORD_AUDIO 已授权，但虚拟音源返回 NotReadableError / Could not start audio source。真实音频采集仍需有输入硬件的设备验证。
- Windows GUI 交叉编译和 PE GUI 子系统检查通过；macOS 用途声明的包生成检查通过，未在 Windows/macOS 实机运行。
- Linux 构建通过；本机 Ubuntu 20.04 仅有 WebKitGTK 4.0，缺少要求的 4.1，未运行桌面 GUI。

## 自动化回归

- 创作工具六种真实编辑器、草稿恢复/冲突/导入导出，广场和资讯浏览器回归通过。
- 原生兼容专项（复制失败/旧客户端回退、导出字节/取消、iframe/空白窗口打印、保存与清理回调）通过。
- 原生 Go 测试覆盖工作区、链接校验、导出上限、窗口隔离和临时文件清理；JavaScript 单元测试 11 项通过。
- 全量 go test ./... 仍有 12 项既有失败，与修复前清单一致：英文首页标题 1、旧科学背景断言 2、缺失 Airdrop tmp 夹具 5、旧导航标签断言 1、旧 PWA 断言 3。未修改这些无关断言或夹具。

## 本地构建产物

构建产物状态：本地验证构建，未发布、未部署线上。下列 SHA256 对应提交前生成并验证的安装包；Android release 使用项目现有签名规则。

- bookstark-wails-arm64-gui-fixed.apk（42.3 MiB）
  - SHA256: 3cb92973c28e8a7ab1a58045b76442673d251a096bb27b72237418b2aee9bdf4
- bookstark-wails-gui-qa-final-x86_64.apk（48.2 MiB）
  - SHA256: 2d9141502912b0a81f46c30170516d9c872f64855c6bbeb1141a8be18f53a5f0
- bookstark-wails-windows-amd64.exe（92.0 MiB）
  - SHA256: 2e7c6c4ece23a8dc541e2ad8a8d8e31877c4f8ed09f0d8ddac23b1968d4b2f47

## 桌面关窗与再次启动回归（2026-11-23）

基线 `d425383` 在 Ubuntu 24.04 / GTK3 / WebKit2GTK 4.1、独立 D-Bus 会话、Xvfb + Openbox 中实际打开窗口，复现：

- 重复启动先绑定已保存的本地端口，报 `address already in use`；原实现没有显式 GUI 单实例唤醒。
- 工作区选择页未加载完整 Wails 前端运行时，缺少 ready 通知，导致 `ExecJS` 排队、关窗确认脚本不执行，Alt+F4 无法关闭。
- macOS 默认最后一个窗口关闭后保留进程；原代码未处理 Dock reopen 事件。此项由当前 Wails 平台实现及应用事件接线确认，未作 macOS 真机复现。

本次修复：桌面在监听端口之前取得单实例所有权；第二次启动激活具名主窗口，最小化时恢复，窗口已销毁时重建；macOS Dock reopen 使用相同恢复逻辑。通过窗口加载脚本发送最小 ready 通知，使受限 BookStark 桥的回执及关闭前保存脚本可以执行。Android 保持先创建 bootstrap 服务的顺序，不启用桌面单实例锁。

实际 GUI 回归通过：

- 重复启动退出码 0，保留同一个主窗口。
- 主窗口最小化后再次启动，恢复同一窗口。
- Linux 正常关闭窗口后进程退出，退出码 0。
- 关闭后重新启动可打开新窗口。
- Linux 测试宿主开启 `DisableQuitOnLastWindowClosed` 模拟 macOS 的进程生命周期，连续 3 次关闭并重新启动，原进程保持不变、每次重建一个新窗口。

定向 Go 回归覆盖窗口并发激活、启动通知、不同配置目录的实例隔离，以及既有工作区、外链、导出边界和书签扩展；窗口恢复测试另通过 race 检查。macOS `darwin/arm64`、`darwin/amd64` 均通过 `wails,production,purego` 交叉编译。macOS Dock、菜单退出和真实系统焦点行为仍需要 Mac 真机验证，Linux 模拟不替代这些验证。

自动回归入口（需要 Go、GTK3/WebKit2GTK 4.1、D-Bus、Xvfb、Openbox、xdotool、xwd）：

```sh
dbus-run-session -- python3 tests/native/desktop_lifecycle_linux.py --out /tmp/bookstark-lifecycle
GOMAXPROCS=2 go test -p=1 -tags wails,production,gtk3,purego . -run 'TestNative(WindowActivation|DesktopSingleInstance|ExportOwnershipAndLimits|ExternalURL|Workspaces|BookmarkExtensionBoundary)$|TestValidate(ServerURL|LocalPassword)$' -count=1
GOMAXPROCS=2 go test -race -p=1 -tags wails,production,gtk3,purego native_window_lifecycle.go native_window_lifecycle_test.go -count=1
```

GUI 脚本通过 `build.py --run` 启动正式程序；只在测试宿主中模拟 macOS 保留进程，不引入生产环境开关。所有测试配置、日志、结果 JSON 和窗口截图写入 `--out`，不使用日常应用配置。验证源码为基线加本次窗口生命周期修复的独立快照；同一工作区同时存在的客户端偏好设置改动未混入本次测试和提交。
