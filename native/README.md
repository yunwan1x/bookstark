# BookStark 桌面和 Android 应用

这个入口以 Wails 3.1.0 和系统 WebView 运行 BookStark。首次打开时选择工作区。

- **远程服务器**输入现有 BookStark 的 HTTPS 地址。局域网还可以使用 HTTP 内网 IP 或 .local 地址。应用记住最近的服务器地址，账户和数据仍由该服务器管理。
- **本地工作区**在应用中启动 BookStark 的 Go 和 SQLite 后端，首次创建时自行设置并确认本地 `admin` 密码，至少 8 个字符、最多 72 UTF-8 字节。创建完成后的密码旁提供复制按钮；已有工作区保留原密码，不会重新初始化。进入账户安全后可以修改密码。数据库、附件和编辑器资源可在本地使用。需要第三方服务的功能仍会使用网络。
- 桌面端从 **工作区 → 切换工作区** 返回，Android 使用窗口顶部的 **切换工作区**。两种模式的数据彼此独立。

本地数据放在系统的用户配置目录 `BookStark/local` 下。Android 使用应用私有存储中的 `bookstark/local`。原有服务器入口由普通 Go 构建保留，Wails 入口用 `wails` 构建标签启用。

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
