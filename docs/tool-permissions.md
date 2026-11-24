# 工具权限与桥接 API

新开发者请先阅读 [插件开发指南](plugin-development.md)，其中包含完整 HTML 示例、安装测试和市场发布流程。

发布页仅提供读取工具文件（`read_files`）、保存工具文件（`save_files`）、TCP 连接（`socket_tcp`）三项 BookStark 桥接权限，默认关闭；安装确认和运行页也仅展示这三项。发布设置写入 `permissions.schema=1`，新增桥接权限的更新需要用户确认，不会自动安装。其余已支持的浏览器能力包括联网默认允许，不提供勾选项；这不会代替浏览器授权，也不能让不支持某项 API 的浏览器获得该能力。

## 权限目录

下表同时列出三项可选的桥接权限和浏览器策略字段。浏览器字段保留用于兼容清单及生成运行策略，不是发布设置中的勾选项。

| 权限 | 声明字段 | 执行位置 |
| --- | --- | --- |
| TCP 连接（后端代理） | `socket_tcp` | 登录、版本、实例、权限和代理开关校验 |
| 浏览器对话框与打印 | `modals` | iframe `sandbox="… allow-modals"` |
| 游戏手柄 | `gamepad` | iframe `allow="gamepad …"` + Permissions-Policy |
| 读取工具文件 | `read_files` | 文件桥接读取校验 |
| 保存工具文件 | `save_files` | 文件桥接写入校验 |
| 访问网络 | `network` | CSP 网页资源和请求策略 |
| 读取剪贴板 | `clipboard_read` | iframe `allow="clipboard-read …"` + Permissions-Policy |
| 写入剪贴板 | `clipboard_write` | iframe `allow="clipboard-write …"` + Permissions-Policy |
| 摄像头 | `camera` | iframe `allow="camera …"` + Permissions-Policy |
| 麦克风 | `microphone` | iframe `allow="microphone …"` + Permissions-Policy |
| 屏幕共享 | `display_capture` | iframe `allow="display-capture …"` + Permissions-Policy |
| 位置信息 | `geolocation` | iframe `allow="geolocation …"` + Permissions-Policy |
| 网页全屏 | `fullscreen` | iframe `allow="fullscreen …"` + Permissions-Policy |
| 媒体自动播放 | `autoplay` | iframe `allow="autoplay …"` + Permissions-Policy |
| 画中画 | `picture_in_picture` | iframe `allow="picture-in-picture …"` + Permissions-Policy |
| 下载文件 | `downloads` | iframe `sandbox="… allow-downloads"` |
| 打开新窗口 | `popups` | iframe `sandbox="… allow-popups"` |
| 提交表单 | `forms` | iframe `sandbox="… allow-forms"` |
| 锁定鼠标 | `pointer_lock` | iframe `sandbox="… allow-pointer-lock"` |
| 锁定屏幕方向 | `orientation_lock` | iframe `sandbox="… allow-orientation-lock"` |
| 保持屏幕唤醒 | `screen_wake_lock` | iframe `allow="screen-wake-lock …"` + Permissions-Policy |
| 系统分享 | `web_share` | iframe `allow="web-share …"` + Permissions-Policy |
| 外接屏幕演示 | `presentation` | iframe `sandbox="… allow-presentation"` |
| 选择音频输出 | `speaker_selection` | iframe `allow="speaker-selection …"` + Permissions-Policy |
| 蓝牙设备 | `bluetooth` | iframe `allow="bluetooth …"` + Permissions-Policy |
| USB 设备 | `usb` | iframe `allow="usb …"` + Permissions-Policy |
| 串口设备 | `serial` | iframe `allow="serial …"` + Permissions-Policy |
| HID 设备 | `hid` | iframe `allow="hid …"` + Permissions-Policy |
| MIDI 设备 | `midi` | iframe `allow="midi …"` + Permissions-Policy |
| 空间追踪 / XR | `xr_spatial_tracking` | iframe `allow="xr-spatial-tracking …"` + Permissions-Policy |
| 受保护媒体 | `encrypted_media` | iframe `allow="encrypted-media …"` + Permissions-Policy |
| 加速度传感器 | `accelerometer` | iframe `allow="accelerometer …"` + Permissions-Policy |
| 陀螺仪 | `gyroscope` | iframe `allow="gyroscope …"` + Permissions-Policy |
| 磁力传感器 | `magnetometer` | iframe `allow="magnetometer …"` + Permissions-Policy |
| 环境光传感器 | `ambient_light_sensor` | iframe `allow="ambient-light-sensor …"` + Permissions-Policy |
| 本地字体 | `local_fonts` | iframe `allow="local-fonts …"` + Permissions-Policy |
| 多屏窗口管理 | `window_management` | iframe `allow="window-management …"` + Permissions-Policy |
| 空闲状态检测 | `idle_detection` | iframe `allow="idle-detection …"` + Permissions-Policy |
| 键盘布局 | `keyboard_map` | iframe `allow="keyboard-map …"` + Permissions-Policy |
| 浏览器支付 | `payment` | iframe `allow="payment …"` + Permissions-Policy |
| 使用通行密钥 | `publickey_credentials_get` | iframe `allow="publickey-credentials-get …"` + Permissions-Policy |
| 创建通行密钥 | `publickey_credentials_create` | iframe `allow="publickey-credentials-create …"` + Permissions-Policy |

## 隔离和浏览器 API

客户端本地工具使用 `http://tool-<安装实例>.localhost:<工作区端口>`，与主站及其他工具的来源不同。主站签名引导页地址，核对来源、安装实例及有效期；HTML 和初始数据通过精确来源的消息传递，不放在 URL 中。运行页限制 iframe 导航范围，运行来源只提供引导页，拒绝主站页面、登录和 API。

工具的 `allow-same-origin` 仅在独立来源运行时由系统添加，发布者不能自行开启。`allow-top-navigation`、`allow-top-navigation-by-user-activation`、`allow-popups-to-escape-sandbox`、第三方 Cookie/storage-access、跳转系统协议等不会开放。脚本是 HTML 工具的基本运行能力。新窗口继续继承沙箱限制。

摄像头和麦克风使用 `navigator.mediaDevices.getUserMedia()`，屏幕共享使用 `getDisplayMedia()`，剪贴板使用 `navigator.clipboard`，定位使用 `navigator.geolocation`。工具用浏览器原生 API，系统通过 iframe 和响应头限制。屏幕共享仍须每次用户选择，浏览器可能要求点击、设备许可或安全上下文；USB、蓝牙、串口、HID、传感器、通行密钥等按浏览器实际支持工作。

网页联网和表单默认允许，运行时 CSP 允许常见网页资源和连接；浏览器请求仍受 CORS 等限制。CSP 不是操作系统防火墙，不能承诺完全离线。TCP 桥接仍需单独声明 `socket_tcp` 并通过后端校验，浏览器联网能力不会自动授予 TCP 桥接。

远端默认使用不带同源权限的隔离 srcdoc；虽然浏览器能力按默认策略委派，设备和部分高级接口仍可能因浏览器的来源限制不可用。管理员可在「系统管理 → 工具市场」设置远端运行来源，例如 `https://{instance}.tools.example.com`，需独立的泛域名 DNS、HTTPS 和反向代理；应转发原始 Host 与协议，禁止在工具来源提供其他应用或共享静态站点。每个安装实例必须拥有不同来源。

原生宿主桥接不会委派给工具 iframe。桌面使用只在主文档注入的窗口证明；Android 使用携带来源与主帧身份的 WebMessageListener，拒绝子帧的宿主请求。

旧版本的权限 JSON 和清单摘要保持不变；运行时将浏览器字段统一视为允许，即使旧字段为 false。三项桥接权限保持原有声明，不会自动获得。新发布版本将浏览器字段规范化为 true，并使用 schema 1 声明。未知权限及未知 schema 会拒绝解析。

## 文件 API

所有接口位于 `BookStark.files`，返回 Promise。数据仅属于当前账号、当前安装工具的数据空间。不是任意本地文件系统，也不能读写来源文章、安装资源和其他工具文件。文件内容由现有 WebDAV 存储保存，接口不暴露底层 WebDAV 节点 ID、数据库路径或公开 URL。

| 方法 | 权限 | 行为 |
| --- | --- | --- |
| `read(path)` | 读取 | 返回 `Uint8Array` |
| `list(path = "")` | 读取 | 返回该目录的直接子项数组 |
| `stat(path = "")` | 读取 | 返回文件或目录信息 |
| `exists(path = "")` | 读取 | 存在返回 true，不存在返回 false；其他错误仍拒绝 |
| `write(path, value)` | 写入 | 写入或覆盖文件，自动创建父目录 |
| `mkdir(path, {recursive: false})` | 写入 | 创建目录；递归模式允许创建缺失的父目录 |
| `remove(path, {recursive: false})` | 写入 | 删除文件或空目录；递归模式删除目录树 |
| `rename(from, to)` | 写入 | 重命名或移动，目标父目录必须存在 |
| `move(from, to)` | 写入 | 与 rename 相同 |
| `copy(from, to)` | 读与写 | 复制文件或完整目录树，目标父目录必须存在 |

目录项格式为 `{name, path, is_directory, size, mime_type, modified}`；path 相对工具根目录，size 单位是字节，modified 是 ISO 时间。首次使用时根目录视为存在，`list()` 返回空数组，无需只读接口创建目录。不能删除、移动或替换工具根目录。重命名、移动、复制不会覆盖已有目标。

```js
const files = BookStark.files;
await files.mkdir('notes/2026', {recursive: true});
await files.write('notes/2026/report.txt', '报告内容');
const info = await files.stat('notes/2026/report.txt');
const children = await files.list('notes/2026');
const text = new TextDecoder().decode(await files.read(info.path));
await files.rename(info.path, 'notes/2026/renamed.txt');
await files.copy('notes/2026', 'notes/backup');
await files.remove('notes/backup', {recursive: true});
```

写入支持字符串、Blob、ArrayBuffer 和 TypedArray。文件大小及总量受工作区文件配额约束。路径禁止 `..`、`.`、重复分隔符、反斜杠和控制字符。每次调用均检查账号、安装实例和修订号；树操作及写入在安装锁内检查权限，更新或卸载期间的旧调用会失败。

常见 `error.code`：`permission_denied`、`not_found`、`already_exists`、`directory_not_empty`、`not_directory`、`invalid_path`、`conflict`、`quota_exceeded`。SDK 最多同时等待 32 个文件请求，单次超时 30 秒。

## TCP Socket API

工具必须声明 `socket_tcp`。本地原生客户端自动启用代理；远端默认关闭，管理员需显式打开「允许此服务器代理工具 TCP 连接」。连接从安装工作区的后端发出：客户端本地模式是本机，远端模式是服务器；`127.0.0.1` 也指该后端，不指访问者的浏览器。

```js
const socket = await BookStark.sockets.connect({host: '192.168.1.10', port: 22});
// 也支持 connect(host, port)。连接成功后 resolve，失败时拒绝。
socket.binaryType = "arraybuffer"; // 或 blob
socket.onmessage = event => consumeBytes(new Uint8Array(event.data));
await socket.send(new Uint8Array([1, 2, 3]));
socket.close();
await socket.closed;

// 或使用标准流，按字节读写：
const streamSocket = await BookStark.sockets.connect({host: '192.168.1.10', port: 22});
const writer = streamSocket.writable.getWriter();
const reader = streamSocket.readable.getReader();
await writer.write(new Uint8Array([1, 2, 3]));
const {value, done} = await reader.read();
writer.releaseLock();
reader.releaseLock();
streamSocket.close();
```

返回对象支持 `send`、`close`、`readyState`、`binaryType`、`bufferedAmount`、`closed`、`onmessage/onclose/onerror`、`addEventListener`，以及 `readable`、`writable` 标准流。`send` 返回 Promise，需 await 以处理背压和错误。字节流不保证每次 send 对应一次 message；应用应自行处理协议分包。不要同时用 message 和 readable 重复处理同一批数据。

单次 send 最多 1 MiB，桥接按 64 KiB 分片。未消费的流有界缓存；每工具最多 8 条连接，每账号最多 16 条，后端总计最多 128 条。连接、读写和心跳有超时；页面离开、更新、卸载、权限撤销及关闭服务器开关后会清理连接，其中服务端权限轮询间隔为 5 秒。

浏览器只连接工作区同源的已登录 WebSocket，服务端验证精确 Origin，防止跨站创建代理。工具 iframe 不获得登录 Cookie、API Token 或可复用认证地址。后端只接受二进制数据，不执行命令，不记录流内容。不提供 UDP、监听端口、任意代理认证或隐式 TLS；TLS/SSH 等由前端协议库处理。

要实现 SSH terminal，可将此二进制流适配到浏览器 SSH/WASM 库，再连接终端 UI。SSH 握手、主机密钥验证、密码/密钥认证和终端尺寸仍是 SSH 工具自身的职责。此接口不会自动创建 SSH 会话。
