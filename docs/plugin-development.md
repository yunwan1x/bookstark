# BookStark 插件开发指南：HTML 工具、权限、文件与 TCP

本文面向希望为 BookStark 开发工具插件的开发者。从一个可以安装的 HTML 工具开始，介绍资源组织、权限声明、数据保存、文件管理、TCP 连接和市场发布。

> **适用版本（2026-11-24）**：本文对应集成 42 项能力声明、完整文件管理与 TCP Socket 桥接的插件运行时。服务器网页端由本次上线提供；本地原生客户端需要安装包含这些能力的客户端版本，服务器部署不会自动更新已安装客户端。远端设备权限仍需配置独立运行来源，TCP 代理默认关闭，具体能力还取决于浏览器与设备。

## 1. 插件是什么

BookStark 当前的工具插件，本质是一个 HTML 网页，配合 JavaScript、CSS、图片或 WASM 等静态资源运行。

- 开发界面和业务逻辑时，使用普通 Web 技术。
- 在服务器创建一篇 **HTML 类型、未加密的文章**，作为工具来源。
- 在发布设置中填写名称、版本、图标、安装范围和运行权限。
- 市场发布的是 HTML 版本、元数据及原始资源引用，不要求上传 ZIP 压缩包。
- 用户登录安装目标工作区后安装；平台下载 HTML 和能识别的静态依赖，保存安装副本。
- 用户打开工具时，平台进入独立运行页，在隔离 iframe 中执行安装副本。

```text
HTML 来源文章 + 原始静态资源
            │ 发布版本、权限和说明
            ▼
        工具发布市场
            │ 安装时下载资源
            ▼
      用户的安装工作区
            │ 创建隔离 iframe
            ▼
    HTML / JavaScript 工具
      ├─ 浏览器原生 API
      ├─ localStorage 状态保存
      ├─ BookStark.files 文件桥接
      └─ BookStark.sockets TCP 桥接
```

不用编写浏览器扩展的 manifest，也不用在 HTML 中加载 BookStark 内部的脚本。平台会在工具代码之前注入桥接对象。

## 2. 三步做出第一个工具

### 第一步：创建一篇 HTML 文章

在文章列表新建 HTML 类型文章，将下面的完整内容粘贴到 HTML 源码中。文章可以保持私有，但不能设置访问密码。

这个示例是一个文本工作台：自动保存输入状态，能够保存、读取工具文件，并列出当前工具的数据目录。

```html
<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>文本工作台</title>
  <style>
    :root { color-scheme: light dark; }
    body { margin: 0; padding: 1rem; font: 16px/1.6 system-ui; }
    main { max-width: 48rem; margin: auto; }
    h1 { font-size: 1.25rem; }
    textarea {
      box-sizing: border-box; width: 100%; min-height: 14rem;
      padding: .75rem; font: inherit;
    }
    .actions { display: flex; flex-wrap: wrap; gap: .5rem; margin-top: .75rem; }
    button { padding: .5rem .75rem; font: inherit; cursor: pointer; }
    button:focus-visible, textarea:focus-visible { outline: 2px solid Highlight; }
    output { display: block; white-space: pre-wrap; overflow-wrap: anywhere; margin-top: .75rem; }
  </style>
</head>
<body>
<main>
  <h1>文本工作台</h1>
  <label for="text">文本内容</label>
  <textarea id="text" placeholder="输入内容后，会保存到工具状态中"></textarea>
  <div class="actions">
    <button type="button" id="saveFile">保存文件</button>
    <button type="button" id="readFile">读取文件</button>
    <button type="button" id="listFiles">列出文件</button>
  </div>
  <output id="status" role="status"></output>
</main>
<script>
'use strict';
const text = document.getElementById('text');
const status = document.getElementById('status');
const filePath = 'notes/workbench.txt';
text.value = localStorage.getItem('workbench.text') ?? '';
text.addEventListener('input', () => {
  try {
    localStorage.setItem('workbench.text', text.value);
    status.textContent = '输入状态已提交保存；文件需点击“保存文件”。';
  } catch (error) {
    status.textContent = '状态写入失败：' + error.message;
  }
});
function bind(id, action) {
  const button = document.getElementById(id);
  button.addEventListener('click', async () => {
    button.disabled = true;
    try {
      if (!window.BookStark?.files) throw Error('请在已安装工具的运行页打开');
      await action();
    } catch (error) {
      status.textContent = '操作失败：' + (error.code ?? error.message);
    } finally {
      button.disabled = false;
    }
  });
}
bind('saveFile', async () => {
  await BookStark.files.write(filePath, text.value);
  status.textContent = '文件已保存：' + filePath;
});
bind('readFile', async () => {
  const bytes = await BookStark.files.read(filePath);
  text.value = new TextDecoder().decode(bytes);
  localStorage.setItem('workbench.text', text.value);
  status.textContent = '文件已读取：' + filePath;
});
bind('listFiles', async () => {
  if (typeof BookStark.files.list !== 'function') throw Error('请升级工具运行时');
  const entries = await BookStark.files.list();
  status.textContent = entries.length
    ? entries.map(item => (item.is_directory ? '目录 ' : '文件 ') + item.path).join('\n')
    : '当前工具还没有文件';
});
</script>
</body>
</html>
```

普通文章预览可以查看界面，但不能替代安装后的运行环境。测试文件桥接时，使用后面的安装入口。

### 第二步：发布为工具

从文章列表的「发布为工具」入口，或「广场 → 工具 → 发布工具」进入来源文章选择页。

选择刚才的文章，在发布设置填写：

| 设置 | 示例 |
| --- | --- |
| 名称 | 文本工作台 |
| 版本 | `1.0.0` |
| 类别 | 文档处理 |
| 简介 | 保存输入状态，读写工具自己的文本文件 |
| 图标 | 选择适合工具的图标和颜色 |
| 读取工具文件 | 开启 |
| 保存工具文件 | 开启 |
| 网页网络、TCP、摄像头等其他权限 | 此示例不需要，保持关闭 |

先点击「检查资源」。这个示例将脚本和样式都放在 HTML 中，没有额外静态依赖。检查通过后发布；普通成员是否需要审核，由发布市场的设置决定。

发布设置由平台生成权限记录，示意如下。**不用把这段 JSON 粘贴到 HTML，也不用额外创建 manifest 文件。**

```json
{
  "schema": 1,
  "read_files": true,
  "save_files": true,
  "network": false
}
```

### 第三步：安装并打开

在「广场 → 工具」找到该工具，阅读安装确认中的权限说明，然后安装并打开。

依次检查：

1. 输入一段文字，等保存请求完成后，用工具顶部的刷新按钮重新打开，输入应能恢复。
2. 点击「保存文件」，应显示 `notes/workbench.txt` 已保存。
3. 点击「列出文件」，根目录应出现 `notes` 目录；此接口默认只列直接子项。
4. 修改文本框内容，再点击「读取文件」，应恢复上一次保存到文件的内容。

你已经完成了一个可发布、安装和保存数据的 HTML 工具。

## 3. 静态资源怎么组织

### 3.1 单文件和多文件

小工具可以直接把 HTML、CSS、JavaScript 放在同一篇 HTML 文章中。较大的工具可以引用独立资源。

```html
<link rel="stylesheet" href="https://assets.example.com/text-tool/1.0.0/app.css">
<script type="module" src="https://assets.example.com/text-tool/1.0.0/app.js"></script>
```

这些地址是格式示例，需要换成你实际提供的资源地址。资源可以来自服务器上传文件、公开 WebDAV 资源或其他可公开读取的 HTTP(S) 地址。

发布端不会给资源下载请求附加作者的登录 Cookie 或私有文件凭据。原始资源必须能被检查器和安装工作区实际读取。公开 WebDAV 资源与工具运行后通过文件桥接生成的私有文件，是两种不同的数据。

### 3.2 相对路径和构建产物

如果把 Vite、React、Vue 等应用的构建 HTML 复制进来源文章，不能假设原来的 `/assets/` 或 `./app.js` 目录仍然存在。文章 URL 和原静态站点的目录不是同一个位置。

优先将 HTML 中的入口资源替换为实际可访问的绝对 URL。需要保留成组相对路径时，可以在来源 HTML 中指定正确的 `<base href="https://assets.example.com/text-tool/1.0.0/">`；安装器会先用它解析依赖，再移除这个 base。

工具页面优先使用组件内部状态或 hash 路由。不要依赖主站的路径路由，也不要把安装运行页的签名地址当成稳定业务地址保存。

### 3.3 安装器识别什么

安装器会检查 HTML 中的脚本、样式、图片、部分媒体和 preload 引用，并递归处理能识别的 CSS 引用、JavaScript 模块导入及字面量 `new URL(...)` 等静态依赖。资源按地址去重。

当前静态依赖限制是：最多 256 个资源，单个资源最多 64 MiB，入口及资源总量最多 256 MiB。工作区上传和文件配额还可能带来额外限制。

运行时 API 请求和动态拼接出来的地址，不会自动变成离线资源。例如 `fetch('/api/example')` 不会被替换为主站 API，也不会自动带上主站登录身份。

对于 WASM、字典或动态加载文件，可以显式声明资源，并从安装后已改写的元素地址读取：

```html
<link id="dictionaryResource" rel="preload" as="fetch"
      href="https://assets.example.com/text-tool/1.0.0/dictionary.json"
      crossorigin="anonymous">
<script>
async function loadDictionary() {
  const url = document.getElementById('dictionaryResource').href;
  const response = await fetch(url);
  if (!response.ok) throw Error('字典读取失败');
  return response.json();
}
</script>
```

离线工具不要继续从硬编码的原始外部地址动态取依赖。媒体直播、外部接口等运行时业务仍需要相应网络权限。Worker、多线程 WASM、IndexedDB 等额外浏览器能力需要单独验证，不能因为入口 HTML 安装成功就假设全部可用。

### 3.4 资源版本与来源删除

HTML 以发布时的版本保存，原始静态资源地址在安装时读取。建议在资源路径加入版本号，避免原地址内容被覆盖后，新安装用户拿到不同的资源。

原始资源应保留到不再提供该版本安装为止。删除资源不会删掉用户已经安装的副本，但会影响后续安装。

仍上架或有待审核版本的来源文章不能直接删除，需要先到发布设置「下架 / 撤回工具」。不要用删除文章的方式停止正在分发的版本。

## 4. 权限怎么声明和执行

### 4.1 声明入口

权限在工具发布设置中选择，随版本安装。只选择实际使用的能力。新增能力默认关闭；旧工具的部分历史行为按兼容规则保留，重新发布时请检查每个选项。

权限声明不会静默替用户授权设备，也不能让浏览器获得它不支持的 API。工具没有运行时动态提升权限的接口；新增权限需要发布新版本并由用户确认更新。

### 4.2 四类执行方式

| 类型 | 执行方式 | 示例 |
| --- | --- | --- |
| 浏览器能力 | iframe `allow` 加服务端 Permissions-Policy | `camera`、`clipboard_read`、`fullscreen` |
| 沙箱行为 | iframe `sandbox` | `downloads`、`forms`、`popups` |
| 网页外部请求 | Content Security Policy，即 CSP | `network` |
| 平台桥接 | 消息来源校验、账号/实例/版本及后端权限校验 | `read_files`、`save_files`、`socket_tcp` |

浏览器原生 API 直接在工具 iframe 中使用，例如 `navigator.clipboard`、`navigator.mediaDevices.getUserMedia()`。文件与 TCP 则调用 `BookStark` 对象。

### 4.3 完整权限目录

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

设备和高级接口以浏览器实际支持为准。声明 USB、串口或蓝牙权限不代表每一种客户端 WebView 都实现了对应接口。MIDI 的系统专有消息、支付确认、通行密钥操作等还可能有浏览器自己的附加要求。

### 4.4 本地和远端的区别

本地客户端使用每个安装实例独立的 `http://tool-<安装实例>.localhost:<端口>` 来源，与主站和其他工具隔离。系统只在独立来源运行时添加 `allow-same-origin`，发布者不能自行添加这个权限来访问宿主页面。

远端尚未配置独立运行来源时，保持不带同源权限的隔离 iframe，设备和部分高级接口不开放。管理员可以在「系统管理 → 工具市场」预留的运行来源配置中填写：

```text
https://{instance}.tools.example.com
```

这需要相应的泛域名 DNS、HTTPS 证书及反向代理，并将 Host 和协议正确传给应用。`{instance}` 是系统替换的安装实例占位符，不要手写某个用户的实例值。工具域名应专门用于工具运行，不要与其他应用共用。

顶层导航、逃离沙箱的新窗口、第三方 Cookie 开放等能力不由工具自由申请。iframe 的 `sandbox` 和 `allow` 由运行时生成，文章中的标签不能覆盖外层限制。

## 5. 状态保存：localStorage 与 sessionStorage

### 5.1 localStorage

工具可以使用常见的同步接口：

```js
localStorage.setItem('settings', JSON.stringify({theme: 'light', pageSize: 20}));
const settings = JSON.parse(localStorage.getItem('settings') ?? '{}');
localStorage.removeItem('settings');
```

运行时会在工具启动时注入这个工具已有的数据，并把后续变更异步同步到安装工作区。当前单工具结构化 JSON 总量上限为 5 MiB。

- 本地客户端的数据保存到设备上的安装工作区。
- 浏览器访问远端工作区时，保存到该工作区的服务器。
- 数据不会同步给发布市场，也不会自动跨账号或跨工作区同步。
- `setItem()` 返回代表本地同步接口完成，不代表后端已经持久化完成；没有返回 Promise 的保存确认 API。
- 不要用 `await localStorage.setItem(...)` 判断持久化是否成功。

运行页会对写入失败提供重试、导出提示；使用宿主返回或刷新时，会等待已收到的写入，必要时提示确认。还没写进存储的编辑内容，平台不能自动替工具保存。

较大的内容、图片、二进制结果或需要 `await` 写入结果的数据，使用文件 API。输入自动保存建议在工具中适度防抖，减少频繁写入。

### 5.2 sessionStorage

工具的 sessionStorage 是运行时内存实现。适合临时界面状态，刷新或关闭后清空，不同步后端。不要用它保存需要长期保留的数据。

工具可以自行使用浏览器提供的 IndexedDB 等接口，但这些数据不属于 BookStark 的后端自动保存范围，需单独处理兼容性和生命周期。

## 6. 完整文件 API

### 6.1 文件空间和权限

文件 API 位于 `BookStark.files`，所有方法返回 Promise。路径相对当前工具的数据根目录，不能访问来源文章资源、安装资源、其他工具文件或任意本地系统路径。

| 权限 | 允许的方法 |
| --- | --- |
| `read_files` | `read`、`list`、`stat`、`exists` |
| `save_files` | `write`、`mkdir`、`remove`、`rename`、`move` |
| 同时具备读与写 | `copy` |

localStorage 的基础状态保存与这两项文件权限相互独立。

### 6.2 接口参考

| 调用 | 返回值与行为 |
| --- | --- |
| `read(path)` | 返回 `Uint8Array`；文本用 TextDecoder 解码 |
| `list(path = '')` | 返回目录直接子项数组，不递归列出整棵树 |
| `stat(path = '')` | 返回文件或目录的信息对象 |
| `exists(path = '')` | 存在返回 true，不存在返回 false；权限等其他错误仍拒绝 |
| `write(path, value)` | 创建或覆盖文件，自动创建父目录；成功返回 undefined |
| `mkdir(path, {recursive: false})` | 创建目录并返回其信息；目录已存在时可重复调用 |
| `remove(path, {recursive: false})` | 删除文件或空目录；递归模式删除目录树；成功返回 null |
| `rename(from, to)` | 重命名或移动，返回目标项信息；目标父目录须存在 |
| `move(from, to)` | 与 rename 相同 |
| `copy(from, to)` | 复制文件或完整目录树，返回目标项信息；目标父目录须存在 |

`write` 支持字符串、Blob、ArrayBuffer 和 TypedArray。其他类型的对象不要直接写入；JSON 对象先调用 `JSON.stringify()`。

目录项结构如下。这个 JSON 是格式示例，modified 使用 ISO 时间：

```json
{
  "name": "report.txt",
  "path": "notes/report.txt",
  "is_directory": false,
  "size": 128,
  "mime_type": "application/octet-stream",
  "modified": "2026-11-24T12:00:00Z"
}
```

`size` 是文件字节数，不是目录树汇总大小。可选的 mime_type 不一定存在。新工具根目录视为存在，尚未生成文件时 `list()` 返回空数组。

### 6.3 常用操作

```js
async function fileExample() {
  const files = BookStark.files;
  await files.mkdir('notes/2026', {recursive: true});
  await files.write('notes/2026/report.txt', '报告内容');
  const bytes = await files.read('notes/2026/report.txt');
  console.log(new TextDecoder().decode(bytes));
  console.log(await files.list('notes/2026'));
  console.log(await files.stat('notes/2026/report.txt'));
  console.log(await files.exists('notes/2026/report.txt'));

  // 目标不能已经存在；重复运行本例前先换名或自行确认清理。
  await files.rename('notes/2026/report.txt', 'notes/2026/renamed.txt');
  await files.copy('notes/2026', 'notes/backup');
  await files.move('notes/backup/renamed.txt', 'notes/copied-report.txt');
  await files.remove('notes/backup', {recursive: true});
}
```

不要删除、移动或替换工具根目录。重命名、移动和复制不会覆盖已有目标。非空目录默认不能删除，只有显式传入布尔值 `recursive: true` 才递归删除。

路径请保持在 2048 个 UTF-8 字节以内（中文等字符会占多个字节），禁止 `..`、`.`、空路径段、反斜杠和控制字符。空字符串或 `/` 只用于根目录的 list、stat、exists。文件大小和总量受安装工作区的文件设置、配额约束。不要把服务器内部 WebDAV 路径拼进工具相对路径。

### 6.4 错误与并发

```js
async function readText(path) {
  try {
    return new TextDecoder().decode(await BookStark.files.read(path));
  } catch (error) {
    if (error.code === 'not_found') return '';
    if (error.code === 'permission_denied') throw Error('请检查工具的读取文件权限');
    throw error;
  }
}
```

常见错误码包括 `permission_denied`、`not_found`、`already_exists`、`directory_not_empty`、`not_directory`、`is_directory`、`invalid_path`、`conflict`、`quota_exceeded`。文件请求最多同时等待 32 个，单次 SDK 等待超时为 30 秒；超时或其他异常不一定都有 code，可回退显示 message。

调用会检查安装实例和版本，旧版本在更新、卸载后不能继续通过桥接修改数据。遇到 `conflict`，重新打开工具，不要不断重试旧实例。

## 7. TCP Socket API

### 7.1 开启条件与连接位置

使用 `BookStark.sockets.connect()` 前，在发布设置声明 `socket_tcp`。这是一项单独的后端网络能力，不会因为勾选普通网页网络权限就自动获得。

- 本地原生客户端：代理默认可用，TCP 从设备上的本地后端发出。
- 远端工作区：默认关闭，管理员需在工具市场管理中启用服务器 TCP 代理。
- `127.0.0.1` 指安装工作区的后端，不一定是正在浏览网页的这台电脑。

```text
工具 iframe
   │ BookStark.sockets
   ▼
宿主运行页
   │ 已登录的同源 WebSocket
   ▼
工作区后端
   │ 原始 TCP 字节流
   ▼
目标主机与端口
```

不要自行索取主站 Cookie 或 API Token，也不要在工具里拼接宿主的已认证 WebSocket 地址。由桥接完成认证和来源校验。

### 7.2 建立连接

```js
async function connectToService() {
  if (!window.BookStark?.sockets?.connect) throw Error('当前运行时尚未提供 TCP 桥接');
  const socket = await BookStark.sockets.connect({host: '192.168.1.10', port: 7000});
  return socket;
}
```

也支持 `connect(host, port)`。host 是主机名或 IP，不带协议和端口；port 是 1～65535 的整数。示例地址需要替换成你的目标服务。

Promise resolve 时连接已经建立，readyState 为 1，不需要再等待 onopen。

| 成员 | 说明 |
| --- | --- |
| `send(data)` | 返回 Promise；接受字符串、Blob、ArrayBuffer 或 TypedArray |
| `close()` | 发起关闭 |
| `closed` | 关闭后 resolve 为 `{code, reason}` 的 Promise |
| `readyState` | 0 连接中、1 已连接、2 关闭中、3 已关闭 |
| `binaryType` | 默认 `arraybuffer`，也可设为 `blob` |
| `bufferedAmount` | SDK 待发送字节数，不代表对端业务已经确认 |
| `onmessage` | 接收 MessageEvent，data 类型由 binaryType 决定 |
| `onclose`、`onerror` | 监听关闭和连接错误 |
| `addEventListener()` | EventTarget 事件监听接口 |
| `readable` | 标准 ReadableStream，输出 Uint8Array |
| `writable` | 标准 WritableStream，写入时经过 send |

本对象提供常用的 WebSocket 式事件和标准流接口，但不是浏览器原生 WebSocket 实例。接第三方协议库时，按该库的自定义传输接口编写适配器。

### 7.3 用本机 echo 服务验证收发

以下示例需要在 TCP 代理所在机器安装 Node.js。创建 `echo-server.cjs`：

```js
const net = require('node:net');
net.createServer(socket => socket.pipe(socket))
  .listen(7000, '127.0.0.1', () => console.log('TCP echo: 127.0.0.1:7000'));
```

运行：

```sh
node echo-server.cjs
```

在已声明 TCP 权限的工具中运行下面的脚本：

```js
async function echoExample(host = '127.0.0.1', port = 7000) {
  const socket = await BookStark.sockets.connect({host, port});
  const writer = socket.writable.getWriter();
  const reader = socket.readable.getReader();
  try {
    const input = new TextEncoder().encode('hello BookStark TCP\n');
    await writer.write(input);
    const chunks = [];
    let size = 0;
    while (size < input.byteLength) {
      const {value, done} = await reader.read();
      if (done) throw Error('目标服务提前关闭连接');
      chunks.push(value);
      size += value.byteLength;
    }
    const output = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      output.set(chunk, offset);
      offset += chunk.byteLength;
    }
    console.log(new TextDecoder().decode(output));
    return output;
  } finally {
    writer.releaseLock();
    reader.releaseLock();
    socket.close();
    await socket.closed;
  }
}
```

执行 `await echoExample()` 后，应收到 `hello BookStark TCP` 和换行。这个例子按字节数累积接收，避免错误地假设一次 send 一定对应一次 message。

### 7.4 流量与生命周期

每工具最多 8 条连接，每账号最多 16 条，后端总计最多 128 条。单次 send 最多 1 MiB，内部按 64 KiB 分片；发送需要 await，以处理背压。连续大文件请分块写入，不要一次发送整个大文件。

readable 有界缓冲。如果长时间不消费数据，连接可能关闭。不要同时用 onmessage 和 readable 重复处理同一批数据。

页面离开时会关闭连接。更新、卸载、撤销 TCP 权限或关闭服务器代理后，连接会被清理；服务端权限检查间隔为 5 秒。连接失败可见 `connect_failed`，缺少权限为 `permission_denied`，未开启代理为 `socket_proxy_disabled`；部分失败只有 message 或关闭事件，应同时处理异常和 closed。

TCP 桥接不提供 UDP、端口监听、隐式 TLS、SSH 登录或远程命令执行接口。发送的是原始字节，应用负责消息边界、编码和上层协议。

### 7.5 开发 SSH terminal

浏览器侧可采用下面的结构：

```text
终端界面（例如 xterm.js）
          ↕
浏览器 SSH 协议库（JS / WASM）
          ↕ 自定义传输适配器
BookStark TCP 二进制流
          ↕
      SSH 服务器
```

例如 [libssh2.js](https://github.com/sitepi/libssh2.js) 提供浏览器端 SSH 与自定义流传输能力。选型时核对库的版本、构建方式、传输回调和许可证，再适配当前 Socket 对象。本文没有把某个 SSH 库封装成内置 BookStark SSH API。

SSH 工具自身仍需完成主机密钥验证、密码或私钥认证、PTY 分配、终端尺寸变化、字符编码和断线处理。TCP 转发成功或收到 SSH banner，不代表已经登录成功。不要把真实账号、密码或私钥写进公开 HTML 或随工具分发的静态资源。

## 8. 浏览器原生能力

浏览器能力继续使用标准 API，BookStark 不提供 `BookStark.camera()` 或 `BookStark.clipboard()` 这样的额外包装。

| 功能 | 发布权限 | 调用入口 |
| --- | --- | --- |
| 复制、粘贴 | clipboard_write、clipboard_read | navigator.clipboard.writeText / readText |
| 摄像头、麦克风 | camera、microphone | navigator.mediaDevices.getUserMedia |
| 屏幕共享 | display_capture | navigator.mediaDevices.getDisplayMedia |
| 位置 | geolocation | navigator.geolocation |
| 工具内容全屏 | fullscreen | Element.requestFullscreen |
| 视频画中画 | picture_in_picture | HTMLVideoElement.requestPictureInPicture |
| 保持屏幕点亮 | screen_wake_lock | navigator.wakeLock.request |
| 系统分享 | web_share | navigator.share |
| USB / 串口 / 蓝牙 | usb / serial / bluetooth | navigator.usb / serial / bluetooth |

使用前做特性检测；从按钮点击等真实用户操作中发起敏感请求；捕获用户拒绝和设备不可用异常。设备不用时停止 MediaStream tracks，关闭串口、USB 或蓝牙连接。

系统不会绕过浏览器设备授权、屏幕选择器、播放策略或跨域 CORS 限制。工具顶部的宿主全屏按钮与工具自己的 requestFullscreen 权限相互独立。

## 9. 从开发到市场分发

1. **开发来源文章**：使用 HTML 类型，保留文章和资源；私有文章也可作为工具源，密码加密文章不可以。
2. **检查安装资源**：查看 HTML 入口、依赖路径和大小；确认资源能公开读取。资源检查不会直接发布。
3. **填写发布设置**：名称、版本、简介、分类、图标与颜色、权限、安装范围、更新说明。
4. **发布或提交审核**：管理员可直接发布；成员是否需审核，以市场配置为准。
5. **客户端连接市场**：在工具设置填写市场地址，例如 `https://你的服务器/market`，测试连接并保存。
6. **安装验证**：登录安装目标工作区；如果发布市场要求登录，还需单独登录市场账号。
7. **发布更新**：修改来源和资源后，使用新的语义化版本号，例如 `1.0.1`；版本号不可覆盖。
8. **检查数据兼容**：工具更新保留已有数据，因此更改 JSON 或文件格式时，工具代码需要处理旧格式。
9. **权限变更**：增加运行权限的更新需要用户手动确认，不能依赖自动更新静默获得新能力。

安装到哪里，取决于安装工作区：原生客户端进入的是设备本地工具库；普通浏览器登录远端工作区时，安装到远端账号。免登录下载公开市场内容，与免登录安装到一个持久化工作区不是同一回事。

下架停止新的安装和下载，不会远程删除用户已有安装。卸载时是否保留数据由用户选择；重新安装可能恢复保留数据，工具不要假设重新安装一定获得空白状态。

## 10. 调试和排错

| 现象 | 检查方向 |
| --- | --- |
| `BookStark` 不存在 | 确认正在打开已安装工具，而非普通来源文章预览或直接打开 HTML 文件 |
| files.list 或 sockets 不存在 | 安装工作区仍是旧运行时；检查版本说明并升级 |
| `permission_denied` | 检查当前已安装版本的权限；只修改来源文章不会更新安装权限 |
| `conflict` | 工具已更新或实例失效，重新打开，停止重试旧实例 |
| `not_found` | 文件路径或原始静态资源不存在；注意工具路径与服务器 URL 的区别 |
| `already_exists` | rename / move / copy 的目标已存在，先换名或由用户确认处理 |
| `directory_not_empty` | 非空目录需要显式递归删除 |
| `quota_exceeded` | 检查工作区单文件限制和总配额；localStorage 也有独立的 5 MiB 上限 |
| 摄像头或剪贴板不可用 | 检查权限声明、安装版本、独立运行来源、HTTPS/本地安全上下文和浏览器支持 |
| 能联网但外部接口失败 | network 不会绕过 CORS，确认目标接口允许浏览器跨域 |
| TCP 被拒绝 | 检查 socket_tcp、服务器代理开关，以及目标从后端网络是否可达 |
| TCP 数据乱码或不完整 | 确认协议、二进制解码和分包；不能假设每次回调就是一整条消息 |
| 开发机正常，安装后 JS/CSS/WASM 丢失 | 查看资源检查列表；检查动态加载地址、相对路径和构建资源是否真的被下载 |
| 状态看起来没有保存 | 确认工具确实写入存储，查看宿主保存失败提示，并区分输入状态和显式保存的文件 |

在开发者工具中区分宿主页面与工具 iframe 的 Console；检查 iframe 的 allow、sandbox、网络请求和报错。宿主内部的 BookStarkHost、BookStarkClient 不是插件公共 API，不应直接调用。

## 11. 发布前验证

- 在实际安装运行页验证主要功能、刷新和返回，检查浏览器错误。
- 在关闭不需要的权限时验证功能；设备授权被拒绝也能给出清晰提示。
- 对文件接口检查不存在、重复目标、目录删除、权限拒绝和配额错误。
- 对 TCP 检查正常收发、目标拒绝、主动关闭、断线和工具关闭后的清理。
- 在手机宽度、深浅主题和减少动效设置下检查布局与可操作性。
- 安装新版本后确认旧数据仍能读取，不因格式变化丢失。
- 在原始静态服务器不可访问时，验证声称支持离线的功能。

当前运行时已用 Chromium 验证设备策略、模拟摄像头/麦克风、剪贴板、文件操作、隔离及 TCP 二进制往返；Linux WebKitGTK 验证了独立本地来源、父页面隔离和文件桥接。高级硬件接口仍需开发者在目标浏览器及真实设备上验证。
