# BookStark 桌面和 Android 应用

这个入口以 Wails 3.1.0 和系统 WebView 运行 BookStark。首次打开时选择工作区。

- **远程服务器**输入现有 BookStark 的 HTTPS 地址。局域网还可以使用 HTTP 内网 IP 或 .local 地址。应用记住最近的服务器地址，账户和数据仍由该服务器管理。
- **本地工作区**在应用中启动 BookStark 的 Go 和 SQLite 后端，首次创建默认账号 `admin`、密码 `wy19870714`，密码旁提供复制按钮。已有工作区保留原密码，不会重新初始化。进入账户安全后可以修改密码。数据库、附件和编辑器资源可在本地使用。需要第三方服务的功能仍会使用网络。
- 桌面端从 **工作区 → 切换工作区** 返回，Android 使用窗口顶部的 **切换工作区**。两种模式的数据彼此独立。
- 链接打开规则：站内新标签页链接在客户端当前窗口打开；书签、导航、资讯等外部 HTTP/HTTPS 链接交给系统默认浏览器，客户端保留原页面。覆盖普通链接、`window.open(url)` 和先开空白窗口再设置地址的编辑器链接。需要更新客户端及其使用的服务端页面资源，旧客户端没有外部链接桥。
- Android 保持关闭通用 Wails JS 桥。`BookStarkNative` 仅提供链接打开，以及经过白名单、大小限制和系统交互约束的复制、保存、打印能力；不会提供任意文件路径读写或命令执行。

## 启动与记住账号密码

首次启动选择本地工作区或远程服务器，默认勾选「以后继续上次工作区」。之后启动直接恢复上次成功打开的工作区；远程连接失败显示重试、切换入口，不会静默切到本地或覆盖已保存的选择。

进入「个人设置 → 工作区」可设置「继续上次工作区」或「每次询问」，查看当前工作区并切换。该设置只影响当前客户端；原生「工作区 → 切换工作区」和 Android 顶部工作区按钮始终可以打开选择页。

客户端登录页默认记住成功登录的账号密码，下次需要登录时自动填充，不自动提交。取消勾选后成功登录会清除已保存的凭据；也可在工作区设置里清除，当前登录会话不受影响。本地工作区与各远端地址分别保存凭据，账号密码用 AES-GCM 加密后存入应用私有目录，密钥文件限制当前用户读取；不写入网页 localStorage。网页消息桥校验来源，并要求主页面完成随机令牌握手，回复前再次检查页面来源。修改密码时同步更新已经记住的凭据。

Windows 使用稳定的 WebView 数据目录，Android 在应用进入后台时刷新持久 Cookie。会话仍遵守工作区自身的到期和退出规则；到期后可以使用已填入的账号密码再次登录。

工具市场在未配置时默认使用 `https://books.vs2010wy.top/market`。在广场「工具」中，管理员可用排序后的齿轮调整来源；已有自定义地址不会被默认值覆盖。安装需要当前工作区登录，远端市场按自身访问规则验证独立的市场账号。

本地数据放在系统的用户配置目录 `BookStark/local` 下。Android 使用应用私有存储中的 `bookstark/local`。原有服务器入口由普通 Go 构建保留，Wails 入口用 `wails` 构建标签启用。

## GUI 适配与验证

- 复制文字优先使用已确认可用的客户端接口；普通浏览器和旧客户端保留浏览器剪贴板及选区复制回退，成功回执后才提示成功。
- 下载、Blob 导出使用系统保存对话框，传输分块并限制为 100 MB；取消不会误报成功。站内 HTTP 下载保留当前登录会话和服务端文件名。
- 打印会把编辑器页面（包括画布和同源 iframe）交给系统打印框架，可另存 PDF。
- 原生返回、前进、切换工作区及关闭窗口先等待保存；失败时使用现有确认弹窗，取消会保留当前编辑内容。权限申请按网站和 Android 运行时授权处理，拒绝不会被绕过。
- macOS 包含摄像头、麦克风用途声明。桌面端提供双语返回/前进菜单和快捷键；Windows Wails 构建使用 GUI 子系统。

redroid 回归使用独立包名，不覆盖正式应用：

```sh
python3 native/build_android.py --abi x86_64 --debug --out artifacts/bookstark-wails-gui-qa-x86_64.apk
adb -s 127.0.0.1:15555 install -r artifacts/bookstark-wails-gui-qa-x86_64.apk
adb -s 127.0.0.1:15555 shell am start -n com.bookstark.wails.qa/com.wails.app.MainActivity
node tests/browser/redroid_native_gui_test.cjs
```

测试需要 Node 可解析 `ws`，adb、Docker（读取 redroid 网桥地址）、`pdftotext`。输出位于忽略版本控制的 `artifacts/native-gui-redroid/`，包含原生界面截图、导出文件、PDF 和逐项结果。默认仅操作 `com.bookstark.wails.qa` 的测试数据。

当前 redroid 没有摄像头，虚拟音频输入无法启动；可验证授权与拒绝，但不能据此声称真实音视频采集通过。Linux GUI 需要 WebKitGTK 4.1 运行时；Ubuntu 20.04 默认的 4.0 不能替代。Windows/macOS 的编译与包声明检查不等同于这些系统上的实机验证。

## 构建

使用 Go 1.26 或更新版。桌面运行时使用系统 WebView。以下命令从仓库根目录执行。

```sh
mkdir -p artifacts

# Windows x64（可从 Linux 交叉编译）。运行时使用 WebView2。
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build -tags wails,production -trimpath -ldflags="-s -w -H windowsgui" -o artifacts/bookstark-wails-windows-amd64.exe .

# Linux，示例目标为安装 GTK3 和 WebKitGTK 4.1 的环境
go build -tags wails,production,gtk3,purego -trimpath -ldflags="-s -w" -o artifacts/bookstark-wails-linux .

# macOS Apple Silicon（M 系列芯片）
python3 native/build_macos.py --arch arm64

# macOS Intel
python3 native/build_macos.py --arch amd64

# Android ARM64，安装 JDK 21、Android SDK 36 及 NDK
# ANDROID_HOME、ANDROID_NDK_HOME 指向相应目录
python3 native/build_android.py
```

macOS 分别提供 arm64（Apple Silicon）和 amd64（Intel）两个单架构包，不再生成 Universal 包。脚本默认使用 arm64，分别输出 `artifacts/bookstark-wails-macos-arm64.zip` 和 `artifacts/bookstark-wails-macos-amd64.zip`，解压得到 `BookStark.app`。在 Mac 上执行脚本会进行临时签名，GitHub Release 也会检查架构与签名。正式分发另需 Developer ID 签名与 Apple 公证。

在 x86_64 Android 测试环境可用 `--abi x86_64`。Android 默认输出 `artifacts/bookstark-wails-arm64.apk`。没有配置正式签名时，构建使用 Gradle 调试证书，供侧载测试。项目使用独立的 Android 包名 `com.bookstark.wails`，可与旧客户端并存。Wails 的 Android 支持仍属于实验性功能。

两种模式的本地 HTTP 集成测试可用以下命令运行。

```sh
go test -tags wails,gtk3,purego -run 'TestNativeWorkspaces|TestValidateServerURL|TestValidateLocalPassword' .
```
