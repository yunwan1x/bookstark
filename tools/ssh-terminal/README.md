# SSH 终端工具

独立静态工具包，不调用系统管理的 SSH 凭据或终端接口。复用 BookStark 已有 xterm、FitAddon、Font Awesome、公共工具函数和对话框。Go `golang.org/x/crypto/ssh` 编译为浏览器 WASM，在 Worker 内通过 `BookStark.sockets` 传输 SSH 原始字节。

## 构建与安装

需要 Go 1.26 与 Python 3。依赖版本和校验固定在当前目录 `go.mod`、`go.sum`。

```sh
python3 tools/ssh-terminal/build.py
```

产物在项目父目录 `artifacts/ssh-terminal/`，包括完整 `package/` 与 `bookstark-ssh-terminal-1.0.1.zip`。无需外部 CDN；许可证随包保留。

在广场的工具发布页选择上传 ZIP，检查入口 `index.html` 后发布。登录的用户可安装。客户端本地提供 TCP 桥接；远端服务器还需在工具市场设置启用工具 TCP 代理。连接地址从 **TCP 代理所在服务器** 解析及访问，并非浏览器自己的内网地址。

## 操作与存储

- 桌面左侧列表可收缩为窄栏；手机从菜单展开，再点遮罩或菜单收起。
- 可选择账户默认 Shell、sh、bash、zsh、fish，或填写自定义绝对路径。指定程序在远端 PTY 中以登录 Shell 启动，路径支持空格及 Unicode，不把输入当作命令参数；程序必须已安装在目标服务器。
- 保存连接只写入名称、主机、端口、用户名、认证方式与 Shell。密码、私钥、私钥口令不写入 localStorage、工具使用数据或 ZIP。
- PEM/OpenSSH 私钥支持加密口令。首次主机密钥显示完整算法及 SHA256 指纹，需核对后选择仅此一次或保存信任；密钥变化会再次确认，取消不能建立 Shell。
- 支持最多 8 个同时连接的会话、真实 PTY、窗口尺寸同步、终端选区复制、手动粘贴回退、搜索、字号调节和手机辅助按键。
- 输入严格按序并确认写入；输出等待 xterm 消费，避免持续输出无限积压。每次重连使用独立运行 ID，旧连接的异步结果不会覆盖新连接。
- 断线保留输出；重新连接需重新输入凭据。刷新不会恢复原来的远端进程，也不会重放命令。
- 浏览器剪贴板仍受运行来源和浏览器授权限制；无法自动读取时弹出手动粘贴框。工具不提供 SFTP、文件上传、端口转发或 SSH agent。

## 导出与重新安装

运行页右上角“更多 → 导出工具包”下载程序 ZIP；“导出数据”仍独立导出使用状态。ZIP 保留程序入口、完整静态资源和声明的权限，重新生成可移植 `tool.json`，移除当前安装的资源路径。用户文件、连接配置、信任记录、主站令牌与运行数据不进入程序包。只有当前账号自己的 ZIP 安装可以导出，并校验安装版本和实例；导出的工具默认要求登录，原来的成员名单不迁移。

再次上传该 ZIP 可发布为新工具并安装；恢复后的工具是新实例，不会自动带入凭据和旧会话。

## 验证

先通过项目根目录 `./build.py --run` 启动隔离测试服务。设置独立 `DB_PATH`、`WEBDAV_DB_PATH`、`PORT=18281` 与 `ADMIN_PASSWORD=admin`，不要指向生产数据库。浏览器测试依赖 Node.js、Playwright、Chromium。

```sh
python3 tools/ssh-terminal/build.py
# 另一个终端启动仅监听 127.0.0.1:18222 的一次性 SSH 测试服务。
cd tools/ssh-terminal
go run ./testserver ../../../artifacts/ssh-terminal
```

测试服务临时生成 SSH 密钥，账号 `tester` / 密码 `terminal-test-only`，仅作本地夹具，不能部署到公网。服务也生成加密私钥夹具 `test-key-encrypted`，测试口令为 `test-key-passphrase`。

```sh
# 从仓库根目录执行，NODE_PATH 仅在 Playwright 未安装到本项目时需要设置。
node tools/ssh-terminal/tests/browser-test.cjs
node tools/ssh-terminal/tests/resilience.cjs
node tools/ssh-terminal/tests/edge-test.cjs
# 设置下述真实SSH环境变量后，验证选择的程序和自定义路径。
node tools/ssh-terminal/tests/shell-browser.cjs
GOMAXPROCS=2 GOMEMLIMIT=350MiB go test -p=1 ./controllers -run TestInstalledToolZIPExport -count=1
```

可用 `BOOKSTARK_TEST_ORIGIN` 与 `BOOKSTARK_SSH_ARTIFACTS` 改测试地址和产物目录。edge 测试默认不访问真实服务器；只有显式设置 `BOOKSTARK_SSH_REAL_HOST`、`BOOKSTARK_SSH_REAL_USER`、`BOOKSTARK_SSH_REAL_KEY` 才执行远端 PTY / Ctrl+C 验证，可选 `BOOKSTARK_SSH_REAL_PORT`。它通过已信任的 SSH CLI 读取远端公开主机密钥指纹进行比对，私钥只通过浏览器本地文件选择读取，不上传到工具发布包或日志。

Shell 程序边界另有嵌套模块测试：`cd tools/ssh-terminal && go test ./internal/...`，验证默认请求、各预设、绝对路径以及单引号/空格/Unicode路径的安全转义。CI 同时执行此测试。

远端未配置独立运行来源时使用 opaque iframe；本地回归可把 `BOOKSTARK_TEST_ORIGIN` 指向 `http://127.0.0.2:18281` 强制使用同样的沙箱，验证公共脚本、Worker、认证及资源加载。共享工具函数会处理 `navigator.serviceWorker` 属性 getter 被沙箱拒绝的情况，不为此扩大 iframe 权限。
